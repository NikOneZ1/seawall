import AppKit
import SeawallCore
import UserNotifications

/// Quiet word about blocks: "5 minutes left", and how one went once it's over. Both are
/// notifications rather than dialogs, so they never take over the screen. Without permission
/// (or with them off in Settings) the end of a block falls back to the old dialog.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private let center = UNUserNotificationCenter.current()
    private var allowed = false

    /// Blocks shorter than this get no "5 minutes left": it would arrive almost at once.
    private static let warning: TimeInterval = 5 * 60

    func setUp() {
        center.delegate = self
        Task { allowed = await center.notificationSettings().authorizationStatus == .authorized }
    }

    /// Asked the first time a block starts, when the reason is obvious.
    private func permitted() async -> Bool {
        guard Preferences.shared.notifications else { return false }
        if !allowed {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        return allowed
    }

    func blockStarted(_ session: Session) {
        Task {
            let lead = session.endsAt.timeIntervalSinceNow - Self.warning
            guard lead > 60, await permitted() else { return }
            let content = UNMutableNotificationContent()
            content.title = "5 minutes left"
            content.body = "\(session.names) open again at \(Format.clockTime(session.endsAt, relativeTo: Date()))."
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: lead, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: Self.id(session), content: content, trigger: trigger))
        }
    }

    /// Posts how a block went. False when it couldn't, so the caller shows a dialog instead.
    func blockEnded(_ session: Session, _ summary: SessionSummary) -> Bool {
        center.removePendingNotificationRequests(withIdentifiers: [Self.id(session)])
        guard Preferences.shared.notifications, allowed else { return false }
        let content = UNMutableNotificationContent()
        content.title = summary.endedEarly ? "Block lifted early" : "Block is over"
        content.body = Format.summary(summary)
        // The block's own end sound plays instead, when sounds are on.
        content.sound = Preferences.shared.sounds ? nil : .default
        center.add(UNNotificationRequest(identifier: Self.id(session) + ".over", content: content, trigger: nil))
        return true
    }

    private static func id(_ session: Session) -> String {
        "block.\(Int(session.startedAt.timeIntervalSince1970))"
    }

    /// Seawall has no Dock icon and is rarely "in front", but its notifications should still show.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

/// Two soft system sounds: deep sonar when a block starts, light glass when one ends.
@MainActor
enum Sounds {
    static func locked() { play("Submarine") }
    static func over() { play("Glass") }

    private static func play(_ name: String) {
        guard Preferences.shared.sounds else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
