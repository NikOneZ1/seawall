import AppKit
import SwiftUI

/// Ordinary windows for what doesn't fit in the menu: the welcome and Settings. They sit in
/// the same still water as the menu. Seawall has no Dock icon, so opening one has to bring
/// the app forward itself.
@MainActor
enum Panels {
    private static var windows: [String: NSWindow] = [:]

    static func show(_ id: String, title: String, size: NSSize, content: () -> some View) {
        if let window = windows[id] {
            bringForward(window)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // Open on whatever Space is in front, full-screen apps included, rather than back on
        // the desktop where the menu click can't be seen to do anything.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: content()
            .frame(width: size.width, height: size.height)
            .background(WaterBackground())
            .environment(\.colorScheme, .dark))
        // The window keeps the size it was made with instead of following the content.
        host.sizingOptions = []
        window.contentView = host
        window.center()
        windows[id] = window
        bringForward(window)
    }

    static func close(_ id: String) {
        windows[id]?.close()
    }

    private static func bringForward(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

extension Panels {
    static func showSettings(controller: BlockController) {
        show("settings", title: "Seawall Settings", size: NSSize(width: 480, height: 680)) {
            SettingsView().environmentObject(controller)
        }
    }

    static func showWelcome(controller: BlockController) {
        show("welcome", title: "Welcome to Seawall", size: NSSize(width: 460, height: 420)) {
            WelcomeView().environmentObject(controller)
        }
    }
}
