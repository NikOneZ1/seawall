import Foundation
import Testing
@testable import SeawallCore

// MARK: - Fakes

final class FakeLicenseClient: LicenseClient, @unchecked Sendable {
    var activateResult: Result<LicenseResponse, Error> = .success(LicenseResponse(instanceID: "ins_1"))
    var validateResult: Result<LicenseResponse, Error> = .success(LicenseResponse(instanceID: "ins_1"))
    var deactivateResult: Result<LicenseResponse, Error> =
        .success(LicenseResponse(status: .active, instanceID: "ins_1", instanceStatus: .deactivated, activations: 0))
    private(set) var calls: [String] = []
    private(set) var lastKey: String?
    private(set) var lastInstanceName: String?

    func activate(key: String, instanceName: String) async throws -> LicenseResponse {
        calls.append("activate")
        lastKey = key
        lastInstanceName = instanceName
        return try activateResult.get()
    }

    func validate(key: String, instanceID: String) async throws -> LicenseResponse {
        calls.append("validate")
        lastKey = key
        return try validateResult.get()
    }

    func deactivate(key: String, instanceID: String) async throws -> LicenseResponse {
        calls.append("deactivate")
        lastKey = key
        return try deactivateResult.get()
    }
}

final class FakeClock {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(days: Double) { now += days * 86_400 }
}

private let day: TimeInterval = 86_400

// MARK: - Manager

@MainActor
struct LicenseManagerTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let client = FakeLicenseClient()
    let keys = InMemoryLicenseKeyStore()
    let records = InMemoryLicenseRecordStore(installID: "k3m9qa")
    let clock: FakeClock

    init() {
        clock = FakeClock(start)
    }

    func makeManager() -> LicenseManager {
        let clock = clock
        return LicenseManager(client: client, keys: keys, records: records, modelName: "MacBookPro18,3", now: { clock.now })
    }

    /// A manager already activated at `start`.
    func activated() async throws -> LicenseManager {
        let manager = makeManager()
        try await manager.activate(key: "KEY-123")
        return manager
    }

    // Activation

    @Test func activationStoresKeyAndInstance() async throws {
        let manager = makeManager()
        let state = try await manager.activate(key: "  KEY-123\n")

        #expect(client.lastKey == "KEY-123")
        #expect(client.lastInstanceName == "Seawall on MacBook Pro · k3m9qa")
        #expect(keys.key == "KEY-123")
        #expect(records.record?.instanceID == "ins_1")
        #expect(records.record?.lastValidatedAt == start)
        #expect(state.isLicensed)
        #expect(state.info?.summary == "Licensed on this Mac · 1 of 3 Macs")
        #expect(state == .licensed(LicenseInfo(kind: .license, activations: 1, activationLimit: 3, expiresAt: nil, lastValidatedAt: start)))
    }

    @Test func activationSurvivesARelaunch() async throws {
        _ = try await activated()
        let relaunched = makeManager()
        #expect(relaunched.state.isLicensed)
        #expect(relaunched.record?.instanceID == "ins_1")
    }

    @Test func emptyKeyNeverReachesTheServer() async {
        let manager = makeManager()
        await #expect(throws: LicenseFailure.emptyKey) { try await manager.activate(key: "  \n") }
        #expect(client.calls.isEmpty)
    }

    @Test func limitReached() async {
        client.activateResult = .failure(LicenseClientError.server(.limitReached, message: "limit"))
        let manager = makeManager()
        await #expect(throws: LicenseFailure.limitReached) { try await manager.activate(key: "KEY") }
        #expect(!manager.state.isLicensed)
        #expect(keys.key == nil)
        #expect(records.record == nil)
        #expect(LicenseFailure.limitReached.message.contains("hello@seawall.work"))
    }

    @Test func invalidKey() async {
        client.activateResult = .failure(LicenseClientError.server(.invalidKey, message: nil))
        let manager = makeManager()
        await #expect(throws: LicenseFailure.invalidKey) { try await manager.activate(key: "KEY") }
        #expect(!manager.state.isLicensed)
        #expect(keys.key == nil)
    }

    @Test func activationOfflineOrServerTrouble() async {
        let manager = makeManager()
        client.activateResult = .failure(LicenseClientError.network("-1009"))
        await #expect(throws: LicenseFailure.offline) { try await manager.activate(key: "KEY") }
        client.activateResult = .failure(LicenseClientError.server(.upstream, message: nil))
        await #expect(throws: LicenseFailure.serverProblem) { try await manager.activate(key: "KEY") }
        client.activateResult = .failure(LicenseClientError.server(.rateLimited, message: nil))
        await #expect(throws: LicenseFailure.rateLimited) { try await manager.activate(key: "KEY") }
        #expect(!manager.state.isLicensed)
    }

    @Test func activationOfAnInactiveKeyFails() async {
        client.activateResult = .success(LicenseResponse(status: .expired, instanceID: "ins_1"))
        let manager = makeManager()
        await #expect(throws: LicenseFailure.notActive) { try await manager.activate(key: "KEY") }
        #expect(records.record == nil)
    }

    @Test func activationWithoutAnInstanceIsAServerProblem() async {
        client.activateResult = .success(LicenseResponse(instanceID: nil))
        let manager = makeManager()
        await #expect(throws: LicenseFailure.serverProblem) { try await manager.activate(key: "KEY") }
        #expect(records.record == nil)
    }

    @Test func instanceNameStaysTheSameForThisInstall() {
        let records = InMemoryLicenseRecordStore()
        let manager = LicenseManager(client: client, keys: keys, records: records, modelName: "Mac14,2")
        let first = manager.instanceName
        #expect(first.hasPrefix("Seawall on Mac · "))
        #expect(manager.instanceName == first)
        #expect(records.installID?.count == 6)
    }

    // Validation

    @Test func validationIsPacedWeekly() async throws {
        let manager = try await activated()
        #expect(!manager.isValidationDue())
        clock.advance(days: 6.9)
        #expect(!manager.isValidationDue())
        clock.advance(days: 0.2)
        #expect(manager.isValidationDue())
    }

    @Test func validationSuccessRefreshesTheDate() async throws {
        let manager = try await activated()
        clock.advance(days: 8)
        client.validateResult = .success(LicenseResponse(instanceID: "ins_1", activations: 2, activationLimit: 3))
        await manager.validateIfDue()

        #expect(client.calls == ["activate", "validate"])
        #expect(records.record?.lastValidatedAt == clock.now)
        #expect(manager.state.info?.summary == "Licensed on this Mac · 2 of 3 Macs")
        #expect(!manager.isValidationDue())
    }

    @Test func networkFailureKeepsLicensedAndRetriesNextDay() async throws {
        let manager = try await activated()
        let before = manager.state
        for error in [LicenseClientError.network("timeout"), .server(.upstream, message: nil),
                      .server(.notConfigured, message: nil), .server(.rateLimited, message: nil),
                      .server(.badRequest, message: nil), .unexpected(httpStatus: 404), .unexpected(httpStatus: 502)] {
            clock.advance(days: 8)
            client.validateResult = .failure(error)
            await manager.validateIfDue()
            #expect(manager.state == before, "\(error)")
            #expect(keys.key == "KEY-123")
        }
        // An attempt was made just now: wait a day before the next one.
        #expect(!manager.isValidationDue())
        clock.advance(days: 1)
        #expect(manager.isValidationDue())
    }

    @Test func unknownKindStatusOrInactiveKeepsTheCache() async throws {
        let manager = try await activated()
        let before = manager.state
        for response in [LicenseResponse(kind: .other("lifetime"), status: .expired, instanceID: "ins_1"),
                         LicenseResponse(status: .other("paused"), instanceID: "ins_1"),
                         LicenseResponse(status: .inactive, instanceID: "ins_1"),
                         LicenseResponse(status: .active, instanceID: "ins_1", instanceStatus: .other("pending"))] {
            clock.advance(days: 8)
            client.validateResult = .success(response)
            await manager.validate()
            #expect(manager.state == before)
            #expect(records.record?.problem == nil)
        }
    }

    @Test func aDefiniteNoStartsGraceButStaysLicensed() async throws {
        let manager = try await activated()
        clock.advance(days: 8)
        let firstNo = clock.now
        client.validateResult = .failure(LicenseClientError.server(.invalidKey, message: nil))
        await manager.validate()

        #expect(manager.state.isLicensed)
        guard case .grace(_, let problem, let until) = manager.state else {
            Issue.record("expected grace, got \(manager.state)")
            return
        }
        #expect(problem == .invalidKey)
        #expect(until == firstNo + 30 * day)
        // During grace it checks daily, so a mistake clears quickly.
        clock.advance(days: 1)
        #expect(manager.isValidationDue())
    }

    @Test func graceEndsOnlyWhenTheNoPersistsThirtyDays() async throws {
        let manager = try await activated()
        client.validateResult = .success(LicenseResponse(status: .expired, instanceID: "ins_1"))

        clock.advance(days: 8)
        await manager.validate()
        #expect(manager.state.isLicensed)

        clock.advance(days: 29)
        await manager.validate()
        #expect(manager.state.isLicensed) // 29 days after the first "no"

        clock.advance(days: 1)
        await manager.validate()
        #expect(manager.state == .unlicensed)
        #expect(keys.key == nil)
        #expect(records.record == nil)
    }

    // Starting blocks needs a license; running blocks never look at it

    @Test func startingABlockNeedsALicense() async throws {
        let manager = makeManager()
        #expect(manager.state == .unlicensed)
        #expect(!LicenseGate.mayStartBlock(manager.state))

        // A failed activation leaves it gated.
        client.activateResult = .failure(LicenseClientError.server(.invalidKey, message: nil))
        _ = try? await manager.activate(key: "WRONG")
        #expect(!LicenseGate.mayStartBlock(manager.state))

        client.activateResult = .success(LicenseResponse(instanceID: "ins_1"))
        try await manager.activate(key: "KEY-123")
        #expect(LicenseGate.mayStartBlock(manager.state))
    }

    @Test func offlineNeverGatesBlocks() async throws {
        let manager = try await activated()
        client.validateResult = .failure(LicenseClientError.network("offline"))
        for _ in 0..<400 {
            clock.advance(days: 1)
            await manager.validateIfDue()
        }
        #expect(LicenseGate.mayStartBlock(manager.state))
    }

    @Test func graceStillStartsBlocksThenNewBlocksNeedAKeyAgain() async throws {
        let manager = try await activated()
        client.validateResult = .success(LicenseResponse(status: .disabled, instanceID: "ins_1")) // refunded

        clock.advance(days: 8)
        await manager.validate()
        guard case .grace = manager.state else {
            Issue.record("expected grace, got \(manager.state)")
            return
        }
        #expect(LicenseGate.mayStartBlock(manager.state))

        clock.advance(days: 29)
        await manager.validate()
        #expect(LicenseGate.mayStartBlock(manager.state))

        clock.advance(days: 1)
        await manager.validate()
        #expect(manager.state == .unlicensed)
        #expect(!LicenseGate.mayStartBlock(manager.state))

        // A key works again straight away.
        client.activateResult = .success(LicenseResponse(instanceID: "ins_2"))
        try await manager.activate(key: "NEW-KEY")
        #expect(LicenseGate.mayStartBlock(manager.state))
    }

    @Test func losingTheLicenseLeavesARunningBlockAlone() async throws {
        let manager = try await activated()
        let started = clock.now
        let session = Session(startedAt: started, endsAt: started + 90 * day, sites: ["reddit.com"], apps: [],
                              blocksOtherBrowsers: false)
        let before = session

        // Refunded and gone after grace, while the (long) block runs.
        client.validateResult = .failure(LicenseClientError.server(.invalidKey, message: nil))
        clock.advance(days: 8)
        await manager.validate()
        clock.advance(days: 31)
        await manager.validate()
        #expect(manager.state == .unlicensed)

        // The block is exactly what it was: same end, still holding, no early way out.
        #expect(session == before)
        #expect(session.endsAt == started + 90 * day)
        #expect(!session.isOver(at: clock.now))
        #expect(session.isHolding(at: clock.now))
        #expect(session.unlockState(at: clock.now) == before.unlockState(at: clock.now))
        // Only a new block is refused.
        #expect(!LicenseGate.mayStartBlock(manager.state))
    }

    @Test func graceNeverEndsWithoutAnAnswer() async throws {
        let manager = try await activated()
        clock.advance(days: 8)
        client.validateResult = .failure(LicenseClientError.server(.invalidKey, message: nil))
        await manager.validate()

        // A year offline after the "no": still licensed, because no second "no" arrived.
        client.validateResult = .failure(LicenseClientError.network("offline"))
        for _ in 0..<365 {
            clock.advance(days: 1)
            await manager.validateIfDue()
        }
        #expect(manager.state.isLicensed)
    }

    @Test func aYesDuringGraceClearsIt() async throws {
        let manager = try await activated()
        clock.advance(days: 8)
        client.validateResult = .success(LicenseResponse(status: .active, instanceID: "ins_1", instanceStatus: .deactivated))
        await manager.validate()
        #expect(records.record?.problem == .deactivated)

        clock.advance(days: 20)
        client.validateResult = .success(LicenseResponse(instanceID: "ins_1"))
        await manager.validate()
        #expect(records.record?.problem == nil)
        #expect(manager.state == .licensed(LicenseInfo(kind: .license, activations: 1, activationLimit: 3, expiresAt: nil, lastValidatedAt: clock.now)))

        // A new "no" starts a fresh 30 days.
        clock.advance(days: 15)
        client.validateResult = .failure(LicenseClientError.server(.invalidKey, message: nil))
        await manager.validate()
        clock.advance(days: 20)
        await manager.validate()
        #expect(manager.state.isLicensed)
    }

    @Test func clockSetBackNeverShortensGrace() async throws {
        let manager = try await activated()
        clock.advance(days: 8)
        client.validateResult = .failure(LicenseClientError.server(.invalidKey, message: nil))
        await manager.validate()
        let firstNo = clock.now

        // Back a year, another "no": the grace still runs from the first one…
        clock.now = firstNo - 365 * day
        #expect(manager.isValidationDue()) // last attempt is "in the future": check rather than wait
        await manager.validate()
        #expect(manager.state.isLicensed)
        #expect(records.record?.problemSince == firstNo)

        // …and putting the clock right doesn't end it early.
        clock.now = firstNo + 10 * day
        await manager.validate()
        #expect(manager.state.isLicensed)
    }

    @Test func clockSetBackKeepsLicensedOffline() async throws {
        let manager = try await activated()
        clock.now = start - 400 * day
        client.validateResult = .failure(LicenseClientError.network("offline"))
        await manager.validateIfDue()
        #expect(manager.state.isLicensed)
    }

    @Test func noKeyMeansNoCheckButStillLicensed() async throws {
        let manager = try await activated()
        keys.key = nil
        clock.advance(days: 30)
        await manager.validateIfDue()
        #expect(client.calls == ["activate"])
        #expect(manager.state.isLicensed)
    }

    // Deactivation

    @Test func deactivateClearsEverything() async throws {
        let manager = try await activated()
        let outcome = try await manager.deactivate()
        #expect(outcome == .deactivated)
        #expect(manager.state == .unlicensed)
        #expect(keys.key == nil)
        #expect(records.record == nil)
        #expect(records.installID == "k3m9qa") // the Mac keeps its name for next time
    }

    @Test func deactivateWhenTheServerAlreadyForgotThisMac() async throws {
        let manager = try await activated()
        client.deactivateResult = .failure(LicenseClientError.server(.invalidKey, message: "not found"))
        let outcome = try await manager.deactivate()
        #expect(outcome == .alreadyGone)
        #expect(manager.state == .unlicensed)
        #expect(keys.key == nil)
    }

    @Test func deactivateOfflineChangesNothingUntilForgotten() async throws {
        let manager = try await activated()
        client.deactivateResult = .failure(LicenseClientError.network("offline"))
        await #expect(throws: LicenseFailure.offline) { try await manager.deactivate() }
        #expect(manager.state.isLicensed)
        #expect(keys.key == "KEY-123")

        client.deactivateResult = .failure(LicenseClientError.server(.upstream, message: nil))
        await #expect(throws: LicenseFailure.serverProblem) { try await manager.deactivate() }
        #expect(manager.state.isLicensed)

        manager.forgetThisMac()
        #expect(manager.state == .unlicensed)
        #expect(keys.key == nil)
        #expect(records.record == nil)
    }

    @Test func deactivateWithoutAKeyRemovesItHere() async throws {
        let manager = try await activated()
        keys.key = nil
        let outcome = try await manager.deactivate()
        #expect(outcome == .removedLocally)
        #expect(manager.state == .unlicensed)
        #expect(client.calls == ["activate"])
    }

    @Test func changesAreAnnounced() async throws {
        let manager = makeManager()
        var count = 0
        manager.onChange = { count += 1 }
        try await manager.activate(key: "KEY")
        _ = try await manager.deactivate()
        #expect(count == 2)
    }
}

// MARK: - Contract

struct LicenseContractTests {
    func decode(_ json: String, status: Int = 200) -> Result<LicenseResponse, LicenseClientError> {
        LicenseWire.decode(Data(json.utf8), httpStatus: status)
    }

    @Test func decodesASuccess() throws {
        let json = """
        {"ok": true, "kind": "license", "status": "active", "instance_id": "ins_abc", "instance_status": "active",
         "activations": 1, "activation_limit": 3, "expires_at": "2027-01-31T12:00:00Z", "something_new": [1, 2]}
        """
        let response = try decode(json).get()
        #expect(response.kind == .license)
        #expect(response.status == .active)
        #expect(response.instanceID == "ins_abc")
        #expect(response.instanceStatus == .active)
        #expect(response.activations == 1)
        #expect(response.activationLimit == 3)
        #expect(response.expiresAt == Date(timeIntervalSince1970: 1_801_396_800))
        #expect(response.isLicensed)
    }

    @Test func decodesNulls() throws {
        let json = """
        {"ok": true, "kind": "license", "status": "active", "instance_id": null, "instance_status": null,
         "activations": 1, "activation_limit": null, "expires_at": null}
        """
        let response = try decode(json).get()
        #expect(response.instanceID == nil)
        #expect(response.instanceStatus == nil)
        #expect(response.activationLimit == nil)
        #expect(response.expiresAt == nil)
        #expect(response.isLicensed) // instance null still counts
        let info = LicenseInfo(kind: .license, activations: 1, activationLimit: nil, expiresAt: nil, lastValidatedAt: .now)
        #expect(info.summary == "Licensed on this Mac")
    }

    @Test func decodesUnknownKindAndStatus() throws {
        let json = """
        {"ok": true, "kind": "lifetime", "status": "paused", "instance_id": "ins_1", "instance_status": "frozen",
         "expires_at": "2027-01-31T12:00:00.250Z"}
        """
        let response = try decode(json).get()
        #expect(response.kind == .other("lifetime"))
        #expect(response.status == .other("paused"))
        #expect(response.instanceStatus == .other("frozen"))
        #expect(response.expiresAt != nil)
        #expect(!response.isLicensed)
        #expect(LicenseManager.verdict(response) == .noAnswer)
    }

    @Test func thereIsNoTrialKind() throws {
        // Seawall is paid only. "trial" is just a word this version doesn't know, handled like any
        // unknown kind: it neither licenses a Mac nor takes a license away.
        let response = try decode(#"{"ok": true, "kind": "trial", "status": "active", "instance_id": "ins_1"}"#).get()
        #expect(response.kind == .other("trial"))
        #expect(LicenseManager.verdict(response) == .noAnswer)
    }

    @Test func wrongTypesReadAsMissing() throws {
        let response = try decode(#"{"ok": true, "status": "active", "activations": "one", "activation_limit": 3.5}"#).get()
        #expect(response.kind == .license)
        #expect(response.activations == nil)
        #expect(response.activationLimit == nil)
    }

    @Test func decodesErrors() {
        #expect(decode(#"{"ok": false, "error": "invalid_key", "message": "Not found"}"#, status: 404)
            == .failure(.server(.invalidKey, message: "Not found")))
        #expect(decode(#"{"ok": false, "error": "limit_reached", "message": "Limit"}"#, status: 409)
            == .failure(.server(.limitReached, message: "Limit")))
        #expect(decode(#"{"ok": false, "error": "rate_limited"}"#, status: 429) == .failure(.server(.rateLimited, message: nil)))
        #expect(decode(#"{"ok": false, "error": "upstream", "message": "x"}"#, status: 502) == .failure(.server(.upstream, message: "x")))
        #expect(decode(#"{"ok": false, "error": "not_configured", "message": "x"}"#, status: 503) == .failure(.server(.notConfigured, message: "x")))
        #expect(decode(#"{"ok": false, "error": "bad_request", "message": "x"}"#, status: 400) == .failure(.server(.badRequest, message: "x")))
        #expect(decode(#"{"ok": false, "error": "teapot", "message": "x"}"#, status: 418) == .failure(.server(.other("teapot"), message: "x")))
    }

    @Test func aPageThatIsntTheContractIsNeverAVerdict() {
        // A bare 404 from a misconfigured host must not read as "invalid key".
        let notFound = decode("<html>Not Found</html>", status: 404)
        #expect(notFound == .failure(.unexpected(httpStatus: 404)))
        #expect(decode("", status: 502) == .failure(.unexpected(httpStatus: 502)))
        #expect(decode(#"{"ok": true}"#, status: 500) == .failure(.unexpected(httpStatus: 500)))
        #expect(decode(#"{"message": "hi"}"#, status: 200) == .failure(.unexpected(httpStatus: 200)))
        #expect(LicenseManager.verdict(.unexpected(httpStatus: 404)) == .noAnswer)
    }

    @Test func verdicts() {
        #expect(LicenseManager.verdict(LicenseResponse(status: .expired)) == .no(.expired))
        #expect(LicenseManager.verdict(LicenseResponse(status: .disabled)) == .no(.disabled))
        #expect(LicenseManager.verdict(LicenseResponse(instanceStatus: .deactivated)) == .no(.deactivated))
        #expect(LicenseManager.verdict(LicenseResponse(status: .inactive)) == .noAnswer)
        #expect(LicenseManager.verdict(.server(.invalidKey, message: nil)) == .no(.invalidKey))
        #expect(LicenseManager.verdict(.server(.upstream, message: nil)) == .noAnswer)
        #expect(LicenseManager.verdict(.network("x")) == .noAnswer)
    }

    @Test func recordRoundTrips() throws {
        let record = LicenseRecord(instanceID: "ins_1", instanceName: "Seawall on Mac · abc234",
                                   activatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                   lastValidatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                   activations: 1, activationLimit: 3, problem: .expired,
                                   problemSince: Date(timeIntervalSince1970: 1_800_100_000))
        let data = try JSONEncoder().encode(record)
        #expect(try JSONDecoder().decode(LicenseRecord.self, from: data) == record)
    }
}

struct LicenseInstanceTests {
    @Test func namesTheKindOfMacOnly() {
        #expect(LicenseInstance.name(model: "MacBookPro18,3", installID: "abc234") == "Seawall on MacBook Pro · abc234")
        #expect(LicenseInstance.family("MacBookAir10,1") == "MacBook Air")
        #expect(LicenseInstance.family("MacBook10,1") == "MacBook")
        #expect(LicenseInstance.family("Macmini9,1") == "Mac mini")
        #expect(LicenseInstance.family("iMac21,1") == "iMac")
        #expect(LicenseInstance.family("iMacPro1,1") == "iMac Pro")
        #expect(LicenseInstance.family("MacPro7,1") == "Mac Pro")
        #expect(LicenseInstance.family("Mac14,2") == "Mac")
        #expect(LicenseInstance.family("") == "Mac")
    }

    @Test func installIDsAreShortAndPlain() {
        let id = LicenseInstance.makeInstallID()
        #expect(id.count == 6)
        #expect(id.allSatisfy { "abcdefghijkmnpqrstuvwxyz23456789".contains($0) })
    }
}
