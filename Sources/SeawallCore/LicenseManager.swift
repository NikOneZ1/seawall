import Foundation

// MARK: - Storage

/// Where the license key lives: the Keychain in the app, memory in tests.
public protocol LicenseKeyStore: AnyObject {
    func loadKey() -> String?
    func saveKey(_ key: String) throws
    func deleteKey()
}

/// Where everything else lives: preferences in the app, memory in tests.
public protocol LicenseRecordStore: AnyObject {
    func loadRecord() -> LicenseRecord?
    func saveRecord(_ record: LicenseRecord?)
    /// Made once per install, kept across deactivating, so a Mac keeps one name.
    func loadInstallID() -> String?
    func saveInstallID(_ id: String)
}

public final class InMemoryLicenseKeyStore: LicenseKeyStore {
    public var key: String?
    public init(key: String? = nil) { self.key = key }
    public func loadKey() -> String? { key }
    public func saveKey(_ key: String) throws { self.key = key }
    public func deleteKey() { key = nil }
}

public final class InMemoryLicenseRecordStore: LicenseRecordStore {
    public var record: LicenseRecord?
    public var installID: String?
    public init(record: LicenseRecord? = nil, installID: String? = nil) {
        self.record = record
        self.installID = installID
    }
    public func loadRecord() -> LicenseRecord? { record }
    public func saveRecord(_ record: LicenseRecord?) { self.record = record }
    public func loadInstallID() -> String? { installID }
    public func saveInstallID(_ id: String) { installID = id }
}

// MARK: - Manager

/// How a deactivation ended. Each one leaves this Mac unlicensed.
public enum DeactivationOutcome: Equatable, Sendable {
    /// The server freed this Mac's seat.
    case deactivated
    /// The server didn't know this Mac any more; cleared here too.
    case alreadyGone
    /// Cleared here without telling the server (no key on this Mac, or removed while offline).
    case removedLocally
}

/// Activates, checks now and then, and deactivates. The rules:
///
/// - Once activated, this Mac stays licensed offline, for good. No answer, a 5xx, "upstream",
///   "rate_limited", a timeout or an answer that isn't the contract never changes anything.
/// - Only a definite "no" counts: `invalid_key`, status expired or disabled, or this instance
///   deactivated. The first one starts a grace period and the app stays licensed. It ends only
///   when the server still says "no" at least 30 days after the first "no" *and* 30 days after
///   the last "yes". Any "yes" in between clears it.
/// - An unknown kind or status, or "inactive", keeps what's cached.
/// - Checks: when a week has passed since the last "yes", at most once a day (daily during grace).
/// - A clock set back never shortens anything: times in the future count as "no time has passed"
///   for the grace period (and a later "no" never moves its start), and as "check now" for pacing,
///   so a check isn't put off for months.
///
/// Nothing here touches blocks.
@MainActor
public final class LicenseManager {
    private let client: LicenseClient
    private let keys: LicenseKeyStore
    private let records: LicenseRecordStore
    private let modelName: String
    private let now: () -> Date
    private var validating = false

    public private(set) var record: LicenseRecord?
    /// Called after the record changes, on the main actor.
    public var onChange: (() -> Void)?

    public init(client: LicenseClient, keys: LicenseKeyStore, records: LicenseRecordStore,
                modelName: String = "Mac", now: @escaping () -> Date = Date.init) {
        self.client = client
        self.keys = keys
        self.records = records
        self.modelName = modelName
        self.now = now
        record = records.loadRecord()
    }

    public var state: LicenseState { LicenseState(record: record) }

    /// "Seawall on MacBook Pro · k3m9qa", the same for this install every time.
    public var instanceName: String {
        let id: String
        if let saved = records.loadInstallID(), !saved.isEmpty {
            id = saved
        } else {
            id = LicenseInstance.makeInstallID()
            records.saveInstallID(id)
        }
        return LicenseInstance.name(model: modelName, installID: id)
    }

    // MARK: Activate

    /// Activates this Mac with `key`. On success the key goes to the key store and the rest to the record.
    @discardableResult
    public func activate(key raw: String) async throws -> LicenseState {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw LicenseFailure.emptyKey }
        guard key.count <= LicensePolicy.maxKeyLength else { throw LicenseFailure.invalidKey }

        let name = instanceName
        let response: LicenseResponse
        do {
            response = try await client.activate(key: key, instanceName: name)
        } catch let error as LicenseClientError {
            throw LicenseFailure(error)
        } catch {
            throw LicenseFailure.offline
        }

        // Unknown kinds are let through: never lock anyone out over a word this version doesn't know.
        guard response.isLicensed else { throw LicenseFailure.notActive }
        guard let instanceID = response.instanceID else { throw LicenseFailure.serverProblem }

        let time = now()
        var record = LicenseRecord(instanceID: instanceID, instanceName: name, activatedAt: time, lastValidatedAt: time)
        record.refresh(from: response, at: time)
        // If the Keychain refuses, the Mac is still licensed; it just can't check in or deactivate
        // with the server later, and "Deactivate" removes it here only.
        try? keys.saveKey(key)
        set(record)
        return state
    }

    // MARK: Validate

    /// Whether a check is due now.
    public func isValidationDue() -> Bool {
        guard let record else { return false }
        let time = now()
        if let last = record.lastAttemptAt, time >= last, time.timeIntervalSince(last) < LicensePolicy.retryInterval {
            return false
        }
        if record.problem != nil { return true }
        // Clock set back past the last "yes": check rather than wait for it to catch up.
        if time < record.lastValidatedAt { return true }
        return time.timeIntervalSince(record.lastValidatedAt) >= LicensePolicy.validationInterval
    }

    /// Checks with the server if it's time to. Safe to call often (at launch, on a timer).
    public func validateIfDue() async {
        guard isValidationDue() else { return }
        await validate()
    }

    /// Checks with the server now. Only a definite "no" counts, and only gently; see the type's notes.
    public func validate() async {
        guard !validating, let sent = record else { return }
        guard let key = keys.loadKey() else { return } // Nothing to ask with; stays licensed.
        validating = true
        defer { validating = false }

        let verdict: Verdict
        do {
            let response = try await client.validate(key: key, instanceID: sent.instanceID)
            verdict = Self.verdict(response)
        } catch let error as LicenseClientError {
            verdict = Self.verdict(error)
        } catch {
            verdict = .noAnswer
        }

        // Deactivated or replaced while the request was out: that answer is about something else.
        guard var record, record.instanceID == sent.instanceID else { return }
        let time = now()
        switch verdict {
        case .yes(let response):
            record.refresh(from: response, at: time)
        case .no(let problem):
            record.lastAttemptAt = time
            // The grace period runs from the first "no". A later "no" never moves that date, even
            // with the clock set back, so a clock change can't bring the end closer.
            if record.problem == nil || record.problemSince == nil {
                record.problemSince = time
            }
            record.problem = problem
            if Self.graceIsOver(record, at: time) {
                clear()
                return
            }
        case .noAnswer:
            record.lastAttemptAt = time
        }
        set(record)
    }

    // MARK: Deactivate

    /// Frees this Mac's seat and forgets the license here. Throws (and changes nothing) when the
    /// server can't be reached; `forgetThisMac()` then removes it here only.
    @discardableResult
    public func deactivate() async throws -> DeactivationOutcome {
        guard let sent = record else { return .removedLocally }
        guard let key = keys.loadKey() else {
            clear()
            return .removedLocally
        }

        do {
            _ = try await client.deactivate(key: key, instanceID: sent.instanceID)
            clearIfStill(sent)
            return .deactivated
        } catch LicenseClientError.server(.invalidKey, _) {
            clearIfStill(sent)
            return .alreadyGone
        } catch let error as LicenseClientError {
            throw LicenseFailure(error)
        } catch {
            throw LicenseFailure.offline
        }
    }

    /// Removes the license from this Mac without asking the server. Its seat stays taken there.
    public func forgetThisMac() {
        clear()
    }

    // MARK: Verdicts

    enum Verdict: Equatable {
        case yes(LicenseResponse)
        case no(LicenseProblem)
        /// Offline, server trouble, or nothing this version understands: keep what's cached.
        case noAnswer
    }

    nonisolated static func verdict(_ response: LicenseResponse) -> Verdict {
        if case .other = response.kind { return .noAnswer }
        switch response.status {
        case .expired: return .no(.expired)
        case .disabled: return .no(.disabled)
        case .active:
            switch response.instanceStatus {
            case nil, .active?: return .yes(response)
            case .deactivated?: return .no(.deactivated)
            case .other?: return .noAnswer
            }
        case .inactive, .other: return .noAnswer
        }
    }

    nonisolated static func verdict(_ error: LicenseClientError) -> Verdict {
        if case .server(.invalidKey, _) = error { return .no(.invalidKey) }
        return .noAnswer
    }

    /// A "no" ends the license only 30 days after both the first "no" and the last "yes".
    /// Dates in the future (a clock set back) count as no time passed.
    nonisolated static func graceIsOver(_ record: LicenseRecord, at time: Date) -> Bool {
        guard record.problem != nil, let since = record.problemSince else { return false }
        func elapsed(_ date: Date) -> TimeInterval { max(0, time.timeIntervalSince(date)) }
        return elapsed(since) >= LicensePolicy.gracePeriod && elapsed(record.lastValidatedAt) >= LicensePolicy.gracePeriod
    }

    // MARK: Storage

    private func set(_ record: LicenseRecord?) {
        self.record = record
        records.saveRecord(record)
        onChange?()
    }

    private func clear() {
        keys.deleteKey()
        set(nil)
    }

    private func clearIfStill(_ sent: LicenseRecord) {
        if record?.instanceID == sent.instanceID { clear() }
    }
}
