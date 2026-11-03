#if DEBUG
import AppKit
import SeawallCore
import SwiftUI

/// Debug builds only: draws the license views to PNG files and quits, for PR screenshots.
///
///     build/Seawall.app/Contents/MacOS/Seawall --render-license-shots ~/Desktop/license-shots
///
/// Runs before the app starts (see `SeawallMain`): no menu bar item, no watchdog, no blocks, no
/// license model, Keychain, network or preferences. The views get made-up values instead.
/// Each view is hosted in an `NSHostingView` in an off-screen window and drawn with
/// `cacheDisplay`, which draws the AppKit-backed text fields and buttons properly, at 2x.
/// Add `--with-image-renderer` to draw with SwiftUI's `ImageRenderer` instead.
///
/// The whole file is compiled out of release builds; scripts/build-app.sh checks for that.
@MainActor
enum LicenseShots {
    static let argument = "--render-license-shots"

    /// Draws and exits when launched with the argument; returns at once otherwise.
    static func runIfAsked() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: argument) else { return }
        guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
            FileHandle.standardError.write(Data("usage: Seawall \(argument) <folder> [--with-image-renderer]\n".utf8))
            exit(2)
        }
        let folder = URL(fileURLWithPath: (arguments[index + 1] as NSString).expandingTildeInPath, isDirectory: true)
        let useImageRenderer = arguments.contains("--with-image-renderer")
        do {
            try render(into: folder, useImageRenderer: useImageRenderer)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("render-license-shots failed: \(error)\n".utf8))
            exit(1)
        }
    }

    // MARK: - States

    private enum Shot: String, CaseIterable {
        case empty, key, working, error, success
    }

    private struct Values {
        var key = ""
        var isWorking = false
        var failure: String?
        var isLicensed = false
    }

    private static let sampleKey = "6F3A2C9E-41B7-4D8A-9E25-7C1D0B8F4A63"

    private static func values(_ shot: Shot) -> Values {
        switch shot {
        case .empty: Values()
        case .key: Values(key: sampleKey)
        case .working: Values(key: sampleKey, isWorking: true)
        case .error: Values(key: sampleKey, failure: LicenseFailure.invalidKey.message)
        case .success: Values(isLicensed: true)
        }
    }

    /// "Licensed on this Mac · 1 of 3 Macs", worded by the real `LicenseInfo`.
    private static var licensedSummary: String {
        let now = Date()
        let record = LicenseRecord(instanceID: "shots", instanceName: "Seawall on Mac · shots", activatedAt: now,
                                   lastValidatedAt: now, activations: 1, activationLimit: 3)
        if case .licensed(let info) = LicenseState(record: record) { return info.summary }
        return "Licensed on this Mac"
    }

    // MARK: - Views

    /// The whole welcome window on its "Activate Seawall" step. The footer mirrors
    /// `WelcomeView.footer` on that step (Back, and Continue Without a Key or Continue).
    private static func welcome(_ shot: Shot) -> some View {
        let v = values(shot)
        let steps = Welcome.Step.shown(showsLicense: true)
        return WelcomeLayout {
            WelcomeLicenseStep(key: .constant(v.key), isWorking: v.isWorking, failure: v.failure,
                               isLicensed: v.isLicensed, buy: {}, activate: {})
        } footer: {
            HStack(spacing: Space.s) {
                WelcomeStepDots(count: steps.count, current: steps.firstIndex(of: .license) ?? 0)
                Spacer()
                Button("Back") {}
                if v.isLicensed {
                    Button("Continue") {}
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Continue Without a Key") {}
                }
            }
        }
    }

    /// Settings, License as a grouped form section. Activated, Settings shows `LicensedRow`.
    private static func settings(_ shot: Shot) -> some View {
        let v = values(shot)
        return Form {
            Section {
                if v.isLicensed {
                    LicensedRow(summary: licensedSummary, isWorking: false, deactivate: {})
                } else {
                    LicenseActivationForm(layout: .formRows, key: .constant(v.key), price: LicenseModel.price,
                                          buyURL: LicenseModel.buyURL, isWorking: v.isWorking, failure: v.failure,
                                          isLicensed: false, buy: {}, activate: {})
                }
            } header: {
                Text("License")
            }
        }
        .formStyle(.grouped)
    }

    private static func settingsHeight(_ shot: Shot) -> CGFloat {
        switch shot {
        case .success: 140
        case .error: 250
        default: 210
        }
    }

    // MARK: - Drawing

    private enum ShotError: Error {
        case bitmap, png
    }

    private static func render(into folder: URL, useImageRenderer: Bool) throws {
        // An app object for AppKit's controls and the app icon, without a Dock icon. It never runs.
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            for shot in Shot.allCases {
                let welcomeURL = folder.appendingPathComponent("welcome-license-\(shot.rawValue)-\(mode).png")
                try write(welcome(shot), size: CGSize(width: 560, height: 640), dark: dark,
                          useImageRenderer: useImageRenderer, to: welcomeURL)
                print(welcomeURL.path)
                let settingsURL = folder.appendingPathComponent("settings-license-\(shot.rawValue)-\(mode).png")
                try write(settings(shot), size: CGSize(width: 520, height: settingsHeight(shot)), dark: dark,
                          useImageRenderer: useImageRenderer, to: settingsURL)
                print(settingsURL.path)
            }
        }
    }

    private static func write(_ view: some View, size: CGSize, dark: Bool, useImageRenderer: Bool, to url: URL) throws {
        guard let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) else { throw ShotError.bitmap }
        let root = view
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)

        var png: Data?
        if useImageRenderer {
            let renderer = ImageRenderer(content: root)
            renderer.scale = 2
            appearance.performAsCurrentDrawingAppearance {
                if let image = renderer.cgImage {
                    png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                }
            }
        } else {
            let hosting = NSHostingView(rootView: root)
            hosting.frame = NSRect(origin: .zero, size: size)
            hosting.appearance = appearance
            // A key window in an active app, so prominent buttons draw in the accent colour as they do on screen.
            NSApplication.shared.setActivationPolicy(.accessory)
            NSApplication.shared.activate(ignoringOtherApps: true)
            let window = KeyableWindow(contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: size),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = appearance
            window.contentView = hosting
            window.orderFrontRegardless()
            window.makeKey()
            // Give SwiftUI a moment to lay out and attach its AppKit controls.
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()

            // 2x whatever the screen is: a bitmap twice the size in pixels, drawn at the view's size in points.
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
                                             pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0)
            else { throw ShotError.bitmap }
            rep.size = size
            appearance.performAsCurrentDrawingAppearance {
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
            }
            window.orderOut(nil)
            window.close()
            png = rep.representation(using: .png, properties: [:])
        }
        guard let png else { throw ShotError.png }
        try png.write(to: url)
    }
}
/// Borderless windows can't become key by default; the screenshots need a key window.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
#endif
