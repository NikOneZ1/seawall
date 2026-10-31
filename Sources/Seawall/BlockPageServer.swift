import Foundation
import Network
import SeawallCore

/// Serves the "blocked" page on localhost, the one picked in Settings. Blocked browser tabs are sent here; the page
/// gets the end time and the original URL in the query and does the rest itself.
/// It also reads and adds its finds here: `GET /finds`, `POST /find?kind=star`.
@MainActor
final class BlockPageServer {
    private static let preferredPort: NWEndpoint.Port = 47_321

    private var listener: NWListener?
    private(set) var port: UInt16?
    /// Kinds of everything found so far, oldest first.
    var finds: () -> [String] = { [] }
    /// Which page to serve; asked on every page load, so a change in Settings is there at once.
    var choice: () -> BlockedPageChoice = { .random }
    /// Records a find; false if the kind is unknown.
    var onFind: (String) -> Bool = { _ in false }

    func start() {
        listen(on: Self.preferredPort)
    }

    /// Closes the port. Only on uninstall: blocked tabs need the page for as long as the app runs.
    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
        port = nil
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
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.serve(connection) }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            MainActor.assumeIsolated {
                let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                let (status, type, body) = self?.respond(to: request) ?? ("404 Not Found", "text/plain", Data())
                let head = [
                    "HTTP/1.1 \(status)",
                    "Content-Type: \(type)",
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

    private func respond(to request: String) -> (status: String, type: String, body: Data) {
        // "POST /find?kind=star HTTP/1.1"
        let line = request.prefix { $0 != "\r" && $0 != "\n" }.split(separator: " ")
        let method = line.first.map(String.init) ?? "GET"
        let target = URLComponents(string: line.count > 1 ? String(line[1]) : "/")
        let path = target?.path ?? "/"

        switch (method, path) {
        case ("GET", "/finds"):
            let body = (try? JSONEncoder().encode(finds())) ?? Data("[]".utf8)
            return ("200 OK", "application/json", body)
        case ("POST", "/find"):
            let kind = target?.queryItems?.first { $0.name == "kind" }?.value ?? ""
            return onFind(kind) ? ("204 No Content", "text/plain", Data()) : ("400 Bad Request", "text/plain", Data())
        case (_, let path) where path.hasPrefix("/favicon"):
            return ("404 Not Found", "text/plain", Data())
        default:
            return ("200 OK", "text/html; charset=utf-8", Data(BlockedPage.html(for: choice()).utf8))
        }
    }
}
