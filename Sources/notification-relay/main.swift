import Foundation
import AppKit

enum CLIError: Error, CustomStringConvertible {
    case usage(String)

    var description: String {
        switch self {
        case .usage(let message):
            return message
        }
    }
}

private let usageText = """
Usage:
  notification-relay run --config /path/to/config.json [--once] [--reset-state]
  notification-relay print-json --config /path/to/config.json [--reset-state]
  notification-relay sample-config

Notes:
  - The process needs Full Disk Access to read macOS notifications.
  - Use includeRules and excludeRules to whitelist or blacklist notifications.
  - Use --reset-state to clear the dedupe checkpoint before a test run.
  - Relay arguments may include {{summary}}, {{json}}, and {{count}} placeholders.
  - print-json emits only the filtered notification array to stdout and skips the relay.
"""

private func parseRunOptions<S: Sequence>(_ arguments: S) throws -> (configPath: String, once: Bool, resetState: Bool) where S.Element == String {
    var configPath = ConfigurationStore.defaultConfigPath
    var once = false
    var resetState = false
    var iterator = arguments.makeIterator()

    while let argument = iterator.next() {
        switch argument {
        case "--config":
            guard let value = iterator.next() else {
                throw CLIError.usage("--config requires a path.\n\n\(usageText)")
            }
            configPath = value
        case "--once":
            once = true
        case "--reset-state":
            resetState = true
        case "help", "--help", "-h":
            throw CLIError.usage(usageText)
        default:
            throw CLIError.usage("Unknown option: \(argument)\n\n\(usageText)")
        }
    }

    return (configPath, once, resetState)
}

private func runCLI() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
        throw CLIError.usage(usageText)
    }

    switch command {
    case "run":
        let options = try parseRunOptions(arguments.dropFirst())
        let config = try options.configPath == ConfigurationStore.defaultConfigPath
            ? ConfigurationStore().prepare() : AppConfig.load(from: options.configPath)
        let monitor = NotificationMonitor(config: config)

        if options.resetState {
            try monitor.resetState()
            print("State reset.")
        }

        if options.once {
            try monitor.runOnce()
            return
        }

        while true {
            do {
                try monitor.runOnce()
            } catch {
                fputs("Run failed: \(error)\n", stderr)
            }
            Thread.sleep(forTimeInterval: config.resolvedPollIntervalSeconds)
        }
    case "print-json":
        let options = try parseRunOptions(arguments.dropFirst())
        let config = try options.configPath == ConfigurationStore.defaultConfigPath
            ? ConfigurationStore().prepare() : AppConfig.load(from: options.configPath)
        let monitor = NotificationMonitor(config: config)

        if options.resetState {
            try monitor.resetState()
        }

        let pending = try monitor.pendingNotifications()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(pending.notifications.map(ForwardNotification.init(record:)))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    case "sample-config":
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(AppConfig.defaults), as: UTF8.self))
    case "help", "--help", "-h":
        print(usageText)
    default:
        throw CLIError.usage(usageText)
    }
}

if CommandLine.arguments.count == 1 && Bundle.main.bundleURL.pathExtension == "app" {
    let application = NSApplication.shared
    let delegate = MenuBarController()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        application.run()
    }
} else {
    do {
        try runCLI()
    } catch {
        fputs("Error: \(error)\n", stderr)
        exit(1)
    }
}
