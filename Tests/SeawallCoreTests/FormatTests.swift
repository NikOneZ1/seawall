import Foundation
import Testing
@testable import SeawallCore

struct FormatTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test(arguments: [
        (0, "0 attempts"), (1, "1 attempt"), (2, "2 attempts"), (21, "21 attempts"),
    ])
    func plurals(_ n: Int, _ expected: String) {
        #expect(Format.attempts(n) == expected)
    }

    @Test func countdown() {
        #expect(Format.countdown(600) == "10:00")
        #expect(Format.countdown(599.2) == "10:00")
        #expect(Format.countdown(59) == "0:59")
        #expect(Format.countdown(3725) == "1:02:05")
        #expect(Format.countdown(-5) == "0:00")
        #expect(Format.countdown(2 * 86_400 + 3725) == "2d 1:02:05")
    }

    @Test func duration() {
        #expect(Format.duration(45 * 60) == "45m")
        #expect(Format.duration(3 * 3600) == "3h")
        #expect(Format.duration(2 * 3600 + 15 * 60) == "2h 15m")
        #expect(Format.duration(29 * 3600 + 5 * 60) == "1d 5h")
        #expect(Format.duration(48 * 3600) == "2d")
    }

    @Test func clockTime() {
        let now = date(7, 10)
        #expect(Format.clockTime(date(7, 18), relativeTo: now, calendar: calendar) == "18:00")
        #expect(Format.clockTime(date(8, 9, 30), relativeTo: now, calendar: calendar) == "tomorrow, 09:30")
        #expect(Format.clockTime(date(12, 9), relativeTo: now, calendar: calendar) == "Oct 12, 09:00")
    }

    @Test func shortClockTime() {
        let now = date(9, 10)
        #expect(Format.shortClockTime(date(9, 22, 25), relativeTo: now, calendar: calendar) == "22:25")
        #expect(Format.shortClockTime(date(10, 19, 25), relativeTo: now, calendar: calendar) == "Sat 19:25")
    }

    @Test func dayNames() {
        let now = date(9, 23, 30)
        #expect(Format.day(0, from: now, calendar: calendar) == "Today")
        #expect(Format.day(1, from: now, calendar: calendar) == "Tomorrow")
        #expect(Format.day(2, from: now, calendar: calendar) == "Sun, Oct 11")
    }

    @Test func untilCountsDaysFromToday() {
        let tomorrow3pm = UntilTime(day: 1, hour: 15, minute: 0)
        #expect(BlockDuration.untilTime.endDate(from: date(7, 10), until: tomorrow3pm, calendar: calendar) == date(8, 15))
        #expect(BlockDuration.untilTime.endDate(from: date(7, 23, 50), until: tomorrow3pm, calendar: calendar) == date(8, 15))

        let nextWeek = UntilTime(day: 7, hour: 9, minute: 30)
        #expect(BlockDuration.untilTime.endDate(from: date(7, 10), until: nextWeek, calendar: calendar) == date(14, 9, 30))

        // Already passed: the block can't start rather than silently moving to tomorrow.
        let thisMorning = UntilTime(day: 0, hour: 9, minute: 0)
        #expect(BlockDuration.untilTime.endDate(from: date(7, 10), until: thisMorning, calendar: calendar) == date(7, 9))

        #expect(BlockDuration.hours2.endDate(from: date(7, 10), until: thisMorning, calendar: calendar) == date(7, 12))
    }
}
