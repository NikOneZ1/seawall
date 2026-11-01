import AppKit
import CoreServices
import SeawallCore

enum BrowserAccess: Equatable {
    case unknown, granted, denied
}

struct BrowserTab {
    let windowID: Int
    let index: Int
    let url: URL
}

enum BrowserError: Error {
    /// The user said no to "Seawall wants to control …" (or revoked it later).
    case notPermitted
    case failed(Int)
}

/// Reads and rewrites one browser's tab URLs over Apple Events. Safari and the Chromium
/// browsers in `KnownBrowsers.readable` share the same words for windows, tabs and URLs, so
/// one script fits them all. No extension needed: just a one-time Automation prompt per browser.
@MainActor
final class BrowserGuard {
    let browser: BlockedApp
    var bundleID: String { browser.bundleID }
    var name: String { browser.name }

    init(_ browser: BlockedApp) {
        self.browser = browser
        listScript = NSAppleScript(source: Self.listSource(for: browser.bundleID))
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    /// Returns `{{windowID, {url, url, …}}, …}`. Falls back to tab-by-tab reads when a window
    /// has a tab without a URL, so one blank tab can't hide the rest of the window.
    private static func listSource(for bundleID: String) -> String {
        """
        tell application id "\(bundleID)"
            set out to {}
            repeat with w in windows
                try
                    set wid to id of w
                    try
                        set urls to URL of tabs of w
                    on error
                        set urls to {}
                        repeat with t in tabs of w
                            try
                                set end of urls to (URL of t)
                            on error
                                set end of urls to ""
                            end try
                        end repeat
                    end try
                    set end of out to {wid, urls}
                end try
            end repeat
            return out
        end tell
        """
    }

    private let listScript: NSAppleScript?

    func tabs() -> Result<[BrowserTab], BrowserError> {
        guard let listScript else { return .failure(.failed(0)) }
        var errorInfo: NSDictionary?
        let result = listScript.executeAndReturnError(&errorInfo)
        if let errorInfo { return .failure(Self.error(from: errorInfo)) }

        var tabs: [BrowserTab] = []
        for window in result.items {
            guard let windowID = window.atIndex(1)?.int32Value, let urls = window.atIndex(2) else { continue }
            for (offset, item) in urls.items.enumerated() {
                guard let string = item.stringValue, let url = URL(string: string) else { continue }
                tabs.append(BrowserTab(windowID: Int(windowID), index: offset + 1, url: url))
            }
        }
        return .success(tabs)
    }

    @discardableResult
    func redirect(_ tab: BrowserTab, to target: String) -> Bool {
        let escaped = target
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
            tell application id "\(bundleID)" to set URL of tab \(tab.index) of window id \(tab.windowID) to "\(escaped)"
            """
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            // Only the error number: the message can quote the script, and with it the blocked address.
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            log.error("\(self.name, privacy: .public) redirect failed: \(code)")
            return false
        }
        return true
    }

    /// Used when we can't look at tabs: no permission, or the browser stopped answering.
    func quit() {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach(AppGuard.close)
    }

    /// `nil` when the browser isn't running: permission can only be checked against a live process.
    /// With `ask: true` this shows the system prompt and blocks until it's answered.
    nonisolated static func determineAccess(_ bundleID: String, ask: Bool) -> BrowserAccess? {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        let status = AEDeterminePermissionToAutomateTarget(
            target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
        switch status {
        case 0: return .granted
        case -1743: return .denied  // errAEEventNotPermitted
        case -1744: return .unknown  // errAEEventWouldRequireUserConsent
        default: return nil  // procNotFound and friends
        }
    }

    private static func error(from info: NSDictionary) -> BrowserError {
        let code = info[NSAppleScript.errorNumber] as? Int ?? 0
        return code == -1743 ? .notPermitted : .failed(code)
    }
}

private extension NSAppleEventDescriptor {
    var items: [NSAppleEventDescriptor] {
        guard numberOfItems > 0 else { return [] }
        return (1...numberOfItems).compactMap { atIndex($0) }
    }
}
