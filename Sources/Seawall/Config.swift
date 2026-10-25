import Foundation
import SeawallCore

/// Lists, schedules and the next block's choices, saved as config.json. Running blocks keep
/// their own copy of what they cover, so editing this never loosens them.
struct Config: Codable, Equatable {
    static let currentVersion = 2

    var version = Config.currentVersion
    /// Every block starts from one of these. Never empty.
    var lists: [BlockList]
    /// Blocks that start on their own, each locking one of the lists.
    var schedules: [Schedule] = []
    /// What the menu has picked for the next block.
    var next: NextBlock

    static var initial: Config {
        let list = BlockList(name: "Distractions", symbol: "water.waves", color: .sea,
                             sites: ["youtube.com/shorts", "twitch.tv", "tiktok.com"].map { Toggled($0) })
        return Config(lists: [list], next: NextBlock(listID: list.id, length: .minutes(60)))
    }

    func list(_ id: UUID?) -> BlockList? {
        lists.first { $0.id == id }
    }

    /// The list the menu has picked, or the first one.
    var selectedList: BlockList? {
        list(next.listID) ?? lists.first
    }

    /// A list name that isn't taken: "New list", "New list 2"…
    func freeName(_ base: String) -> String {
        guard lists.contains(where: { $0.name == base }) else { return base }
        var n = 2
        while lists.contains(where: { $0.name == "\(base) \(n)" }) { n += 1 }
        return "\(base) \(n)"
    }

    /// Reads either format: version 2, or the single-menu config of earlier versions, moved over.
    static func decode(_ data: Data) -> (config: Config, migrated: Bool)? {
        let decoder = JSONDecoder()
        if let probe = try? decoder.decode(VersionProbe.self, from: data), probe.version == currentVersion {
            return (try? decoder.decode(Config.self, from: data)).map { ($0, false) }
        }
        guard let legacy = try? decoder.decode(LegacyConfig.self, from: data) else { return nil }
        return (Config(migrating: legacy), true)
    }

    private struct VersionProbe: Decodable {
        var version: Int?
    }
}

// MARK: - Moving over from the single menu

extension Config {
    /// Earlier versions had one menu of chips, each on or off, plus saved lists of them.
    /// Every saved list becomes a list; so does the menu's own selection, unless it's exactly
    /// one of them. Whole web becomes the list's mode, keeping its allowed sites.
    init(migrating old: LegacyConfig) {
        var lists: [BlockList] = []
        let colors = ListColor.allCases

        for (index, saved) in old.lists.enumerated() {
            var list = BlockList(name: saved.name, symbol: Self.symbol(for: saved.name), color: colors[(index + 1) % colors.count])
            list.mode = saved.groups.contains(.web) ? .allExcept : .only
            list.groups = saved.groups.filter { $0 != .web }.map { Toggled($0) }
            list.sites = saved.sites.map { Toggled($0) }
            list.apps = saved.apps.compactMap { id in
                old.apps.first { $0.bundleID == id }.map { ListApp(bundleID: $0.bundleID, name: $0.name, path: $0.path) }
            }
            list.allowed = old.allowedSites
            list.otherBrowsers = saved.otherBrowsers
            lists.append(list)
        }

        let current = old.currentList
        var selected = current.flatMap { saved in lists.first { $0.name == saved.name }?.id }
        if current == nil {
            var mine = BlockList(name: lists.isEmpty ? "Distractions" : "My list", symbol: "water.waves", color: .sea)
            mine.mode = old.groups.contains { $0.group == .web && $0.enabled } ? .allExcept : .only
            mine.groups = old.groups.filter { $0.group != .web }.map { Toggled($0.group, isOn: $0.enabled) }
            mine.sites = old.sites.map { Toggled($0.pattern, isOn: $0.enabled) }
            mine.apps = old.apps.map { ListApp(bundleID: $0.bundleID, name: $0.name, path: $0.path, isOn: $0.enabled) }
            mine.allowed = old.allowedSites
            mine.otherBrowsers = old.blockOtherBrowsers
            lists.insert(mine, at: 0)
            selected = mine.id
        }

        var schedules = old.schedules
        for index in schedules.indices where schedules[index].listID == nil {
            let name = schedules[index].listName
            schedules[index].listID = lists.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
        }

        let length: BlockLength
        switch old.duration {
        case .untilTime: length = .until(old.until)
        case .rounds: length = .minutes(120)
        default: length = .minutes(Int((old.duration.interval ?? 3600) / 60))
        }
        self.init(lists: lists, schedules: schedules,
                  next: NextBlock(listID: selected ?? lists.first?.id, length: length, breaks: old.duration == .rounds))
    }

    /// A first guess at a symbol for a list moved over from a name alone.
    static func symbol(for name: String) -> String {
        let name = name.lowercased()
        if name.contains("work") || name.contains("job") { return "briefcase.fill" }
        if name.contains("evening") || name.contains("night") || name.contains("sleep") { return "moon.fill" }
        if name.contains("study") || name.contains("read") { return "book.fill" }
        if name.contains("deep") || name.contains("focus") { return "water.waves" }
        return "lock.fill"
    }
}

/// config.json as versions before lists wrote it. Only read, to move over.
struct LegacyConfig: Decodable {
    struct SiteItem: Decodable {
        var pattern: String
        var enabled = true
    }

    struct GroupItem: Decodable {
        var group: SiteGroup
        var enabled = true
    }

    struct AppItem: Decodable {
        var bundleID: String
        var name: String
        var path: String
        var enabled = true
    }

    struct SavedList: Decodable {
        var name: String
        var groups: [SiteGroup]
        var sites: [String]
        var apps: [String]
        var otherBrowsers: Bool
    }

    var groups: [GroupItem] = []
    var sites: [SiteItem]
    var allowedSites: [String] = []
    var lists: [SavedList] = []
    var schedules: [Schedule] = []
    var apps: [AppItem]
    var blockOtherBrowsers: Bool
    var duration: BlockDuration
    var until: UntilTime

    private enum CodingKeys: String, CodingKey {
        case groups, sites, allowedSites, lists, schedules, apps, blockOtherBrowsers, duration, until, untilTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groups = try c.decodeIfPresent([GroupItem].self, forKey: .groups) ?? []
        sites = try c.decode([SiteItem].self, forKey: .sites)
        allowedSites = try c.decodeIfPresent([String].self, forKey: .allowedSites) ?? []
        lists = try c.decodeIfPresent([SavedList].self, forKey: .lists) ?? []
        schedules = try c.decodeIfPresent([Schedule].self, forKey: .schedules) ?? []
        apps = try c.decode([AppItem].self, forKey: .apps)
        blockOtherBrowsers = try c.decode(Bool.self, forKey: .blockOtherBrowsers)
        duration = try c.decode(BlockDuration.self, forKey: .duration)
        if let until = try c.decodeIfPresent(UntilTime.self, forKey: .until) {
            self.until = until
        } else if let time = try c.decodeIfPresent(Date.self, forKey: .untilTime) {
            // Before "Until…" had a day it was only a time of day.
            let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
            let minute = parts.minute ?? 0
            until = UntilTime(day: 0, hour: parts.hour ?? 18, minute: minute - minute % UntilTime.minuteStep)
        } else {
            until = UntilTime(day: 0, hour: 18, minute: 0)
        }
    }

    /// The saved list that matches what was switched on, if any.
    var currentList: SavedList? {
        let groups = Set(self.groups.filter(\.enabled).map(\.group))
        let sites = Set(self.sites.filter(\.enabled).map(\.pattern))
        let apps = Set(self.apps.filter(\.enabled).map(\.bundleID))
        return lists.first { list in
            Set(list.groups) == groups && Set(list.sites) == sites && Set(list.apps) == apps && list.otherBrowsers == blockOtherBrowsers
        }
    }
}

/// Something picked up from the sand on the block page. The Today page keeps them.
struct Find: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case scallop, glass, stone, dollar, snail, star

        var title: String {
            switch self {
            case .scallop: "Scallop shell"
            case .glass: "Sea glass"
            case .stone: "Smooth stone"
            case .dollar: "Sand dollar"
            case .snail: "Snail shell"
            case .star: "Starfish"
            }
        }
    }

    var kind: Kind
    var foundAt: Date
}
