import Foundation
import XCTest
@testable import notification_relay

final class ConfigurationStoreTests: XCTestCase {
    private func withHome(_ body: (URL, ConfigurationStore) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(home, ConfigurationStore(homeDirectory: home))
    }

    private func write(_ text: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func testFreshConfigurationIsDisabledAndPrivate() throws {
        try withHome { _, store in
            let config = try store.prepare()
            XCTAssertEqual(config.monitoringEnabled, false)
            XCTAssertEqual(config.relay.executable, "")
            XCTAssertEqual(config.checkpointPath, store.stateURL.path)
            let attributes = try FileManager.default.attributesOfItem(atPath: store.configURL.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            let directory = try FileManager.default.attributesOfItem(atPath: store.directoryURL.path)
            XCTAssertEqual((directory[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        }
    }

    func testMigrationPreservesConfigurationAndForwardedIDs() throws {
        try withHome { home, store in
            let legacy = home.appendingPathComponent(".config/mac-notifications/config.json")
            try write(#"{"relay":{"executable":"/usr/bin/true","arguments":[],"stdin":"json","environment":{"TEST":"value"}},"pollIntervalSeconds":95,"includeRules":[{"name":"mail","bundleIdentifiers":["example.mail"]}],"excludeRules":[{"name":"noise","body":[{"type":"contains","value":"ignore"}]}]}"#, at: legacy)
            try write(#"{"forwardedNotificationKeys":["rec:1","rec:2"]}"#,
                      at: home.appendingPathComponent(".local/state/mac-notifications/state.json"))
            let config = try store.prepare()
            XCTAssertEqual(config.pollIntervalSeconds, 95)
            XCTAssertEqual(config.relay.environment, ["TEST": "value"])
            XCTAssertEqual(config.relay.arguments, [])
            XCTAssertEqual(config.includeRules?.first?.name, "mail")
            XCTAssertEqual(config.excludeRules?.first?.name, "noise")
            XCTAssertEqual(config.checkpointPath, store.stateURL.path)
            XCTAssertEqual(try StateStore(path: store.stateURL.path).load().forwardedNotificationKeys, ["rec:1", "rec:2"])
            XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
        }
    }

    func testExplicitLegacyCheckpointMigrates() throws {
        try withHome { home, store in
            try write(#"{"checkpointPath":"~/.local/state/mac-notifications/state.json","relay":{"executable":"/usr/bin/true"}}"#,
                      at: home.appendingPathComponent(".config/mac-notifications/config.json"))
            XCTAssertEqual(try store.prepare().checkpointPath, store.stateURL.path)
        }
    }

    func testCustomCheckpointRemainsAuthoritative() throws {
        try withHome { home, store in
            try write(#"{"checkpointPath":"~/custom/checkpoint.json","relay":{"executable":"/usr/bin/true"}}"#,
                      at: home.appendingPathComponent(".config/mac-notifications/config.json"))
            let custom = home.appendingPathComponent("custom/checkpoint.json")
            try write(#"{"forwardedNotificationKeys":["rec:custom"]}"#, at: custom)
            XCTAssertEqual(try store.prepare().checkpointPath, "~/custom/checkpoint.json")
            XCTAssertEqual(try StateStore(path: custom.path).load().forwardedNotificationKeys, ["rec:custom"])
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.stateURL.path))
        }
    }

    func testRepeatedPreparationNeverOverwritesNewConfiguration() throws {
        try withHome { home, store in
            var config = try store.prepare()
            config.pollIntervalSeconds = 120
            try store.save(config)
            try write("corrupt obsolete config", at: home.appendingPathComponent(".config/mac-notifications/config.json"))
            XCTAssertEqual(try store.prepare().pollIntervalSeconds, 120)
        }
    }

    func testCorruptLegacyConfigurationFailsWithoutCreatingReplacement() throws {
        try withHome { home, store in
            try write("corrupt", at: home.appendingPathComponent(".config/mac-notifications/config.json"))
            XCTAssertThrowsError(try store.prepare())
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.configURL.path))
        }
    }

    func testCorruptLegacyCheckpointFailsWithoutCreatingReplacement() throws {
        try withHome { home, store in
            try write(#"{"relay":{"executable":"/usr/bin/true"}}"#,
                      at: home.appendingPathComponent(".config/mac-notifications/config.json"))
            try write("corrupt", at: home.appendingPathComponent(".local/state/mac-notifications/state.json"))
            XCTAssertThrowsError(try store.prepare())
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.configURL.path))
        }
    }

    func testExistingConfigurationDoesNotMaskCorruptState() throws {
        try withHome { _, store in
            _ = try store.prepare()
            try write("corrupt", at: store.stateURL)
            XCTAssertThrowsError(try store.prepare())
        }
    }
}
