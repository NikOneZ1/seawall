import SeawallCore
import SwiftUI

/// Choices made in Settings, kept in UserDefaults.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    /// How the next block can be left early.
    @Published var earlyExit: EarlyExit {
        didSet { defaults.set(earlyExit.rawValue, forKey: "earlyExit") }
    }
    /// The menu bar shows "1h 24m" instead of the end time.
    @Published var showsTimeLeft: Bool {
        didSet { defaults.set(showsTimeLeft, forKey: "showsTimeLeft") }
    }
    /// ⌃⌥⌘L opens the menu from anywhere.
    @Published var shortcut: Bool {
        didSet {
            defaults.set(shortcut, forKey: "shortcut")
            MenuShortcut.shared.update(shortcut)
        }
    }
    /// "5 minutes left" and "Block is over" as notifications.
    @Published var notifications: Bool {
        didSet { defaults.set(notifications, forKey: "notifications") }
    }
    /// A soft sound when a block starts and ends.
    @Published var sounds: Bool {
        didSet { defaults.set(sounds, forKey: "sounds") }
    }

    /// Which page a blocked tab lands on.
    @Published var blockedPage: BlockedPageChoice {
        didSet { defaults.set(blockedPage.rawValue, forKey: "blockedPage") }
    }

    private init() {
        defaults.register(defaults: ["showsTimeLeft": false, "shortcut": true, "notifications": true, "sounds": true])
        earlyExit = EarlyExit(rawValue: defaults.string(forKey: "earlyExit") ?? "") ?? .wait10
        showsTimeLeft = defaults.bool(forKey: "showsTimeLeft")
        shortcut = defaults.bool(forKey: "shortcut")
        notifications = defaults.bool(forKey: "notifications")
        sounds = defaults.bool(forKey: "sounds")
        blockedPage = BlockedPageChoice(rawValue: defaults.string(forKey: "blockedPage") ?? "") ?? .random
        // The sea and the hold animations are gone; drop what older versions stored for them.
        defaults.removeObject(forKey: "sea")
        defaults.removeObject(forKey: "holdAnimation")
    }
}
