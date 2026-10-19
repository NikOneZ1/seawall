import Foundation

/// `seawall://lock?list=Work&for=2h` or `…&until=18:00`: starts a block from outside the app,
/// for a Shortcuts automation that runs when a Focus turns on, or from Raycast and the like.
/// Without `list` it locks what's switched on; without `for` or `until`, the menu's duration.
public struct LockLink: Equatable, Sendable {
    public var list: String?
    public var duration: TimeInterval?
    public var until: TimeOfDay?

    /// Opening a link is one click away from any web page, so a link can't lock for longer than this.
    public static let longest: TimeInterval = 12 * 60 * 60

    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == "seawall",
              url.host?.lowercased() == "lock" || url.path.lowercased() == "lock" || url.path.lowercased() == "/lock" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name.lowercased() == name }?.value?.trimmingCharacters(in: .whitespaces)
        }
        list = value("list").flatMap { $0.isEmpty ? nil : $0 }
        if let text = value("for") {
            guard let seconds = Self.duration(text) else { return nil }
            duration = seconds
        }
        if let text = value("until") {
            let parts = text.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
            until = TimeOfDay(hour: parts[0], minute: parts[1])
        }
    }

    /// "90" (minutes), "45m", "2h", "1h30m".
    static func duration(_ text: String) -> TimeInterval? {
        let text = text.lowercased()
        if let minutes = Int(text), minutes > 0 { return TimeInterval(minutes * 60) }
        var total = 0, number = ""
        for character in text {
            if character.isNumber { number.append(character); continue }
            guard let n = Int(number) else { return nil }
            switch character {
            case "h": total += n * 3600
            case "m": total += n * 60
            default: return nil
            }
            number = ""
        }
        guard number.isEmpty, total > 0 else { return nil }
        return TimeInterval(total)
    }

    /// When the block would end, if started at `now`: the next `until`, or `now` plus the
    /// duration, never more than `longest` away. `nil` means "use the menu's duration".
    public func end(from now: Date, calendar: Calendar = .current) -> Date? {
        var end: Date?
        if let duration { end = now + duration }
        if let until, let today = calendar.date(bySettingHour: until.hour, minute: until.minute, second: 0, of: now) {
            end = today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
        }
        return end.map { min($0, now + Self.longest) }
    }
}
