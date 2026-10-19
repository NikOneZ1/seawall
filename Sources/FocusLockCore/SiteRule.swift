import Foundation

/// A site to block: a domain ("twitch.tv"), optionally narrowed to a section ("youtube.com/shorts").
///
/// The domain covers its subdomains too (www., m., clips.), except the few that are really a
/// different site (music.youtube.com) — those are blocked only when listed themselves.
/// The path matches whole segments only, so "youtube.com/shorts" blocks /shorts/abc but not
/// /watch or /shortsale.
public struct SiteRule: Hashable, Sendable, CustomStringConvertible {
    public let host: String
    public let path: String

    /// Accepts what people actually paste: any case, with or without scheme, www., trailing slash or query.
    public init?(_ pattern: String) {
        var text = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = text.range(of: "://") { text.removeSubrange(..<scheme.upperBound) }
        if let tail = text.firstIndex(where: { $0 == "?" || $0 == "#" }) { text.removeSubrange(tail...) }

        let slash = text.firstIndex(of: "/") ?? text.endIndex
        var host = String(text[..<slash])
        var path = String(text[slash...])
        if host.hasPrefix("www.") { host.removeFirst(4) }
        while path.hasSuffix("/") { path.removeLast() }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard host.contains("."), !host.hasPrefix("."), !host.hasSuffix("."), !host.contains(".."),
              host.unicodeScalars.allSatisfy(allowed.contains) else { return nil }

        self.host = host
        self.path = path
    }

    public var description: String { host + path }

    /// What people call it: "YouTube Shorts", "Twitch", "Hacker News", "Example".
    public var displayName: String {
        let site = brand?.name ?? Self.mainLabel(of: host).capitalized
        guard let section = path.split(separator: "/").last else { return site }
        return site + " " + section.prefix(1).uppercased() + section.dropFirst()
    }

    /// The well-known site this rule is on, matched by domain so "m.youtube.com" is YouTube too.
    public var brand: (domain: String, name: String)? {
        let labels = host.split(separator: ".")
        for start in labels.indices {
            let domain = labels[start...].joined(separator: ".")
            if let name = Self.brands[domain] { return (domain, name) }
        }
        return nil
    }

    private static let brands = [
        "youtube.com": "YouTube", "youtu.be": "YouTube", "tiktok.com": "TikTok", "twitch.tv": "Twitch",
        "x.com": "X", "twitter.com": "Twitter", "instagram.com": "Instagram", "facebook.com": "Facebook",
        "reddit.com": "Reddit", "netflix.com": "Netflix", "vk.com": "VK", "linkedin.com": "LinkedIn",
        "news.ycombinator.com": "Hacker News", "discord.com": "Discord", "pinterest.com": "Pinterest",
        "threads.net": "Threads", "kick.com": "Kick", "telegram.org": "Telegram",
        "music.youtube.com": "YouTube Music",
    ]

    /// Subdomains that are their own thing rather than part of the parent site: blocking
    /// "youtube.com" shouldn't take away music while working.
    private static let separateSites: Set<String> = ["music.youtube.com"]

    /// Whether `other` is this rule's host or one of its subdomains, short of a separate site under it.
    private func reaches(_ other: String) -> Bool {
        if other == host { return true }
        guard other.hasSuffix("." + host) else { return false }
        return !Self.separateSites.contains { site in
            site.hasSuffix("." + host) && (other == site || other.hasSuffix("." + site))
        }
    }

    /// "example" in "www.example.com", "bbc" in "bbc.co.uk".
    private static func mainLabel(of host: String) -> String {
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return host }
        let candidate = labels[labels.count - 2]
        if candidate.count <= 3, labels.count >= 3 { return labels[labels.count - 3] }
        return candidate
    }

    public func matches(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let urlHost = url.host?.lowercased(), reaches(urlHost) else { return false }
        guard !path.isEmpty else { return true }
        let urlPath = url.path.lowercased()
        return urlPath == path || urlPath.hasPrefix(path + "/")
    }

    /// Whether this rule blocks everything `other` does: "youtube.com" covers "youtube.com/shorts".
    public func covers(_ other: SiteRule) -> Bool {
        guard reaches(other.host) else { return false }
        return path.isEmpty || other.path == path || other.path.hasPrefix(path + "/")
    }
}
