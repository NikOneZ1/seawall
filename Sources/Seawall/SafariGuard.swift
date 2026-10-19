import AppKit
import CoreServices

enum SafariAccess: Equatable {
    case unknown, granted, denied
}

struct SafariTab {
    let windowID: Int
    let index: Int
    let url: URL
}

enum SafariError: Error {
    /// The user said no to "Seawall wants to control Safari" (or revoked it later).
    case notPermitted
    case failed(Int)
}

/// Reads and rewrites Safari tab URLs over Apple Events. No extension needed:
/// just the one-time Automation permission prompt.
@MainActor
final class SafariGuard {
    nonisolated static let bundleID = "com.apple.Safari"

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Returns `{{windowID, {url, url, …}}, …}`. Falls back to tab-by-tab reads when a window
    /// has a tab without a URL, so one blank tab can't hide the rest of the window.
    private static let listSource = """
        tell application id "com.apple.Safari"
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

    private let listScript = NSAppleScript(source: listSource)

    func tabs() -> Result<[SafariTab], SafariError> {
        guard let listScript else { return .failure(.failed(0)) }
        var errorInfo: NSDictionary?
        let result = listScript.executeAndReturnError(&errorInfo)
        if let errorInfo { return .failure(Self.error(from: errorInfo)) }

        var tabs: [SafariTab] = []
        for window in result.items {
            guard let windowID = window.atIndex(1)?.int32Value, let urls = window.atIndex(2) else { continue }
            for (offset, item) in urls.items.enumerated() {
                guard let string = item.stringValue, let url = URL(string: string) else { continue }
                tabs.append(SafariTab(windowID: Int(windowID), index: offset + 1, url: url))
            }
        }
        return .success(tabs)
    }

    @discardableResult
    func redirect(_ tab: SafariTab, to target: String) -> Bool {
        let escaped = target
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
            tell application id "\(Self.bundleID)" to set URL of tab \(tab.index) of window id \(tab.windowID) to "\(escaped)"
            """
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            log.error("Safari redirect failed: \(errorInfo, privacy: .public)")
            return false
        }
        return true
    }

    /// Used when we're not allowed to look at tabs: no permission, no Safari during a block.
    func quitSafari() {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).forEach(AppGuard.close)
    }

    /// `nil` when Safari isn't running — permission can only be checked against a live process.
    /// With `ask: true` this shows the system prompt and blocks until it's answered.
    nonisolated static func determineAccess(ask: Bool) -> SafariAccess? {
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

    private static func error(from info: NSDictionary) -> SafariError {
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
