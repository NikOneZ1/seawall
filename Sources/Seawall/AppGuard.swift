import AppKit
import SeawallCore

/// Closes blocked apps as soon as they appear: the ones on the list, and any game while a
/// block covers Games.
@MainActor
final class AppGuard {
    var onAttempt: ((NSRunningApplication) -> Void)?

    private var blocked: Set<String> = []
    private var closesGames = false
    private var handled: Set<pid_t> = []
    private var observation: NSKeyValueObservation?

    /// Sets what to close; called whenever a block starts or ends. `countRunning`: whether apps
    /// that are already open count as attempts. Not when a block starts (you just pressed the
    /// button), but yes after a relaunch mid-block.
    func update(bundleIDs: Set<String>, games: Bool, countRunning: Bool) {
        guard !bundleIDs.isEmpty || games else { return stop() }
        blocked = bundleIDs
        closesGames = games
        sweep(count: countRunning)
        if observation == nil {
            observation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.sweep() }
                }
            }
        }
    }

    func stop() {
        observation = nil
        blocked = []
        closesGames = false
        handled = []
    }

    /// Runs on every launch notification and on the regular tick as a safety net.
    func sweep(count: Bool = true) {
        guard !blocked.isEmpty || closesGames else { return }
        let running = NSWorkspace.shared.runningApplications
        handled.formIntersection(running.map(\.processIdentifier))
        for app in running {
            let listed = app.bundleIdentifier.map(blocked.contains) ?? false
            guard listed || (closesGames && Self.isGame(app)), !app.isTerminated,
                  handled.insert(app.processIdentifier).inserted else { continue }
            Self.close(app)
            if count { onAttempt?(app) }
        }
    }

    /// Whether macOS files the app under Games, it came from a Steam or Epic library, or it's a
    /// launcher. Read from the app's Info.plist once per app.
    static func isGame(_ app: NSRunningApplication) -> Bool {
        let path = (app.bundleURL ?? app.executableURL)?.path
        let key = path ?? app.bundleIdentifier ?? ""
        if let known = gameCache[key] { return known }
        let category = app.bundleURL.flatMap(Bundle.init(url:))?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        let game = SiteGroup.isGame(bundleID: app.bundleIdentifier, category: category, path: path)
        gameCache[key] = game
        return game
    }

    private static var gameCache: [String: Bool] = [:]

    /// Asks the app to quit, and kills it if it's still around a second later
    /// (games love "Are you sure you want to quit?" dialogs).
    static func close(_ app: NSRunningApplication) {
        guard !app.isTerminated else { return }
        app.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if !app.isTerminated { app.forceTerminate() }
        }
    }
}
