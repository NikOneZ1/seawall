import ServiceManagement

/// "Open at login", through the system's own Login Items list. Separate from the watchdog,
/// which only brings the app back while a block runs.
@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    @Published private(set) var status = SMAppService.mainApp.status

    var isOn: Bool { status == .enabled }
    /// Registered, but switched off by hand in System Settings → Login Items.
    var needsApproval: Bool { status == .requiresApproval }

    /// Whether the user has ever made the call. Until then the welcome suggests turning it on;
    /// afterwards it shows what they chose. (An app that was never registered reports
    /// `.notFound`, not `.notRegistered`, so the status alone can't tell.)
    var hasBeenChosen: Bool { UserDefaults.standard.bool(forKey: Self.chosenKey) }
    private static let chosenKey = "loginItemChosen"

    func set(_ on: Bool) {
        UserDefaults.standard.set(true, forKey: Self.chosenKey)
        do {
            if on {
                try SMAppService.mainApp.register()
            } else if isOn || needsApproval {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Login item: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func refresh() {
        let current = SMAppService.mainApp.status
        if status != current { status = current }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
