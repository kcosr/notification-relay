import XCTest
import SQLite3
@testable import notification_relay

final class RegressionTests: XCTestCase {
    func testInvalidExcludeRegexRejectsConfiguration() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("config.json")
            try Data(#"{"relay":{"executable":"/usr/bin/true"},"excludeRules":[{"name":"bad regex","body":[{"type":"regex","value":"["}]}]}"#.utf8).write(to: url)
            XCTAssertThrowsError(try AppConfig.load(from: url.path))
        }
    }

    func testRelayMayExitWithoutConsumingLargeInput() throws {
        let relay = try JSONDecoder().decode(RelayConfig.self,
            from: Data(#"{"executable":"/usr/bin/true","arguments":[],"stdin":"summary","skipIfEmpty":false}"#.utf8))
        XCTAssertNoThrow(try RelayRunner.run(relay: relay, notifications: [],
            summary: String(repeating: "x", count: 96_000)))
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    func testMissingCheckpointStartsEmpty() throws {
        try withDirectory { directory in
            XCTAssertTrue(try StateStore(path: directory.appendingPathComponent("state.json").path)
                .load().forwardedNotificationKeys.isEmpty)
        }
    }

    func testDamagedCheckpointIsNotSilentlyReset() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("state.json")
            try Data("broken".utf8).write(to: url)
            XCTAssertThrowsError(try StateStore(path: url.path).load())
        }
    }

    func testCheckpointRoundTripAndReset() throws {
        try withDirectory { directory in
            let store = StateStore(path: directory.appendingPathComponent("nested/state.json").path)
            try store.save(StoredState(forwardedNotificationKeys: ["rec:1"]))
            XCTAssertEqual(try store.load().forwardedNotificationKeys, ["rec:1"])
            try store.reset()
            XCTAssertTrue(try store.load().forwardedNotificationKeys.isEmpty)
        }
    }

    func testBatchLimitDoesNotHideNewMatchingRows() throws {
        try withDirectory { directory in
            let databasePath = directory.appendingPathComponent("db").path
            var db: OpaquePointer?
            XCTAssertEqual(sqlite3_open(databasePath, &db), SQLITE_OK)
            defer { sqlite3_close(db) }
            let sql = """
            CREATE TABLE app (app_id INTEGER, identifier TEXT);
            CREATE TABLE record (rec_id INTEGER, app_id INTEGER, uuid BLOB, data BLOB,
                                 request_date REAL, delivered_date REAL, presented INTEGER);
            INSERT INTO app VALUES (1, 'example.allowed'), (2, 'example.excluded');
            INSERT INTO record VALUES (1, 1, NULL, NULL, 1, 1, 1);
            INSERT INTO record VALUES (2, 2, NULL, NULL, 2, 2, 1);
            INSERT INTO record VALUES (3, 1, NULL, NULL, 3, 3, 1);
            INSERT INTO record VALUES (4, 1, NULL, NULL, 4, 4, 1);
            """
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
            let checkpoint = directory.appendingPathComponent("state.json").path
            try StateStore(path: checkpoint).save(StoredState(forwardedNotificationKeys: ["rec:1", "rec:999"]))
            var config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"relay":{"executable":"/usr/bin/true"},"excludeRules":[{"name":"exclude","bundleIdentifiers":["example.excluded"]}]}"#.utf8))
            config.databasePath = databasePath
            config.checkpointPath = checkpoint
            config.initialLookbackSeconds = 0
            config.maxNotificationsPerRun = 1
            let monitor = NotificationMonitor(config: config)
            let pending = try monitor.pendingNotifications()
            XCTAssertEqual(pending.notifications.map(\.recordID), [3])
            XCTAssertEqual(pending.state.forwardedNotificationKeys, ["rec:1"])
            try monitor.runOnce()
            XCTAssertEqual(try monitor.pendingNotifications().notifications.map(\.recordID), [4])
        }
    }
}
