import Combine
import Foundation

/// What the first-run welcome needs from licensing, for its "Activate Seawall" step.
///
/// The same file exists on eng/first-run-setup (PR #4) as a stand-in with `isAvailable = false`,
/// so that branch builds on main without the license code. This is the real one. When both PRs
/// are merged, Git reports an add/add conflict on this file: keep this version (the one backed
/// by `LicenseModel`).
@MainActor
final class WelcomeLicense: ObservableObject {
    static let shared = WelcomeLicense()
    static let buyURL = LicenseModel.buyURL
    static let price = LicenseModel.price

    /// Whether this build has licensing at all. The welcome skips its license step when it doesn't.
    let isAvailable = true

    private let model = LicenseModel.shared
    private var watching: AnyCancellable?

    private init() {
        watching = model.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var isLicensed: Bool { model.mayStartBlock }
    var isWorking: Bool { model.isWorking }
    var failure: String? { model.failure?.message }

    func activate(_ key: String) async {
        await model.activate(key)
    }
}
