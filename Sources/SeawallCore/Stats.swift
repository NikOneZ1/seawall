import Foundation

/// One block that ran, kept for the Today page: when it ran, what it was, how it went.
public struct BlockRecord: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var endedAt: Date
    public var name: String
    public var color: ListColor?
    public var attempts: Int
    public var endedEarly: Bool

    public init(startedAt: Date, endedAt: Date, name: String, color: ListColor?, attempts: Int, endedEarly: Bool) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.name = name
        self.color = color
        self.attempts = attempts
        self.endedEarly = endedEarly
    }

    public init(_ session: Session, endedAt: Date, early: Bool) {
        self.init(startedAt: session.startedAt, endedAt: endedAt, name: session.title, color: session.label?.color,
                  attempts: session.attempts, endedEarly: early)
    }

    /// How much history to keep: enough for a long streak, small enough to read in a blink.
    public static let kept = 400
}

/// Today's numbers: time locked (overlapping blocks counted once), tries caught, and how many
/// days in a row had a block.
public struct DayStats: Equatable, Sendable {
    public var locked: TimeInterval
    public var attempts: Int
    public var streak: Int

    /// `running` blocks count up to `now`.
    public init(day: Date, now: Date, history: [BlockRecord], running: [Session], calendar: Calendar = .current) {
        let intervals = history.map { ($0.startedAt, $0.endedAt) } + running.map { ($0.startedAt, min($0.endsAt, now)) }
        locked = Self.covered(intervals, on: day, calendar: calendar)
        attempts = history.filter { calendar.isDate($0.endedAt, inSameDayAs: day) }.reduce(0) { $0 + $1.attempts }
            + running.reduce(0) { $0 + $1.attempts }

        var streak = 0
        var cursor = calendar.startOfDay(for: day)
        // Today without a block yet doesn't break the streak; it just hasn't grown.
        if Self.covered(intervals, on: cursor, calendar: calendar) < 60 {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        while Self.covered(intervals, on: cursor, calendar: calendar) >= 60 {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        self.streak = streak
    }

    /// Seconds of `day` inside at least one interval.
    static func covered(_ intervals: [(Date, Date)], on day: Date, calendar: Calendar) -> TimeInterval {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let clipped = intervals
            .map { (max($0.0, start), min($0.1, end)) }
            .filter { $0.0 < $0.1 }
            .sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for interval in clipped {
            if let open = current, interval.0 <= open.1 {
                current = (open.0, max(open.1, interval.1))
            } else {
                if let open = current { total += open.1.timeIntervalSince(open.0) }
                current = interval
            }
        }
        if let open = current { total += open.1.timeIntervalSince(open.0) }
        return total
    }
}
