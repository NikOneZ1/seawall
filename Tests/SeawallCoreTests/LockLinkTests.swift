import Foundation
import Testing
@testable import SeawallCore

struct LockLinkTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func link(_ string: String) -> LockLink? { LockLink(URL(string: string)!) }

    @Test func readsListAndLength() {
        let work = link("seawall://lock?list=Work&for=2h")
        #expect(work?.list == "Work")
        #expect(work?.end(from: now) == now + 7200)
        #expect(link("seawall://lock?for=45m")?.duration == 2700)
        #expect(link("seawall://lock?for=1h30m")?.duration == 5400)
        #expect(link("seawall://lock?for=90")?.duration == 5400)
        #expect(link("seawall://lock")?.end(from: now) == nil)
    }

    @Test func untilIsTheNextTimeItComesAround() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 20))!
        let six = try #require(link("seawall://lock?until=18:00"))
        #expect(six.end(from: morning, calendar: calendar) == calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 18)))
        // Past 18:00 already: tomorrow's, but no more than 12 hours away.
        #expect(six.end(from: evening, calendar: calendar) == evening + LockLink.longest)
    }

    @Test func refusesWhatIsntALockLink() {
        #expect(link("https://lock?list=Work") == nil)
        #expect(link("seawall://unlock") == nil)
        #expect(link("seawall://lock?for=forever") == nil)
        #expect(link("seawall://lock?until=25:00") == nil)
    }

    @Test func neverLocksLongerThanTwelveHours() {
        #expect(link("seawall://lock?for=100h")?.end(from: now) == now + LockLink.longest)
    }
}
