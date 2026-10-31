import Foundation

/// What Seawall says about itself in a feedback or crash email: versions and the Mac, never
/// anything about lists, sites or browsing.
public struct AppInfo: Equatable, Sendable {
    public var version: String
    public var build: String
    /// `ProcessInfo.operatingSystemVersionString`, like "Version 14.5 (Build 23F79)".
    public var system: String
    /// "Mac14,2", from `hw.model`. Empty when it can't be read.
    public var model: String
    /// "arm64" or "x86_64".
    public var architecture: String

    public init(version: String, build: String, system: String, model: String, architecture: String) {
        self.version = version
        self.build = build
        self.system = system
        self.model = model
        self.architecture = architecture
    }

    /// "Seawall 0.1.0 (build 1)", "macOS Version 14.5 (Build 23F79)", "Mac14,2, arm64".
    public var lines: [String] {
        var lines = ["Seawall \(version) (build \(build))", "macOS \(system)"]
        let mac = [model, architecture].filter { !$0.isEmpty }.joined(separator: ", ")
        if !mac.isEmpty { lines.append("Mac: \(mac)") }
        return lines
    }
}

/// A `mailto:` link with everything after `?` percent-encoded, and what to do when it's too
/// long to open: Mail and other clients start cutting or refusing links past a couple of
/// thousand characters, so a long body goes in a file instead.
public struct FeedbackMail: Equatable, Sendable {
    public static let address = "hello@seawall.work"
    /// Kept well under what Mail and the URL handling around it put up with.
    public static let longestLink = 2000
    /// How much of the log goes in: the newest lines, at most this many…
    public static let logLines = 200
    /// …and at most this many bytes of them.
    public static let logBytes = 8 * 1024

    public var subject: String
    public var body: String

    public init(subject: String, body: String) {
        self.subject = subject
        self.body = body
    }

    /// The link Mail opens.
    public var link: String {
        "mailto:\(Self.address)?subject=\(Self.encode(subject))&body=\(Self.encode(body))"
    }

    public var fits: Bool { link.count <= Self.longestLink }

    // MARK: - Feedback

    /// "Seawall feedback (0.1.0, build 1)".
    public static func feedbackSubject(_ info: AppInfo) -> String {
        "Seawall feedback (\(info.version), build \(info.build))"
    }

    /// Room to write first, then what helps answer: versions, the Mac, the newest log lines.
    /// `logs` should already be scrubbed.
    public static func diagnostics(_ info: AppInfo, logs: [String], note: String? = nil) -> String {
        var text = "----\n" + info.lines.joined(separator: "\n") + "\n"
        if let note { text += note + "\n" }
        let tail = cap(logs)
        text += "\nRecent log (\(tail.count) \(Format.plural(tail.count, "line", "lines"))):\n"
        text += tail.isEmpty ? "(nothing logged)\n" : tail.joined(separator: "\n") + "\n"
        return text
    }

    /// The feedback email. When the whole of it would make the link too long, the email gets
    /// only the versions and a pointer to `savedAs`, and `overflow` is the full text to copy
    /// and save.
    public static func feedback(_ info: AppInfo, logs: [String], note: String? = nil,
                                savedAs: String) -> (mail: FeedbackMail, overflow: String?) {
        let subject = feedbackSubject(info)
        let full = blankArea + diagnostics(info, logs: logs, note: note)
        let mail = FeedbackMail(subject: subject, body: full)
        if mail.fits { return (mail, nil) }

        let short = blankArea + "----\n" + info.lines.joined(separator: "\n") + "\n\n"
            + "The recent log was too long for an email link. It's on the clipboard and saved as \(savedAs). "
            + "Paste it here or attach the file."
        return (FeedbackMail(subject: subject, body: short).shortened(), full)
    }

    /// Where the person writes, above everything Seawall adds.
    public static let blankArea = "\n\n\n"

    // MARK: - Crash reports

    /// "Seawall crash report (0.1.0, build 1)".
    public static func crashSubject(_ info: AppInfo) -> String {
        "Seawall crash report (\(info.version), build \(info.build))"
    }

    /// A crash report email: a few summary lines and a reminder to attach the file, which can be
    /// far too long for a link.
    public static func crash(_ info: AppInfo, summary: [String], fileName: String) -> FeedbackMail {
        let body = blankArea + "----\n"
            + "Please attach the report Seawall showed in Finder: \(fileName)\n\n"
            + (info.lines + summary).joined(separator: "\n") + "\n"
        return FeedbackMail(subject: crashSubject(info), body: body).shortened()
    }

    // MARK: - Parts

    /// The newest `logLines` lines that together stay under `logBytes`. A single line longer
    /// than that keeps its end.
    public static func cap(_ lines: [String], maxLines: Int = logLines, maxBytes: Int = logBytes) -> [String] {
        var kept: [String] = []
        var bytes = 0
        for line in lines.suffix(maxLines).reversed() {
            let size = line.utf8.count + 1
            if bytes + size > maxBytes {
                if kept.isEmpty { kept.append(String(decoding: Array(line.utf8.suffix(maxBytes - 1)), as: UTF8.self)) }
                break
            }
            kept.append(line)
            bytes += size
        }
        return kept.reversed()
    }

    /// Percent-encodes for a mailto query (RFC 6068): everything but letters, digits and `-._~`,
    /// so `&`, `=`, `+`, `#` and `%` in the text can't end a field early. Line breaks become CRLF.
    public static func encode(_ text: String) -> String {
        let normal = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
        let hex = Array("0123456789ABCDEF")
        var out = ""
        for byte in normal.utf8 {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"):
                out.append(Character(UnicodeScalar(byte)))
            default:
                out += "%" + String(hex[Int(byte >> 4)]) + String(hex[Int(byte & 0x0F)])
            }
        }
        return out
    }

    /// Cuts the body, on a character boundary, until the link fits. Only a safety net: the
    /// short bodies above fit anyway.
    func shortened() -> FeedbackMail {
        var mail = self
        while !mail.fits, !mail.body.isEmpty {
            let over = mail.link.count - Self.longestLink
            // An encoded character is at most 12 link characters (4 bytes), so this never cuts too little for long.
            mail.body = String(mail.body.dropLast(max(1, over / 12)))
        }
        return mail
    }
}
