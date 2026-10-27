import Foundation

/// The app's bundle ID, and the move away from the one it started with.
///
/// Seawall began as FocusLock, and its bundle ID said so until 1.0. The new ID means a new
/// UserDefaults domain, watchdog label and login item; `moveFromLegacy` carries those over and
/// retires the old watchdog, so nothing is lost but the browser and notification permissions,
/// which macOS ties to the ID and asks for again.
@MainActor
enum BundleID {
    nonisolated static let legacy = "com.nikitaverba.FocusLock"
    nonisolated static var current: String { Bundle.main.bundleIdentifier ?? legacy }

    private static let movedKey = "movedFromLegacyBundleID"

    /// Runs on every launch; does nothing once done.
    static func moveFromLegacy() {
        guard current != legacy else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: movedKey) else { return }
        let old = defaults.persistentDomain(forName: legacy) ?? [:]
        // Only fill in what this ID doesn't have yet, so a newer choice is never overwritten.
        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: movedKey)
        Watchdog.uninstallLegacy()
        // Open at login is registered per ID. Older builds didn't store whether it was on, only
        // that a choice was made, and the welcome suggests turning it on, so it comes back on;
        // macOS says so in a notification, and it's one switch in Settings to turn off.
        if old["loginItemChosen"] as? Bool == true, !LoginItem.shared.isOn {
            LoginItem.shared.set(true)
        }
    }
}
