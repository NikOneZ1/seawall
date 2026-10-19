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
    /// How long you have to wait after asking to leave early.
    public static let unlockDelay: TimeInterval = 10 * 60
    /// How long the unlock button stays once the wait is over, so it can't be kept armed "just in case".
    public static let unlockWindow: TimeInterval = 2 * 60
    /// Clock changes smaller than this are normal drift (NTP sync, waking from sleep).
    static let clockJumpThreshold: TimeInterval = 30

    public var startedAt: Date
    public var endsAt: Date
    public var sites: [String]
    public var apps: [BlockedApp]
    public var blocksOtherBrowsers: Bool
    public var siteAttempts = 0
    public var appAttempts = 0
    public var unlockRequestedAt: Date?

    public init(startedAt: Date, endsAt: Date, sites: [String], apps: [BlockedApp], blocksOtherBrowsers: Bool) {
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.sites = sites
        self.apps = apps
        self.blocksOtherBrowsers = blocksOtherBrowsers
    }

    public var attempts: Int { siteAttempts + appAttempts }

    public var blockedBundleIDs: Set<String> {
        Set((apps + (blocksOtherBrowsers ? KnownBrowsers.all : [])).map(\.bundleID))
    }

    /// "YouTube Shorts, Twitch, Steam, other browsers".
    public var names: String {
        var names = sites.map { SiteRule($0)?.displayName ?? $0 } + apps.map(\.name)
        if blocksOtherBrowsers { names.append("other browsers") }
        return names.joined(separator: ", ")
    }

    public func isOver(at now: Date) -> Bool { now >= endsAt }

    public func unlockState(at now: Date) -> UnlockState {
        guard let requested = unlockRequestedAt else { return .locked }
        let waited = now.timeIntervalSince(requested)
        if waited < Self.unlockDelay {
            return .waiting(remaining: Self.unlockDelay - waited)
        }
        if waited < Self.unlockDelay + Self.unlockWindow {
            return .ready(expiresIn: Self.unlockDelay + Self.unlockWindow - waited)
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
