import AppKit

/// Closes blocked apps as soon as they appear.
@MainActor
final class AppGuard {
    var onAttempt: ((NSRunningApplication) -> Void)?

    private var blocked: Set<String> = []
    private var handled: Set<pid_t> = []
    private var observation: NSKeyValueObservation?

    /// Sets what to close; called whenever a block starts or ends. `countRunning`: whether apps
    /// that are already open count as attempts. Not when a block starts (you just pressed the
    /// button), but yes after a relaunch mid-block.
    func update(bundleIDs: Set<String>, countRunning: Bool) {
        guard !bundleIDs.isEmpty else { return stop() }
        blocked = bundleIDs
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
        handled = []
    }

    /// Runs on every launch notification and on the regular tick as a safety net.
    func sweep(count: Bool = true) {
        guard !blocked.isEmpty else { return }
        let running = NSWorkspace.shared.runningApplications
        handled.formIntersection(running.map(\.processIdentifier))
        for app in running {
            guard let id = app.bundleIdentifier, blocked.contains(id), !app.isTerminated,
                  handled.insert(app.processIdentifier).inserted else { continue }
            Self.close(app)
            if count { onAttempt?(app) }
        }
    }

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
