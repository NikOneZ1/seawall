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
    public var siteAttempts = 0
    public var appAttempts = 0
    public var unlockRequestedAt: Date?

    public init(startedAt: Date, endsAt: Date, sites: [String], apps: [BlockedApp], blocksOtherBrowsers: Bool,
                groups: [SiteGroup] = [], allowedSites: [String] = [], earlyExit: EarlyExit = .wait10) {
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.sites = sites
        self.apps = apps
        self.blocksOtherBrowsers = blocksOtherBrowsers
        self.groups = groups
        self.allowedSites = allowedSites
        self.earlyExit = earlyExit
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
        if let requested = unlockRequestedAt { unlockRequestedAt = requested + skew }
    }
}

extension Session {
    private enum CodingKeys: String, CodingKey {
        case startedAt, endsAt, sites, apps, blocksOtherBrowsers, groups, allowedSites, earlyExit, siteAttempts, appAttempts, unlockRequestedAt
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
        siteAttempts = try c.decodeIfPresent(Int.self, forKey: .siteAttempts) ?? 0
        appAttempts = try c.decodeIfPresent(Int.self, forKey: .appAttempts) ?? 0
        unlockRequestedAt = try c.decodeIfPresent(Date.self, forKey: .unlockRequestedAt)
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
