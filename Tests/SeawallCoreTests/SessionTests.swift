import Foundation
import Testing
@testable import SeawallCore

struct SessionTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func makeSession(hours: Double = 2) -> Session {
        Session(startedAt: start, endsAt: start + hours * 3600, sites: ["twitch.tv"], apps: [], blocksOtherBrowsers: false)
    }

    @Test func unlockNeedsTenMinutesOfWaiting() {
        var session = makeSession()
        #expect(session.unlockState(at: start) == .locked)

        session.unlockRequestedAt = start
        #expect(session.unlockState(at: start) == .waiting(remaining: 600))
        #expect(session.unlockState(at: start + 599) == .waiting(remaining: 1))
        #expect(session.unlockState(at: start + 600) == .ready(expiresIn: 120))
        #expect(session.unlockState(at: start + 719) == .ready(expiresIn: 1))
        #expect(session.unlockState(at: start + 720) == .locked)
    }

    @Test func onlyTheOpenWindowIsReady() {
        var session = makeSession()
        session.unlockRequestedAt = start
        #expect(!session.unlockState(at: start + 599).isReady)
        #expect(session.unlockState(at: start + 600).isReady)
        #expect(!session.unlockState(at: start + 720).isReady)
    }

    @Test func namesWhatItBlocks() {
        var session = makeSession()
        session.sites = ["youtube.com/shorts", "twitch.tv"]
        session.apps = [BlockedApp(bundleID: "com.valvesoftware.steam", name: "Steam")]
        session.blocksOtherBrowsers = true
        #expect(session.names == "YouTube Shorts, Twitch, Steam, other browsers")
    }

    @Test func unansweredUnlockExpires() {
        var session = makeSession()
        session.unlockRequestedAt = start

        session.expireUnlockRequest(at: start + 700)
        #expect(session.unlockRequestedAt == start)

        session.expireUnlockRequest(at: start + 720)
        #expect(session.unlockRequestedAt == nil)
    }

    @Test func movingClockForwardDoesNotShortenBlock() {
        var session = makeSession()
        session.unlockRequestedAt = start
        session.absorbClockJump(3 * 3600)
        #expect(session.endsAt == start + 5 * 3600)
        #expect(session.unlockRequestedAt == start + 3 * 3600)
    }

    @Test func clockDriftIsIgnored() {
        var session = makeSession()
        session.absorbClockJump(4)
        session.absorbClockJump(-12)
        #expect(session.endsAt == start + 2 * 3600)
    }

    @Test func otherBrowsersJoinTheAppList() {
        var session = makeSession()
        session.apps = [BlockedApp(bundleID: "com.valvesoftware.steam", name: "Steam")]
        #expect(session.blockedBundleIDs == ["com.valvesoftware.steam"])

        session.blocksOtherBrowsers = true
        #expect(session.blockedBundleIDs.contains("org.mozilla.firefox"))
        #expect(session.blockedBundleIDs.contains("com.valvesoftware.steam"))
        // Browsers whose tabs can be read get the block page instead of being closed.
        for browser in KnownBrowsers.readable {
            #expect(!session.blockedBundleIDs.contains(browser.bundleID))
        }
    }

    @Test func overlappingBlocksCountTheAttemptOnTheOneEndingLast() {
        let twitchTillEvening = makeSession(hours: 8)
        var everythingForAnHour = makeSession(hours: 1)
        everythingForAnHour.startedAt = start + 60
        everythingForAnHour.sites = ["twitch.tv", "youtube.com"]
        let sessions = [twitchTillEvening, everythingForAnHour]

        #expect(sessions.lastEnding { $0.sites.contains("twitch.tv") } == 0)
        #expect(sessions.lastEnding { $0.sites.contains("youtube.com") } == 1)
        #expect(sessions.lastEnding { $0.sites.contains("tiktok.com") } == nil)
        #expect(twitchTillEvening.id != everythingForAnHour.id)
    }

    @Test func clockWatchReportsOnlyTheJump() {
        var watch = ClockWatch(wall: start, real: 0)
        #expect(watch.skew(wall: start + 1, real: 1_000_000_000) == 0)
        // Clock moved forward by an hour within one real second.
        #expect(watch.skew(wall: start + 3602, real: 2_000_000_000) == 3600)
    }
}
