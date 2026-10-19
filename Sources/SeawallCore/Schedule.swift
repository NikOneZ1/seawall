import Foundation

/// A time of day, like 10:00.
public struct TimeOfDay: Codable, Hashable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public var text: String { String(format: "%02d:%02d", hour, minute) }
}

/// A block that starts on its own, like Work on weekdays from 10:00 to 18:00. The days are the
/// days it starts on; an end before the start runs past midnight into the next day.
public struct Schedule: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    /// The saved list it locks.
    public var listName: String
    /// Weekdays it starts on, as `Calendar` numbers them: 1 is Sunday, 7 is Saturday.
    public var days: Set<Int>
    public var start: TimeOfDay
    public var end: TimeOfDay
    public var enabled = true
    /// When the last stretch it started began, so one ended early doesn't start again.
    public var lastRun: Date?

    public init(id: UUID = UUID(), listName: String, days: Set<Int>, start: TimeOfDay, end: TimeOfDay) {
        self.id = id
        self.listName = listName
        self.days = days
        self.start = start
        self.end = end
    }

    /// The stretch `now` falls in, if any: started today, or yesterday and running past midnight.
    public func stretch(containing now: Date, calendar: Calendar = .current) -> (start: Date, end: Date)? {
        let today = calendar.startOfDay(for: now)
        for offset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  days.contains(calendar.component(.weekday, from: day)),
                  let from = calendar.date(bySettingHour: start.hour, minute: start.minute, second: 0, of: day),
                  var to = calendar.date(bySettingHour: end.hour, minute: end.minute, second: 0, of: day) else { continue }
            if to <= from { to = calendar.date(byAdding: .day, value: 1, to: to) ?? to }
            if from <= now, now < to { return (from, to) }
        }
        return nil
    }

    /// The stretch to start now: one is under way and this schedule hasn't started it yet.
    public func due(at now: Date, calendar: Calendar = .current) -> (start: Date, end: Date)? {
        guard enabled, let stretch = stretch(containing: now, calendar: calendar) else { return nil }
        if let lastRun, lastRun >= stretch.start { return nil }
        return stretch
    }

    /// "Weekdays, 10:00–18:00".
    public var summary: String {
        "\(Self.dayNames(days)), \(start.text)–\(end.text)"
    }

    /// "Every day", "Weekdays", "Weekends", or "Mon, Wed, Fri" in Monday-first order.
    public static func dayNames(_ days: Set<Int>) -> String {
        if days.count == 7 { return "Every day" }
        if days == [2, 3, 4, 5, 6] { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        if days.isEmpty { return "No days" }
        let names = [2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat", 1: "Sun"]
        return [2, 3, 4, 5, 6, 7, 1].filter(days.contains).compactMap { names[$0] }.joined(separator: ", ")
    }
}
