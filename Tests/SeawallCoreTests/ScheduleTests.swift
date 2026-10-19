import Foundation
import Testing
@testable import SeawallCore

struct ScheduleTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar
    }

    /// October 2026: the 19th is a Monday, the 24th a Saturday.
    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    let workdays = Schedule(listName: "Work", days: [2, 3, 4, 5, 6], start: TimeOfDay(hour: 10, minute: 0), end: TimeOfDay(hour: 18, minute: 0))

    @Test func startsInsideItsHoursOnItsDays() {
        #expect(workdays.stretch(containing: date(19, 9, 59), calendar: calendar) == nil)
        let stretch = workdays.stretch(containing: date(19, 10), calendar: calendar)
        #expect(stretch?.start == date(19, 10))
        #expect(stretch?.end == date(19, 18))
        #expect(workdays.stretch(containing: date(19, 18), calendar: calendar) == nil)
        #expect(workdays.stretch(containing: date(24, 12), calendar: calendar) == nil)
    }

    @Test func runsPastMidnightIntoTheNextDay() {
        let nights = Schedule(listName: "Night", days: [6], start: TimeOfDay(hour: 22, minute: 0), end: TimeOfDay(hour: 7, minute: 0))
        // Friday the 23rd, 22:00 to Saturday 07:00.
        #expect(nights.stretch(containing: date(24, 3), calendar: calendar)?.start == date(23, 22))
        #expect(nights.stretch(containing: date(24, 7), calendar: calendar) == nil)
    }

    @Test func aStretchStartsOnceEvenIfEndedEarly() {
        var schedule = workdays
        #expect(schedule.due(at: date(19, 11), calendar: calendar)?.start == date(19, 10))
        schedule.lastRun = date(19, 10)
        #expect(schedule.due(at: date(19, 12), calendar: calendar) == nil)
        #expect(schedule.due(at: date(20, 10, 1), calendar: calendar)?.start == date(20, 10))
        schedule.enabled = false
        #expect(schedule.due(at: date(20, 10, 1), calendar: calendar) == nil)
    }

    @Test func namesItsDays() {
        #expect(workdays.summary == "Weekdays, 10:00–18:00")
        #expect(Schedule.dayNames([1, 7]) == "Weekends")
        #expect(Schedule.dayNames(Set(1...7)) == "Every day")
        #expect(Schedule.dayNames([1, 2, 4]) == "Mon, Wed, Sun")
    }
}
