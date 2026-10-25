import Foundation

/// How long the next block lasts: a number of minutes, or until a set time.
public enum BlockLength: Codable, Equatable, Hashable, Sendable {
    case minutes(Int)
    case until(UntilTime)

    /// The three one-tap lengths in the menu.
    public static let presets: [BlockLength] = [.minutes(25), .minutes(60), .minutes(120)]
    /// More fixed lengths, under the menu's last segment.
    public static let more: [BlockLength] = [.minutes(15), .minutes(30), .minutes(45), .minutes(90), .minutes(180), .minutes(240)]

    public func end(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .minutes(let minutes): now + TimeInterval(minutes * 60)
        case .until(let until): until.date(from: now, calendar: calendar)
        }
    }

    /// "25m", "1h", "1h 30m": the segment's label.
    public var short: String {
        switch self {
        case .minutes(let minutes): Format.duration(TimeInterval(minutes * 60))
        case .until: "Until…"
        }
    }

    /// "25 minutes", "1 hour", "1 hour 30 minutes".
    public var title: String {
        switch self {
        case .minutes(let minutes): Format.length(minutes)
        case .until(let until): "Until \(String(format: "%02d:%02d", until.hour, until.minute))"
        }
    }
}

/// Moments people actually mean by "until": the end of the workday, tonight, the next morning.
public enum UntilPreset: CaseIterable, Sendable {
    case endOfWorkday, tonight, morning

    /// "This morning" before nine, "Tomorrow morning" after.
    public func title(for until: UntilTime) -> String {
        switch self {
        case .endOfWorkday: "End of workday"
        case .tonight: "Tonight"
        case .morning: until.day == 0 ? "This morning" : "Tomorrow morning"
        }
    }

    public var time: TimeOfDay {
        switch self {
        case .endOfWorkday: TimeOfDay(hour: 18, minute: 0)
        case .tonight: TimeOfDay(hour: 22, minute: 0)
        case .morning: TimeOfDay(hour: 9, minute: 0)
        }
    }

    /// The moment, if it's still ahead: today's for the first two, the next 09:00 for the morning,
    /// so a block started after midnight doesn't run until the morning after.
    public func until(from now: Date, calendar: Calendar = .current) -> UntilTime? {
        let today = UntilTime(day: 0, hour: time.hour, minute: time.minute)
        if today.date(from: now, calendar: calendar) > now { return today }
        return self == .morning ? UntilTime(day: 1, hour: time.hour, minute: time.minute) : nil
    }
}
