// Renders Resources/AppIcon.svg into Resources/AppIcon.icns. WebKit draws the SVG, so its
// blurs and gradients come out exactly as in a browser. Run from the repo root:
//
//   swift scripts/render-icon.swift
import AppKit
import WebKit

let svgURL = URL(fileURLWithPath: "Resources/AppIcon.svg")
let icnsURL = URL(fileURLWithPath: "Resources/AppIcon.icns")
let side: CGFloat = 1024

@MainActor
final class Renderer: NSObject, WKNavigationDelegate {
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: side, height: side))

    func start() throws {
        let svg = try Data(contentsOf: svgURL).base64EncodedString()
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = self
        view.loadHTMLString("""
            <html><body style="margin:0;background:transparent">
            <img src="data:image/svg+xml;base64,\(svg)" width="\(Int(side))" height="\(Int(side))" style="display:block">
            </body></html>
            """, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let config = WKSnapshotConfiguration()
        config.rect = NSRect(x: 0, y: 0, width: side, height: side)
        webView.takeSnapshot(with: config) { image, error in
            guard let image else { fail(error?.localizedDescription ?? "snapshot failed") }
            do { try writeIcns(from: image) } catch { fail(error.localizedDescription) }
            print("Wrote \(icnsURL.path)")
            exit(0)
        }
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("render-icon: \(message)\n".utf8))
    exit(1)
}

/// Every size macOS asks an .icns for, downscaled from the one snapshot.
func writeIcns(from image: NSImage) throws {
    let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = points * scale
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0) else { fail("no bitmap") }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
            NSGraphicsContext.restoreGraphicsState()
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
        }
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
    try iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else { fail("iconutil failed") }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = MainActor.assumeIsolated { Renderer() }
MainActor.assumeIsolated {
    do { try renderer.start() } catch { fail(error.localizedDescription) }
}
app.run()
