import Foundation

/// The first launch, as a few steps: pick what pulls you in, let Seawall see browser tabs,
/// choose how hard leaving early is, then start the first block.
public enum Welcome {
    public enum Step: Int, CaseIterable, Sendable {
        case pick, browsers, leaving, start

        public var next: Step? { Step(rawValue: rawValue + 1) }
        public var previous: Step? { Step(rawValue: rawValue - 1) }
        public var isLast: Bool { next == nil }
    }

    /// Shown once, on its own, and never over a block restored from disk: a block running
    /// means Seawall has been set up already, and the watchdog's relaunches must stay invisible.
    public static func showsAtLaunch(seen: Bool, blocksRunning: Bool) -> Bool {
        !seen && !blocksRunning
    }
}

/// One tile on the welcome's first screen: a site (X is both of its addresses), a category, or
/// an app found on this Mac.
public struct StarterItem: Hashable, Identifiable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Site rules in their normal form; the first one names the tile.
        case sites([String])
        case group(SiteGroup)
        case app(ListApp)
    }

    public let kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public static func site(_ patterns: String...) -> StarterItem {
        StarterItem(.sites(patterns))
    }

    public var id: String {
        switch kind {
        case .sites(let patterns): "site:\(patterns.first ?? "")"
        case .group(let group): "group:\(group.rawValue)"
        case .app(let app): "app:\(app.bundleID)"
        }
    }

    /// Whether the list holds this, switched on. A site with two addresses counts when either is on.
    func isOn(in list: BlockList) -> Bool {
        switch kind {
        case .sites(let patterns):
            patterns.contains { pattern in list.sites.contains { $0.isOn && Self.same($0.value, pattern) } }
        case .group(let group):
            list.groups.contains { $0.isOn && $0.value == group }
        case .app(let app):
            list.apps.contains { $0.isOn && $0.bundleID == app.bundleID }
        }
    }

    /// Ticks or unticks this in the list, adding it only when it's switched on and missing.
    func set(_ on: Bool, in list: inout BlockList) {
        switch kind {
        case .sites(let patterns):
            for pattern in patterns {
                let normal = SiteRule(pattern)?.description ?? pattern
                list.sites.set(on, where: { Self.same($0.value, normal) }) { Toggled(normal) }
            }
        case .group(let group):
            list.groups.set(on, where: { $0.value == group }) { Toggled(group) }
        case .app(let app):
            var app = app
            app.isOn = true
            list.apps.set(on, where: { $0.bundleID == app.bundleID }) { app }
        }
    }

    /// The same rule however it was typed: "www.Reddit.com/" is reddit.com.
    private static func same(_ a: String, _ b: String) -> Bool {
        guard let left = SiteRule(a), let right = SiteRule(b) else { return a == b }
        return left == right
    }
}

/// What the welcome offers, and how the picks land in a list.
public enum Starter {
    /// Ticked on a fresh install, and what the first list holds before anyone touches it.
    public static let suggested: [StarterItem] = [
        .site("youtube.com/shorts"), .site("x.com", "twitter.com"), .site("reddit.com"), .site("instagram.com"),
    ]

    /// More sites on offer, after the suggested ones.
    public static let moreSites: [StarterItem] = [
        .site("tiktok.com"), .site("twitch.tv"), .site("youtube.com"), .site("netflix.com"),
        .site("facebook.com"), .site("news.ycombinator.com"),
    ]

    public static let groups: [SiteGroup] = [.social, .video, .games, .news, .shopping]

    /// Apps people often lock. The welcome offers the ones installed here.
    public static let appBundleIDs = [
        "com.valvesoftware.steam", "com.hnc.Discord", "ru.keepcoder.Telegram", "com.tinyspeck.slackmacgap",
        "net.whatsapp.WhatsApp", "com.epicgames.EpicGamesLauncher", "com.spotify.client",
    ]

    /// Every tile, in order: suggested sites, more sites, categories, then installed apps.
    public static func items(apps: [ListApp] = []) -> [StarterItem] {
        suggested + moreSites + groups.map { StarterItem(.group($0)) } + apps.map { StarterItem(.app($0)) }
    }

    /// The suggested sites as list items, for a fresh first list.
    public static var suggestedSites: [Toggled<String>] {
        suggested.flatMap { item -> [String] in
            if case .sites(let patterns) = item.kind { return patterns }
            return []
        }
        .map { Toggled($0) }
    }

    /// The tiles that are on in the list, by id.
    public static func picked(in list: BlockList, from items: [StarterItem]) -> Set<String> {
        Set(items.filter { $0.isOn(in: list) }.map(\.id))
    }

    /// Applies only what changed on the welcome's screen: a tile ticked there is added or switched
    /// on, a tile unticked there is switched off, never removed. Tiles left as they were, and
    /// everything else in the list, stay exactly as they are, so seeing the welcome again can't
    /// undo a list built since.
    public static func apply(from before: Set<String>, to after: Set<String>, offered items: [StarterItem],
                             to list: inout BlockList) {
        for item in items where before.contains(item.id) != after.contains(item.id) {
            item.set(after.contains(item.id), in: &list)
        }
    }

    /// The list as it would be with these picks, to tell whether it would lock anything.
    public static func applying(from before: Set<String>, to after: Set<String>, offered items: [StarterItem],
                                to list: BlockList) -> BlockList {
        var list = list
        apply(from: before, to: after, offered: items, to: &list)
        return list
    }
}

private protocol Switchable {
    var isOn: Bool { get set }
}

extension Toggled: Switchable {}
extension ListApp: Switchable {}

private extension Array where Element: Switchable {
    /// Ticks or unticks every matching item (there should be one), adding one only when it's
    /// switched on and missing.
    mutating func set(_ on: Bool, where matches: (Element) -> Bool, make: () -> Element) {
        let found = indices.filter { matches(self[$0]) }
        for index in found { self[index].isOn = on }
        if found.isEmpty, on { append(make()) }
    }
}
