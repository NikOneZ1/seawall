import AppKit
import SeawallCore
import os
import UniformTypeIdentifiers

let log = Logger(subsystem: "com.nikitaverba.FocusLock", category: "app")

struct SiteItem: Codable, Identifiable, Hashable {
    var pattern: String
    var enabled = true
    var id: String { pattern }
}

struct AppItem: Codable, Identifiable, Hashable {
    var bundleID: String
    var name: String
    var path: String
    var enabled = true
    var id: String { bundleID }
}

/// Something picked up from the sand on the block page. The menu shows them in its own sand.
struct Find: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case scallop, glass, stone, dollar, snail, star

        var title: String {
            switch self {
            case .scallop: "Scallop shell"
            case .glass: "Sea glass"
            case .stone: "Smooth stone"
            case .dollar: "Sand dollar"
            case .snail: "Snail shell"
            case .star: "Starfish"
            }
        }
    }

    var kind: Kind
    var foundAt: Date
}

/// What the next block will cover. Running blocks keep their own copy, so editing this never loosens them.
struct Config: Codable, Equatable {
    var sites: [SiteItem]
    var apps: [AppItem]
    var blockOtherBrowsers: Bool
    var duration: BlockDuration
    var until: UntilTime

    static var initial: Config {
        Config(
            sites: ["youtube.com/shorts", "twitch.tv", "tiktok.com"].map { SiteItem(pattern: $0) },
            apps: [],
            blockOtherBrowsers: true,
            duration: .hours2,
            until: UntilTime(day: 0, hour: 18, minute: 0)
        )
    }

    var enabledSites: [String] { sites.filter(\.enabled).map(\.pattern) }
    var enabledApps: [BlockedApp] { apps.filter(\.enabled).map { BlockedApp(bundleID: $0.bundleID, name: $0.name) } }
    var isEmpty: Bool { enabledSites.isEmpty && enabledApps.isEmpty && !blockOtherBrowsers }
}

extension Config {
    /// Before "Until…" had a day it was only a time of day, saved as `untilTime`.
    private enum LegacyKeys: String, CodingKey {
        case untilTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sites = try container.decode([SiteItem].self, forKey: .sites)
        apps = try container.decode([AppItem].self, forKey: .apps)
        blockOtherBrowsers = try container.decode(Bool.self, forKey: .blockOtherBrowsers)
        duration = try container.decode(BlockDuration.self, forKey: .duration)
        if let until = try container.decodeIfPresent(UntilTime.self, forKey: .until) {
            self.until = until
        } else if let time = try decoder.container(keyedBy: LegacyKeys.self).decodeIfPresent(Date.self, forKey: .untilTime) {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
            let minute = parts.minute ?? 0
            until = UntilTime(day: 0, hour: parts.hour ?? 18, minute: minute - minute % UntilTime.minuteStep)
        } else {
            until = Config.initial.until
        }
    }
}

@MainActor
final class BlockController: ObservableObject {
    @Published var config: Config {
        didSet { if config != oldValue { store.save(config, as: .config) } }
    }
    /// Running blocks, oldest first.
    @Published private(set) var sessions: [Session]
    @Published private(set) var lastSummary: SessionSummary?
    @Published private(set) var safariAccess: SafariAccess = .unknown
    /// Picked up on the block page, oldest first.
    @Published private(set) var finds: [Find]
    /// Ticks once a second for countdowns.
    @Published private(set) var now = Date()

    private let store = Store()
    private let safari = SafariGuard()
    private let appGuard = AppGuard()
    private let pageServer = BlockPageServer()
    private var clock = ClockWatch()
    /// Site rules of each running block; blocks without sites are left out.
    private var rules: [Session.ID: [SiteRule]] = [:]
    /// Tab+URL → when we redirected it, so a redirect still in flight isn't counted twice.
    private var recentRedirects: [String: Date] = [:]
    /// The "End now?" alert on screen for a block whose wait is over.
    private var unlockPrompt: (id: Session.ID, alert: NSAlert)?
    private var timer: Timer?

    init() {
        config = store.load(Config.self, from: .config) ?? .initial
        var sessions = store.load([Session].self, from: .sessions) ?? []
        // Written by versions that ran one block at a time.
        if let legacy = store.load(Session.self, from: .session) {
            sessions.append(legacy)
            store.save(sessions, as: .sessions)
            store.remove(.session)
        }
        self.sessions = sessions
        lastSummary = store.load(SessionSummary.self, from: .summary)
        finds = store.load([Find].self, from: .finds) ?? []
    }

    func launch() {
        pageServer.finds = { [weak self] in self?.finds.map(\.kind.rawValue) ?? [] }
        pageServer.onFind = { [weak self] kind in self?.addFind(kind) ?? false }
        pageServer.start()
        appGuard.onAttempt = { [weak self] app in
            log.info("Closed \(app.bundleIdentifier ?? "?", privacy: .public)")
            self?.countAttempt(app)
        }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        refreshSafariAccess()
        if !sessions.isEmpty {
            finish(sessions.filter { $0.isOver(at: Date()) }, early: false)
            applyBlocks(countRunningApps: true)
            tick()
        }
    }

    // MARK: - Block lifecycle

    /// Another block can start while others run: it only ever adds to what's blocked.
    var canStart: Bool { !config.isEmpty && plannedEnd > now }

    var plannedEnd: Date {
        config.duration.endDate(from: now, until: config.until)
    }

    /// When everything is open again.
    var blockedUntil: Date? { sessions.map(\.endsAt).max() }

    /// Attempts across running blocks; the menu's water stirs when it goes up.
    var totalAttempts: Int { sessions.reduce(0) { $0 + $1.attempts } }

    /// The block page reports a find by its kind; anything else is ignored.
    func addFind(_ kind: String) -> Bool {
        guard let kind = Find.Kind(rawValue: kind) else { return false }
        finds.append(Find(kind: kind, foundAt: Date()))
        store.save(finds, as: .finds)
        return true
    }

    func startBlock() {
        let start = Date()
        let end = config.duration.endDate(from: start, until: config.until)
        guard !config.isEmpty, end > start else { return }
        sessions.append(Session(
            startedAt: start,
            endsAt: end,
            sites: config.enabledSites,
            apps: config.enabledApps,
            blocksOtherBrowsers: config.blockOtherBrowsers
        ))
        persistSessions()
        applyBlocks(countRunningApps: false)
        tick()
    }

    func requestUnlock(_ id: Session.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }),
              sessions[index].unlockRequestedAt == nil else { return }
        sessions[index].unlockRequestedAt = Date()
        persistSessions()
    }

    func cancelUnlock(_ id: Session.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].unlockRequestedAt = nil
        persistSessions()
    }

    func confirmUnlock(_ id: Session.ID) {
        guard let session = sessions.first(where: { $0.id == id }),
              case .ready = session.unlockState(at: Date()) else { return }
        finish([session], early: true)
        applyBlocks(countRunningApps: false)
    }

    /// Asks the moment a wait is over. "End now" is only on offer for two minutes, and
    /// tucked away in the menu it would pass unseen.
    private func promptForUnlock(at now: Date) {
        if let prompt = unlockPrompt {
            let ready = sessions.first { $0.id == prompt.id }?.unlockState(at: now).isReady ?? false
            // Only the topmost modal can be aborted: a summary shown on top has to close first.
            if !ready, NSApp.modalWindow === prompt.alert.window { NSApp.abortModal() }
            return
        }
        guard let session = sessions.first(where: { $0.unlockState(at: now).isReady }) else { return }

        let alert = NSAlert()
        alert.messageText = "End the block now?"
        alert.informativeText = "The 10-minute wait is over. If you stay, \(session.names) stay blocked until "
            + "\(Format.clockTime(session.endsAt, relativeTo: now)). This question goes away in 2 minutes."
        alert.addButton(withTitle: "Stay")
        alert.addButton(withTitle: "End now").hasDestructiveAction = true
        unlockPrompt = (session.id, alert)

        let id = session.id
        // Outside the current tick, like the summary. The timer keeps ticking inside
        // runModal's loop, which is what closes the alert once the offer is gone.
        DispatchQueue.main.async {
            NSApp.activate()
            let response = alert.runModal()
            self.unlockPrompt = nil
            switch response {
            case .alertSecondButtonReturn: self.confirmUnlock(id)
            case .abort: break
            default: self.cancelUnlock(id)
            }
        }
    }

    /// Points the guards at everything the running blocks cover.
    /// `countRunningApps`: see `AppGuard.update`.
    private func applyBlocks(countRunningApps: Bool) {
        rules = [:]
        for session in sessions {
            let siteRules = session.sites.compactMap(SiteRule.init)
            if !siteRules.isEmpty { rules[session.id] = siteRules }
        }
        let bundleIDs = sessions.reduce(into: Set<String>()) { $0.formUnion($1.blockedBundleIDs) }
        appGuard.update(bundleIDs: bundleIDs, countRunning: countRunningApps)
        if sessions.isEmpty {
            Watchdog.uninstall()
        } else {
            Watchdog.install(appPath: Bundle.main.bundlePath)
        }
    }

    private func tick() {
        let wall = Date()
        let skew = clock.skew(wall: wall)

        if !sessions.isEmpty {
            var updated = sessions
            for index in updated.indices {
                updated[index].absorbClockJump(skew)
                updated[index].expireUnlockRequest(at: wall)
            }
            if updated != sessions {
                sessions = updated
                persistSessions()
            }
            let over = sessions.filter { $0.isOver(at: wall) }
            if !over.isEmpty {
                finish(over, early: false)
                applyBlocks(countRunningApps: false)
            }
            appGuard.sweep()
            enforceSafari()
        }
        promptForUnlock(at: wall)

        if Int(wall.timeIntervalSince1970) != Int(now.timeIntervalSince1970) {
            now = wall
        }
    }

    private func enforceSafari() {
        guard !rules.isEmpty, SafariGuard.isRunning else { return }

        switch safari.tabs() {
        case .success(let tabs):
            setSafariAccess(.granted)
            let cutoff = Date().addingTimeInterval(-5)
            recentRedirects = recentRedirects.filter { $0.value > cutoff }

            var updated = sessions
            for tab in tabs {
                guard let index = updated.lastEnding(where: { session in
                    rules[session.id]?.contains { $0.matches(tab.url) } == true
                }) else { continue }
                let key = "\(tab.windowID)/\(tab.index)/\(tab.url.absoluteString)"
                if recentRedirects[key] == nil { updated[index].siteAttempts += 1 }
                recentRedirects[key] = Date()
                let page = pageServer.pageURL(until: updated[index].endsAt, blocked: tab.url, attempts: updated[index].attempts)
                safari.redirect(tab, to: page)
            }
            if updated != sessions {
                sessions = updated
                persistSessions()
            }

        case .failure(.notPermitted):
            // No permission means no way to filter tabs — so no Safari until the block ends.
            setSafariAccess(.denied)
            safari.quitSafari()

        case .failure(.failed(let code)):
            // -600: Safari quit mid-poll; -1712: timeout. Next tick will retry.
            if code != -600 { log.debug("Safari poll failed: \(code)") }
        }
    }

    /// Ends blocks and shows how each went. The caller then re-applies what's left, so a
    /// relaunch can still count apps that were opened while Seawall wasn't running.
    private func finish(_ ended: [Session], early: Bool) {
        guard !ended.isEmpty else { return }
        let endedAt = Date()
        let ids = Set(ended.map(\.id))
        sessions.removeAll { ids.contains($0.id) }
        persistSessions()
        for session in ended {
            let summary = SessionSummary(session, endedAt: endedAt, early: early)
            lastSummary = summary
            showSummary(summary)
        }
        if let lastSummary { store.save(lastSummary, as: .summary) }
    }

    private func countAttempt(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier,
              let index = sessions.lastEnding(where: { $0.blockedBundleIDs.contains(bundleID) }) else { return }
        sessions[index].appAttempts += 1
        persistSessions()
    }

    private func persistSessions() {
        if sessions.isEmpty {
            store.remove(.sessions)
        } else {
            store.save(sessions, as: .sessions)
        }
    }

    private func showSummary(_ summary: SessionSummary) {
        // Outside the current tick: runModal spins its own loop.
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = summary.endedEarly ? "Block lifted early" : "Block is over"
            alert.informativeText = Format.summary(summary)
            alert.addButton(withTitle: "OK")
            NSApp.activate()
            alert.runModal()
        }
    }

    // MARK: - Editing the lists

    /// When the running blocks let go of a site from the list, if any of them holds it.
    func blockedUntil(site pattern: String) -> Date? {
        guard let rule = SiteRule(pattern) else { return nil }
        return sessions
            .filter { $0.sites.contains { SiteRule($0)?.covers(rule) == true } }
            .map(\.endsAt).max()
    }

    func blockedUntil(app bundleID: String) -> Date? {
        sessions.filter { $0.blockedBundleIDs.contains(bundleID) }.map(\.endsAt).max()
    }

    var otherBrowsersBlockedUntil: Date? {
        sessions.filter(\.blocksOtherBrowsers).map(\.endsAt).max()
    }

    func addSite(_ pattern: String) -> Bool {
        guard let rule = SiteRule(pattern) else { return false }
        if !config.sites.contains(where: { $0.pattern == rule.description }) {
            config.sites.append(SiteItem(pattern: rule.description))
        }
        return true
    }

    func removeSite(_ item: SiteItem) {
        config.sites.removeAll { $0.id == item.id }
    }

    func removeApp(_ item: AppItem) {
        config.apps.removeAll { $0.id == item.id }
    }

    func pickApps() {
        let panel = NSOpenPanel()
        panel.title = "Apps to close during a block"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate()
        guard panel.runModal() == .OK else { return }

        let excluded: Set<String> = [Bundle.main.bundleIdentifier ?? "", "com.apple.finder"]
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, !excluded.contains(id),
                  !config.apps.contains(where: { $0.bundleID == id }) else { continue }
            config.apps.append(AppItem(bundleID: id, name: url.deletingPathExtension().lastPathComponent, path: url.path))
        }
    }

    // MARK: - Safari permission

    func refreshSafariAccess() {
        if let access = SafariGuard.determineAccess(ask: false) { setSafariAccess(access) }
    }

    func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }

    private func setSafariAccess(_ access: SafariAccess) {
        if safariAccess != access { safariAccess = access }
    }
}
