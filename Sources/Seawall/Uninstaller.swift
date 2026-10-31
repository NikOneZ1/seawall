import AppKit
import SeawallCore

/// "Uninstall Seawall…": removes everything Seawall put on this Mac, then quits.
///
/// Never while a block holds, or a schedule is about to start one (`Uninstall.refusal`): it
/// takes the watchdog down, so it must not be a faster way out than leaving early. The check
/// runs when asked and again, together with the teardown, once the user confirms.
@MainActor
enum Uninstaller {
    static func begin(controller: BlockController) {
        MenuShortcut.closeMenu()
        // Outside the button's action: runModal spins its own loop.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let refusal = controller.uninstallRefusal(at: Date()) {
                refuse(refusal)
                return
            }

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Uninstall Seawall?"
            alert.informativeText = confirmation(schedules: controller.config.schedules.count)
            // First button is the default, so Return cancels; Escape cancels too.
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Uninstall").hasDestructiveAction = true
            let trash = NSButton(checkboxWithTitle: "Also move Seawall to the Trash", target: nil, action: nil)
            trash.state = .on  // On by default: most people want the app gone too.
            alert.accessoryView = trash
            guard alert.runModal() == .alertSecondButtonReturn else { return }

            // The dialog may have been up a while: a schedule could have started meanwhile.
            if let refusal = controller.stopForUninstall() {
                refuse(refusal)
                return
            }
            finish(trashApp: trash.state == .on)
        }
    }

    /// What goes, said before it goes.
    private static func confirmation(schedules: Int) -> String {
        var lines = [
            "This removes from this Mac:",
            "• Your lists, schedules, Today history and finds",
            "• Seawall's settings and saved site icons",
            "• The helper that reopens Seawall during a block",
            "• Open at login",
            "• Seawall's permission to read browser tabs (Automation)",
            "",
        ]
        if schedules > 0 {
            lines.append(schedules == 1
                ? "Your schedule won't start a block again."
                : "Your \(schedules) schedules won't start blocks again.")
        }
        lines.append("Then Seawall quits. This can't be undone.")
        return lines.joined(separator: "\n")
    }

    private static func refuse(_ refusal: UninstallRefusal) {
        let alert = NSAlert()
        alert.messageText = refusal.title
        alert.informativeText = refusal.message(relativeTo: Date())
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Everything after the check, in order. The watchdog is already down (`stopForUninstall`).
    private static func finish(trashApp: Bool) {
        var leftovers: [String] = []

        Notifier.shared.removeAll()
        MenuShortcut.shared.update(false)

        let login = LoginItem.shared
        login.refresh()
        if login.isOn || login.needsApproval {
            login.set(false)
            if login.isOn || login.needsApproval {
                leftovers.append("Turn Seawall off in System Settings, General, Login Items.")
            }
        }

        // Closed windows don't save their frames into the preferences removed below.
        Panels.close("main")
        Panels.close("welcome")

        leftovers += removeData()

        if !resetAutomation() {
            leftovers.append("Forget the browser permission, in Terminal: tccutil reset AppleEvents \(Uninstall.bundleID)")
        }

        // Last, just before quitting: the app keeps running from the Trash until then.
        var trashFailed = false
        let app = Bundle.main.bundleURL
        if trashApp {
            do {
                // Run without a bundle (`swift run`), bundleURL is the build folder: leave that alone.
                guard app.pathExtension == "app" else { throw CocoaError(.fileWriteInvalidFileName) }
                try FileManager.default.trashItem(at: app, resultingItemURL: nil)
            } catch {
                log.error("Uninstall, moving the app to the Trash: \(error.localizedDescription, privacy: .public)")
                trashFailed = true
                leftovers.append("Drag Seawall from \(app.deletingLastPathComponent().path) to the Trash.")
            }
        }

        if !leftovers.isEmpty || !trashApp {
            let alert = NSAlert()
            alert.messageText = "Seawall is uninstalled"
            var text: [String] = []
            if !leftovers.isEmpty {
                text.append("A few things are left to do by hand:\n" + leftovers.map { "• \($0)" }.joined(separator: "\n"))
            }
            if !trashApp {
                text.append("To remove the app too, drag Seawall from \(app.deletingLastPathComponent().path) to the Trash.")
            }
            alert.informativeText = text.joined(separator: "\n\n")
            alert.addButton(withTitle: "Quit")
            if trashFailed || !trashApp { alert.addButton(withTitle: "Show in Finder") }
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([app])
            }
        }
        NSApp.terminate(nil)
    }

    /// Deletes Seawall's files and preferences. Called once while uninstalling and again as the
    /// app quits, for anything written in between (a site icon still downloading, a window frame).
    /// Returns what couldn't be removed, as steps for the user.
    @discardableResult
    static func removeData() -> [String] {
        var leftovers: [String] = []
        let files = FileManager.default
        for url in Uninstall.files(home: files.homeDirectoryForCurrentUser) where files.fileExists(atPath: url.path) {
            do {
                try files.removeItem(at: url)
            } catch {
                log.error("Uninstall, removing \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                leftovers.append("Delete \(url.path)")
            }
        }
        UserDefaults.standard.removePersistentDomain(forName: Uninstall.bundleID)
        UserDefaults.standard.synchronize()
        return leftovers
    }

    /// `tccutil reset AppleEvents <bundle ID>`: forgets "Seawall wants to control Safari" and the
    /// rest. It works without admin rights for the current user's own grants; if it fails anyway,
    /// the user gets the command to run.
    private static func resetAutomation() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "AppleEvents", Uninstall.bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log.error("Uninstall, tccutil: \(error.localizedDescription, privacy: .public)")
            return false
        }
        if process.terminationStatus != 0 { log.error("Uninstall, tccutil exited with \(process.terminationStatus)") }
        return process.terminationStatus == 0
    }
}
