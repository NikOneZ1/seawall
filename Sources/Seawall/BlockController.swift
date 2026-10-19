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

/// A Games, Social… chip in the list, on or off like a site.
struct GroupItem: Codable, Identifiable, Hashable {
    var group: SiteGroup
    var enabled = true
    var id: SiteGroup { group }
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

/// A named set of what to lock, like Work or Evening, picked from the "Lock" title.
struct SavedList: Codable, Identifiable, Hashable {
    var name: String
    var groups: [SiteGroup]
    var sites: [String]
    var apps: [String]
    var otherBrowsers: Bool
    var id: String { name }
}

/// What the next block will cover. Running blocks keep their own copy, so editing this never loosens them.
struct Config: Codable, Equatable {
    var groups: [GroupItem] = []
    var sites: [SiteItem]
    /// Left open while Whole web is on.
    var allowedSites: [String] = []
    var lists: [SavedList] = []
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

    var enabledGroups: [SiteGroup] { groups.filter(\.enabled).map(\.group) }
    var enabledSites: [String] { sites.filter(\.enabled).map(\.pattern) }
    var enabledApps: [BlockedApp] { apps.filter(\.enabled).map { BlockedApp(bundleID: $0.bundleID, name: $0.name) } }
    /// "Other browsers" only counts when there's one installed for it to close.
    var closesOtherBrowsers: Bool { blockOtherBrowsers && !InstalledBrowsers.unreadable.isEmpty }
    var isEmpty: Bool { enabledGroups.isEmpty && enabledSites.isEmpty && enabledApps.isEmpty && !closesOtherBrowsers }
    /// Whether the next block covers any sites, its groups' included.
    var coversSites: Bool { !enabledSites.isEmpty || enabledGroups.contains { !$0.sites.isEmpty || $0 == .web } }
    var blocksWholeWeb: Bool { enabledGroups.contains(.web) }

    /// What's switched on right now, as a list called `name`.
    func selection(named name: String) -> SavedList {
        SavedList(name: name, groups: enabledGroups, sites: enabledSites,
                  apps: apps.filter(\.enabled).map(\.bundleID), otherBrowsers: blockOtherBrowsers)
    }

    /// The saved list that's switched on right now, if any.
    var currentList: SavedList? {
        let now = selection(named: "")
        return lists.first { list in
            Set(list.groups) == Set(now.groups) && Set(list.sites) == Set(now.sites)
                && Set(list.apps) == Set(now.apps) && list.otherBrowsers == now.otherBrowsers
        }
    }

    /// Switches on exactly what the list holds, and everything else off.
    mutating func apply(_ list: SavedList) {
        for i in groups.indices { groups[i].enabled = list.groups.contains(groups[i].group) }
        for i in sites.indices { sites[i].enabled = list.sites.contains(sites[i].pattern) }
        for i in apps.indices { apps[i].enabled = list.apps.contains(apps[i].bundleID) }
        blockOtherBrowsers = list.otherBrowsers
    }
}

extension Config {
    /// Before "Until…" had a day it was only a time of day, saved as `untilTime`.
    private enum LegacyKeys: String, CodingKey {
        case untilTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groups = try container.decodeIfPresent([GroupItem].self, forKey: .groups) ?? []
        sites = try container.decode([SiteItem].self, forKey: .sites)
        allowedSites = try container.decodeIfPresent([String].self, forKey: .allowedSites) ?? []
        lists = try container.decodeIfPresent([SavedList].self, forKey: .lists) ?? []
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
    /// Automation access per readable browser, by bundle ID; missing until checked.
    @Published private(set) var browserAccess: [String: BrowserAccess] = [:]
    /// Picked up on the block page, oldest first.
    @Published private(set) var finds: [Find]
    /// Ticks once a second for countdowns.
    @Published private(set) var now = Date()
    /// The menu bar's end time, which changes far less often than `now`.
    let menuBar = MenuBarState()

    private let store = Store()
    /// Safari and the Chromium browsers whose blocked tabs get the block page.
    let browsers = KnownBrowsers.readable.map(BrowserGuard.init)
    private let appGuard = AppGuard()
    private let pageServer = BlockPageServer()
    private var clock = ClockWatch()
    /// What each running block keeps closed in browsers; blocks that only cover apps are left out.
    private var filters: [Session.ID: WebFilter] = [:]
    /// Tab+URL → when we redirected it, so a redirect still in flight isn't counted twice.
    private var recentRedirects: [String: Date] = [:]
    /// The "End now?" alert on screen for a block whose wait is over.
    private var unlockPrompt: (id: Session.ID, alert: NSAlert)?
    private var timer: Timer?
    /// When each browser's tabs were last read; see `enforce(_:)`.
    private var lastBrowserCheck: [String: Date] = [:]
    /// Reads in a row that failed for a reason other than permission, per browser.
    private var browserFailures: [String: Int] = [:]
    /// Browsers whose "Seawall wants to control …" question is on screen right now.
    private var askingAccess: Set<String> = []
    private static let backgroundBrowserInterval: TimeInterval = 5
    /// A browser that stops answering can't be watched, so it's closed like one we may not look at.
    private static let failuresBeforeClosing = 4

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
        Notifier.shared.setUp()
        MenuShortcut.shared.update(Preferences.shared.shortcut)
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

        refreshBrowserAccess()
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
            blocksOtherBrowsers: config.closesOtherBrowsers,
            groups: config.enabledGroups,
            allowedSites: config.blocksWholeWeb ? config.allowedSites : [],
            earlyExit: Preferences.shared.earlyExit
        ))
        persistSessions()
        applyBlocks(countRunningApps: false)
        tick()
        Sounds.locked()
        if let session = sessions.last { Notifier.shared.blockStarted(session) }
    }

    func requestUnlock(_ id: Session.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }),
              sessions[index].unlockRequestedAt == nil, sessions[index].earlyExit.wait != nil else { return }
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
        let minutes = Int((session.earlyExit.wait ?? 0) / 60)
        alert.informativeText = "The \(minutes)-minute wait is over. If you stay, \(session.names) stay blocked until "
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
        // A new block checks the browsers right away, wherever they are.
        lastBrowserCheck = [:]
        filters = [:]
        for session in sessions {
            let filter = WebFilter(session)
            if !filter.isEmpty { filters[session.id] = filter }
        }
        let bundleIDs = sessions.reduce(into: Set<String>()) { $0.formUnion($1.blockedBundleIDs) }
        appGuard.update(bundleIDs: bundleIDs, games: sessions.contains(where: \.blocksGames), countRunning: countRunningApps)
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
            enforceBrowsers()
        }
        promptForUnlock(at: wall)

        if Int(wall.timeIntervalSince1970) != Int(now.timeIntervalSince1970) {
            now = wall
        }
        menuBar.update(blockedUntil.map { until in
            // "1h 24m" counts down a minute at a time and never shows 0m while anything is blocked.
            Preferences.shared.showsTimeLeft
                ? Format.duration((until.timeIntervalSince(wall) / 60).rounded(.up) * 60)
                : Format.clockTime(until, relativeTo: wall)
        })
    }

    private func enforceBrowsers() {
        guard !filters.isEmpty else { return }
        for browser in browsers where browser.isRunning {
            enforce(browser)
        }
    }

    private func enforce(_ browser: BrowserGuard) {
        let id = browser.bundleID
        // Reading tabs before the user has answered "Seawall wants to control …" would wait on
        // that question with the whole app frozen, every other browser included. So the
        // question is asked off to the side, and this browser is read once it's answered.
        if browserAccess[id] == nil || browserAccess[id] == .unknown {
            if let access = BrowserGuard.determineAccess(id, ask: false) { setAccess(access, for: browser) }
            if browserAccess[id] != .granted, browserAccess[id] != .denied {
                guard !askingAccess.contains(id) else { return }
                askingAccess.insert(id)
                Task {
                    await ask(browser)
                    askingAccess.remove(id)
                }
                return
            }
        }

        // Asking a browser for its tabs is most of what a block costs. In front it's asked on
        // every tick; behind other apps, where nobody is looking at it, every few seconds is enough.
        let checkedAt = Date()
        if !browser.isFrontmost, checkedAt.timeIntervalSince(lastBrowserCheck[id] ?? .distantPast) < Self.backgroundBrowserInterval {
            return
        }
        lastBrowserCheck[id] = checkedAt

        switch browser.tabs() {
        case .success(let tabs):
            browserFailures[id] = 0
            setAccess(.granted, for: browser)
            let cutoff = Date().addingTimeInterval(-5)
            recentRedirects = recentRedirects.filter { $0.value > cutoff }

            var updated = sessions
            for tab in tabs {
                guard let index = updated.lastEnding(where: { session in
                    filters[session.id]?.blocks(tab.url) == true
                }) else { continue }
                let key = "\(id)/\(tab.windowID)/\(tab.index)/\(tab.url.absoluteString)"
                if recentRedirects[key] == nil { updated[index].siteAttempts += 1 }
                recentRedirects[key] = Date()
                let page = pageServer.pageURL(until: updated[index].endsAt, blocked: tab.url, attempts: updated[index].attempts)
                browser.redirect(tab, to: page)
            }
            if updated != sessions {
                sessions = updated
                persistSessions()
            }

        case .failure(.notPermitted):
            // No permission means no way to filter tabs, so no browser until the block ends.
            setAccess(.denied, for: browser)
            browser.quit()

        case .failure(.failed(let code)):
            // -600 and -609: the browser quit mid-read. Anything else is retried on the next
            // check, but a browser that keeps failing can't be left open around the block.
            guard code != -600, code != -609 else { return }
            let failures = (browserFailures[id] ?? 0) + 1
            browserFailures[id] = failures
            log.debug("\(browser.name, privacy: .public) read failed: \(code)")
            if failures >= Self.failuresBeforeClosing {
                log.error("\(browser.name, privacy: .public) keeps failing (\(code)), closing it during the block")
                browserFailures[id] = 0
                browser.quit()
            }
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
        Sounds.over()
        for session in ended {
            let summary = SessionSummary(session, endedAt: endedAt, early: early)
            lastSummary = summary
            if !Notifier.shared.blockEnded(session, summary) { showSummary(summary) }
        }
        if let lastSummary { store.save(lastSummary, as: .summary) }
    }

    private func countAttempt(_ app: NSRunningApplication) {
        let bundleID = app.bundleIdentifier ?? ""
        guard let index = sessions.lastEnding(where: { session in
            session.blockedBundleIDs.contains(bundleID) || (session.blocksGames && AppGuard.isGame(app))
        }) else { return }
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

    func blockedUntil(group: SiteGroup) -> Date? {
        sessions.filter { $0.groups.contains(group) }.map(\.endsAt).max()
    }

    func addGroup(_ group: SiteGroup) {
        if !config.groups.contains(where: { $0.group == group }) { config.groups.append(GroupItem(group: group)) }
    }

    func removeGroup(_ item: GroupItem) {
        config.groups.removeAll { $0.group == item.group }
    }

    /// Saves what's switched on under `name`, replacing a list of the same name.
    func saveList(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let list = config.selection(named: name)
        if let i = config.lists.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            config.lists[i] = list
        } else {
            config.lists.append(list)
        }
    }

    func applyList(_ list: SavedList) {
        config.apply(list)
    }

    func deleteList(_ list: SavedList) {
        config.lists.removeAll { $0.name == list.name }
    }

    /// Sites Whole web leaves open. False if the text isn't a site.
    func allowSite(_ pattern: String) -> Bool {
        guard let rule = SiteRule(pattern) else { return false }
        if !config.allowedSites.contains(rule.description) { config.allowedSites.append(rule.description) }
        return true
    }

    func disallowSite(_ pattern: String) {
        config.allowedSites.removeAll { $0 == pattern }
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

    // MARK: - Browser permission

    /// Readable browsers on this Mac, Safari first.
    var installedBrowsers: [BrowserGuard] { browsers.filter(\.isInstalled) }

    /// Installed browsers that said no to Automation; they get closed during blocks with sites.
    var deniedBrowsers: [BrowserGuard] { installedBrowsers.filter { browserAccess[$0.bundleID] == .denied } }

    func refreshBrowserAccess() {
        for browser in installedBrowsers {
            if let access = BrowserGuard.determineAccess(browser.bundleID, ask: false) { setAccess(access, for: browser) }
        }
    }

    /// From the welcome: shows each browser's "control …" prompt now rather than in the middle of
    /// a block. macOS only asks about a running app, so a closed browser is opened in the background first.
    func askForBrowserAccess() async {
        for browser in installedBrowsers where browserAccess[browser.bundleID] != .granted {
            await ask(browser)
        }
    }

    private func ask(_ browser: BrowserGuard) async {
        let id = browser.bundleID
        if BrowserGuard.determineAccess(id, ask: false) == nil,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.hides = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        // A browser that's still starting up isn't ready for the question; give it a few seconds.
        for _ in 0..<20 {
            if let access = await Task.detached(operation: { BrowserGuard.determineAccess(id, ask: true) }).value {
                setAccess(access, for: browser)
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }

    private func setAccess(_ access: BrowserAccess, for browser: BrowserGuard) {
        if browserAccess[browser.bundleID] != access { browserAccess[browser.bundleID] = access }
    }
}
