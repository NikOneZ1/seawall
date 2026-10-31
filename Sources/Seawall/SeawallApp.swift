import SeawallCore
import SwiftUI

@main
struct SeawallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(appDelegate.controller)
        } label: {
            MenuBarLabel(state: appDelegate.controller.menuBar)
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
        Updates.shared.start(blocks: controller)

        if !UserDefaults.standard.bool(forKey: Self.welcomeShownKey) {
            UserDefaults.standard.set(true, forKey: Self.welcomeShownKey)
            Panels.showWelcome(controller: controller)
        }
    }

    private static let welcomeShownKey = "welcomeShown"

    /// `seawall://lock?list=Work&until=18:00`, from Shortcuts, Raycast or a Focus automation.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let link = LockLink(url) { controller.lock(link) }
        }
    }

    /// The watchdog `open`s the app every few seconds during a block; that must stay invisible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }
}

/// What the menu bar shows. Kept apart from the controller, which ticks every second: redrawing
/// the status item that often kept an idle Seawall at a steady 2% CPU.
@MainActor
final class MenuBarState: ObservableObject {
    /// "18:00", or "1h 24m" left, while anything is blocked.
    @Published private(set) var blockedUntil: String?
    /// How far along until everything opens, in steps of `SlabGlyph.ringSteps`.
    @Published private(set) var step: Int?

    func update(_ text: String?, progress: Double?) {
        if blockedUntil != text { blockedUntil = text }
        let step = progress.map { Int(($0 * Double(SlabGlyph.ringSteps)).rounded(.down)) }
        if self.step != step { self.step = step }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var state: MenuBarState

    var body: some View {
        if let until = state.blockedUntil {
            HStack(spacing: 4) {
                Image(nsImage: SlabGlyph.ring(step: state.step ?? 0))
                Text(until)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Seawall, locked until \(until)")
        } else {
            Image(nsImage: SlabGlyph.open)
        }
    }
}
