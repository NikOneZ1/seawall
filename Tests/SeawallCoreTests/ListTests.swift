import Foundation
import Testing
@testable import SeawallCore

struct ListTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return calendar
    }

    /// October 2026: the 19th is a Monday.
    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    var work: BlockList {
        BlockList(name: "Work", symbol: "briefcase.fill", color: .sea,
                  groups: [Toggled(.social), Toggled(.games), Toggled(.news, isOn: false)],
                  sites: [Toggled("youtube.com/shorts"), Toggled("twitch.tv"), Toggled("reddit.com", isOn: false)],
                  apps: [ListApp(bundleID: "com.valvesoftware.steam", name: "Steam", path: "/Applications/Steam.app"),
                         ListApp(bundleID: "com.hnc.Discord", name: "Discord", path: "/Applications/Discord.app")],
                  otherBrowsers: false)
    }

    @Test func saysWhatItLocks() {
        // Social's sites and Games' sites, Shorts and Twitch; reddit.com is off but Social has it anyway.
        let sites = SiteGroup.social.sites.count + SiteGroup.games.sites.count + 2
        #expect(work.blockedSiteCount == sites)
        #expect(work.summary(otherBrowsersInstalled: false) == "\(sites) sites, 2 apps and every game")
        #expect(work.itemNames == ["Social", "Games", "YouTube Shorts", "Twitch", "Steam", "Discord"])
    }

    @Test func coveredSitesCountOnce() {
        let list = BlockList(name: "Video", sites: [Toggled("youtube.com"), Toggled("youtube.com/shorts"), Toggled("m.youtube.com")])
        #expect(list.blockedSiteCount == 1)
        #expect(list.summary(otherBrowsersInstalled: false) == "1 site")
    }

    @Test func allExceptBlocksTheWholeWeb() {
        var list = work
        list.mode = .allExcept
        list.allowed = ["docs.google.com", "github.com"]
        #expect(list.enabledSites.isEmpty)
        #expect(list.sessionGroups == [.games, .web])
        #expect(list.summary(otherBrowsersInstalled: false) == "The whole web except 2 sites, 2 apps and every game")
        #expect(list.itemNames.first == "The whole web except Google Docs and GitHub")

        let session = Session(list, startedAt: date(19, 10), endsAt: date(19, 12), earlyExit: .wait10, otherBrowsersInstalled: true)
        #expect(session.blocksWholeWeb)
        #expect(session.allowedSites == ["docs.google.com", "github.com"])
        #expect(session.label?.name == "Work")
    }

    @Test func emptyUnlessSomethingIsOn() {
        var list = BlockList(name: "Empty", otherBrowsers: true)
        #expect(list.isEmpty(otherBrowsersInstalled: false))
        #expect(!list.isEmpty(otherBrowsersInstalled: true))
        list.mode = .allExcept
        #expect(!list.isEmpty(otherBrowsersInstalled: false))
    }

    @Test func addingKeepsOneOfEach() {
        var list = work
        let added = list.addSite("https://www.Reddit.com/")
        #expect(added)
        #expect(list.sites.filter { $0.value == "reddit.com" }.count == 1)
        #expect(list.sites.first { $0.value == "reddit.com" }?.isOn == true)
        let refused = list.addSite("not a site")
        #expect(!refused)
        list.addGroup(.news)
        #expect(list.groups.first { $0.value == .news }?.isOn == true)
        list.addGroup(.web)
        #expect(list.mode == .allExcept)
        list.addSite("notion.so")
        #expect(list.allowed == ["notion.so"])
    }

    @Test func roundsFitTheLength() {
        #expect(Rounds.fitting(25 * 60) == nil)
        #expect(Rounds.fitting(60 * 60)?.count == 2)
        #expect(Rounds.fitting(120 * 60)?.count == 4)
        #expect(Rounds.fitting(120 * 60)?.total == TimeInterval(115 * 60))
    }

    @Test func untilPresetsStayAhead() {
        #expect(UntilPreset.endOfWorkday.until(from: date(19, 14), calendar: calendar) == UntilTime(day: 0, hour: 18, minute: 0))
        #expect(UntilPreset.endOfWorkday.until(from: date(19, 19), calendar: calendar) == nil)
        #expect(UntilPreset.tonight.until(from: date(19, 23), calendar: calendar) == nil)
        let lateEvening = UntilPreset.morning.until(from: date(19, 23), calendar: calendar)
        #expect(lateEvening == UntilTime(day: 1, hour: 9, minute: 0))
        #expect(lateEvening.map(UntilPreset.morning.title) == "Tomorrow morning")
        // After midnight the next morning is this one, not the one after.
        let smallHours = UntilPreset.morning.until(from: date(20, 1, 30), calendar: calendar)
        #expect(smallHours == UntilTime(day: 0, hour: 9, minute: 0))
        #expect(smallHours.map(UntilPreset.morning.title) == "This morning")
    }

    @Test func lengthsEndWhereTheySay() {
        #expect(BlockLength.minutes(90).end(from: date(19, 10), calendar: calendar) == date(19, 11, 30))
        #expect(BlockLength.until(UntilTime(day: 1, hour: 9, minute: 0)).end(from: date(19, 22), calendar: calendar) == date(20, 9))
        #expect(BlockLength.minutes(90).title == "1 hour 30 minutes")
        #expect(BlockLength.minutes(25).short == "25m")
    }

    @Test func runningBlocksOnlyGetStricter() {
        var session = Session(work, startedAt: date(19, 10), endsAt: date(19, 12), earlyExit: .wait10, otherBrowsersInstalled: false)
        session.extend(by: 30 * 60)
        #expect(session.endsAt == date(19, 12, 30))
        session.extend(by: -600)
        #expect(session.endsAt == date(19, 12, 30))
        let tightened = session.add(site: "news.ycombinator.com")
        #expect(tightened)
        #expect(session.sites.contains("news.ycombinator.com"))
        session.add(site: "m.youtube.com/shorts")
        #expect(session.sites.filter { $0.contains("youtube") }.count == 1)

        var rounds = Session(work, startedAt: date(19, 10), endsAt: date(19, 11, 55), earlyExit: .wait10,
                             rounds: Rounds.fitting(120 * 60), otherBrowsersInstalled: false)
        rounds.extend(by: 30 * 60)
        #expect(rounds.rounds?.count == 5)
        #expect(rounds.endsAt == date(19, 12, 25))
    }

    @Test func todayCountsOverlapsOnce() {
        let history = [
            BlockRecord(startedAt: date(19, 9), endedAt: date(19, 11), name: "Work", color: .sea, attempts: 2, endedEarly: false),
            BlockRecord(startedAt: date(19, 10), endedAt: date(19, 12), name: "Video", color: .coral, attempts: 1, endedEarly: false),
            BlockRecord(startedAt: date(18, 22), endedAt: date(19, 1), name: "Night", color: .violet, attempts: 0, endedEarly: false),
            BlockRecord(startedAt: date(17, 20), endedAt: date(17, 21), name: "Evening", color: nil, attempts: 4, endedEarly: true),
        ]
        let stats = DayStats(day: date(19, 15), now: date(19, 15), history: history, running: [], calendar: calendar)
        #expect(stats.locked == 4 * 3600)  // 00:00–01:00 and 09:00–12:00
        #expect(stats.attempts == 3)
        #expect(stats.streak == 3)  // the 17th, 18th and 19th
    }

    @Test func timelineCarriesNightsOver() {
        let listID = UUID()
        let night = Schedule(listID: listID, days: [1], start: TimeOfDay(hour: 22, minute: 0), end: TimeOfDay(hour: 6, minute: 0))
        // Sunday the 18th at 22:00 runs into Monday the 19th until 06:00.
        let monday = Timeline.stretches(on: date(19, 12), schedules: [night], colors: [listID: .violet], running: [], calendar: calendar)
        #expect(monday.count == 1)
        #expect(monday.first?.from == 0)
        #expect(monday.first?.to == 0.25)
        #expect(monday.first?.color == .violet)
        #expect(Timeline.weekCells(night).map(\.column) == [6, 0])
        let next = Timeline.nextStart(after: date(19, 12), schedules: [night], calendar: calendar)
        #expect(next?.0 == date(25, 22))
    }

    @Test func schedulesSummariseShortly() {
        let schedule = Schedule(days: [2, 3, 4, 5, 6], start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 12, minute: 30))
        #expect(schedule.shortSummary == "Mon–Fri 9–12:30")
    }
}
