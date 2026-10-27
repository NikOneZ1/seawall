import Foundation

/// The app's bundle ID, and the move away from the one it started with.
///
/// Seawall began as FocusLock, and its bundle ID still says so. Changing it (one line in
/// Resources/Info.plist) gives the app a new UserDefaults domain and a new watchdog label;
/// `moveFromLegacy` carries settings over and retires the old watchdog, so nothing is lost
/// but the browser permission, which macOS ties to the ID and asks for again.
enum BundleID {
    static let legacy = "com.nikitaverba.FocusLock"
    static var current: String { Bundle.main.bundleIdentifier ?? legacy }

    private static let movedKey = "movedFromLegacyBundleID"

    /// Runs on every launch; does nothing while the ID is still the legacy one, or once done.
    static func moveFromLegacy() {
        guard current != legacy else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: movedKey) else { return }
        // Only fill in what this ID doesn't have yet, so a newer choice is never overwritten.
        for (key, value) in defaults.persistentDomain(forName: legacy) ?? [:] where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: movedKey)
        Watchdog.uninstallLegacy()
    }
}
