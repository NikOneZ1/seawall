import Foundation

/// While a block runs, a LaunchAgent re-opens the app every 10 seconds and at login.
/// Killing FocusLock in Activity Monitor buys you at most 10 seconds; once relaunched it
/// picks the session up from disk and closes whatever you opened in the meantime.
enum Watchdog {
    static let label = "com.nikitaverba.FocusLock.watchdog"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    private static var domain: String { "gui/\(getuid())" }
    private static var service: String { "\(domain)/\(label)" }

    /// Idempotent: safe to call on every launch during a block.
    static func install(appPath: String) {
        let plist: [String: Any] = [
            "Label": label,
            // `open` on an already running app does nothing, so this is cheap.
            "ProgramArguments": ["/usr/bin/open", "-g", appPath],
            "RunAtLoad": true,
            "StartInterval": 10,
            "ProcessType": "Background",
            "AssociatedBundleIdentifiers": [Bundle.main.bundleIdentifier ?? "com.nikitaverba.FocusLock"],
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }

        let current = try? Data(contentsOf: plistURL)
        if current == data && launchctl("print", service) == 0 { return }

        launchctl("bootout", service)
        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: plistURL, options: .atomic)
        } catch {
            log.error("Watchdog plist: \(error.localizedDescription, privacy: .public)")
            return
        }
        let status = launchctl("bootstrap", domain, plistURL.path)
        if status != 0 { log.error("launchctl bootstrap exited with \(status)") }
    }

    static func uninstall() {
        launchctl("bootout", service)
        try? FileManager.default.removeItem(at: plistURL)
    }

    @discardableResult
    private static func launchctl(_ arguments: String...) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
