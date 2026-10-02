import Foundation

/// Owns configuration and performs a one-time, non-destructive migration from the CLI layout.
struct ConfigurationStore {
    static var defaultConfigPath: String { ConfigurationStore().configURL.path }
    static var defaultStatePath: String { ConfigurationStore().stateURL.path }

    let homeDirectory: URL
    var directoryURL: URL { homeDirectory.appendingPathComponent("Library/Application Support/Notification Relay", isDirectory: true) }
    var configURL: URL { directoryURL.appendingPathComponent("config.json") }
    var stateURL: URL { directoryURL.appendingPathComponent("state.json") }
    private var legacyConfigURL: URL { homeDirectory.appendingPathComponent(".config/mac-notifications/config.json") }
    private var legacyStateURL: URL { homeDirectory.appendingPathComponent(".local/state/mac-notifications/state.json") }

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func prepare() throws -> AppConfig {
        if let data = try readIfPresent(configURL) {
            let config = try decode(data)
            try validateState(at: checkpointURL(for: config))
            return config
        }

        var config: AppConfig
        if let legacy = try readIfPresent(legacyConfigURL) {
            config = try decode(legacy)
            let source = config.checkpointPath.map(resolve) ?? legacyStateURL
            // Custom checkpoint locations remain authoritative; only the old default moves.
            if source.standardizedFileURL == legacyStateURL.standardizedFileURL {
                let oldState = try readIfPresent(source)
                if let oldState { _ = try JSONDecoder().decode(StoredState.self, from: oldState) }
                if let existing = try readIfPresent(stateURL) {
                    _ = try JSONDecoder().decode(StoredState.self, from: existing)
                } else if let oldState {
                    try writePrivate(oldState, to: stateURL)
                }
                config.checkpointPath = stateURL.path
            } else {
                try validateState(at: source)
            }
        } else {
            config = AppConfig.defaults
            config.checkpointPath = stateURL.path
            try validateState(at: stateURL)
        }
        try save(config)
        return config
    }

    func save(_ config: AppConfig) throws {
        try config.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try writePrivate(encoder.encode(config), to: configURL)
    }

    private func decode(_ data: Data) throws -> AppConfig {
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        try config.validate()
        return config
    }

    private func checkpointURL(for config: AppConfig) -> URL {
        config.checkpointPath.map(resolve) ?? stateURL
    }

    private func resolve(_ path: String) -> URL {
        if path == "~" { return homeDirectory }
        if path.hasPrefix("~/") { return homeDirectory.appendingPathComponent(String(path.dropFirst(2))) }
        return URL(fileURLWithPath: path.expandingTildeInPath)
    }

    private func validateState(at url: URL) throws {
        if let data = try readIfPresent(url) { _ = try JSONDecoder().decode(StoredState.self, from: data) }
    }

    private func readIfPresent(_ url: URL) throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directoryURL, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        try data.write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
