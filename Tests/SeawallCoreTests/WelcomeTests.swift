import Foundation
import Testing
@testable import SeawallCore

struct WelcomeTests {
    let steam = ListApp(bundleID: "com.valvesoftware.steam", name: "Steam", path: "/Applications/Steam.app")

    /// Kept, not made anew each time: a list's id is part of what makes two lists equal.
    let fresh = BlockList(name: "Distractions", sites: Starter.suggestedSites)

    @Test func showsOnceAndNeverOverABlock() {
        #expect(Welcome.showsAtLaunch(seen: false, blocksRunning: false))
        #expect(!Welcome.showsAtLaunch(seen: true, blocksRunning: false))
        // A watchdog relaunch, or a block restored after the preferences were reset.
        #expect(!Welcome.showsAtLaunch(seen: false, blocksRunning: true))
        #expect(!Welcome.showsAtLaunch(seen: true, blocksRunning: true))
    }

    @Test func stepsRunInOrder() {
        #expect(Welcome.Step.allCases == [.pick, .browsers, .leaving, .start])
        #expect(Welcome.Step.pick.previous == nil)
        #expect(Welcome.Step.pick.next == .browsers)
        #expect(Welcome.Step.start.next == nil)
        #expect(Welcome.Step.start.isLast)
        #expect(!Welcome.Step.leaving.isLast)
    }

    @Test func suggestsTheFourUsualSuspects() {
        #expect(Starter.suggestedSites.map(\.value) == ["youtube.com/shorts", "x.com", "twitter.com", "reddit.com", "instagram.com"])
        #expect(Starter.suggestedSites.allSatisfy(\.isOn))
        for item in Starter.items() {
            if case .sites(let patterns) = item.kind {
                for pattern in patterns {
                    // Already in normal form, so they match what the list editor stores.
                    #expect(SiteRule(pattern)?.description == pattern, "\(pattern)")
                }
            }
        }
        let ids = Starter.items(apps: [steam]).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func aFreshListShowsTheSuggestionsTicked() {
        let picked = Starter.picked(in: fresh, from: Starter.items())
        #expect(picked == Set(Starter.suggested.map(\.id)))
    }

    @Test func untouchedPicksLeaveTheListAlone() {
        var list = fresh
        let picked = Starter.picked(in: list, from: Starter.items())
        Starter.apply(from: picked, to: picked, offered: Starter.items(), to: &list)
        #expect(list == fresh)
    }

    @Test func tickingAddsOnceAndUntickingKeepsTheItem() {
        let items = Starter.items(apps: [steam])
        var list = fresh
        let before = Starter.picked(in: list, from: items)
        var after = before
        after.insert("site:twitch.tv")
        after.insert("group:games")
        after.insert("app:com.valvesoftware.steam")
        after.remove("site:x.com")
        Starter.apply(from: before, to: after, offered: items, to: &list)

        #expect(list.sites.first { $0.value == "twitch.tv" }?.isOn == true)
        #expect(list.groups.map(\.value) == [.games])
        #expect(list.apps.map(\.bundleID) == ["com.valvesoftware.steam"])
        // X is both of its addresses: off, but still in the list to tick again.
        #expect(list.sites.filter { $0.value == "x.com" || $0.value == "twitter.com" }.map(\.isOn) == [false, false])
        #expect(list.sites.count == Starter.suggestedSites.count + 1)

        // Seen again: what's on shows ticked, and ticking X back on adds nothing new.
        let again = Starter.picked(in: list, from: items)
        #expect(!again.contains("site:x.com"))
        var on = again
        on.insert("site:x.com")
        Starter.apply(from: again, to: on, offered: items, to: &list)
        #expect(list.sites.count == Starter.suggestedSites.count + 1)
        #expect(list.sites.filter { $0.value == "x.com" || $0.value == "twitter.com" }.allSatisfy(\.isOn))
    }

    @Test func mergesIntoAListBuiltSince() {
        // Someone's own list: Reddit typed in by hand, unticked; their own sites and an app.
        var list = BlockList(name: "Work", sites: [Toggled("www.Reddit.com/", isOn: false), Toggled("news.ycombinator.com"),
                                                   Toggled("example.com")],
                             apps: [ListApp(bundleID: "com.hnc.Discord", name: "Discord", path: "/Applications/Discord.app")])
        let original = list
        let items = Starter.items()
        let before = Starter.picked(in: list, from: items)
        #expect(before == ["site:news.ycombinator.com"])

        var after = before
        after.insert("site:reddit.com")
        after.insert("site:instagram.com")
        Starter.apply(from: before, to: after, offered: items, to: &list)

        // Reddit is ticked where it is rather than added twice; Instagram is new.
        #expect(list.sites.count == original.sites.count + 1)
        #expect(list.sites[0].isOn)
        #expect(list.sites.last == Toggled("instagram.com"))
        // Nothing the welcome doesn't offer changed.
        #expect(list.sites.contains(Toggled("example.com")))
        #expect(list.apps == original.apps)
        #expect(list.name == "Work")
    }

    @Test func tickingAnAppKeepsItsDetails() {
        var list = BlockList(name: "Games", apps: [ListApp(bundleID: steam.bundleID, name: "Steam", path: "/Games/Steam.app", isOn: false)])
        let items = Starter.items(apps: [steam])
        let before = Starter.picked(in: list, from: items)
        #expect(before.isEmpty)
        Starter.apply(from: before, to: ["app:\(steam.bundleID)"], offered: items, to: &list)
        #expect(list.apps.count == 1)
        #expect(list.apps[0].isOn)
        #expect(list.apps[0].path == "/Games/Steam.app")
    }

    @Test func applyingTellsWhetherAnythingIsLeft() {
        let items = Starter.items()
        let before = Starter.picked(in: fresh, from: items)
        let none = Starter.applying(from: before, to: [], offered: items, to: fresh)
        #expect(none.isEmpty(otherBrowsersInstalled: false))
        #expect(none.sites.count == Starter.suggestedSites.count)
        let one = Starter.applying(from: before, to: ["site:reddit.com"], offered: items, to: fresh)
        #expect(!one.isEmpty(otherBrowsersInstalled: false))
        #expect(one.enabledSites == ["reddit.com"])
    }
}
