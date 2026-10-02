import Foundation

struct AppConfig: Codable, Sendable {
    var monitoringEnabled: Bool?
    var databasePath: String?
    var checkpointPath: String?
    var pollIntervalSeconds: Double?
    var initialLookbackSeconds: Double?
    var maxNotificationsPerRun: Int?
    var summary: SummaryConfig?
    var relay: RelayConfig
    var includeRules: [NotificationRule]?
    var excludeRules: [NotificationRule]?

    static var defaults: AppConfig {
        AppConfig(monitoringEnabled: false, pollIntervalSeconds: 60,
                  initialLookbackSeconds: 1800, maxNotificationsPerRun: 50,
                  summary: SummaryConfig(),
                  relay: RelayConfig(executable: "", arguments: [], stdin: .json),
                  includeRules: [], excludeRules: [])
    }

    var resolvedMonitoringEnabled: Bool { monitoringEnabled ?? true }

    var resolvedDatabasePath: String {
        (databasePath ?? "~/Library/Group Containers/group.com.apple.usernoted/db2/db").expandingTildeInPath
    }

    var resolvedCheckpointPath: String {
        (checkpointPath ?? ConfigurationStore.defaultStatePath).expandingTildeInPath
    }

    var resolvedPollIntervalSeconds: Double {
        max(5, pollIntervalSeconds ?? 60)
    }

    var resolvedInitialLookbackSeconds: Double {
        max(0, initialLookbackSeconds ?? 1800)
    }

    var resolvedMaxNotificationsPerRun: Int {
        max(1, maxNotificationsPerRun ?? 50)
    }

    var resolvedSummary: SummaryConfig {
        summary ?? SummaryConfig()
    }

    var resolvedIncludeRules: [NotificationRule] {
        includeRules ?? []
    }

    var resolvedExcludeRules: [NotificationRule] {
        excludeRules ?? []
    }

    static func load(from path: String) throws -> AppConfig {
        let resolvedPath = path.expandingTildeInPath
        let data = try Data(contentsOf: URL(fileURLWithPath: resolvedPath))
        let decoder = JSONDecoder()
        let config = try decoder.decode(AppConfig.self, from: data)
        try config.validate()
        return config
    }

    func validate() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigurationError.invalid(message) }
        }
        try require(resolvedPollIntervalSeconds.isFinite && (5...86400).contains(pollIntervalSeconds ?? 60),
                    "Polling interval must be between 5 and 86400 seconds.")
        try require(resolvedInitialLookbackSeconds.isFinite && (initialLookbackSeconds ?? 1800) >= 0,
                    "Lookback must be a finite nonnegative number of seconds.")
        try require((1...10000).contains(maxNotificationsPerRun ?? 50), "Batch size must be between 1 and 10000.")
        try require(!resolvedMonitoringEnabled || !relay.executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Choose a relay script before enabling monitoring.")
        if !relay.executable.isEmpty {
            try require(relay.resolvedExecutable.hasPrefix("/"), "Relay executable must be an absolute path.")
        }
        try require(resolvedDatabasePath.hasPrefix("/") && resolvedCheckpointPath.hasPrefix("/"),
                    "Database and checkpoint paths must be absolute paths.")
        if let directory = relay.resolvedWorkingDirectory {
            try require(directory.hasPrefix("/"), "Working directory must be an absolute path.")
        }
        for key in relay.environment?.keys ?? Dictionary<String, String>().keys {
            try require(!key.isEmpty && !key.contains("=") && !key.contains("\0"), "Environment variable names must be nonempty and cannot contain = or NUL.")
        }
        // A typo in an exclusion regex must not silently broaden forwarding.
        for rule in resolvedIncludeRules + resolvedExcludeRules {
            let fields = [rule.title, rule.subtitle, rule.body, rule.anyField,
                          rule.threadIdentifier, rule.category]
            for matcher in fields.compactMap({ $0 }).flatMap({ $0 }) where matcher.type == .regex {
                _ = try NSRegularExpression(pattern: matcher.value,
                    options: matcher.caseSensitive == true ? [] : [.caseInsensitive])
            }
        }
    }
}

enum ConfigurationError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

struct SummaryConfig: Codable, Sendable {
    var maxItems: Int?
    var maxBodyLength: Int?
    var includeDeliveredAt: Bool?

    init(maxItems: Int? = nil, maxBodyLength: Int? = nil, includeDeliveredAt: Bool? = nil) {
        self.maxItems = maxItems
        self.maxBodyLength = maxBodyLength
        self.includeDeliveredAt = includeDeliveredAt
    }

    var resolvedMaxItems: Int {
        max(1, maxItems ?? 8)
    }

    var resolvedMaxBodyLength: Int {
        max(20, maxBodyLength ?? 140)
    }

    var resolvedIncludeDeliveredAt: Bool {
        includeDeliveredAt ?? false
    }
}

struct RelayConfig: Codable, Sendable {
    var executable: String
    var arguments: [String]?
    var workingDirectory: String?
    var environment: [String: String]?
    var stdin: RelayInputMode?
    var skipIfEmpty: Bool?

    var resolvedExecutable: String {
        executable.expandingTildeInPath
    }

    var resolvedArguments: [String] {
        arguments ?? ["{{summary}}"]
    }

    var resolvedWorkingDirectory: String? {
        workingDirectory?.expandingTildeInPath
    }

    var resolvedStdin: RelayInputMode {
        stdin ?? .none
    }

    var resolvedSkipIfEmpty: Bool {
        skipIfEmpty ?? true
    }
}

enum RelayInputMode: String, Codable {
    case none
    case summary
    case json
}

extension String {
    var expandingTildeInPath: String {
        (self as NSString).expandingTildeInPath
    }
}
