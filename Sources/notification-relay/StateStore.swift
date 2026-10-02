import Foundation

struct StoredState: Codable {
    var forwardedNotificationKeys: [String]

    init(forwardedNotificationKeys: [String] = []) {
        self.forwardedNotificationKeys = forwardedNotificationKeys
    }
}

final class StateStore {
    private let path: String

    init(path: String) {
        self.path = path
    }

    func load() throws -> StoredState {
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return StoredState()
        }
        let decoder = JSONDecoder()
        return try decoder.decode(StoredState.self, from: data)
    }

    func save(_ state: StoredState) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    func reset() throws {
        try save(StoredState())
    }
}
