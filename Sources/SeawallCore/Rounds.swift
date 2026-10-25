import Foundation

/// A block in rounds, Pomodoro style: locked for `work`, open for `rest`, `count` times over,
/// with no break after the last round.
public struct Rounds: Codable, Equatable, Sendable {
    public var count: Int
    public var work: TimeInterval
    public var rest: TimeInterval

    public static let standard = Rounds(count: 4, work: 25 * 60, rest: 5 * 60)

    public init(count: Int, work: TimeInterval, rest: TimeInterval) {
        self.count = count
        self.work = work
        self.rest = rest
    }

    /// From the start of the first round to the end of the last.
    public var total: TimeInterval { Double(count) * work + Double(max(0, count - 1)) * rest }

    /// As many standard rounds as fit in `length`, breaks between them; `nil` when fewer
    /// than two fit, since one round has no break to take.
    public static func fitting(_ length: TimeInterval, work: TimeInterval = standard.work, rest: TimeInterval = standard.rest) -> Rounds? {
        let count = Int((length + rest) / (work + rest))
        return count >= 2 ? Rounds(count: count, work: work, rest: rest) : nil
    }
}

/// Where a block in rounds is: which round, or on a break before the next one.
public enum Phase: Equatable, Sendable {
    /// Round `round` (1-based) is locked until `endsAt`.
    case locked(round: Int, endsAt: Date)
    /// A break; round `nextRound` locks again at `until`.
    case resting(nextRound: Int, until: Date)
}

extension Rounds {
    /// The phase `elapsed` seconds after the first round started.
    public func phase(after elapsed: TimeInterval, from start: Date) -> Phase {
        let period = work + rest
        let index = min(count - 1, max(0, Int(elapsed / period)))
        let roundStart = Double(index) * period
        let into = elapsed - roundStart
        if into < work || index == count - 1 {
            return .locked(round: index + 1, endsAt: start + roundStart + work)
        }
        return .resting(nextRound: index + 2, until: start + roundStart + period)
    }
}
