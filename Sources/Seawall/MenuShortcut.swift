import AppKit
import Carbon.HIToolbox

/// ⌃⌥⌘L opens the menu from anywhere. (⌥⌘L alone is Downloads in Safari and Finder.)
/// A Carbon hot key needs no Accessibility permission.
@MainActor
final class MenuShortcut {
    static let shared = MenuShortcut()
    static let title = "⌃⌥⌘L"

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func update(_ on: Bool) {
        if on { register() } else { unregister() }
    }

    private func register() {
        guard hotKey == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { MenuShortcut.openMenu() } }
            return noErr
        }, 1, &pressed, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x5357_4C4C), id: 1)  // "SWLL"
        RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(controlKey | optionKey | cmdKey), id,
                            GetApplicationEventTarget(), 0, &hotKey)
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    /// Clicks Seawall's own lock in the menu bar, so the menu opens (or closes) where it always does.
    static func openMenu() {
        for window in NSApp.windows where window.className.contains("StatusBar") {
            if let button = window.contentView.flatMap(statusButton) {
                button.performClick(nil)
                return
            }
        }
    }

    /// Closes the menu if it's open. Left open over a window, it takes that window's first
    /// click just to close itself. Clicking the lock again, rather than closing the panel
    /// directly, keeps the menu bar item in step.
    static func closeMenu() {
        let open = NSApp.windows.contains { $0.isVisible && $0.className.contains("MenuBarExtraWindow") }
        if open { openMenu() }
    }

    private static func statusButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = statusButton(in: subview) { return button }
        }
        return nil
    }
}
