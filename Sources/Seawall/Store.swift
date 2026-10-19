import Foundation

/// JSON files in ~/Library/Application Support/Seawall.
struct Store {
    enum File: String {
        /// `session` is the single block of older versions, read once to migrate.
        case config, sessions, session, summary, finds
    }

    let directory: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("Seawall", isDirectory: true)
        // The app was called FocusLock; its blocks and finds move over on the first launch.
        let old = support.appendingPathComponent("FocusLock", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path), FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.moveItem(at: old, to: directory)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load<T: Decodable>(_ type: T.Type, from file: File) -> T? {
        guard let data = try? Data(contentsOf: url(file)) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            log.error("Can't read \(file.rawValue).json: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save<T: Encodable>(_ value: T, as file: File) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(value).write(to: url(file), options: .atomic)
        } catch {
            log.error("Can't write \(file.rawValue).json: \(error.localizedDescription, privacy: .public)")
        }
    }

    func remove(_ file: File) {
        try? FileManager.default.removeItem(at: url(file))
    }

    private func url(_ file: File) -> URL {
        directory.appendingPathComponent("\(file.rawValue).json")
    }
}
