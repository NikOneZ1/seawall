import Foundation

/// The small text report Seawall writes when it crashes, while crash reports are on in Settings.
///
/// The crash handler can only write plain bytes (see CrashCatcher), so it writes a raw `.crash`
/// file: the header made here at launch, the signal or exception, the time in seconds and the
/// stack. On the next launch `finish` turns that into the `.txt` someone can attach to an email:
/// a readable time, and everything run through the scrubber once more.
public enum CrashReport {
    public static let title = "Seawall crash report"
    /// Raw, as the crash handler left it.
    public static let rawEnding = "crash"
    /// Finished and scrubbed, ready to send.
    public static let reportEnding = "txt"
    /// No more than this many finished reports are kept…
    public static let kept = 5
    /// …and none older than this.
    public static let maxAge: TimeInterval = 30 * 86_400

    /// Written first, before anything has gone wrong, so the crash handler has nothing to format.
    public static func header(_ info: AppInfo, launchedAt: Date) -> String {
        ([title] + info.lines + ["Launched: \(timestamp(launchedAt))"]).joined(separator: "\n") + "\n"
    }

    /// The raw report made readable and scrubbed. The crash time, which the handler can only
    /// write as seconds since 1970, becomes a date.
    public static func finish(_ raw: String, scrubber: LogScrubber) -> String {
        var lines: [String] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("Crashed at: "), let seconds = TimeInterval(line.dropFirst("Crashed at: ".count).trimmingCharacters(in: .whitespaces)) {
                lines.append("Crashed at: \(timestamp(Date(timeIntervalSince1970: seconds)))")
            } else {
                lines.append(line)
            }
        }
        return scrubber.scrub(lines.joined(separator: "\n"))
    }

    /// The lines worth putting in the email itself: what stopped Seawall, and when.
    public static func summary(_ report: String) -> [String] {
        let keys = ["Signal:", "Exception:", "Crashed at:"]
        return report.split(separator: "\n").map(String.init).filter { line in keys.contains { line.hasPrefix($0) } }
    }

    /// "seawall-crash-2026-10-31-140512.txt".
    public static func fileName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "seawall-crash-\(formatter.string(from: date)).\(reportEnding)"
    }

    /// Reports to delete: anything past `maxAge`, and the oldest beyond the newest `kept`.
    public static func expired(_ reports: [(name: String, date: Date)], now: Date, kept: Int = kept,
                               maxAge: TimeInterval = maxAge) -> [String] {
        let newest = reports.sorted { $0.date > $1.date }
        return newest.enumerated().filter { index, report in
            index >= kept || now.timeIntervalSince(report.date) > maxAge
        }.map(\.element.name)
    }

    /// "2026-10-31 14:05:12 UTC": one fixed form, whatever the Mac's language.
    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return formatter.string(from: date)
    }
}
