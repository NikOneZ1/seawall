import AppKit
import OSLog
import SeawallCore
import SystemConfiguration

/// "Send Feedback…": an email to hello@seawall.work with room to write, the versions, and the
/// last half hour of Seawall's own log, scrubbed. Nothing is sent by Seawall; Mail opens with
/// the email ready, and the person decides.
@MainActor
enum Diagnostics {
    nonisolated static let subsystem = "com.nikitaverba.FocusLock"
    /// How far back the log in a feedback email goes.
    static let logWindow: TimeInterval = 30 * 60
    /// When this run of Seawall started; read once at launch, so it's set then. The log can't
    /// see further back than this (see `readLog`).
    static let launchedAt = Date()

    static var info: AppInfo {
        let bundle = Bundle.main.infoDictionary ?? [:]
        return AppInfo(version: bundle["CFBundleShortVersionString"] as? String ?? "?",
                       build: bundle["CFBundleVersion"] as? String ?? "?",
                       system: ProcessInfo.processInfo.operatingSystemVersionString,
                       model: model, architecture: architecture)
    }

    /// "Mac14,2". Cheap: one sysctl.
    private static var model: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }

    /// Takes out everything that could say what someone blocks or browses: the lists, the
    /// running blocks, the schedules' list names, and who and which Mac this is.
    static func scrubber(_ controller: BlockController) -> LogScrubber {
        var secrets = LogScrubber.secrets(lists: controller.config.lists, sessions: controller.sessions,
                                          scheduleNames: controller.config.schedules.map(\.listName))
        secrets += [NSFullUserName(), ProcessInfo.processInfo.hostName]
        // "Nikita's MacBook Pro". Not Host.current(), which can wait on the network.
        if let name = SCDynamicStoreCopyComputerName(nil, nil) { secrets.append(name as String) }
        return LogScrubber(secrets: secrets, home: NSHomeDirectory(), userName: NSUserName())
    }

    /// Where saved diagnostics and crash reports live, next to the rest of Seawall's state.
    static func folder(_ name: String) -> URL {
        let url = Store().directory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// `~/Library/…` rather than `/Users/name/Library/…`, for text that goes in an email.
    static func shortPath(_ url: URL) -> String {
        let home = NSHomeDirectory()
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    // MARK: - Send Feedback

    static func sendFeedback(controller: BlockController) {
        MenuShortcut.closeMenu()
        let cleaner = Self.scrubber(controller)
        let appInfo = Self.info
        let since = max(Date() - logWindow, launchedAt)
        let file = folder("Diagnostics").appendingPathComponent("feedback-\(fileStamp()).txt")
        let note = "Log since \(Format.clockTime(since, relativeTo: Date())), this run of Seawall only."
        Task {
            // Reading the log store can take a moment; keep it off the main thread.
            let logs = await Task.detached { Diagnostics.readLog(since: since, scrubber: cleaner) }.value
            let (mail, overflow) = FeedbackMail.feedback(appInfo, logs: logs, note: note, savedAs: Diagnostics.shortPath(file))
            if let overflow {
                Diagnostics.keep(overflow, at: file)
            }
            Diagnostics.compose(mail, fallback: overflow ?? mail.body)
        }
    }

    /// Opens the email in the person's mail app. Without one, says where to write and puts
    /// the details on the clipboard.
    static func compose(_ mail: FeedbackMail, fallback: String) {
        if let url = URL(string: mail.link), NSWorkspace.shared.open(url) { return }
        copy(fallback)
        let alert = NSAlert()
        alert.messageText = "No email app is set up"
        alert.informativeText = "Write to \(FeedbackMail.address) from any email app. The details are on the clipboard; paste them in."
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    /// The full text, saved, shown in Finder and on the clipboard, for an email too long for a link.
    private static func keep(_ text: String, at file: URL) {
        removeOld(in: file.deletingLastPathComponent())
        try? text.write(to: file, atomically: true, encoding: .utf8)
        copy(text)
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Saved feedback is only needed until it's sent; a month is plenty.
    private static func removeOld(in folder: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(date) > CrashReport.maxAge { try? FileManager.default.removeItem(at: file) }
        }
    }

    private static func fileStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }

    // MARK: - The log

    /// Seawall's own log lines since `since`, each scrubbed, newest last.
    ///
    /// `OSLogStore(scope: .currentProcessIdentifier)` works without any entitlement, but only
    /// sees this process: after a relaunch, everything from the run before is out of reach.
    /// The `.system` scope would see older runs, but it needs the `com.apple.logging.local-store`
    /// entitlement (or admin rights), which a self-built, ad-hoc signed app can't have.
    /// Debug lines aren't kept by the log store, so they don't show up here either.
    nonisolated static func readLog(since: Date, scrubber: LogScrubber) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let entries = try store.getEntries(at: store.position(date: since),
                                               matching: NSPredicate(format: "subsystem == %@", subsystem))
            var lines: [String] = []
            for case let entry as OSLogEntryLog in entries where entry.date >= since {
                // Only the message is scrubbed: the time and level are Seawall's own.
                lines.append("\(formatter.string(from: entry.date)) \(level(entry.level)) [\(entry.category)] "
                    + scrubber.scrub(entry.composedMessage))
            }
            return FeedbackMail.cap(lines)
        } catch {
            return ["(The log couldn't be read: \(scrubber.scrub(error.localizedDescription)))"]
        }
    }

    nonisolated private static func level(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        default: "log"
        }
    }
}
