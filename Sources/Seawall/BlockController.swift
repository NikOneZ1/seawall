import AppKit
import SeawallCore
import os
import UniformTypeIdentifiers

let log = Logger(subsystem: "com.nikitaverba.FocusLock", category: "app")

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
    /// Blocks that have ended, oldest first, for the Today page.
    @Published private(set) var history: [BlockRecord]
    /// Ticks once a second for countdowns.
    @Published private(set) var now = Date()
    /// How strict the next block is, when it differs from the default in Settings. Cleared
    /// once that block starts, so a one-off choice never becomes the new default.
    @Published var strictness: EarlyExit?
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
    /// Blocks holding things closed right now: all of them, except those on a break between rounds.
    private var holdingIDs: Set<Session.ID> = []
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
        if let data = store.data(.config), let loaded = Config.decode(data) {
            config = loaded.config
            if loaded.migrated { store.save(loaded.config, as: .config) }
        } else {
            config = .initial
        }
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
        history = store.load([BlockRecord].self, from: .history) ?? []
    }

    func launch() {
        Notifier.shared.setUp()
        MenuShortcut.shared.update(Preferences.shared.shortcut)
        pageServer.finds = { [weak self] in self?.finds.map(\.kind.rawValue) ?? [] }
        pageServer.onFind = { [weak self] kind in self?.addFind(kind) ?? false }
        pageServer.choice = { Preferences.shared.blockedPage }
        pageServer.start()
        appGuard.onAttempt = { [weak self] app in
            // Which app is block list content: private, so it never shows up in a feedback email.
            log.info("Closed \(app.bundleIdentifier ?? "?", privacy: .private)")
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

    // MARK: - The next block

    /// Whether "Other browsers" has anything to close on this Mac.
    var otherBrowsersInstalled: Bool { !InstalledBrowsers.unreadable.isEmpty }

    var selectedList: BlockList? { config.selectedList }

    func select(_ list: BlockList) {
        config.next.listID = list.id
    }

    /// How strict the next block will be: the one-off choice, or the default from Settings.
    var nextStrictness: EarlyExit { strictness ?? Preferences.shared.earlyExit }

    /// Rounds that fit the chosen length: at least two, and only for blocks up to four
    /// hours, where breaks make sense.
    var availableRounds: Rounds? {
        let length = config.next.length.end(from: now).timeIntervalSince(now)
        return length <= 4 * 3600 ? Rounds.fitting(length) : nil
    }

    /// The rounds the next block will have, when breaks are on.
    var plannedRounds: Rounds? {
        config.next.breaks ? availableRounds : nil
    }

    /// When the next block would end if it started now.
    var plannedEnd: Date {
        if let rounds = plannedRounds { return now + rounds.total }
        return config.next.length.end(from: now)
    }

    /// Another block can start while others run: it only ever adds to what's blocked.
    var canStart: Bool {
        guard let list = selectedList else { return false }
        return !list.isEmpty(otherBrowsersInstalled: otherBrowsersInstalled) && plannedEnd > now
    }

    func startBlock() {
        guard let list = selectedList else { return }
        let start = Date()
        let rounds = plannedRounds
        let end = rounds.map { start + $0.total } ?? config.next.length.end(from: start)
        let session = Session(list, startedAt: start, endsAt: end, earlyExit: nextStrictness, rounds: rounds,
                              otherBrowsersInstalled: otherBrowsersInstalled)
        guard !session.isEmpty, end > start else { return }
        sessions.append(session)
        strictness = nil
        persistSessions()
        applyBlocks(countRunningApps: false)
        tick()
        Sounds.locked()
        Notifier.shared.blockStarted(session)
    }

    /// When everything is open again.
    var blockedUntil: Date? { sessions.map(\.endsAt).max() }

    /// The block page reports a find by its kind; anything else is ignored.
    func addFind(_ kind: String) -> Bool {
        guard let kind = Find.Kind(rawValue: kind) else { return false }
        finds.append(Find(kind: kind, foundAt: Date()))
        store.save(finds, as: .finds)
        return true
    }

    // MARK: - Schedules and links

    /// Starts any schedule whose time has come, until the end of its stretch. Each stretch
    /// starts once, so ending one early doesn't bring it straight back. A schedule whose list
    /// was deleted does nothing.
    private func runSchedules(at now: Date) {
        for index in config.schedules.indices {
            let schedule = config.schedules[index]
            guard let stretch = schedule.due(at: now), stretch.end.timeIntervalSince(now) > 60,
                  let list = list(for: schedule) else { continue }
            config.schedules[index].lastRun = stretch.start
            if let session = start(list, at: now, until: stretch.end) {
                Notifier.shared.scheduleStarted(session, list: list.name)
            }
        }
    }

    func list(for schedule: Schedule) -> BlockList? {
        if let id = schedule.listID { return config.list(id) }
        return config.lists.first { $0.name.caseInsensitiveCompare(schedule.listName) == .orderedSame }
    }

    /// From a `seawall://lock` link, like one a Shortcuts automation opens when a Focus turns on.
    /// A list that doesn't exist locks nothing, rather than something else.
    func lock(_ link: LockLink) {
        let now = Date()
        let list: BlockList
        if let name = link.list {
            guard let named = config.lists.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                // The list's name is the user's own words; it stays out of the log.
                log.error("seawall://lock asked for a list that doesn't exist")
                return
            }
            list = named
        } else {
            guard let selected = selectedList else { return }
            list = selected
        }
        let end = link.end(from: now) ?? config.next.length.end(from: now)
        _ = start(list, at: now, until: min(end, now + LockLink.longest))
    }

    /// A block of what `list` holds, started outside the menu: by a schedule or a link.
    private func start(_ list: BlockList, at now: Date, until end: Date) -> Session? {
        let session = Session(list, startedAt: now, endsAt: end, earlyExit: Preferences.shared.earlyExit,
                              otherBrowsersInstalled: otherBrowsersInstalled)
        // Two blocks can't share a start time: it's their ID.
        guard !session.isEmpty, end > now, !sessions.contains(where: { $0.id == session.id }) else { return nil }
        sessions.append(session)
        persistSessions()
        applyBlocks(countRunningApps: false)
        Sounds.locked()
        Notifier.shared.blockStarted(session)
        return session
    }

    func saveSchedule(_ schedule: Schedule) {
        var schedule = schedule
        if let list = list(for: schedule) { schedule.listName = list.name }
        if let index = config.schedules.firstIndex(where: { $0.id == schedule.id }) {
            config.schedules[index] = schedule
        } else {
            config.schedules.append(schedule)
        }
    }

    func deleteSchedule(_ schedule: Schedule) {
        config.schedules.removeAll { $0.id == schedule.id }
    }

    func schedules(of list: BlockList) -> [Schedule] {
        config.schedules.filter { self.list(for: $0)?.id == list.id }
    }

    // MARK: - Tightening a running block

    /// More time on a running block. Only ever longer, so it needs no wait.
    func extend(_ id: Session.ID, by seconds: TimeInterval) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].extend(by: seconds)
        persistSessions()
        applyBlocks(countRunningApps: false)
    }

    /// One more site on a running block. False if the text isn't a site or the block already
    /// covers every site.
    @discardableResult
    func add(site pattern: String, to id: Session.ID) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == id }), sessions[index].add(site: pattern) else { return false }
        persistSessions()
        applyBlocks(countRunningApps: false)
        return true
    }

    func add(app: ListApp, to id: Session.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].add(app: BlockedApp(bundleID: app.bundleID, name: app.name))
        persistSessions()
        applyBlocks(countRunningApps: true)
    }

    func add(group: SiteGroup, to id: Session.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), group != .web else { return }
        sessions[index].add(group: group)
        persistSessions()
        applyBlocks(countRunningApps: true)
    }

    // MARK: - Leaving early

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
        alert.messageText = "End \(session.title) now?"
        let minutes = Int((session.earlyExit.wait ?? 0) / 60)
        alert.informativeText = "The \(minutes)-minute wait is over. If you stay, \(session.names) stay blocked until "
            + "\(Format.clockTime(session.endsAt, relativeTo: now)). This question goes away in 2 minutes."
        alert.addButton(withTitle: "Stay Locked")
        alert.addButton(withTitle: "End Now").hasDestructiveAction = true
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

    // MARK: - Enforcement

    /// Points the guards at everything the running blocks cover.
    /// `countRunningApps`: see `AppGuard.update`.
    private func applyBlocks(countRunningApps: Bool) {
        // A new block checks the browsers right away, wherever they are.
        lastBrowserCheck = [:]
        filters = [:]
        let holding = sessions.filter { $0.isHolding(at: Date()) }
        holdingIDs = Set(holding.map(\.id))
        for session in holding {
            let filter = WebFilter(session)
            if !filter.isEmpty { filters[session.id] = filter }
        }
        let bundleIDs = holding.reduce(into: Set<String>()) { $0.formUnion($1.blockedBundleIDs) }
        appGuard.update(bundleIDs: bundleIDs, games: holding.contains(where: \.blocksGames), countRunning: countRunningApps)
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
            // A block in rounds going on a break, or back from one.
            let holding = Set(sessions.filter { $0.isHolding(at: wall) }.map(\.id))
            if holding != holdingIDs {
                for session in sessions where holding.contains(session.id) != holdingIDs.contains(session.id) {
                    Notifier.shared.phaseChanged(session, at: wall)
                    if holding.contains(session.id) { Sounds.locked() } else { Sounds.over() }
                }
                applyBlocks(countRunningApps: false)
            }
            appGuard.sweep()
            enforceBrowsers()
        }
        promptForUnlock(at: wall)
        runSchedules(at: wall)

        if Int(wall.timeIntervalSince1970) != Int(now.timeIntervalSince1970) {
            now = wall
        }
        if let until = blockedUntil, let start = sessions.map(\.startedAt).min() {
            // "1h 24m" counts down a minute at a time and never shows 0m while anything is blocked.
            let text = Preferences.shared.showsTimeLeft
                ? Format.duration((until.timeIntervalSince(wall) / 60).rounded(.up) * 60)
                : Format.clockTime(until, relativeTo: wall)
            let total = until.timeIntervalSince(start)
            let progress = total > 0 ? min(max(wall.timeIntervalSince(start) / total, 0), 1) : 1
            menuBar.update(text, progress: progress)
        } else {
            menuBar.update(nil, progress: nil)
        }
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
            history.append(BlockRecord(session, endedAt: min(endedAt, session.endsAt), early: early))
            if !Notifier.shared.blockEnded(session, summary) { showSummary(summary) }
        }
        if history.count > BlockRecord.kept { history.removeFirst(history.count - BlockRecord.kept) }
        store.save(history, as: .history)
        if let lastSummary { store.save(lastSummary, as: .summary) }
    }

    private func countAttempt(_ app: NSRunningApplication) {
        let bundleID = app.bundleIdentifier ?? ""
        guard let index = sessions.lastEnding(where: { session in
            holdingIDs.contains(session.id)
                && (session.blockedBundleIDs.contains(bundleID) || (session.blocksGames && AppGuard.isGame(app)))
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

    // MARK: - Today

    var todayStats: DayStats {
        DayStats(day: now, now: now, history: history, running: sessions)
    }

    // MARK: - Lists

    /// A new, empty list, picked for the next block. Returns its id.
    @discardableResult
    func addList() -> UUID {
        let used = Set(config.lists.map(\.color))
        let color = ListColor.allCases.first { !used.contains($0) } ?? .sea
        let list = BlockList(name: config.freeName("New list"), symbol: "lock.fill", color: color)
        config.lists.append(list)
        return list.id
    }

    func update(_ list: BlockList) {
        guard let index = config.lists.firstIndex(where: { $0.id == list.id }) else { return }
        config.lists[index] = list
    }

    /// Changes one list where it is now. Undo uses this: it runs seconds later, when a copy of
    /// the list taken earlier would put back everything changed since.
    func mutateList(_ id: UUID, _ change: (inout BlockList) -> Void) {
        guard let index = config.lists.firstIndex(where: { $0.id == id }) else { return }
        change(&config.lists[index])
    }

    @discardableResult
    func duplicate(_ list: BlockList) -> UUID {
        var copy = list
        copy.id = UUID()
        copy.name = config.freeName("\(list.name) copy")
        config.lists.append(copy)
        return copy.id
    }

    /// Deletes a list and its schedules. The last list can't go: every block starts from one.
    func delete(_ list: BlockList) {
        guard config.lists.count > 1 else { return }
        config.schedules.removeAll { self.list(for: $0)?.id == list.id }
        config.lists.removeAll { $0.id == list.id }
        if config.next.listID == list.id { config.next.listID = config.lists.first?.id }
    }

    /// Whether a running block holds a site, and through what: YouTube Shorts can be held by
    /// youtube.com, by Video, or by the whole web, even with it unticked here.
    func hold(site pattern: String) -> Hold? {
        guard let rule = SiteRule(pattern) else { return nil }
        let covers = { (other: String) in SiteRule(other)?.covers(rule) == true }
        return latest(sessions.compactMap { session in
            if session.blocksWholeWeb {
                return session.allowedSites.contains(where: covers) ? nil : Hold(until: session.endsAt, by: "the whole web")
            }
            if let site = session.sites.first(where: covers) {
                let name = SiteRule(site)?.displayName ?? site
                return Hold(until: session.endsAt, by: SiteRule(site) == rule ? nil : name)
            }
            if let group = session.groups.first(where: { $0.sites.contains(where: covers) }) {
                return Hold(until: session.endsAt, by: group.title)
            }
            return nil
        })
    }

    func hold(app bundleID: String) -> Hold? {
        latest(sessions.filter { $0.blockedBundleIDs.contains(bundleID) }.map { Hold(until: $0.endsAt, by: nil) })
    }

    func hold(group: SiteGroup) -> Hold? {
        latest(sessions.compactMap { session in
            if session.groups.contains(group) { return Hold(until: session.endsAt, by: nil) }
            if session.blocksWholeWeb, group != .games { return Hold(until: session.endsAt, by: "the whole web") }
            return nil
        })
    }

    private func latest(_ holds: [Hold]) -> Hold? {
        holds.max { $0.until < $1.until }
    }

    /// Apps picked in an Open panel, as list items. Seawall and Finder can't be blocked.
    func pickApps() -> [ListApp] {
        let panel = NSOpenPanel()
        panel.title = "Apps to close during a block"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate()
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap(InstalledApps.item(at:))
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

/// A running block holding something in a list: until when, and through what, when that's
/// something else ("YouTube" holding YouTube Shorts).
struct Hold {
    let until: Date
    let by: String?
}
