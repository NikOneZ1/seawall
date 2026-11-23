#if DEBUG
import AppKit
import SeawallCore
import SwiftUI

/// Debug builds only: draws the menu (ready to lock, and during a block's wait to leave early)
/// and the welcome's first step to PNG files, light and dark, then quits. For checking the look.
///
///     SEAWALL_DATA_DIR=/tmp/demo build/Seawall.app/Contents/MacOS/Seawall --render-design-shots ~/Desktop/design-shots
///
/// Refuses to run without `SEAWALL_DATA_DIR`: it writes a made-up block into that folder, never
/// into the real one. Like `LicenseShots` it runs before the app starts, so there's no menu bar
/// item, no watchdog and no guards, and it can run beside an installed Seawall.
@MainActor
enum DesignShots {
    static let argument = "--render-design-shots"

    static func runIfAsked() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: argument) else { return }
        guard index + 1 < arguments.count, ProcessInfo.processInfo.environment["SEAWALL_DATA_DIR"] != nil else {
            FileHandle.standardError.write(Data("usage: SEAWALL_DATA_DIR=<demo folder> Seawall \(argument) <folder>\n".utf8))
            exit(2)
        }
        let folder = URL(fileURLWithPath: (arguments[index + 1] as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = Store()

        // Ready to lock: no blocks.
        store.remove(.sessions)
        let idle = BlockController()
        for dark in [false, true] {
            draw(menu(idle), width: 320, height: nil, dark: dark, to: folder.appendingPathComponent("menu-\(dark ? "dark" : "light").png"))
            draw(WelcomeView().environmentObject(idle), width: 560, height: 640, dark: dark,
                 to: folder.appendingPathComponent("welcome-\(dark ? "dark" : "light").png"))
        }

        // During a block, a few seconds into the wait to leave early.
        if let list = idle.config.lists.first {
            let now = Date()
            var session = Session(list, startedAt: now - 23 * 60, endsAt: now + 97, earlyExit: .wait10, otherBrowsersInstalled: false)
            session.unlockRequestedAt = now - 2
            session.siteAttempts = 1
            store.save([session], as: .sessions)
            let locked = BlockController()
            for dark in [false, true] {
                draw(menu(locked), width: 320, height: nil, dark: dark, to: folder.appendingPathComponent("locked-\(dark ? "dark" : "light").png"))
            }
            store.remove(.sessions)
        }
        exit(0)
    }

    private static func menu(_ controller: BlockController) -> some View {
        MenuView()
            .environmentObject(controller)
            .tint(Color.ink)
            .buttonStyle(SoftButtonStyle())
    }

    private static func draw(_ view: some View, width: CGFloat, height: CGFloat?, dark: Bool, to url: URL) {
        guard let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) else { return }
        let root = view
            .frame(width: width, height: height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = appearance
        let size = NSSize(width: width, height: height ?? hosting.fittingSize.height)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = hosting
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        appearance.performAsCurrentDrawingAppearance { hosting.cacheDisplay(in: hosting.bounds, to: rep) }
        window.orderOut(nil)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
