import Foundation

/// The only place the app sends anything about licenses. Never Creem directly.
public enum LicenseEndpoint {
    public static let baseURL = URL(string: "https://seawall.work/license")!
}

/// The three calls of the seawall.work license proxy.
public protocol LicenseClient: Sendable {
    func activate(key: String, instanceName: String) async throws -> LicenseResponse
    func validate(key: String, instanceID: String) async throws -> LicenseResponse
    func deactivate(key: String, instanceID: String) async throws -> LicenseResponse
}

/// Talks to the proxy over HTTPS. Throws only `LicenseClientError`. Never logs the key.
public struct URLSessionLicenseClient: LicenseClient {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = LicenseEndpoint.baseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.session = session ?? {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 30
            config.httpCookieStorage = nil
            config.urlCache = nil
            config.httpShouldSetCookies = false
            return URLSession(configuration: config)
        }()
    }

    public func activate(key: String, instanceName: String) async throws -> LicenseResponse {
        try await post("activate", ["key": key, "instance_name": instanceName])
    }

    public func validate(key: String, instanceID: String) async throws -> LicenseResponse {
        try await post("validate", ["key": key, "instance_id": instanceID])
    }

    public func deactivate(key: String, instanceID: String) async throws -> LicenseResponse {
        try await post("deactivate", ["key": key, "instance_id": instanceID])
    }

    private func post(_ path: String, _ body: [String: String]) async throws -> LicenseResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONEncoder().encode(body)

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            throw LicenseClientError.network((error as? URLError)?.code.rawValue.description ?? "request failed")
        }
        let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
        return try LicenseWire.decode(result.0, httpStatus: status).get()
    }
}
