import AppKit
import CrashCatcher
import SeawallCore

/// Opt-in crash reports, without any third-party SDK.
///
/// With "Offer to send crash reports" on, a crash writes a small text report to
/// ~/Library/Application Support/Seawall/Crashes: versions, the signal or exception, and the
/// stack. On the next launch it's scrubbed again and Seawall asks, once, whether to email it.
/// Nothing is sent without that "yes", and Seawall never sends anything itself: Mail opens
/// with the email ready and the file shown in Finder to attach.
///
/// With it off, no handlers are installed and saved reports are deleted.
///
/// Why not the alternatives: macOS's own `.ips` reports in ~/Library/Logs/DiagnosticReports
/// aren't scrubbed and hold paths and the user name, so attaching them would mean editing a
/// large JSON file the person can't easily check. MetricKit's crash diagnostics do exist on
/// macOS 12+, but they arrive whenever the system decides, often a day later or not at all for
/// an app run outside the App Store, and they'd need scrubbing too.
@MainActor
final class CrashReporter: ObservableObject {
    static let shared = CrashReporter()

    /// Finished reports, newest first, for Settings.
    @Published private(set) var reports: [URL] = []

    private var installed = false
    /// Reports already offered, by file name, so a "Not Now" isn't asked again.
    private let offeredKey = "crashReportsOffered"
    /// Long enough for a relaunch mid-block to have put every block back before asking.
    private static let offerDelay: TimeInterval = 5

    private var folder: URL { Diagnostics.folder("Crashes") }

    /// At launch, before the blocks are restored, so a crash while restoring is caught too.
    /// Finishes what the last crash left; the offer itself comes a few seconds later.
    func start(controller: BlockController) {
        guard Preferences.shared.crashReports else {
            deleteAll()
            return
        }
        install()
        finishRaw(scrubber: Diagnostics.scrubber(controller))
        tidy()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.offerDelay) { [weak self] in
            self?.offer()
        }
    }

    /// From Settings.
    func setEnabled(_ on: Bool) {
        if on {
            install()
        } else {
            uninstall()
            deleteAll()
        }
    }

    // MARK: - Catching

    private func install() {
        let path = folder.appendingPathComponent("run-\(Int(Date().timeIntervalSince1970))-\(getpid()).\(CrashReport.rawEnding)").path
        let header = CrashReport.header(Diagnostics.info, launchedAt: Diagnostics.launchedAt)
        guard seawall_crash_install(path, header) == 0 else {
            log.error("Crash reports: couldn't set up the handler")
            return
        }
        NSSetUncaughtExceptionHandler(handleUncaughtException)
        installed = true
        log.notice("Crash reports are on")
    }

    private func uninstall() {
        guard installed else { return }
        seawall_crash_uninstall()
        NSSetUncaughtExceptionHandler(nil)
        installed = false
        log.notice("Crash reports are off")
    }

    // MARK: - After a crash

    /// Turns each raw report a crash left behind into a scrubbed `.txt`. The raw file is deleted.
    private func finishRaw(scrubber: LogScrubber) {
        for raw in files(ending: CrashReport.rawEnding) {
            let date = modified(raw)
            if let text = try? String(contentsOf: raw, encoding: .utf8), !text.isEmpty {
                let report = CrashReport.finish(text, scrubber: scrubber)
                try? report.write(to: folder.appendingPathComponent(CrashReport.fileName(date)), atomically: true, encoding: .utf8)
            }
            try? FileManager.default.removeItem(at: raw)
        }
    }

    /// Keeps a handful of recent reports, never a growing pile.
    private func tidy() {
        let current = files(ending: CrashReport.reportEnding)
        let expired = Set(CrashReport.expired(current.map { (name: $0.lastPathComponent, date: modified($0)) }, now: Date()))
        for file in current where expired.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
        refresh()
    }

    func refresh() {
        reports = files(ending: CrashReport.reportEnding).sorted { modified($0) > modified($1) }
        var offered = Set(UserDefaults.standard.stringArray(forKey: offeredKey) ?? [])
        offered.formIntersection(reports.map(\.lastPathComponent))
        UserDefaults.standard.set(Array(offered), forKey: offeredKey)
    }

    /// Asks once about the newest report not yet offered. Every block is already back by now,
    /// and the 0.5-second timer keeps enforcing while the alert is up (it runs in the common
    /// run loop modes, modal ones included), so answering it can wait.
    private func offer() {
        // The "End now?" question or a block summary on screen goes first.
        if NSApp.modalWindow != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.offerDelay) { [weak self] in self?.offer() }
            return
        }
        refresh()
        var offered = Set(UserDefaults.standard.stringArray(forKey: offeredKey) ?? [])
        let fresh = reports.filter { !offered.contains($0.lastPathComponent) }
        guard let report = fresh.first else { return }
        // Asked about once, whatever the answer, older unasked ones included.
        offered.formUnion(fresh.map(\.lastPathComponent))
        UserDefaults.standard.set(Array(offered), forKey: offeredKey)

        let alert = NSAlert()
        alert.messageText = "Seawall quit unexpectedly"
        alert.informativeText = "A short report is saved on this Mac: the versions and where in Seawall's code it stopped, "
            + "nothing about your lists or sites. Send it by email? Mail opens with the email ready, and the report is shown "
            + "in Finder to attach."
        alert.addButton(withTitle: "Send by Email…")
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "Delete Report")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: send(report)
        case .alertThirdButtonReturn: delete(report)
        default: break
        }
    }

    func send(_ report: URL) {
        let text = (try? String(contentsOf: report, encoding: .utf8)) ?? ""
        let mail = FeedbackMail.crash(Diagnostics.info, summary: CrashReport.summary(text), fileName: report.lastPathComponent)
        NSWorkspace.shared.activateFileViewerSelecting([report])
        Diagnostics.compose(mail, fallback: text)
    }

    func showInFinder() {
        refresh()
        NSWorkspace.shared.activateFileViewerSelecting(reports.isEmpty ? [folder] : reports)
    }

    func delete(_ report: URL) {
        try? FileManager.default.removeItem(at: report)
        refresh()
    }

    func deleteAll() {
        for file in files(ending: CrashReport.rawEnding) + files(ending: CrashReport.reportEnding) {
            try? FileManager.default.removeItem(at: file)
        }
        UserDefaults.standard.removeObject(forKey: offeredKey)
        refresh()
    }

    private func files(ending: String) -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return all.filter { $0.pathExtension == ending }
    }

    private func modified(_ file: URL) -> Date {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
    }

    // MARK: - Test crash

    /// For testing crash reports on a Mac: launch with `SEAWALL_TEST_CRASH` set and Seawall
    /// crashes on purpose 10 seconds later, once the launch has settled.
    ///
    ///     open --env SEAWALL_TEST_CRASH=trap -a Seawall
    ///
    /// `trap` (or `1`) is a Swift runtime trap, `segv` a bad memory access, `exception` an
    /// uncaught Objective-C exception. The variable only reaches that one launch: the watchdog
    /// relaunches with a plain `open`, so it can't turn into a crash loop. Nothing in the app
    /// sets it, so it can't happen by accident. Crashing mid-block is fine; the watchdog
    /// brings Seawall back and the block with it.
    static func crashForTestingIfAsked() {
        guard let kind = ProcessInfo.processInfo.environment["SEAWALL_TEST_CRASH"], !kind.isEmpty, kind != "0" else { return }
        log.notice("Test crash (\(kind, privacy: .public)) in 10 seconds")
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            switch kind {
            case "segv":
                UnsafeMutablePointer<Int>(bitPattern: 8)!.pointee = 1
            case "exception":
                // On a thread of its own: AppKit catches exceptions on the main thread, reports
                // them to the console and carries on, so those never reach the handler (or crash).
                Thread.detachNewThread {
                    NSException(name: .genericException, reason: "Seawall test crash", userInfo: nil).raise()
                }
            default:
                fatalError("Seawall test crash")
            }
        }
    }
}

/// Uncaught Objective-C exceptions: their name, reason and stack go in the report, then the
/// runtime aborts and the signal handler adds the rest. Exceptions AppKit catches on the main
/// thread never get here; it logs them and Seawall keeps running. A free function, because the handler
/// is a C function pointer. Scrubbed here already, and again when the report is finished.
private func handleUncaughtException(_ exception: NSException) {
    let reason = LogScrubber().scrub(exception.reason ?? "")
    let text = "Exception: \(exception.name.rawValue)\nReason: \(reason)\nException stack:\n"
        + exception.callStackSymbols.joined(separator: "\n")
    seawall_crash_write_exception(text)
}
