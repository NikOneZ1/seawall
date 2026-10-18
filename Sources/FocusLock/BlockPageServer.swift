import Foundation
import Network

/// Serves the "blocked" page on localhost. Blocked Safari tabs are sent here; the page
/// gets the end time and the original URL in the query and does the rest itself.
@MainActor
final class BlockPageServer {
    private static let preferredPort: NWEndpoint.Port = 47_321

    private var listener: NWListener?
    private(set) var port: UInt16?

    func start() {
        listen(on: Self.preferredPort)
    }

    func pageURL(until: Date, blocked: URL, attempts: Int) -> String {
        guard let port else { return "about:blank" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let original = blocked.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return "http://127.0.0.1:\(port)/?until=\(Int(until.timeIntervalSince1970))&n=\(attempts)&url=\(original)"
    }

    private func listen(on port: NWEndpoint.Port) {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: port)
        } catch {
            log.error("Block page server: \(error.localizedDescription, privacy: .public)")
            return
        }

        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .ready:
                    self?.port = listener.port?.rawValue
                case .failed(let error):
                    listener.cancel()
                    log.error("Block page server on \(port.rawValue): \(error.localizedDescription, privacy: .public)")
                    // Preferred port taken — any free one will do.
                    if port != .any { self?.listen(on: .any) }
                default:
                    break
                }
            }
        }
        listener.newConnectionHandler = { Self.serve($0) }
        listener.start(queue: .main)
        self.listener = listener
    }

    nonisolated private static func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let isPage = !request.hasPrefix("GET /favicon")
            let body = isPage ? Data(blockPageHTML.utf8) : Data()
            let head = [
                isPage ? "HTTP/1.1 200 OK" : "HTTP/1.1 404 Not Found",
                "Content-Type: text/html; charset=utf-8",
                "Content-Length: \(body.count)",
                "Cache-Control: no-store",
                "Connection: close",
                "", "",
            ].joined(separator: "\r\n")
            connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
