import AppKit

/// Site icons for the chips, fetched once from the site itself and kept on disk.
/// Until one arrives (or if a site has none) the chip shows a globe.
@MainActor
final class SiteIcons: ObservableObject {
    static let shared = SiteIcons()

    @Published private var icons: [String: NSImage] = [:]
    private var requested: Set<String> = []
    private let directory = Store().directory.appendingPathComponent("Icons", isDirectory: true)

    func icon(for host: String) -> NSImage? {
        if let icon = icons[host] { return icon }
        if requested.insert(host).inserted {
            // Never publish from inside a view update.
            Task { await load(host) }
        }
        return nil
    }

    private func load(_ host: String) async {
        let file = directory.appendingPathComponent("\(host).png")
        if let image = NSImage(contentsOf: file) {
            icons[host] = image
            return
        }
        // The touch icon is the crisp one; favicon.ico is the fallback nearly every site has.
        for path in ["/apple-touch-icon.png", "/favicon.ico"] {
            guard let url = URL(string: "https://\(host)\(path)"),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data), image.isValid,
                  let png = NSBitmapImageRep(data: image.tiffRepresentation ?? Data())?.representation(using: .png, properties: [:])
            else { continue }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? png.write(to: file, options: .atomic)
            icons[host] = image
            return
        }
    }
}
