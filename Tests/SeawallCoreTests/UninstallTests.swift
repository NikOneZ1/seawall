import Foundation
import Testing
@testable import SeawallCore

struct UninstallTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar
    }

    /// October 2026: the 19th is a Monday.
    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func block(from start: Date, hours: Double) -> Session {
        Session(startedAt: start, endsAt: start + hours * 3600, sites: ["twitch.tv"], apps: [], blocksOtherBrowsers: false)
    }

    let workdays = Schedule(listName: "Work", days: [2, 3, 4, 5, 6], start: TimeOfDay(hour: 10, minute: 0), end: TimeOfDay(hour: 18, minute: 0))

    func refusal(_ sessions: [Session] = [], _ schedules: [Schedule] = [], at now: Date,
                 canStart: @escaping (Schedule) -> Bool = { _ in true }) -> UninstallRefusal? {
        Uninstall.refusal(sessions: sessions, schedules: schedules, now: now, calendar: calendar, canStart: canStart)
    }

    @Test func goesAheadWithNothingRunning() {
        #expect(refusal(at: date(19, 9)) == nil)
    }

    @Test func refusesDuringABlock() {
        let now = date(19, 12)
        #expect(refusal([block(from: date(19, 11), hours: 2)], at: now) == .blockRunning(until: date(19, 13)))
    }

    @Test func namesTheLastEndOfStackedBlocks() {
        let now = date(19, 12)
        let blocks = [block(from: date(19, 11), hours: 4), block(from: date(19, 11, 30), hours: 1)]
        #expect(refusal(blocks, at: now) == .blockRunning(until: date(19, 15)))
    }

    @Test func refusesOnABreakBetweenRounds() {
        // 2 rounds of 25 minutes with 5 off: 10:25 is on the first break.
        var session = block(from: date(19, 10), hours: 1)
        session.rounds = Rounds(count: 2, work: 25 * 60, rest: 5 * 60)
        session.endsAt = date(19, 10) + session.rounds!.total
        #expect(!session.isHolding(at: date(19, 10, 27)))
        #expect(refusal([session], at: date(19, 10, 27)) == .blockRunning(until: session.endsAt))
    }

    @Test func refusesWhileWaitingToLeaveEarly() {
        // Asking to leave isn't leaving: the block holds until "End now".
        var session = block(from: date(19, 11), hours: 2)
        session.unlockRequestedAt = date(19, 11, 30)
        #expect(refusal([session], at: date(19, 11, 45)) == .blockRunning(until: date(19, 13)))
        #expect(refusal([session], at: date(19, 11, 41)) != nil)
    }

    @Test func aBlockThatsOverDoesntCount() {
        let session = block(from: date(19, 10), hours: 1)
        #expect(refusal([session], at: date(19, 11)) == nil)
        #expect(refusal([session], at: date(19, 10, 59)) != nil)
    }

    @Test func refusesWhenAScheduleIsAboutToStart() {
        // Inside its hours and not yet started: the next tick starts it.
        #expect(refusal([], [workdays], at: date(19, 10)) == .scheduleStarting(until: date(19, 18)))
    }

    @Test func aScheduleLaterOrAlreadyEndedEarlyIsFine() {
        // Before its hours: uninstalling removes it.
        #expect(refusal([], [workdays], at: date(19, 9, 59)) == nil)
        // Started today and left early: it doesn't start again until tomorrow.
        var schedule = workdays
        schedule.lastRun = date(19, 10)
        #expect(refusal([], [schedule], at: date(19, 12)) == nil)
        schedule.enabled = false
        #expect(refusal([], [schedule], at: date(20, 12)) == nil)
    }

    @Test func aScheduleThatCantStartAnythingDoesntCount() {
        #expect(refusal([], [workdays], at: date(19, 12), canStart: { _ in false }) == nil)
    }

    @Test func aRunningBlockComesFirst() {
        let now = date(19, 10)
        #expect(refusal([block(from: date(19, 9), hours: 3)], [workdays], at: now) == .blockRunning(until: date(19, 12)))
    }

    @Test func refusalSaysUntilWhen() {
        let message = UninstallRefusal.blockRunning(until: date(19, 18)).message(relativeTo: date(19, 12), calendar: calendar)
        #expect(message.contains("until 18:00"))
        #expect(message.contains("leave it early"))
        #expect(!message.contains("—"))
    }

    @Test func removesOnlySeawallsOwnFiles() {
        let home = URL(fileURLWithPath: "/Users/nikita", isDirectory: true)
        let paths = Uninstall.files(home: home).map(\.path)
        #expect(paths == [
            "/Users/nikita/Library/LaunchAgents/com.nikitaverba.FocusLock.watchdog.plist",
            "/Users/nikita/Library/Application Support/Seawall",
            "/Users/nikita/Library/Application Support/FocusLock",
            "/Users/nikita/Library/Caches/com.nikitaverba.FocusLock",
            "/Users/nikita/Library/HTTPStorages/com.nikitaverba.FocusLock",
            "/Users/nikita/Library/HTTPStorages/com.nikitaverba.FocusLock.binarycookies",
            "/Users/nikita/Library/Saved Application State/com.nikitaverba.FocusLock.savedState",
        ])
        // Never a shared folder itself.
        let shared = ["Library", "LaunchAgents", "Application Support", "Caches", "HTTPStorages", "Saved Application State"]
            .map { $0 == "Library" ? "/Users/nikita/Library" : "/Users/nikita/Library/\($0)" }
        for path in paths {
            #expect(path.hasPrefix("/Users/nikita/Library/"))
            #expect(!shared.contains(path))
        }
    }

    @Test func knowsWhereTheWatchdogAndPreferencesLive() {
        let home = URL(fileURLWithPath: "/Users/nikita", isDirectory: true)
        #expect(Uninstall.launchAgent(home: home).lastPathComponent == "com.nikitaverba.FocusLock.watchdog.plist")
        #expect(Uninstall.preferences(home: home).path == "/Users/nikita/Library/Preferences/com.nikitaverba.FocusLock.plist")
    }
}
