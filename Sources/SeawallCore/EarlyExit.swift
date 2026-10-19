import Foundation

/// How a block can be ended before its time: after a wait, or not at all. Chosen in Settings;
/// each block keeps the choice it started with, so changing it never loosens a running block.
public enum EarlyExit: String, Codable, CaseIterable, Identifiable, Sendable {
    case wait10, wait30, never

    public var id: String { rawValue }

    /// How long you wait after asking to leave; `nil` when there's no way out.
    public var wait: TimeInterval? {
        switch self {
        case .wait10: 10 * 60
        case .wait30: 30 * 60
        case .never: nil
        }
    }

    public var title: String {
        switch self {
        case .wait10: "After a 10-minute wait"
        case .wait30: "After a 30-minute wait"
        case .never: "Not at all"
        }
    }

    /// The menu's own line under the duration.
    public var menuTitle: String {
        switch self {
        case .wait10: "Leave early after 10 min"
        case .wait30: "Leave early after 30 min"
        case .never: "No leaving early"
        }
    }

    /// The line under the hold button: what you're agreeing to.
    public var finePrint: String {
        switch self {
        case .wait10: "Leaving early will take a 10-minute wait."
        case .wait30: "Leaving early will take a 30-minute wait."
        case .never: "There's no leaving early once it's locked."
        }
    }
}
