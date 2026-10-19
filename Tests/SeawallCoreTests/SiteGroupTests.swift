import Foundation
import Testing
@testable import SeawallCore

struct SiteGroupTests {
    @Test(arguments: SiteGroup.allCases.filter { $0 != .web })
    func everySiteIsAValidRule(_ group: SiteGroup) {
        #expect(!group.sites.isEmpty)
        for site in group.sites {
            #expect(SiteRule(site) != nil, "\(group.title): \(site)")
        }
    }

    @Test func gamesAreFoundByCategoryFolderOrLauncher() {
        #expect(SiteGroup.isGame(bundleID: "com.example.chess", category: "public.app-category.games", path: nil))
        #expect(SiteGroup.isGame(bundleID: "com.example.doom", category: "public.app-category.action-games", path: nil))
        #expect(SiteGroup.isGame(bundleID: "com.valvesoftware.steam", category: nil, path: nil))
        #expect(SiteGroup.isGame(
            bundleID: "unity.Studio.Game", category: nil,
            path: "/Users/me/Library/Application Support/Steam/steamapps/common/Game/Game.app"))
        #expect(!SiteGroup.isGame(bundleID: "com.apple.Safari", category: "public.app-category.productivity", path: "/Applications/Safari.app"))
        #expect(!SiteGroup.isGame(bundleID: "com.example.notes", category: nil, path: "/Applications/Notes.app"))
    }

    @Test func groupSitesJoinTheBlock() throws {
        let rule = try #require(SiteRule("instagram.com"))
        let session = Session(startedAt: Date(), endsAt: Date() + 60, sites: ["twitch.tv"], apps: [],
                              blocksOtherBrowsers: false, groups: [.social, .games])
        #expect(session.allSites.contains("twitch.tv"))
        #expect(session.allSites.contains(rule.description))
        #expect(session.blocksGames)
        #expect(session.names.hasPrefix("Social, Games, Twitch"))
    }

    @Test func blocksSavedBeforeGroupsStillLoad() throws {
        let json = """
            [{"startedAt": 800000000, "endsAt": 800003600, "sites": ["twitch.tv"], "apps": [],
              "blocksOtherBrowsers": true, "siteAttempts": 2, "appAttempts": 0}]
            """
        let sessions = try JSONDecoder().decode([Session].self, from: Data(json.utf8))
        #expect(sessions.first?.groups == [])
        #expect(sessions.first?.siteAttempts == 2)
        #expect(sessions.first?.blocksGames == false)
    }
}
