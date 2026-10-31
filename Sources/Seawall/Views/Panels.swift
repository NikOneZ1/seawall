import AppKit
import SwiftUI

/// The Seawall window and the welcome. Seawall has no Dock icon, so opening one has to bring
/// the app forward itself, onto whatever Space is in front.
@MainActor
enum Panels {
    private static var windows: [String: NSWindow] = [:]
    static let main = MainWindowModel()

    /// Opens the Seawall window at a list, Schedules, Today or Settings.
    static func showMain(_ section: MainSection, controller: BlockController) {
        MenuShortcut.closeMenu()
        main.selection = section.resolved(in: controller)
        if let window = windows["main"] {
            bringForward(window)
            return
        }
        let host = NSHostingController(rootView: MainWindowView(model: main).environmentObject(controller))
        // A real toolbar gives the title its own bar, so scrolled content passes under glass
        // instead of under the bare title.
        host.sceneBridgingOptions = [.title, .toolbars]
        let window = NSWindow(contentViewController: host)
        window.title = "Seawall"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbar = NSToolbar(identifier: "SeawallMain")
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 780, height: 600))
        window.contentMinSize = NSSize(width: 680, height: 480)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.setFrameAutosaveName("SeawallMain")
        window.center()
        windows["main"] = window
        bringForward(window)
    }

    /// A new, empty list, picked for the next block and open in the window with its name ready to type.
    static func showNewList(controller: BlockController) {
        let id = controller.addList()
        controller.config.next.listID = id
        main.focusName = id
        showMain(.list(id), controller: controller)
    }

    static func showWelcome(controller: BlockController) {
        MenuShortcut.closeMenu()
        if let window = windows["welcome"] {
            bringForward(window)
            return
        }
        let host = NSHostingController(rootView: WelcomeView().environmentObject(controller))
        let window = NSWindow(contentViewController: host)
        window.title = "Welcome to Seawall"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.setContentSize(NSSize(width: 560, height: 640))
        window.center()
        windows["welcome"] = window
        bringForward(window)
    }

    /// "Activate Seawall": a key field and a Buy link, shown when a block couldn't start without a license.
    static func showActivate(reason: String?) {
        MenuShortcut.closeMenu()
        let view = ActivateView(reason: reason)
        if let window = windows["activate"], let host = window.contentViewController as? NSHostingController<ActivateView> {
            host.rootView = view
            bringForward(window)
            return
        }
        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.title = "Activate Seawall"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        windows["activate"] = window
        bringForward(window)
    }

    static func close(_ id: String) {
        windows[id]?.close()
    }

    /// The menu never makes Seawall the active app, so a plain `activate()` is only a request,
    /// and with some apps in front macOS turns it down: the window opened behind them and
    /// its first click went to bringing it forward.
    private static func bringForward(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Where the Seawall window is.
enum MainSection: Hashable {
    case list(UUID?)
    case schedules
    case today
    case settings

    /// A list section with no list picks the menu's list.
    @MainActor
    func resolved(in controller: BlockController) -> MainSection {
        if case .list(nil) = self { return .list(controller.selectedList?.id) }
        return self
    }
}

@MainActor
final class MainWindowModel: ObservableObject {
    @Published var selection: MainSection? = .list(nil)
    /// A list just made, whose name field takes the keyboard when it shows.
    @Published var focusName: UUID?
    /// A list whose "Delete?" question should come up, asked for from the sidebar.
    @Published var deleting: UUID?
}
