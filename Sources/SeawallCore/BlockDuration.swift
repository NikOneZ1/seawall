import Foundation

public enum BlockDuration: String, Codable, CaseIterable, Identifiable, Sendable {
    case minutes15, minutes30, minutes45, hour1, hours2, hours3, hours4, untilTime

    public var id: String { rawValue }

    /// How long the fixed lengths last; `nil` for "until a set time".
    public var interval: TimeInterval? {
        switch self {
        case .minutes15: 15 * 60
        case .minutes30: 30 * 60
        case .minutes45: 45 * 60
        case .hour1: 60 * 60
        case .hours2: 2 * 60 * 60
        case .hours3: 3 * 60 * 60
        case .hours4: 4 * 60 * 60
        case .untilTime: nil
        }
    }

    public var title: String {
        switch self {
        case .minutes15: "15 minutes"
        case .minutes30: "30 minutes"
        case .minutes45: "45 minutes"
        case .hour1: "1 hour"
        case .hours2: "2 hours"
        case .hours3: "3 hours"
        case .hours4: "4 hours"
        case .untilTime: "Until a set time…"
        }
    }

    public func endDate(from now: Date, until: UntilTime, calendar: Calendar = .current) -> Date {
        interval.map { now + $0 } ?? until.date(from: now, calendar: calendar)
    }
}

/// "Until tomorrow, 15:00". The day counts from today, so a saved "tomorrow"
/// still means the day after whenever the next block is started.
public struct UntilTime: Codable, Equatable, Sendable {
    /// Today plus a week ahead.
    public static let days = 0...7
    public static let minuteStep = 5

    public var day: Int
    public var hour: Int
    public var minute: Int

    public init(day: Int, hour: Int, minute: Int) {
        self.day = day
        self.hour = hour
        self.minute = minute
    }

    /// Can be in the past ("today, 09:00" picked in the evening); such a block can't start.
    public func date(from now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: self.day, to: today) ?? today
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}
