import Foundation

/// What one block keeps closed in the browser: its sites, its groups' sites, or with Whole web
/// on, every site except the allowed ones. Pages on this Mac are never blocked, the block page
/// itself included, so a blocked tab can't be sent somewhere that's blocked too.
public struct WebFilter: Sendable {
    let rules: [SiteRule]
    let wholeWeb: Bool
    let allowed: [SiteRule]

    public init(_ session: Session) {
        rules = session.allSites.compactMap(SiteRule.init)
        wholeWeb = session.blocksWholeWeb
        allowed = session.allowedSites.compactMap(SiteRule.init)
    }

    /// Nothing to look for in browsers: the block only covers apps.
    public var isEmpty: Bool { rules.isEmpty && !wholeWeb }

    public func blocks(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), !Self.isLocal(host) else { return false }
        if allowed.contains(where: { $0.matches(url) }) { return false }
        return wholeWeb || rules.contains { $0.matches(url) }
    }

    static func isLocal(_ host: String) -> Bool {
        ["localhost", "127.0.0.1", "::1", "[::1]", "0.0.0.0"].contains(host) || host.hasSuffix(".localhost") || host.hasSuffix(".local")
    }
}
