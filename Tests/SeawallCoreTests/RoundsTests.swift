import Foundation
import Testing
@testable import SeawallCore

struct RoundsTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func session() -> Session {
        Session(startedAt: start, endsAt: start + Rounds.standard.total, sites: ["twitch.tv"], apps: [],
                blocksOtherBrowsers: false, rounds: .standard)
    }

    @Test func fourRoundsOfTwentyFiveWithThreeBreaks() {
        #expect(Rounds.standard.total == 115 * 60)
        #expect(BlockDuration.rounds.endDate(from: start, until: UntilTime(day: 0, hour: 18, minute: 0)) == start + 115 * 60)
    }

    @Test func phasesFollowTheClock() {
        let s = session()
        #expect(s.phase(at: start) == .locked(round: 1, endsAt: start + 25 * 60))
        #expect(s.phase(at: start + 25 * 60) == .resting(nextRound: 2, until: start + 30 * 60))
        #expect(s.phase(at: start + 30 * 60) == .locked(round: 2, endsAt: start + 55 * 60))
        #expect(s.phase(at: start + 112 * 60) == .locked(round: 4, endsAt: start + 115 * 60))
        #expect(s.isHolding(at: start + 10 * 60))
        #expect(!s.isHolding(at: start + 27 * 60))
    }

    @Test func aBlockInOneStretchHasNoPhases() {
        let s = Session(startedAt: start, endsAt: start + 3600, sites: [], apps: [], blocksOtherBrowsers: false)
        #expect(s.phase(at: start) == nil)
        #expect(s.isHolding(at: start + 100))
    }

    @Test func roundsKeepTheirLengthWhenTheClockJumps() {
        var s = session()
        s.absorbClockJump(3600)
        #expect(s.phase(at: start + 3600 + 26 * 60) == .resting(nextRound: 2, until: start + 3600 + 30 * 60))
    }
}
