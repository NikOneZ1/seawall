import AppKit
import Combine
import SeawallCore
import Sparkle

/// Updates through Sparkle: a check once a day, and "Check for Updates…" in the menu.
///
/// An update never installs while a block runs. Installing quits the app and opens the new
/// one; the block would come back from disk, but for those seconds nothing is closed, and the
/// watchdog could reopen the old copy mid-swap. So the relaunch waits until every block is over.
@MainActor
final class Updates: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = Updates()

    /// False in builds still carrying the placeholder key (`make build` before the first
    /// release): Sparkle would refuse to start and show an alert on every launch.
    @Published private(set) var isAvailable = false
    /// False while a check is already under way.
    @Published private(set) var canCheck = false
    @Published var checksAutomatically = false {
        didSet {
            guard let updater, updater.automaticallyChecksForUpdates != checksAutomatically else { return }
            updater.automaticallyChecksForUpdates = checksAutomatically
        }
    }
    /// An update is downloaded and waiting for the running blocks to end.
    @Published private(set) var waitingForBlock = false

    private var controller: SPUStandardUpdaterController?
    private var updater: SPUUpdater? { controller?.updater }
    private weak var blocks: BlockController?
    private var pendingInstall: (() -> Void)?
    private var cancellables: Set<AnyCancellable> = []

    private override init() {
        super.init()
    }

    /// Once, at launch, after the single-instance check.
    func start(blocks: BlockController) {
        guard controller == nil else { return }
        self.blocks = blocks
        guard UpdateKey.isUsable(Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String) else {
            log.info("Updates are off: SUPublicEDKey is still the placeholder")
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        isAvailable = true
        checksAutomatically = controller.updater.automaticallyChecksForUpdates

        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheck = $0 }
            .store(in: &cancellables)
        blocks.$sessions
            .map(\.isEmpty)
            .removeDuplicates()
            .sink { [weak self] unlocked in
                if unlocked { self?.installIfWaiting() }
            }
            .store(in: &cancellables)
    }

    func checkNow() {
        guard let controller else { return }
        MenuShortcut.closeMenu()
        // No Dock icon: without this the update window can open behind the app in front.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    private var blocksRunning: Bool { !(blocks?.sessions.isEmpty ?? true) }

    // MARK: - SPUUpdaterDelegate

    /// Called before Sparkle quits the app to install and reopen it, whether the person clicked
    /// "Install and Relaunch" or a reminder did. An update that's already downloaded can also
    /// install when the app quits for another reason (logout, shutdown, a kill). That's safe:
    /// the bundle is replaced at the same path, the watchdog opens the new copy within 10
    /// seconds, and it picks the block up from disk, as after any relaunch.
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard blocksRunning else { return false }
        pendingInstall = installHandler
        if !waitingForBlock {
            waitingForBlock = true
            log.info("Update \(item.displayVersionString, privacy: .public) waits for the block to end")
            // Outside Sparkle's call: runModal spins its own loop.
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Seawall will update when the block ends"
                alert.informativeText = "The block keeps running as it is. Once everything is open again, "
                    + "Seawall installs version \(item.displayVersionString) and opens again by itself."
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
        return true
    }

    /// The last block just ended. Give the summary a moment, then install, unless a schedule
    /// or a link started another block in the meantime.
    private func installIfWaiting() {
        guard pendingInstall != nil else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !self.blocksRunning, let install = self.pendingInstall else { return }
            self.pendingInstall = nil
            self.waitingForBlock = false
            install()
        }
    }
}
