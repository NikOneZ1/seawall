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

    func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
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
