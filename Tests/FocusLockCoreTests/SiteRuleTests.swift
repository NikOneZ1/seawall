import Foundation
import Testing
@testable import FocusLockCore

struct SiteRuleTests {
    @Test func normalizesPastedInput() throws {
        let rule = try #require(SiteRule("  HTTPS://www.YouTube.com/Shorts/?feature=share "))
        #expect(rule.host == "youtube.com")
        #expect(rule.path == "/shorts")
        #expect(rule.description == "youtube.com/shorts")
    }

    @Test(arguments: ["", "   ", "youtube", "you tube.com", ".com", "twitch.", "a..b", "https://", "localhost:8080"])
    func rejectsGarbage(_ pattern: String) {
        #expect(SiteRule(pattern) == nil)
    }

    @Test func sectionRuleBlocksOnlyThatSection() throws {
        let rule = try #require(SiteRule("youtube.com/shorts"))
        #expect(rule.matches(url("https://www.youtube.com/shorts/abc123")))
        #expect(rule.matches(url("https://m.youtube.com/shorts")))
        #expect(rule.matches(url("https://youtube.com/Shorts/abc?feature=share")))
        #expect(!rule.matches(url("https://www.youtube.com/watch?v=dQw4w9WgXcQ")))
        #expect(!rule.matches(url("https://www.youtube.com/")))
        #expect(!rule.matches(url("https://www.youtube.com/shortsale")))
        #expect(!rule.matches(url("https://notyoutube.com/shorts/abc")))
    }

    @Test func domainRuleCoversSubdomains() throws {
        let rule = try #require(SiteRule("twitch.tv"))
        #expect(rule.matches(url("https://www.twitch.tv/xqc")))
        #expect(rule.matches(url("https://clips.twitch.tv/abc")))
        #expect(rule.matches(url("http://twitch.tv")))
        #expect(!rule.matches(url("https://nottwitch.tv/")))
        #expect(!rule.matches(url("https://twitch.tv.example.com/")))
    }

    @Test func separateSitesNeedTheirOwnRule() throws {
        let youtube = try #require(SiteRule("youtube.com"))
        let music = try #require(SiteRule("music.youtube.com"))
        #expect(!youtube.matches(url("https://music.youtube.com/watch?v=abc")))
        #expect(!youtube.covers(music))
        #expect(youtube.matches(url("https://www.youtube.com/watch?v=abc")))
        #expect(music.matches(url("https://music.youtube.com/watch?v=abc")))
        #expect(!music.matches(url("https://www.youtube.com/")))
        #expect(music.covers(try #require(SiteRule("music.youtube.com/library"))))
    }

    @Test func ignoresNonWebURLs() throws {
        let rule = try #require(SiteRule("twitch.tv"))
        #expect(!rule.matches(url("file:///Users/me/twitch.tv")))
        #expect(!rule.matches(url("about:blank")))
    }

    @Test func wholeSiteCoversItsSections() throws {
        let youtube = try #require(SiteRule("youtube.com"))
        let shorts = try #require(SiteRule("youtube.com/shorts"))
        #expect(youtube.covers(shorts))
        #expect(youtube.covers(try #require(SiteRule("m.youtube.com/shorts"))))
        #expect(shorts.covers(shorts))
        #expect(!shorts.covers(youtube))
        #expect(!shorts.covers(try #require(SiteRule("youtube.com/shortsale"))))
        #expect(!youtube.covers(try #require(SiteRule("notyoutube.com"))))
    }

    @Test(arguments: [
        ("youtube.com/shorts", "YouTube Shorts"), ("twitch.tv", "Twitch"), ("m.youtube.com", "YouTube"),
        ("music.youtube.com", "YouTube Music"),
        ("news.ycombinator.com", "Hacker News"), ("example.org", "Example"), ("bbc.co.uk", "Bbc"),
        ("reddit.com/r/funny", "Reddit Funny"),
    ])
    func displayNames(_ pattern: String, _ expected: String) throws {
        #expect(try #require(SiteRule(pattern)).displayName == expected)
    }

    private func url(_ string: String) -> URL { URL(string: string)! }
}
