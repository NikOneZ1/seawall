import Combine
import Foundation

/// What the first-run welcome needs from licensing, for its "Activate Seawall" step.
///
/// This is a stand-in so this branch builds on main, which has no license code yet: with
/// `isAvailable` false the welcome skips the license step and the hold-to-lock works as before.
/// eng/license-activation (PR #7) adds the real version of this same file, backed by
/// `LicenseModel`. When both PRs are merged, Git reports an add/add conflict on this file:
/// keep PR #7's version. Nothing else needs wiring.
@MainActor
final class WelcomeLicense: ObservableObject {
    static let shared = WelcomeLicense()
    static let buyURL = URL(string: "https://seawall.work")!
    static let price = "$14.99"

    /// Whether this build has licensing at all. The welcome skips its license step when it doesn't.
    let isAvailable = false

    private init() {}

    var isLicensed: Bool { false }
    var isWorking: Bool { false }
    var failure: String? { nil }

    func activate(_ key: String) async {}
}
