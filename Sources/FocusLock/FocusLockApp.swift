import FocusLockCore
import SwiftUI

@main
struct FocusLockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(appDelegate.controller)
        } label: {
            MenuBarLabel(controller: appDelegate.controller)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = BlockController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != NSRunningApplication.current }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }
        controller.launch()
    }

    /// The watchdog `open`s the app every few seconds during a block; that must stay invisible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }
}

struct MenuBarLabel: View {
    @ObservedObject var controller: BlockController

    var body: some View {
        if let until = controller.blockedUntil {
            HStack(spacing: 4) {
                Image(nsImage: SlabGlyph.locked)
                Text(Format.clockTime(until, relativeTo: controller.now))
            }
        } else {
            Image(nsImage: SlabGlyph.open)
        }
    }
}
