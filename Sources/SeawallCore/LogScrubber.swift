import Foundation

/// Takes anything personal out of log lines and crash reports before they can leave the Mac:
/// web addresses, host names and bare domains, IP addresses, email addresses, file paths and
/// the user's name, plus whatever the caller knows is block list content (list names, sites,
/// app names). It errs on the side of taking too much: a line that reads `<domain>` where it
/// didn't need to is fine; a site someone tried to open is not.
public struct LogScrubber: Sendable {
    /// Words to take out as whole words, ignoring case: list names, sites, apps.
    public var secrets: [String]
    /// The home folder, like `/Users/nikita`. Taken out before any other path.
    public var home: String?
    /// The short user name, taken out anywhere it appears on its own.
    public var userName: String?

    /// File endings that aren't web domains, so `config.json` and `libswiftCore.dylib` stay
    /// readable. None of these is a top-level domain; `.app` is, so it isn't here.
    public static let fileEndings: Set<String> = ["json", "dylib", "swift", "plist", "txt", "ips", "log", "framework", "crash", "m", "c", "h"]

    /// Secrets shorter than this are left alone: taking out every "a" would leave nothing to read.
    static let shortestSecret = 2

    public init(secrets: [String] = [], home: String? = nil, userName: String? = nil) {
        self.secrets = secrets
        self.home = home
        self.userName = userName
    }

    public func scrub(_ text: String) -> String {
        var text = text

        if let home, home.count > 1 {
            text = text.replacingOccurrences(of: home, with: "~")
        }

        // Before the patterns, so a list called "Reddit" can't hide inside "reddit.com" and an
        // app name with a space in it goes as a whole.
        let words = Set(secrets.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter { $0.count >= Self.shortestSecret }
            .sorted { $0.count > $1.count }
        for word in words {
            text = Self.replace(Self.word(word), in: text, with: "<list item>")
        }

        text = Self.replace(Self.url, in: text, with: "<url>")
        text = Self.replace(Self.email, in: text, with: "<email>")
        text = Self.replace(Self.ipv4, in: text, with: "<ip>")
        text = Self.replace(Self.ipv6, in: text, with: "<ip>")
        text = Self.replace(Self.path, in: text, with: "<path>")
        text = Self.replaceDomains(in: text)
        // Whatever still has a slash in it is part of a path or an address that got split up,
        // like the rest of `~/Library/Application Support/…` after the space.
        text = Self.replace(Self.slashed, in: text, with: "<path>")

        if let userName, userName.count >= Self.shortestSecret {
            text = Self.replace(Self.word(userName), in: text, with: "<user>")
        }
        return text
    }

    // MARK: - Patterns

    /// `https://…`, `seawall://lock?list=…`, `file:///…`: a scheme and everything after it up to a space.
    static let url = regex(#"\b[A-Za-z][A-Za-z0-9+.\-]*://[^\s"'<>]*"#)
    /// Anything with an @ in the middle. Wider than real addresses, on purpose.
    static let email = regex(#"[^\s"'<>(),;:]+@[^\s"'<>(),;:]+"#)
    static let ipv4 = regex(#"(?<![\d.])\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?(?![\d])"#)
    /// Anything with `::`, or eight groups of hex. Plain times like 10:23:45 are left alone.
    static let ipv6 = regex(#"\[?(?:[0-9A-Fa-f]{0,4}:){1,7}:(?:[0-9A-Fa-f]{0,4}:?){0,7}[0-9A-Fa-f]{0,4}\]?(?::\d+)?|(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}"#)
    /// An absolute path or one under `~`, up to a space or quote. Folder names hold app and file names.
    static let path = regex(#"(?<![\w.~<>/])(?:~|/(?=[\p{L}\p{N}._\-]))[^\s"'“”‘’<>(),;]*"#)
    /// `reddit.com`, `youtube.com/shorts`, `m.twitch.tv:443`, `com.valvesoftware.steam`, `пример.рф`.
    static let domain = regex(#"(?<![\p{L}\p{N}_\-.@])(?:[\p{L}\p{N}](?:[\p{L}\p{N}\-]*[\p{L}\p{N}])?\.)+([\p{L}][\p{L}\p{N}\-]*)(?::\d+)?(?:/[^\s"'“”<>]*)?"#)

    /// Text with no slash-free reading: `Support/Seawall/x`, `and/or`.
    static let slashed = regex(#"[^\s"'“”<>(),;]*[^\s"'“”<>(),;/]/[^\s"'“”<>(),;]*|(?<![<\w])/[^\s"'“”<>(),;]+"#)

    private static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // The patterns are fixed and covered by tests, so a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    /// One secret on its own, not inside a longer word: "Work" goes, "Network" stays.
    private static func word(_ text: String) -> NSRegularExpression {
        regex("(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: text) + "(?![\\p{L}\\p{N}])", options: [.caseInsensitive])
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with replacement: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
    }

    /// Domains go one by one, so file names like `config.json` can stay.
    private static func replaceDomains(in text: String) -> String {
        let source = text as NSString
        var result = ""
        var last = 0
        for match in domain.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let ending = source.substring(with: match.range(at: 1)).lowercased()
            let whole = source.substring(with: match.range)
            // A file name keeps its ending only when nothing follows it: `x.json/y` is a site's path.
            let keep = fileEndings.contains(ending) && !whole.contains("/") && !whole.contains(":")
            result += source.substring(with: NSRange(location: last, length: match.range.location - last))
            result += keep ? whole : "<domain>"
            last = match.range.location + match.range.length
        }
        result += source.substring(from: last)
        return result
    }
}

extension LogScrubber {
    /// Everything in the lists and running blocks that could say what someone blocks.
    public static func secrets(lists: [BlockList], sessions: [Session], scheduleNames: [String] = []) -> [String] {
        var words: [String] = scheduleNames
        for list in lists {
            words.append(list.name)
            words += list.sites.map(\.value) + list.allowed
            words += list.apps.flatMap { [$0.name, $0.bundleID] }
            words += list.sites.compactMap { SiteRule($0.value)?.displayName }
            words += list.groups.map(\.value.title)
        }
        for session in sessions {
            if let label = session.label { words.append(label.name) }
            words += session.sites + session.allowedSites
            words += session.apps.flatMap { [$0.name, $0.bundleID] }
        }
        return words
    }
}
