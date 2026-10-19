import Foundation

/// Ready-made groups for "Lock": one chip covers a whole kind of distraction, so you don't have
/// to think of every site. Games also covers apps, found by what they are rather than by name.
public enum SiteGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case games, social, video, news, shopping

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .games: "Games"
        case .social: "Social"
        case .video: "Video"
        case .news: "News"
        case .shopping: "Shopping"
        }
    }

    /// What the chip covers, for its tooltip.
    public var summary: String {
        switch self {
        case .games: "Any app macOS lists as a game, games from Steam and Epic, launchers like Steam and Battle.net, and game sites"
        case .social: "Instagram, TikTok, X, Facebook, Reddit, Threads, Bluesky and more"
        case .video: "YouTube, Twitch, Netflix, Kick, Prime Video, Disney+ and more"
        case .news: "Hacker News, Google News, BBC, CNN, The New York Times, The Guardian and more"
        case .shopping: "Amazon, eBay, AliExpress, Temu, Etsy and more"
        }
    }

    /// Site rules the group blocks, in the same form as the ones you type in.
    public var sites: [String] {
        switch self {
        case .games:
            ["store.steampowered.com", "steamcommunity.com", "epicgames.com", "roblox.com", "chess.com",
             "lichess.org", "poki.com", "crazygames.com", "miniclip.com"]
        case .social:
            ["instagram.com", "tiktok.com", "x.com", "twitter.com", "facebook.com", "reddit.com", "threads.net",
             "bsky.app", "snapchat.com", "pinterest.com", "vk.com", "tumblr.com"]
        case .video:
            ["youtube.com", "twitch.tv", "netflix.com", "kick.com", "primevideo.com", "disneyplus.com",
             "max.com", "hulu.com", "dailymotion.com"]
        case .news:
            ["news.ycombinator.com", "news.google.com", "bbc.com", "bbc.co.uk", "cnn.com", "nytimes.com",
             "theguardian.com", "foxnews.com", "washingtonpost.com", "reuters.com", "apnews.com"]
        case .shopping:
            ["amazon.com", "amazon.co.uk", "amazon.de", "ebay.com", "aliexpress.com", "temu.com", "etsy.com",
             "walmart.com", "shein.com", "target.com"]
        }
    }

    /// Launchers that open games but aren't filed under Games themselves.
    public static let gameLaunchers: Set<String> = [
        "com.valvesoftware.steam",
        "com.epicgames.EpicGamesLauncher",
        "net.battle.app",
        "com.blizzard.bna",
        "com.gog.galaxy",
        "com.mojang.minecraftlauncher",
        "com.roblox.RobloxPlayer",
        "com.riotgames.RiotGames.RiotClient",
        "com.riotgames.LeagueofLegends.LeagueClient",
    ]

    /// Folders games get installed into, whatever their own Info.plist says.
    static let gameFolders = ["/steamapps/common/", "/Epic Games/"]

    /// Whether an app is a game: macOS files it under Games or one of its kinds (action games,
    /// puzzle games…), it was installed into a Steam or Epic library, or it's a known launcher.
    /// Many Steam games don't name a category at all, which is why the folder counts.
    public static func isGame(bundleID: String?, category: String?, path: String?) -> Bool {
        if let bundleID, gameLaunchers.contains(bundleID) { return true }
        if let category, category.hasPrefix("public.app-category."), category.hasSuffix("games") { return true }
        if let path, gameFolders.contains(where: path.contains) { return true }
        return false
    }
}
