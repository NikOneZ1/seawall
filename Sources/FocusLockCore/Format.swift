import Foundation

/// Wording for times and counts shown in the UI.
public enum Format {
    public static func plural(_ n: Int, _ one: String, _ other: String) -> String {
        n == 1 ? one : other
    }

    public static func attempts(_ n: Int) -> String {
        "\(n) \(plural(n, "attempt", "attempts"))"
    }

    /// "1:05:09", "9:41" or "2d 1:05:09". Rounds up, so a fresh 10-minute wait reads "10:00", not "9:59".
    public static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let d = total / 86_400, h = total / 3600 % 24, m = total / 60 % 60, s = total % 60
        if d > 0 { return String(format: "%dd %d:%02d:%02d", d, h, m, s) }
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// "2h 15m", "45m", "3h", "1d 4h".
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        let d = minutes / 1440, h = minutes / 60 % 24, m = minutes % 60
        if d > 0 { return h == 0 ? "\(d)d" : "\(d)d \(h)h" }
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    /// "18:00", "tomorrow, 09:00" or "Oct 12, 09:00".
    public static func clockTime(_ date: Date, relativeTo now: Date, calendar: Calendar = .current) -> String {
        let formatter = formatter(calendar)
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: date)

        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow, \(time)"
        }
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: date)
    }

    /// "22:25" today, "Sat 19:25" on another day — for tight spots.
    public static func shortClockTime(_ date: Date, relativeTo now: Date, calendar: Calendar = .current) -> String {
        let formatter = formatter(calendar)
        formatter.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "HH:mm" : "EEE HH:mm"
        return formatter.string(from: date)
    }

    /// A day `offset` days from today: "Today", "Tomorrow", "Sun, Oct 11".
    public static func day(_ offset: Int, from now: Date, calendar: Calendar = .current) -> String {
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default:
            let date = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            let formatter = formatter(calendar)
            formatter.dateFormat = "EEE, MMM d"
            return formatter.string(from: date)
        }
    }

    public static func summary(_ summary: SessionSummary) -> String {
        let length = duration(summary.endedAt.timeIntervalSince(summary.startedAt))
        guard summary.attempts > 0 else {
            return "Lasted \(length). Not a single attempt to break it — nice."
        }
        return "Lasted \(length). \(attempts(summary.attempts)) blocked "
            + "(sites: \(summary.siteAttempts), apps: \(summary.appAttempts))."
    }

    private static func formatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return formatter
    }
}
