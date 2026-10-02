import Foundation

enum RelayRunnerError: Error, CustomStringConvertible {
    case executableMissing(String)
    case commandFailed(Int32, String)

    var description: String {
        switch self {
        case .executableMissing(let path):
            return "Relay executable not found at \(path)"
        case .commandFailed(let code, let stderr):
            return "Relay command failed with exit code \(code): \(stderr)"
        }
    }
}

enum RelayRunner {
    static func run(relay: RelayConfig, notifications: [NotificationRecord], summary: String) throws {
        if notifications.isEmpty, relay.resolvedSkipIfEmpty {
            return
        }

        let executable = relay.resolvedExecutable
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw RelayRunnerError.executableMissing(executable)
        }

        let json = try encodeJSON(notifications.map(ForwardNotification.init(record:)))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = relay.resolvedArguments.map {
            $0
                .replacingOccurrences(of: "{{summary}}", with: summary)
                .replacingOccurrences(of: "{{json}}", with: json)
                .replacingOccurrences(of: "{{count}}", with: String(notifications.count))
        }
        if let workingDirectory = relay.resolvedWorkingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        var environment = ProcessInfo.processInfo.environment
        environment["MAC_NOTIFICATIONS_SUMMARY"] = summary
        environment["MAC_NOTIFICATIONS_COUNT"] = String(notifications.count)
        environment["MAC_NOTIFICATIONS_JSON"] = json
        for (key, value) in relay.environment ?? [:] {
            environment[key] = value
        }
        process.environment = environment

        // Inherit output instead of filling undrained pipes while waiting for exit.
        // CLI callers can redirect it, and no notification output is retained here.
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        // A private temporary file avoids blocking/SIGPIPE when a relay exits
        // without consuming stdin. Unlink it immediately after opening it.
        var inputHandle: FileHandle?
        defer { try? inputHandle?.close() }
        if relay.resolvedStdin != .none {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            let inputURL = directory.appendingPathComponent("stdin")
            let input = relay.resolvedStdin == .summary ? summary : json
            try Data(input.utf8).write(to: inputURL)
            inputHandle = try FileHandle(forReadingFrom: inputURL)
            try FileManager.default.removeItem(at: inputURL)
            process.standardInput = inputHandle
        } else {
            process.standardInput = FileHandle.nullDevice
        }
        try process.run()

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw RelayRunnerError.commandFailed(process.terminationStatus, "Check the relay's stderr for details.")
        }
    }

    private static func encodeJSON(_ payload: [ForwardNotification]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        return String(decoding: data, as: UTF8.self)
    }
}
