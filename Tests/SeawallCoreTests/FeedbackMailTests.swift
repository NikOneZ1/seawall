import Foundation
import Testing
@testable import SeawallCore

struct FeedbackMailTests {
    let info = AppInfo(version: "0.1.0", build: "1", system: "Version 14.5 (Build 23F79)", model: "Mac14,2", architecture: "arm64")

    @Test func encodesEverythingButTheUnreservedCharacters() {
        #expect(FeedbackMail.encode("a b&c=d+e#f%g?h/i") == "a%20b%26c%3Dd%2Be%23f%25g%3Fh%2Fi")
        #expect(FeedbackMail.encode("-._~AZaz09") == "-._~AZaz09")
        #expect(FeedbackMail.encode("é✓") == "%C3%A9%E2%9C%93")
        // Line breaks are CRLF in a mailto body, however they came in.
        #expect(FeedbackMail.encode("one\ntwo\r\nthree") == "one%0D%0Atwo%0D%0Athree")
    }

    @Test func linkHasTheAddressSubjectAndBody() {
        let mail = FeedbackMail(subject: "Hi & bye", body: "x=1")
        #expect(mail.link == "mailto:hello@seawall.work?subject=Hi%20%26%20bye&body=x%3D1")
        #expect(URL(string: mail.link) != nil)
    }

    @Test func subjectSaysTheVersion() {
        #expect(FeedbackMail.feedbackSubject(info) == "Seawall feedback (0.1.0, build 1)")
        #expect(FeedbackMail.crashSubject(info) == "Seawall crash report (0.1.0, build 1)")
    }

    @Test func roomToWriteComesFirst() {
        let (mail, overflow) = FeedbackMail.feedback(info, logs: ["12:00:00 notice [app] Seawall 0.1.0 (1) started"],
                                                     note: "Log since 11:30.", savedAs: "~/feedback.txt")
        #expect(overflow == nil)
        #expect(mail.fits)
        #expect(mail.body.hasPrefix(FeedbackMail.blankArea + "----\n"))
        #expect(mail.body.contains("Seawall 0.1.0 (build 1)"))
        #expect(mail.body.contains("macOS Version 14.5 (Build 23F79)"))
        #expect(mail.body.contains("Mac: Mac14,2, arm64"))
        #expect(mail.body.contains("Log since 11:30."))
        #expect(mail.body.contains("Recent log (1 line):"))
        #expect(mail.body.contains("started"))
    }

    @Test func noLogSaysSo() {
        let (mail, _) = FeedbackMail.feedback(info, logs: [], savedAs: "x")
        #expect(mail.body.contains("(nothing logged)"))
    }

    @Test func aLongLogGoesInAFileInstead() throws {
        let logs = (1...150).map { "12:00:\($0) info [app] line number \($0) of the log" }
        let (mail, overflow) = FeedbackMail.feedback(info, logs: logs, savedAs: "~/Library/Application Support/Seawall/Diagnostics/f.txt")
        let full = try #require(overflow)
        #expect(mail.fits)
        #expect(mail.link.count <= FeedbackMail.longestLink)
        #expect(mail.body.hasPrefix(FeedbackMail.blankArea))
        #expect(mail.body.contains("Seawall 0.1.0 (build 1)"))
        #expect(mail.body.contains("~/Library/Application Support/Seawall/Diagnostics/f.txt"))
        #expect(!mail.body.contains("line number"))
        #expect(full.contains("line number 150 of the log"))
        #expect(full.contains("Seawall 0.1.0 (build 1)"))
    }

    @Test func capKeepsTheNewestLines() {
        let lines = (1...300).map { "line \($0)" }
        let capped = FeedbackMail.cap(lines)
        #expect(capped.count == 200)
        #expect(capped.first == "line 101")
        #expect(capped.last == "line 300")
    }

    @Test func capKeepsUnderTheByteLimit() {
        let lines = (1...100).map { "\($0) " + String(repeating: "x", count: 200) }
        let capped = FeedbackMail.cap(lines, maxLines: 200, maxBytes: 1000)
        #expect(capped.map { $0.utf8.count + 1 }.reduce(0, +) <= 1000)
        #expect(capped.last == lines.last)
        #expect(capped.count == 4)
        // One line longer than the whole limit keeps its end.
        let one = FeedbackMail.cap([String(repeating: "a", count: 50) + "END"], maxLines: 10, maxBytes: 11)
        #expect(one == ["aaaaaaaEND"])
    }

    @Test func crashMailAsksForTheFileAndStaysShort() {
        let mail = FeedbackMail.crash(info, summary: ["Signal: 11 (SIGSEGV)", "Crashed at: 2026-10-31 14:05:12 UTC"],
                                      fileName: "seawall-crash-2026-10-31-140512.txt")
        #expect(mail.subject == "Seawall crash report (0.1.0, build 1)")
        #expect(mail.fits)
        #expect(mail.body.contains("seawall-crash-2026-10-31-140512.txt"))
        #expect(mail.body.contains("Signal: 11 (SIGSEGV)"))
        #expect(mail.body.contains("Seawall 0.1.0 (build 1)"))
    }

    @Test func aBodyTooLongIsCutUntilItFits() {
        let long = FeedbackMail(subject: "s", body: String(repeating: "ü&", count: 3000)).shortened()
        #expect(long.fits)
        #expect(!long.body.isEmpty)
        #expect(long.link.count > FeedbackMail.longestLink - 20)
    }
}

struct CrashReportTests {
    let info = AppInfo(version: "0.1.0", build: "1", system: "Version 14.5 (Build 23F79)", model: "", architecture: "arm64")

    @Test func headerHasVersionsAndLaunchTime() {
        let header = CrashReport.header(info, launchedAt: Date(timeIntervalSince1970: 1_793_449_925))
        #expect(header == """
            Seawall crash report
            Seawall 0.1.0 (build 1)
            macOS Version 14.5 (Build 23F79)
            Mac: arm64
            Launched: 2026-10-31 12:32:05 UTC

            """)
    }

    @Test func finishingMakesTheTimeReadableAndScrubs() {
        let raw = CrashReport.header(info, launchedAt: Date(timeIntervalSince1970: 0))
            + "Exception: NSInvalidArgumentException\nReason: can't open https://twitch.tv/x for Evening\n"
            + "Signal: 6 (SIGABRT)\nCrashed at: 1793449925\nStack:\n0   Seawall   0x0000000100a1c2e0 handle_crash + 120\n"
        let report = CrashReport.finish(raw, scrubber: LogScrubber(secrets: ["Evening"]))
        #expect(report.contains("Crashed at: 2026-10-31 12:32:05 UTC"))
        #expect(report.contains("Reason: can't open <url> for <list item>"))
        #expect(!report.contains("twitch"))
        #expect(report.contains("0   Seawall   0x0000000100a1c2e0 handle_crash + 120"))
        #expect(CrashReport.summary(report) == [
            "Exception: NSInvalidArgumentException", "Signal: 6 (SIGABRT)", "Crashed at: 2026-10-31 12:32:05 UTC",
        ])
    }

    @Test func fileNameIsSortableAndPlain() {
        #expect(CrashReport.fileName(Date(timeIntervalSince1970: 1_793_449_925)) == "seawall-crash-2026-10-31-123205.txt")
    }

    @Test func keepsAFewRecentReports() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reports = (0..<8).map { (name: "r\($0)", date: now - Double($0) * 3600) }
            + [(name: "old", date: now - 40 * 86_400)]
        #expect(Set(CrashReport.expired(reports, now: now)) == ["r5", "r6", "r7", "old"])
        #expect(CrashReport.expired([(name: "old", date: now - 31 * 86_400)], now: now) == ["old"])
        #expect(CrashReport.expired([], now: now).isEmpty)
    }
}
