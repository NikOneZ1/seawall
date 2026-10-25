import Foundation

/// A stretch of one day on a timeline, as fractions of the day from 0 (midnight) to 1.
public struct DayStretch: Equatable, Sendable {
    public enum Kind: Sendable { case scheduled, running }

    public var from: Double
    public var to: Double
    public var kind: Kind
    public var color: ListColor?
    public var listID: UUID?
    public var scheduleID: UUID?

    public init(from: Double, to: Double, kind: Kind, color: ListColor?, listID: UUID? = nil, scheduleID: UUID? = nil) {
        self.from = from
        self.to = to
        self.kind = kind
        self.color = color
        self.listID = listID
        self.scheduleID = scheduleID
    }
}

public enum Timeline {
    /// What `day` holds: each enabled schedule's stretches (including one carried over from
    /// the night before) and the running blocks, clipped to the day.
    public static func stretches(on day: Date, schedules: [Schedule], colors: [UUID: ListColor], running: [Session],
                                 calendar: Calendar = .current) -> [DayStretch] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let length = end.timeIntervalSince(start)
        func fraction(_ date: Date) -> Double { min(max(date.timeIntervalSince(start) / length, 0), 1) }

        var result: [DayStretch] = []
        for schedule in schedules where schedule.enabled {
            for offset in [-1, 0] {
                guard let base = calendar.date(byAdding: .day, value: offset, to: start),
                      schedule.days.contains(calendar.component(.weekday, from: base)),
                      let from = calendar.date(bySettingHour: schedule.start.hour, minute: schedule.start.minute, second: 0, of: base),
                      var to = calendar.date(bySettingHour: schedule.end.hour, minute: schedule.end.minute, second: 0, of: base) else { continue }
                if to <= from { to = calendar.date(byAdding: .day, value: 1, to: to) ?? to }
                guard to > start, from < end else { continue }
                let color = schedule.listID.flatMap { colors[$0] }
                result.append(DayStretch(from: fraction(from), to: fraction(to), kind: .scheduled, color: color,
                                         listID: schedule.listID, scheduleID: schedule.id))
            }
        }
        for session in running where session.endsAt > start && session.startedAt < end {
            result.append(DayStretch(from: fraction(session.startedAt), to: fraction(session.endsAt), kind: .running,
                                     color: session.label?.color, listID: session.label?.listID))
        }
        return result
    }

    /// The next time a schedule starts after `now`, within a week, with the schedule.
    public static func nextStart(after now: Date, schedules: [Schedule], calendar: Calendar = .current) -> (Date, Schedule)? {
        var best: (Date, Schedule)?
        let today = calendar.startOfDay(for: now)
        for schedule in schedules where schedule.enabled {
            for offset in 0...7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      schedule.days.contains(calendar.component(.weekday, from: day)),
                      let from = calendar.date(bySettingHour: schedule.start.hour, minute: schedule.start.minute, second: 0, of: day),
                      from > now else { continue }
                if best.map({ from < $0.0 }) ?? true { best = (from, schedule) }
                break
            }
        }
        return best
    }

    /// A schedule on a Monday-first week grid: per column (0 is Monday), the stretches in
    /// fractions of the day. A night past midnight continues at the top of the next column.
    public static func weekCells(_ schedule: Schedule) -> [(column: Int, from: Double, to: Double)] {
        let start = Double(schedule.start.hour * 60 + schedule.start.minute) / 1440
        let end = Double(schedule.end.hour * 60 + schedule.end.minute) / 1440
        var cells: [(Int, Double, Double)] = []
        for weekday in schedule.days.sorted() {
            let column = (weekday + 5) % 7
            if end > start {
                cells.append((column, start, end))
            } else {
                cells.append((column, start, 1))
                if end > 0 { cells.append(((column + 1) % 7, 0, end)) }
            }
        }
        return cells
    }
}
