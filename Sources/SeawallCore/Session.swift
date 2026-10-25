import Foundation

public struct BlockedApp: Codable, Hashable, Sendable {
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

public enum UnlockState: Equatable, Sendable {
    /// No early exit requested.
    case locked
    /// Early exit requested; the unlock button appears once the wait is over.
    case waiting(remaining: TimeInterval)
    /// The unlock button is available, but only for a short window.
    case ready(expiresIn: TimeInterval)

    public var isReady: Bool {
        if case .ready = self { true } else { false }
    }
}

/// A running block. Several can run at once, each with its own end and its own way out.
/// Persisted to disk so they survive quitting, crashes and reboots.
public struct Session: Codable, Equatable, Sendable {
    /// How long the unlock button stays once the wait is over, so it can't be kept armed "just in case".
    public static let unlockWindow: TimeInterval = 2 * 60
    /// Clock changes smaller than this are normal drift (NTP sync, waking from sleep).
    static let clockJumpThreshold: TimeInterval = 30

    public var startedAt: Date
    public var endsAt: Date
    public var sites: [String]
    public var apps: [BlockedApp]
    public var blocksOtherBrowsers: Bool
    /// Games, Social and the rest; their sites count as this block's own.
    public var groups: [SiteGroup] = []
    /// Sites left open while the whole web is blocked.
    public var allowedSites: [String] = []
    /// The way out this block started with.
    public var earlyExit: EarlyExit = .wait10
    /// Set for a block in rounds, with breaks in between; `nil` for one stretch.
    public var rounds: Rounds?
    /// Clock changes absorbed so far, so the rounds keep their real length too.
    var roundsShift: TimeInterval = 0
    public var siteAttempts = 0
    public var appAttempts = 0
    public var unlockRequestedAt: Date?
    /// The list it came from, for its name and colour while it runs; `nil` for older blocks.
    public var label: SessionLabel?

    public init(startedAt: Date, endsAt: Date, sites: [String], apps: [BlockedApp], blocksOtherBrowsers: Bool,
                groups: [SiteGroup] = [], allowedSites: [String] = [], earlyExit: EarlyExit = .wait10,
                rounds: Rounds? = nil, label: SessionLabel? = nil) {
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.sites = sites
        self.apps = apps
        self.blocksOtherBrowsers = blocksOtherBrowsers
        self.groups = groups
        self.allowedSites = allowedSites
        self.earlyExit = earlyExit
        self.rounds = rounds
        self.label = label
    }

    /// A block of what `list` holds. `otherBrowsersInstalled` decides whether its
    /// "Other browsers" switch has anything to close.
    public init(_ list: BlockList, startedAt: Date, endsAt: Date, earlyExit: EarlyExit, rounds: Rounds? = nil,
                otherBrowsersInstalled: Bool) {
        self.init(startedAt: startedAt, endsAt: endsAt, sites: list.enabledSites, apps: list.enabledApps,
                  blocksOtherBrowsers: list.otherBrowsers && otherBrowsersInstalled,
                  groups: list.sessionGroups, allowedSites: list.mode == .allExcept ? list.allowed : [],
                  earlyExit: earlyExit, rounds: rounds,
                  label: SessionLabel(listID: list.id, name: list.name, symbol: list.symbol, color: list.color))
    }

    /// Covers nothing at all, so there's no point starting it.
    public var isEmpty: Bool { allSites.isEmpty && apps.isEmpty && groups.isEmpty && !blocksOtherBrowsers }

    // MARK: - Tightening a running block

    /// Locks for longer: `seconds` more, or for a block in rounds, as many more rounds.
    public mutating func extend(by seconds: TimeInterval) {
        guard seconds > 0 else { return }
        if var rounds {
            let extra = max(1, Int((seconds / (rounds.work + rounds.rest)).rounded()))
            rounds.count += extra
            self.rounds = rounds
            endsAt = startedAt + roundsShift + rounds.total
        } else {
            endsAt += seconds
        }
    }

    /// Adds a site to what's blocked. Only ever stricter: an all-except block has nothing to add.
    @discardableResult
    public mutating func add(site pattern: String) -> Bool {
        guard !blocksWholeWeb, let rule = SiteRule(pattern) else { return false }
        if !allSites.contains(where: { SiteRule($0)?.covers(rule) == true }) { sites.append(rule.description) }
        return true
    }

    public mutating func add(app: BlockedApp) {
        if !apps.contains(where: { $0.bundleID == app.bundleID }) { apps.append(app) }
    }

    public mutating func add(group: SiteGroup) {
        if !groups.contains(group) { groups.append(group) }
    }

    /// Which round a block in rounds is in, or `nil` for a block in one stretch.
    public func phase(at now: Date) -> Phase? {
        let start = startedAt + roundsShift
        return rounds?.phase(after: now.timeIntervalSince(start), from: start)
    }

    /// Whether the block is holding things closed right now: always, except on a break.
    public func isHolding(at now: Date) -> Bool {
        if case .resting = phase(at: now) { return false }
        return true
    }

    /// The sites typed in, plus every site of the block's groups.
    public var allSites: [String] { sites + groups.flatMap(\.sites) }

    /// Games are found by what they are, not by a list; see `SiteGroup.isGame`.
    public var blocksGames: Bool { groups.contains(.games) }

    public var blocksWholeWeb: Bool { groups.contains(.web) }

    public var attempts: Int { siteAttempts + appAttempts }

    public var blockedBundleIDs: Set<String> {
        // With the whole web blocked, a browser Seawall can't look into is just a way around it.
        Set((apps + (blocksOtherBrowsers || blocksWholeWeb ? KnownBrowsers.unreadable : [])).map(\.bundleID))
    }

    /// Its list's name, or what it holds for blocks from before lists: "Work", "Twitch and Steam".
    public var title: String { label?.name ?? names }

    /// "Games, YouTube Shorts, Twitch, Steam, other browsers".
    public var names: String {
        var names = groups.map(\.title) + sites.map { SiteRule($0)?.displayName ?? $0 } + apps.map(\.name)
        if blocksOtherBrowsers { names.append("other browsers") }
        return names.joined(separator: ", ")
    }

    public func isOver(at now: Date) -> Bool { now >= endsAt }

    public func unlockState(at now: Date) -> UnlockState {
        guard let requested = unlockRequestedAt, let delay = earlyExit.wait else { return .locked }
        let waited = now.timeIntervalSince(requested)
        if waited < delay {
            return .waiting(remaining: delay - waited)
        }
        if waited < delay + Self.unlockWindow {
            return .ready(expiresIn: delay + Self.unlockWindow - waited)
        }
        return .locked
    }

    /// Drops an unlock request whose button window has passed.
    public mutating func expireUnlockRequest(at now: Date) {
        if unlockRequestedAt != nil, unlockState(at: now) == .locked {
            unlockRequestedAt = nil
        }
    }

    /// Keeps the block's real length when the system clock is changed.
    /// `skew` is how far the wall clock moved beyond (or short of) real elapsed time.
    public mutating func absorbClockJump(_ skew: TimeInterval) {
        guard abs(skew) >= Self.clockJumpThreshold else { return }
        endsAt += skew
        roundsShift += skew
        if let requested = unlockRequestedAt { unlockRequestedAt = requested + skew }
    }
}

extension Session {
    private enum CodingKeys: String, CodingKey {
        case startedAt, endsAt, sites, apps, blocksOtherBrowsers, groups, allowedSites, earlyExit, rounds, roundsShift, siteAttempts, appAttempts, unlockRequestedAt, label
    }

    /// Blocks saved before groups existed have no `groups`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endsAt = try c.decode(Date.self, forKey: .endsAt)
        sites = try c.decode([String].self, forKey: .sites)
        apps = try c.decode([BlockedApp].self, forKey: .apps)
        blocksOtherBrowsers = try c.decode(Bool.self, forKey: .blocksOtherBrowsers)
        groups = try c.decodeIfPresent([SiteGroup].self, forKey: .groups) ?? []
        allowedSites = try c.decodeIfPresent([String].self, forKey: .allowedSites) ?? []
        earlyExit = try c.decodeIfPresent(EarlyExit.self, forKey: .earlyExit) ?? .wait10
        rounds = try c.decodeIfPresent(Rounds.self, forKey: .rounds)
        roundsShift = try c.decodeIfPresent(TimeInterval.self, forKey: .roundsShift) ?? 0
        siteAttempts = try c.decodeIfPresent(Int.self, forKey: .siteAttempts) ?? 0
        appAttempts = try c.decodeIfPresent(Int.self, forKey: .appAttempts) ?? 0
        unlockRequestedAt = try c.decodeIfPresent(Date.self, forKey: .unlockRequestedAt)
        label = try c.decodeIfPresent(SessionLabel.self, forKey: .label)
    }
}

extension Session: Identifiable {
    /// Two blocks can't start in the same instant, so the start time doubles as an ID
    /// that session files from before multiple blocks already have.
    public var id: Date { startedAt }
}

extension [Session] {
    /// Of the blocks covering something, the one ending last: it decides when that opens
    /// again, so the attempt counts there.
    public func lastEnding(where covers: (Session) -> Bool) -> Int? {
        indices.filter { covers(self[$0]) }.max { self[$0].endsAt < self[$1].endsAt }
    }
}

/// Which list a block came from, kept with the block so renaming the list later doesn't change it.
public struct SessionLabel: Codable, Equatable, Sendable {
    public var listID: UUID
    public var name: String
    public var symbol: String
    public var color: ListColor

    public init(listID: UUID, name: String, symbol: String, color: ListColor) {
        self.listID = listID
        self.name = name
        self.symbol = symbol
        self.color = color
    }
}

public struct SessionSummary: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var endedAt: Date
    public var siteAttempts: Int
    public var appAttempts: Int
    public var endedEarly: Bool

    public init(_ session: Session, endedAt: Date, early: Bool) {
        startedAt = session.startedAt
        self.endedAt = endedAt
        siteAttempts = session.siteAttempts
        appAttempts = session.appAttempts
        endedEarly = early
    }

    public var attempts: Int { siteAttempts + appAttempts }
}
