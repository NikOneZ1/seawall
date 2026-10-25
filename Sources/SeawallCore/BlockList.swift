import Foundation

/// A named set of what to lock, like Work or Evening. Every block starts from one: the menu
/// shows them as cards, the Seawall window edits them.
public struct BlockList: Codable, Identifiable, Equatable, Sendable {
    /// Whether the list's sites are the ones blocked, or the only ones left open.
    public enum Mode: String, Codable, Sendable {
        case only, allExcept
    }

    public var id: UUID
    public var name: String
    /// An SF Symbol name, one of `BlockList.symbols`.
    public var symbol: String
    public var color: ListColor
    public var mode: Mode
    /// Categories, Games included. Whole web isn't one: it's `mode`.
    public var groups: [Toggled<SiteGroup>]
    /// Site rules in their normal form ("youtube.com/shorts").
    public var sites: [Toggled<String>]
    public var apps: [ListApp]
    /// Sites left open while `mode` is `.allExcept`.
    public var allowed: [String]
    /// Close the browsers Seawall can't look into.
    public var otherBrowsers: Bool

    public init(id: UUID = UUID(), name: String, symbol: String = "lock.fill", color: ListColor = .sea, mode: Mode = .only,
                groups: [Toggled<SiteGroup>] = [], sites: [Toggled<String>] = [], apps: [ListApp] = [],
                allowed: [String] = [], otherBrowsers: Bool = true) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.color = color
        self.mode = mode
        self.groups = groups
        self.sites = sites
        self.apps = apps
        self.allowed = allowed
        self.otherBrowsers = otherBrowsers
    }

    /// Symbols a list can wear, picked in the list editor.
    public static let symbols = [
        "briefcase.fill", "moon.fill", "water.waves", "book.fill", "graduationcap.fill", "laptopcomputer",
        "pencil", "paintbrush.fill", "music.note", "dumbbell.fill", "sun.max.fill", "leaf.fill",
        "cup.and.saucer.fill", "house.fill", "bed.double.fill", "gamecontroller.fill", "lock.fill", "sparkles",
    ]

    // MARK: - What it covers

    /// Categories that are on. Games covers apps too; the rest are sites.
    public var enabledGroups: [SiteGroup] { groups.filter(\.isOn).map(\.value).filter { $0 != .web } }
    /// Site categories only, the ones that matter while every site is blocked anyway.
    public var enabledSiteGroups: [SiteGroup] { mode == .allExcept ? [] : enabledGroups.filter { $0 != .games } }
    public var enabledSites: [String] { mode == .allExcept ? [] : sites.filter(\.isOn).map(\.value) }
    public var enabledApps: [BlockedApp] { apps.filter(\.isOn).map { BlockedApp(bundleID: $0.bundleID, name: $0.name) } }
    public var blocksGames: Bool { enabledGroups.contains(.games) }

    /// The groups a session stores: categories, Games, and Whole web for an all-except list.
    public var sessionGroups: [SiteGroup] {
        var groups = enabledGroups.filter { $0 == .games || mode == .only }
        if mode == .allExcept { groups.append(.web) }
        return groups
    }

    /// Nothing to lock. "Other browsers" alone counts only when one is installed to close.
    public func isEmpty(otherBrowsersInstalled: Bool) -> Bool {
        mode == .only && enabledGroups.isEmpty && enabledSites.isEmpty && enabledApps.isEmpty
            && !(otherBrowsers && otherBrowsersInstalled)
    }

    /// Every site this list blocks, its categories' included, without repeats.
    public var blockedSiteCount: Int {
        var rules: [SiteRule] = []
        for pattern in enabledSites + enabledGroups.flatMap(\.sites) {
            guard let rule = SiteRule(pattern), !rules.contains(where: { $0.covers(rule) }) else { continue }
            rules.removeAll { rule.covers($0) }
            rules.append(rule)
        }
        return rules.count
    }

    /// "23 sites, 2 apps and every game", said right above the hold button.
    public func summary(otherBrowsersInstalled: Bool) -> String {
        var parts: [String] = []
        switch mode {
        case .only:
            let sites = blockedSiteCount
            if sites > 0 { parts.append(Format.count(sites, "site", "sites")) }
        case .allExcept:
            parts.append(allowed.isEmpty ? "the whole web" : "the whole web except \(Format.count(allowed.count, "site", "sites"))")
        }
        let apps = enabledApps.count
        if apps > 0 { parts.append(Format.count(apps, "app", "apps")) }
        if blocksGames { parts.append("every game") }
        if otherBrowsers, otherBrowsersInstalled { parts.append("other browsers") }
        guard !parts.isEmpty else { return "Nothing to lock yet" }
        let text = Format.list(parts)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// What's in it, by name: "Social, Games, YouTube Shorts, Twitch, Steam, Discord".
    public var itemNames: [String] {
        switch mode {
        case .only:
            return enabledGroups.map(\.title) + enabledSites.map { SiteRule($0)?.displayName ?? $0 } + enabledApps.map(\.name)
        case .allExcept:
            let open = allowed.map { SiteRule($0)?.displayName ?? $0 }
            let web = open.isEmpty ? "The whole web" : "The whole web except \(Format.list(open))"
            return [web] + (blocksGames ? ["Games"] : []) + enabledApps.map(\.name)
        }
    }

    // MARK: - Editing

    /// Adds a site in its normal form, or turns it back on. False if the text isn't a site.
    @discardableResult
    public mutating func addSite(_ pattern: String) -> Bool {
        guard let rule = SiteRule(pattern) else { return false }
        let normal = rule.description
        if mode == .allExcept {
            if !allowed.contains(normal) { allowed.append(normal) }
            return true
        }
        if let index = sites.firstIndex(where: { $0.value == normal }) {
            sites[index].isOn = true
        } else {
            sites.append(Toggled(normal))
        }
        return true
    }

    public mutating func addGroup(_ group: SiteGroup) {
        guard group != .web else {
            mode = .allExcept
            return
        }
        if let index = groups.firstIndex(where: { $0.value == group }) {
            groups[index].isOn = true
        } else {
            groups.append(Toggled(group))
        }
    }

    public mutating func addApp(_ app: ListApp) {
        if let index = apps.firstIndex(where: { $0.bundleID == app.bundleID }) {
            apps[index].isOn = true
        } else {
            apps.append(app)
        }
    }
}

/// Something in a list, on or off. Off stays in the list, ready to tick again.
public struct Toggled<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public var value: Value
    public var isOn: Bool

    public init(_ value: Value, isOn: Bool = true) {
        self.value = value
        self.isOn = isOn
    }
}

public struct ListApp: Codable, Hashable, Identifiable, Sendable {
    public var bundleID: String
    public var name: String
    public var path: String
    public var isOn: Bool
    public var id: String { bundleID }

    public init(bundleID: String, name: String, path: String, isOn: Bool = true) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
        self.isOn = isOn
    }
}

/// A list's colour: its card, its dot, its stretch on the schedule.
public enum ListColor: String, Codable, CaseIterable, Sendable {
    case sea, coral, violet, amber, leaf, sky, rose, slate
}

/// What the menu remembers for the next block: the list, how long, and whether it has breaks.
public struct NextBlock: Codable, Equatable, Sendable {
    public var listID: UUID?
    public var length: BlockLength
    public var breaks: Bool

    public init(listID: UUID? = nil, length: BlockLength = .minutes(60), breaks: Bool = false) {
        self.listID = listID
        self.length = length
        self.breaks = breaks
    }
}
