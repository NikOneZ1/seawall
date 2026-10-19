import Foundation
import Testing
@testable import SeawallCore

struct WebFilterTests {
    func session(sites: [String] = [], groups: [SiteGroup] = [], allowed: [String] = []) -> Session {
        Session(startedAt: Date(), endsAt: Date() + 60, sites: sites, apps: [], blocksOtherBrowsers: false,
                groups: groups, allowedSites: allowed)
    }

    func url(_ string: String) -> URL { URL(string: string)! }

    @Test func sitesOnly() {
        let filter = WebFilter(session(sites: ["twitch.tv"]))
        #expect(filter.blocks(url("https://www.twitch.tv/somebody")))
        #expect(!filter.blocks(url("https://github.com")))
        #expect(!filter.isEmpty)
    }

    @Test func wholeWebBlocksEverythingButTheAllowedSites() {
        let filter = WebFilter(session(groups: [.web], allowed: ["docs.google.com", "github.com"]))
        #expect(filter.blocks(url("https://www.google.com/search?q=x")))
        #expect(filter.blocks(url("http://example.org")))
        #expect(!filter.blocks(url("https://docs.google.com/document/d/1")))
        #expect(!filter.blocks(url("https://gist.github.com/x")))
    }

    @Test func pagesOnThisMacAreNeverBlocked() {
        let filter = WebFilter(session(sites: ["127.0.0.1"], groups: [.web]))
        #expect(!filter.blocks(url("http://127.0.0.1:47321/?until=1&n=1&url=x")))
        #expect(!filter.blocks(url("http://localhost:3000")))
        #expect(!filter.blocks(url("http://printer.local")))
        #expect(!filter.blocks(url("file:///Users/me/index.html")))
        #expect(!filter.blocks(url("about:blank")))
    }

    @Test func allowedSitesWinOverBlockedOnes() {
        let filter = WebFilter(session(sites: ["google.com"], allowed: ["docs.google.com"]))
        #expect(filter.blocks(url("https://google.com")))
        #expect(!filter.blocks(url("https://docs.google.com")))
    }

    @Test func wholeWebClosesBrowsersThatCantBeRead() {
        #expect(session(groups: [.web]).blockedBundleIDs.contains("org.mozilla.firefox"))
        #expect(!session(groups: [.social]).blockedBundleIDs.contains("org.mozilla.firefox"))
    }
}
