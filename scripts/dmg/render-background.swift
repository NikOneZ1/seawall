// Renders the installer-DMG background at @1x (640x400) and @2x (1280x800), in the Soft look:
// white paper, an ink arrow from the app to Applications, and the line in Barlow Semi Condensed,
// the same embedded font as the blocked page (Sources/SeawallCore/BlockedPageFonts.swift).
// No colour but ink: Finder shows the picture as is in light and dark mode, and the two icons
// bring their own.
//
//     swift scripts/dmg/render-background.swift
//
// The committed PNGs in this folder are what make-dmg.sh uses; run this again only if you
// change the design. Icon positions match make-dmg.sh: centres at (160, 186) and (480, 186).
import AppKit
import WebKit

let folder = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let root = folder.deletingLastPathComponent().deletingLastPathComponent()
let fontsSwift = try! String(contentsOf: root.appendingPathComponent("Sources/SeawallCore/BlockedPageFonts.swift"), encoding: .utf8)
let fontCSS: String = {
    guard let start = fontsSwift.range(of: "##\"\"\"\n"), let end = fontsSwift.range(of: "\n\"\"\"##") else {
        fatalError("render-background: can't find the font CSS in BlockedPageFonts.swift")
    }
    return String(fontsSwift[start.upperBound..<end.lowerBound])
}()

let html = """
<!doctype html><html><head><meta charset="utf-8"><style>
\(fontCSS)
html,body{margin:0;width:640px;height:400px;background:#FFFFFF;overflow:hidden}
h1{position:absolute;left:0;right:0;top:34px;margin:0;text-align:center;color:#161616;
   font:700 22px/1 "Barlow Semi Condensed",sans-serif;letter-spacing:-.005em}
p{position:absolute;left:0;right:0;top:330px;margin:0;text-align:center;color:#6B6B67;font:400 14px/1 "Barlow",sans-serif}
svg{position:absolute;left:0;top:0}
</style></head><body>
<h1>Drag Seawall to Applications</h1>
<svg width="640" height="400" viewBox="0 0 640 400" aria-hidden="true">
  <path d="M244 186H386" stroke="#161616" stroke-width="5" stroke-linecap="round" fill="none"/>
  <path d="M372 172 388 186 372 200" stroke="#161616" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
</svg>
<p>Then open it from Applications.</p>
</body></html>
"""

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

final class Renderer: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            _ = try? await webView.callAsyncJavaScript("await document.fonts.ready", contentWorld: .page)
            try? await Task.sleep(for: .milliseconds(300))
            for scale in [1, 2] {
                let config = WKSnapshotConfiguration()
                config.rect = NSRect(x: 0, y: 0, width: 640, height: 400)
                config.snapshotWidth = NSNumber(value: 640 * scale / Int(NSScreen.main?.backingScaleFactor ?? 2))
                let image = try! await webView.takeSnapshot(configuration: config)
                // Draw into an exact pixel size, whatever the screen's scale.
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640 * scale, pixelsHigh: 400 * scale,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                NSGraphicsContext.current?.imageInterpolation = .high
                image.draw(in: NSRect(x: 0, y: 0, width: 640 * scale, height: 400 * scale))
                NSGraphicsContext.restoreGraphicsState()
                rep.size = NSSize(width: 640, height: 400)
                let url = folder.appendingPathComponent("background@\(scale)x.png")
                try! rep.representation(using: .png, properties: [:])!.write(to: url)
                print("wrote \(url.path)")
            }
            exit(0)
        }
    }
}

let renderer = Renderer()
renderer.web.navigationDelegate = renderer
renderer.web.appearance = NSAppearance(named: .aqua)
let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 640, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
window.contentView = renderer.web
window.orderBack(nil)
renderer.web.loadHTMLString(html, baseURL: nil)
DispatchQueue.main.asyncAfter(deadline: .now() + 30) { print("render-background: timed out"); exit(1) }
app.run()
