import AppKit
import Sparkle

/// Automatic updates, through Sparkle. Only release builds carry the feed address and the
/// key updates are signed with (see scripts/build-app.sh); a build from a clone has neither,
/// so it never checks and Settings doesn't offer updates.
@MainActor
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    private var controller: SPUStandardUpdaterController?
    /// False while a check is already under way.
    @Published private(set) var canCheck = false
    /// Whether a block is running. An update waits for it to end before relaunching the app.
    var isBlocking: () -> Bool = { false }
    /// The relaunch Sparkle was asked to hold back until the blocks end.
    private var heldInstall: (() -> Void)?

    var isAvailable: Bool { controller != nil }

    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    /// Whether this build knows where to look for updates and how to trust them.
    static var isConfigured: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = info["SUFeedURL"] as? String ?? ""
        let key = info["SUPublicEDKey"] as? String ?? ""
        return !feed.isEmpty && !key.isEmpty
    }

    func start() {
        guard controller == nil, Self.isConfigured else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    func checkForUpdates() {
        // An agent app's windows open behind whatever is in front unless it steps forward.
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    /// Called when the last block ends: lets a held update install and relaunch.
    func blocksEnded() {
        guard let install = heldInstall else { return }
        heldInstall = nil
        install()
    }
}

extension Updater: SPUUpdaterDelegate {
    /// Relaunching mid-block would hand the watchdog a half-replaced app, so the install waits.
    nonisolated func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                             untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        MainActor.assumeIsolated {
            guard isBlocking() else { return false }
            heldInstall = installHandler
            return true
        }
    }
}

extension Updater: SPUStandardUserDriverDelegate {
    /// Seawall has no Dock icon, so Sparkle asks before putting a window in front unprompted.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                              state: SPUUserUpdateState) {
        guard handleShowingUpdate else { return }
        MainActor.assumeIsolated { NSApp.activate(ignoringOtherApps: true) }
    }
}
