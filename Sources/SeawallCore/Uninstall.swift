import Foundation

/// Why Seawall can't be uninstalled right now. Uninstalling removes the watchdog and the
/// blocks with it, so it waits until nothing is held: it must never be a faster way out
/// than leaving early.
public enum UninstallRefusal: Equatable, Sendable {
    /// A block is running (on a break between rounds counts too), until `until`.
    case blockRunning(until: Date)
    /// A schedule's hours have come and its block is about to start, until `until`.
    case scheduleStarting(until: Date)

    /// The title of the alert that says no.
    public var title: String {
        switch self {
        case .blockRunning: "Seawall can't be uninstalled during a block"
        case .scheduleStarting: "A scheduled block is starting"
        }
    }

    /// What to do instead, for the alert and the line under the button in Settings.
    public func message(relativeTo now: Date, calendar: Calendar = .current) -> String {
        switch self {
        case .blockRunning(let until):
            "Something is blocked until \(Format.clockTime(until, relativeTo: now, calendar: calendar)). "
                + "Wait for the block to end, or leave it early from the menu if it allows that. "
                + "Then you can uninstall."
        case .scheduleStarting(let until):
            "A schedule locks a list until \(Format.clockTime(until, relativeTo: now, calendar: calendar)). "
                + "Wait for that block to end, or leave it early from the menu if it allows that. "
                + "Then you can uninstall."
        }
    }
}

/// What uninstalling decides and touches. The removal itself lives in the app.
public enum Uninstall {
    public static let bundleID = "com.nikitaverba.FocusLock"
    public static let watchdogLabel = "com.nikitaverba.FocusLock.watchdog"

    /// Why uninstalling has to wait, or `nil` when it can go ahead.
    ///
    /// `sessions`: every block known, in memory and on disk; a block that's over but not yet
    /// tidied away doesn't count. `schedules`: a schedule whose hours have come and that hasn't
    /// started its block yet is about to, on the next tick. `canStart` says whether a schedule
    /// would start anything at all (its list might be gone). Schedules that start later don't
    /// count: uninstalling removes them.
    public static func refusal(sessions: [Session], schedules: [Schedule], now: Date,
                               calendar: Calendar = .current,
                               canStart: (Schedule) -> Bool = { _ in true }) -> UninstallRefusal? {
        let running = sessions.filter { !$0.isOver(at: now) }
        if let until = running.map(\.endsAt).max() {
            return .blockRunning(until: until)
        }
        let starting = schedules.compactMap { schedule -> Date? in
            guard canStart(schedule), let stretch = schedule.due(at: now, calendar: calendar) else { return nil }
            return stretch.end
        }
        if let until = starting.max() {
            return .scheduleStarting(until: until)
        }
        return nil
    }

    /// The watchdog's LaunchAgent, which reopens the app during a block.
    public static func launchAgent(home: URL) -> URL {
        library(home).appendingPathComponent("LaunchAgents/\(watchdogLabel).plist")
    }

    /// Every file and folder Seawall (or macOS on its behalf) writes in the home folder, to
    /// delete on uninstall. Always built from the fixed bundle ID, never the running bundle's:
    /// an empty one would turn `Caches/<id>` into all of Caches. Preferences are left out: they go through `UserDefaults`, since
    /// deleting the plist under cfprefsd's feet can bring it back.
    public static func files(home: URL) -> [URL] {
        let library = library(home)
        return [
            launchAgent(home: home),
            // Lists, schedules, running blocks, history, finds, and the site icons in Icons/.
            library.appendingPathComponent("Application Support/Seawall", isDirectory: true),
            // Where the app kept them while it was called FocusLock; moved on first launch,
            // but left behind if both existed.
            library.appendingPathComponent("Application Support/FocusLock", isDirectory: true),
            // URLSession's cache and cookie store, from fetching site icons.
            library.appendingPathComponent("Caches/\(bundleID)", isDirectory: true),
            library.appendingPathComponent("HTTPStorages/\(bundleID)", isDirectory: true),
            library.appendingPathComponent("HTTPStorages/\(bundleID).binarycookies"),
            // Window positions macOS may keep when the app quits.
            library.appendingPathComponent("Saved Application State/\(bundleID).savedState", isDirectory: true),
        ]
    }

    /// The preferences file, for the docs and for checking it's gone. Removed through
    /// `UserDefaults.removePersistentDomain`, not deleted directly.
    public static func preferences(home: URL) -> URL {
        library(home).appendingPathComponent("Preferences/\(bundleID).plist")
    }

    private static func library(_ home: URL) -> URL {
        home.appendingPathComponent("Library", isDirectory: true)
    }
}
