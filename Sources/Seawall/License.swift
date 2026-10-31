import Foundation
import Security
import SeawallCore

/// The license. Seawall is paid only: without one the app opens, the welcome, lists and schedules
/// all work, but a new block doesn't start (`LicenseGate`); "Activate Seawall" asks for a key instead.
/// A block that is already running never looks at the license: nothing here ends, unlocks,
/// shortens or pauses one, or quits the app.
@MainActor
final class LicenseModel: ObservableObject {
    static let shared = LicenseModel()

    static let buyURL = URL(string: "https://seawall.work")!
    static let price = "$14.99"
    static let supportEmail = "hello@seawall.work"

    @Published private(set) var state: LicenseState
    @Published private(set) var isWorking = false
    /// The last thing that went wrong, in words.
    @Published var failure: LicenseFailure?
    /// Deactivating couldn't reach the server; offer to remove the license here only.
    @Published private(set) var offersLocalRemoval = false

    private let manager: LicenseManager
    private var timer: Timer?

    private init() {
        manager = LicenseManager(client: URLSessionLicenseClient(), keys: KeychainLicenseKeyStore(),
                                 records: DefaultsLicenseRecordStore(), modelName: Self.hardwareModel())
        state = manager.state
        manager.onChange = { [weak self] in self?.refresh() }
    }

    /// At launch: check in if it's been a week, then look again every few hours (it asks the
    /// server at most once a day, and only when a check is due).
    func start() {
        guard timer == nil else { return }
        checkIfDue()
        let timer = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        timer.tolerance = 600
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func activate(_ key: String) async {
        guard !isWorking else { return }
        isWorking = true
        failure = nil
        defer { isWorking = false }
        do {
            try await manager.activate(key: key)
        } catch {
            failure = error as? LicenseFailure ?? .offline
        }
        refresh()
    }

    func deactivate() async {
        guard !isWorking else { return }
        isWorking = true
        failure = nil
        offersLocalRemoval = false
        defer { isWorking = false }
        do {
            try await manager.deactivate()
        } catch {
            failure = error as? LicenseFailure ?? .offline
            offersLocalRemoval = failure == .offline || failure == .serverProblem
        }
        refresh()
    }

    /// After a deactivation that couldn't reach the server. The seat stays taken there.
    func removeFromThisMac() {
        manager.forgetThisMac()
        failure = nil
        offersLocalRemoval = false
        refresh()
    }

    /// Whether a new block may start now. Grace counts as licensed.
    var mayStartBlock: Bool { LicenseGate.mayStartBlock(state) }

    /// The calm "Activate Seawall" window, for a block that didn't start because there's no key.
    func askToActivate(because reason: String? = nil) {
        Panels.showActivate(reason: reason)
    }

    private func checkIfDue() {
        Task { await manager.validateIfDue() }
    }

    private func refresh() {
        let current = manager.state
        if state != current { state = current }
        if !current.isLicensed { offersLocalRemoval = false }
    }

    /// "MacBookPro18,3". Only the kind of Mac goes into the activation's name.
    private static func hardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "Mac" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// The license key, as a generic password in the login Keychain.
final class KeychainLicenseKeyStore: LicenseKeyStore {
    private let service = "Seawall License"
    private let account = "license-key"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func loadKey() -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound { log.error("Keychain read: \(status, privacy: .public)") }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func saveKey(_ key: String) throws {
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrLabel as String] = "Seawall license key"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            log.error("Keychain write: \(status, privacy: .public)")
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func deleteKey() {
        SecItemDelete(query as CFDictionary)
    }
}

/// The rest of the activation (instance id, dates, cached status), in UserDefaults next to the
/// other preferences. Never the key.
final class DefaultsLicenseRecordStore: LicenseRecordStore {
    private let defaults = UserDefaults.standard
    private static let recordKey = "license"
    private static let installIDKey = "licenseInstallID"

    func loadRecord() -> LicenseRecord? {
        guard let data = defaults.data(forKey: Self.recordKey) else { return nil }
        return try? JSONDecoder().decode(LicenseRecord.self, from: data)
    }

    func saveRecord(_ record: LicenseRecord?) {
        guard let record else {
            defaults.removeObject(forKey: Self.recordKey)
            return
        }
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: Self.recordKey)
        }
    }

    func loadInstallID() -> String? {
        defaults.string(forKey: Self.installIDKey)
    }

    func saveInstallID(_ id: String) {
        defaults.set(id, forKey: Self.installIDKey)
    }
}
