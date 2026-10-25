import AppKit
import SeawallCore

/// The apps on this Mac, for the list editor's search box. Read once, in the background, from
/// the usual Applications folders; Seawall itself and Finder can't be blocked, so they're left out.
@MainActor
final class InstalledApps: ObservableObject {
    static let shared = InstalledApps()

    @Published private(set) var apps: [ListApp] = []
    private var loading = false

    func load() {
        guard apps.isEmpty, !loading else { return }
        loading = true
        Task.detached(priority: .utility) {
            let found = Self.scan()
            await MainActor.run {
                self.apps = found
                self.loading = false
            }
        }
    }

    /// Apps whose name starts with `query`, then those with a later word starting with it.
    func matches(_ query: String, limit: Int = 5) -> [ListApp] {
        let query = query.lowercased()
        guard !query.isEmpty else { return [] }
        let starts = apps.filter { $0.name.lowercased().hasPrefix(query) }
        let words = apps.filter { app in
            let name = app.name.lowercased()
            return !name.hasPrefix(query) && name.split(separator: " ").contains { $0.hasPrefix(query) }
        }
        return Array((starts + words).prefix(limit))
    }

    /// A list item for the app bundle at `url`, unless it's one Seawall won't block.
    nonisolated static func item(at url: URL) -> ListApp? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !excluded.contains(id) else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return ListApp(bundleID: id, name: name, path: url.path)
    }

    nonisolated private static let excluded: Set<String> = [
        Bundle.main.bundleIdentifier ?? "com.nikitaverba.FocusLock", "com.apple.finder", "com.apple.systempreferences",
    ]

    nonisolated private static func scan() -> [ListApp] {
        let fm = FileManager.default
        let folders = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
        var seen = Set<String>()
        var apps: [ListApp] = []
        for folder in folders {
            guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for url in items where url.pathExtension == "app" {
                guard let app = item(at: url), seen.insert(app.bundleID).inserted else { continue }
                apps.append(app)
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Installed browsers whose tabs can't be read, so "Other browsers" closes them. With none
/// installed the switch has nothing to do and stays out of sight.
enum InstalledBrowsers {
    static let unreadable: [(name: String, icon: NSImage)] = KnownBrowsers.unreadable.compactMap { browser in
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) else { return nil }
        return (browser.name, NSWorkspace.shared.icon(forFile: url.path))
    }
}
