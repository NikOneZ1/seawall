import Foundation

// The license as seawall.work/license describes it, and what the app makes of it.
// Kept apart from blocks entirely: nothing here can start, end or change a block.

// MARK: - Wire format

/// What the server says a license is. "license" today; a Creem trial can later come back as "trial".
public enum LicenseKind: Equatable, Sendable {
    case license
    case trial
    /// A kind this version doesn't know. Treated conservatively: never a reason to lock anyone out.
    case other(String)

    public init(_ raw: String?) {
        switch raw {
        case "license", nil: self = .license
        case "trial": self = .trial
        case let raw?: self = .other(raw)
        }
    }

    public var rawValue: String {
        switch self {
        case .license: "license"
        case .trial: "trial"
        case .other(let raw): raw
        }
    }
}

public enum LicenseStatus: Equatable, Sendable {
    case active, inactive, expired, disabled
    case other(String)

    public init(_ raw: String?) {
        switch raw {
        case "active": self = .active
        case "inactive": self = .inactive
        case "expired": self = .expired
        case "disabled": self = .disabled
        case let raw: self = .other(raw ?? "")
        }
    }
}

public enum InstanceStatus: Equatable, Sendable {
    case active, deactivated
    case other(String)

    /// `nil` when the server sent null or nothing.
    public init?(_ raw: String?) {
        switch raw {
        case nil: return nil
        case "active": self = .active
        case "deactivated": self = .deactivated
        case let raw?: self = .other(raw)
        }
    }
}

/// A successful answer (HTTP 200, `"ok": true`). The same shape for activate, validate and deactivate.
/// Unknown fields are ignored; a field of the wrong type reads as missing rather than failing the whole answer.
public struct LicenseResponse: Equatable, Sendable {
    public var kind: LicenseKind
    public var status: LicenseStatus
    public var instanceID: String?
    public var instanceStatus: InstanceStatus?
    public var activations: Int?
    public var activationLimit: Int?
    public var expiresAt: Date?

    public init(kind: LicenseKind = .license, status: LicenseStatus = .active, instanceID: String? = nil,
                instanceStatus: InstanceStatus? = .active, activations: Int? = 1, activationLimit: Int? = 3,
                expiresAt: Date? = nil) {
        self.kind = kind
        self.status = status
        self.instanceID = instanceID
        self.instanceStatus = instanceStatus
        self.activations = activations
        self.activationLimit = activationLimit
        self.expiresAt = expiresAt
    }

    /// The contract's rule: ok && status == active && instance active or null.
    public var isLicensed: Bool {
        status == .active && (instanceStatus == nil || instanceStatus == .active)
    }
}

extension LicenseResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, status
        case instanceID = "instance_id"
        case instanceStatus = "instance_status"
        case activations
        case activationLimit = "activation_limit"
        case expiresAt = "expires_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil }
        func int(_ key: CodingKeys) -> Int? { (try? c.decodeIfPresent(Int.self, forKey: key)) ?? nil }
        kind = LicenseKind(string(.kind))
        status = LicenseStatus(string(.status))
        instanceID = string(.instanceID).flatMap { $0.isEmpty ? nil : $0 }
        instanceStatus = InstanceStatus(string(.instanceStatus))
        activations = int(.activations)
        activationLimit = int(.activationLimit)
        expiresAt = string(.expiresAt).flatMap(LicenseWire.date)
    }
}

/// The `error` codes the proxy sends with `"ok": false`.
public enum LicenseErrorCode: Equatable, Sendable {
    case badRequest, invalidKey, limitReached, rateLimited, upstream, notConfigured
    case other(String)

    public init(_ raw: String) {
        switch raw {
        case "bad_request": self = .badRequest
        case "invalid_key": self = .invalidKey
        case "limit_reached": self = .limitReached
        case "rate_limited": self = .rateLimited
        case "upstream": self = .upstream
        case "not_configured": self = .notConfigured
        default: self = .other(raw)
        }
    }
}

/// Why a request didn't produce a `LicenseResponse`.
public enum LicenseClientError: Error, Equatable, Sendable {
    /// The proxy answered with `"ok": false` and a code.
    case server(LicenseErrorCode, message: String?)
    /// No answer: offline, DNS, TLS, timeout.
    case network(String)
    /// An answer that isn't the contract (an HTML error page, a bare 404 or 502, garbage).
    /// Never read as a verdict on the key.
    case unexpected(httpStatus: Int)
}

public enum LicenseWire {
    private struct Envelope: Decodable {
        var ok: Bool?
        var error: String?
        var message: String?
    }

    /// Reads an HTTP answer from the proxy. Only a parseable `"ok": false` body with a code counts as
    /// the server saying something about the key; a 404 page from a misconfigured host is `.unexpected`.
    public static func decode(_ data: Data, httpStatus: Int) -> Result<LicenseResponse, LicenseClientError> {
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else {
            return .failure(.unexpected(httpStatus: httpStatus))
        }
        if envelope.ok == true, httpStatus == 200 {
            guard let response = try? decoder.decode(LicenseResponse.self, from: data) else {
                return .failure(.unexpected(httpStatus: httpStatus))
            }
            return .success(response)
        }
        if envelope.ok == false, let code = envelope.error {
            return .failure(.server(LicenseErrorCode(code), message: envelope.message))
        }
        return .failure(.unexpected(httpStatus: httpStatus))
    }

    /// "2027-01-31T12:00:00Z", with or without fractional seconds.
    static func date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

// MARK: - What the app keeps

/// The server said no in a way that counts: the key or this Mac's activation is gone.
public enum LicenseProblem: String, Codable, Equatable, Sendable {
    case invalidKey, expired, disabled, deactivated

    /// Finishes "seawall.work says …".
    public var wording: String {
        switch self {
        case .invalidKey: "this key isn't valid any more"
        case .expired: "this license has expired"
        case .disabled: "this license has been switched off"
        case .deactivated: "this Mac was deactivated for this key"
        }
    }
}

/// Everything about the activation except the key itself, which lives in the Keychain.
public struct LicenseRecord: Codable, Equatable, Sendable {
    public var instanceID: String
    public var instanceName: String
    public var activatedAt: Date
    /// The last definite "yes" from the server (activation counts).
    public var lastValidatedAt: Date
    /// The last time the app asked, whatever came back. Paces retries.
    public var lastAttemptAt: Date?
    public var kind: String
    public var activations: Int?
    public var activationLimit: Int?
    public var expiresAt: Date?
    /// The first definite "no" since the last "yes", and when it came. Starts the grace period.
    public var problem: LicenseProblem?
    public var problemSince: Date?

    public init(instanceID: String, instanceName: String, activatedAt: Date, lastValidatedAt: Date,
                lastAttemptAt: Date? = nil, kind: String = "license", activations: Int? = nil,
                activationLimit: Int? = nil, expiresAt: Date? = nil, problem: LicenseProblem? = nil,
                problemSince: Date? = nil) {
        self.instanceID = instanceID
        self.instanceName = instanceName
        self.activatedAt = activatedAt
        self.lastValidatedAt = lastValidatedAt
        self.lastAttemptAt = lastAttemptAt
        self.kind = kind
        self.activations = activations
        self.activationLimit = activationLimit
        self.expiresAt = expiresAt
        self.problem = problem
        self.problemSince = problemSince
    }

    /// Takes in what a "yes" said.
    mutating func refresh(from response: LicenseResponse, at now: Date) {
        if case .other = response.kind {} else { kind = response.kind.rawValue }
        activations = response.activations ?? activations
        activationLimit = response.activationLimit ?? activationLimit
        expiresAt = response.expiresAt
        lastValidatedAt = now
        lastAttemptAt = now
        problem = nil
        problemSince = nil
    }
}

// MARK: - Entitlement

public struct LicenseInfo: Equatable, Sendable {
    public var kind: LicenseKind
    public var activations: Int?
    public var activationLimit: Int?
    public var expiresAt: Date?
    public var lastValidatedAt: Date

    /// "Licensed on this Mac · 1 of 3 Macs".
    public var summary: String {
        let head = kind == .trial ? "Trial on this Mac" : "Licensed on this Mac"
        guard let used = activations, let limit = activationLimit, limit > 0 else { return head }
        return "\(head) · \(used) of \(Format.count(limit, "Mac", "Macs"))"
    }
}

/// What this Mac is entitled to. Derived from the stored record; never from blocks.
public enum LicenseState: Equatable, Sendable {
    case unlicensed
    case licensed(LicenseInfo)
    /// Reserved for a Creem trial (`kind: "trial"`). Nothing offers a trial yet.
    case trial(LicenseInfo)
    /// Still licensed. The server said no once, and keeps the app working at least until `until`;
    /// only another "no" after that date ends it.
    case grace(LicenseInfo, problem: LicenseProblem, until: Date)

    public init(record: LicenseRecord?) {
        guard let record else {
            self = .unlicensed
            return
        }
        let info = LicenseInfo(kind: LicenseKind(record.kind), activations: record.activations,
                               activationLimit: record.activationLimit, expiresAt: record.expiresAt,
                               lastValidatedAt: record.lastValidatedAt)
        if let problem = record.problem {
            let since = max(record.problemSince ?? record.lastValidatedAt, record.lastValidatedAt)
            self = .grace(info, problem: problem, until: since + LicensePolicy.gracePeriod)
        } else if info.kind == .trial {
            self = .trial(info)
        } else {
            self = .licensed(info)
        }
    }

    public var isLicensed: Bool {
        if case .unlicensed = self { return false }
        return true
    }

    public var info: LicenseInfo? {
        switch self {
        case .unlicensed: nil
        case .licensed(let info), .trial(let info), .grace(let info, _, _): info
        }
    }
}

/// The timings, in one place.
public enum LicensePolicy {
    /// Ask the server again a week after the last "yes".
    public static let validationInterval: TimeInterval = 7 * 86_400
    /// After an attempt that got no answer (or during grace), wait a day before trying again.
    public static let retryInterval: TimeInterval = 86_400
    /// A "no" has to still be a "no" this long after the first one, and after the last "yes".
    public static let gracePeriod: TimeInterval = 30 * 86_400
    /// Longer than any real key; keeps the request well under the proxy's 2 KB.
    public static let maxKeyLength = 256
}

// MARK: - Wording for failures

/// What went wrong, in words for the License section.
public enum LicenseFailure: Error, Equatable, Sendable {
    case emptyKey
    case invalidKey
    case limitReached
    case notActive
    case rateLimited
    /// No answer from seawall.work, or a broken one. Never changes the license.
    case offline
    /// The proxy is up but can't reach Creem, or isn't set up.
    case serverProblem
    case busy

    public var message: String {
        switch self {
        case .emptyKey: "Paste your license key first."
        case .invalidKey: "That key wasn't found. Check it against the email from your purchase."
        case .limitReached:
            "This key is already active on 3 Macs. Deactivate it on one of them in Settings, License, or email hello@seawall.work and we'll sort it out."
        case .notActive: "This key isn't active. If you think it should be, email hello@seawall.work."
        case .rateLimited: "Too many tries in a row. Wait a minute and try again."
        case .offline: "Couldn't reach seawall.work. Check your connection and try again."
        case .serverProblem: "The license server is having trouble. Try again in a few minutes."
        case .busy: "Still working on the last request."
        }
    }

    init(_ error: LicenseClientError) {
        switch error {
        case .server(.invalidKey, _), .server(.badRequest, _): self = .invalidKey
        case .server(.limitReached, _): self = .limitReached
        case .server(.rateLimited, _): self = .rateLimited
        case .server(.upstream, _), .server(.notConfigured, _), .server(.other, _): self = .serverProblem
        case .network, .unexpected: self = .offline
        }
    }
}

// MARK: - Instance name

/// "Seawall on MacBook Pro · k3m9qa": the Mac's kind and a random id made once per install.
/// No user name, no computer name (it usually holds one), no serial number.
public enum LicenseInstance {
    public static func name(model: String, installID: String) -> String {
        "Seawall on \(family(model)) · \(installID)"
    }

    /// "MacBookPro18,3" → "MacBook Pro". Newer identifiers ("Mac14,2") don't say which kind; those are "Mac".
    public static func family(_ model: String) -> String {
        let families: [(prefix: String, name: String)] = [
            ("MacBookPro", "MacBook Pro"), ("MacBookAir", "MacBook Air"), ("MacBook", "MacBook"),
            ("Macmini", "Mac mini"), ("MacPro", "Mac Pro"), ("iMacPro", "iMac Pro"), ("iMac", "iMac"),
        ]
        return families.first { model.hasPrefix($0.prefix) }?.name ?? "Mac"
    }

    /// Six characters, no look-alikes (0/o, 1/l).
    public static func makeInstallID() -> String {
        let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }
}
