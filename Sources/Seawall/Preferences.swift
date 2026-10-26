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
    /// When the menu shows the sea.
    @Published var sea: SeaMode {
        didSet { defaults.set(sea.rawValue, forKey: "sea") }
    }
    /// How "Hold to lock" plays: see `HoldAnimation` and VARIANTS.md.
    @Published var holdAnimation: HoldAnimation {
        didSet { defaults.set(holdAnimation.rawValue, forKey: HoldAnimation.defaultsKey) }
    }

    private init() {
        defaults.register(defaults: ["showsTimeLeft": false, "shortcut": true, "notifications": true, "sounds": true])
        earlyExit = EarlyExit(rawValue: defaults.string(forKey: "earlyExit") ?? "") ?? .wait10
        showsTimeLeft = defaults.bool(forKey: "showsTimeLeft")
        shortcut = defaults.bool(forKey: "shortcut")
        notifications = defaults.bool(forKey: "notifications")
        sounds = defaults.bool(forKey: "sounds")
        sea = SeaMode(rawValue: defaults.string(forKey: "sea") ?? "") ?? .whileLocked
        holdAnimation = HoldAnimation(rawValue: defaults.string(forKey: HoldAnimation.defaultsKey) ?? "") ?? .bloom
    }
}

/// How much sea the menu shows: always, as the sign of a running block, or never.
enum SeaMode: String, CaseIterable, Identifiable {
    case always, whileLocked, never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .always: "Always"
        case .whileLocked: "While locked"
        case .never: "Never"
        }
    }
}

/// How the hold to lock looks. Only the picture changes: the hold itself (0.8 s, the same
/// keys, the same cancelling) is `HoldButton`'s and doesn't depend on this.
///
/// Settings, Look, "Hold to lock animation" picks one; so does
/// `defaults write com.nikitaverba.FocusLock holdAnimation bloom`.
enum HoldAnimation: String, CaseIterable, Identifiable {
    /// The sea blooms outward from the button, soft at its edge; the button fills from its middle.
    case bloom
    /// The sea fades in from the bottom as a soft fog, with no edge to see; the button fills with a soft sweep.
    case tide
    /// No movement across the menu: the sea fades in as one tint and settles from a hair larger.
    case tint
    /// The first version: a hard-edged rise from the floor, stirring up silt, and a bar across the button.
    case classic

    static let defaultsKey = "holdAnimation"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bloom: "Bloom"
        case .tide: "Soft tide"
        case .tint: "Tint"
        case .classic: "Rising water"
        }
    }

    var detail: String {
        switch self {
        case .bloom: "Water spreads out from the button in a soft circle. Recommended."
        case .tide: "Water fades in from the bottom as a mist, with no edge."
        case .tint: "The whole menu slowly turns to sea. Nothing moves across it."
        case .classic: "The original: water climbs the menu and kicks up sand."
        }
    }

    /// The curve of the hold's progress, over `HoldButton.holdTime`. The new ones ease in and
    /// out, so nothing lurches at the start or stops dead at the end; the original is linear.
    var holdCurve: Animation {
        switch self {
        case .classic: .linear(duration: HoldButton.holdTime)
        default: .timingCurve(0.35, 0, 0.25, 1, duration: HoldButton.holdTime)
        }
    }

    /// Letting go early: the progress drains back, quickly in the original, gently in the others.
    var releaseCurve: Animation {
        switch self {
        case .classic: .easeOut(duration: 0.25)
        default: .easeOut(duration: 0.45)
        }
    }

    /// How long a half-finished sea takes to fade when the hold is let go.
    var releaseFade: Double { self == .classic ? 0.25 : 0.45 }
}
