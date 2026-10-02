import Foundation
import SQLite3

enum NotificationDatabaseError: Error, CustomStringConvertible {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    var description: String {
        switch self {
        case .openFailed(let message):
            return "Unable to open notification database: \(message)"
        case .prepareFailed(let message):
            return "Unable to prepare notification query: \(message)"
        case .stepFailed(let message):
            return "Unable to read notification rows: \(message)"
        }
    }
}

final class NotificationDatabase {
    private let path: String

    init(path: String) {
        self.path = path
    }

    func fetchNotifications(deliveredAfter: Date?, limit: Int, accepting: (NotificationRecord) -> Bool = { _ in true }) throws -> [NotificationRecord] {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX

        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if db != nil {
                sqlite3_close(db)
            }
            throw NotificationDatabaseError.openFailed(message)
        }
        defer { sqlite3_close(db) }

        let sql: String
        if deliveredAfter != nil {
            sql = """
            SELECT r.rec_id, a.identifier, r.uuid, r.data, r.request_date, r.delivered_date, r.presented
            FROM record r
            JOIN app a ON a.app_id = r.app_id
            WHERE r.delivered_date >= ?
            ORDER BY r.delivered_date ASC, r.rec_id ASC
            ;
            """
        } else {
            sql = """
            SELECT r.rec_id, a.identifier, r.uuid, r.data, r.request_date, r.delivered_date, r.presented
            FROM record r
            JOIN app a ON a.app_id = r.app_id
            ORDER BY r.delivered_date ASC, r.rec_id ASC
            ;
            """
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NotificationDatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        if let deliveredAfter {
            sqlite3_bind_double(statement, 1, deliveredAfter.timeIntervalSinceReferenceDate)
        }

        var notifications: [NotificationRecord] = []

        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                let notification = try decodeRow(statement)
                if accepting(notification) {
                    notifications.append(notification)
                    if notifications.count >= limit { break }
                }
            } else if result == SQLITE_DONE {
                break
            } else {
                throw NotificationDatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }

        return notifications
    }

    func fetchExistingTrackingKeys() throws -> Set<String> {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX

        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if db != nil {
                sqlite3_close(db)
            }
            throw NotificationDatabaseError.openFailed(message)
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT rec_id, uuid
        FROM record;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NotificationDatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var keys: Set<String> = []

        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                let recordID = sqlite3_column_int64(statement, 0)
                let uuidData = Data(sqliteBlobAt: 1, statement: statement)
                let key: String
                if let uuid = uuidData.flatMap(UUID.init(data:)) {
                    key = "uuid:\(uuid.uuidString.lowercased())"
                } else {
                    key = "rec:\(recordID)"
                }
                keys.insert(key)
            } else if result == SQLITE_DONE {
                break
            } else {
                throw NotificationDatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
        }

        return keys
    }

    private func decodeRow(_ statement: OpaquePointer?) throws -> NotificationRecord {
        let recordID = sqlite3_column_int64(statement, 0)
        let bundleIdentifier = String(cString: sqlite3_column_text(statement, 1))
        let uuidData = Data(sqliteBlobAt: 2, statement: statement)
        let payloadData = Data(sqliteBlobAt: 3, statement: statement) ?? Data()
        let requestedAt = sqliteDateAt(column: 4, statement: statement)
        let deliveredAt = sqliteDateAt(column: 5, statement: statement)
        let presented = sqlite3_column_int(statement, 6) != 0

        let payload = decodePayload(from: payloadData)
        let request = payload["req"] as? [String: Any] ?? [:]

        return NotificationRecord(
            recordID: recordID,
            bundleIdentifier: bundleIdentifier,
            deliveredAt: deliveredAt,
            requestedAt: requestedAt,
            presented: presented,
            systemUUID: uuidData.flatMap(UUID.init(data:)),
            title: stringValue(request["titl"]),
            subtitle: stringValue(request["subt"]),
            body: stringValue(request["body"]),
            category: stringValue(request["cate"]),
            threadIdentifier: stringValue(request["thre"]),
            sourceIdentifier: stringValue(request["filcr"])
        )
    }

    private func decodePayload(from data: Data) -> [String: Any] {
        if let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            return dict
        }

        let allowedClasses: [AnyClass] = [
            NSDictionary.self,
            NSArray.self,
            NSString.self,
            NSNumber.self,
            NSData.self,
            NSDate.self,
        ]
        if let dict = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: data) as? [String: Any] {
            return dict
        }

        return [:]
    }

    private func sqliteDateAt(column: Int32, statement: OpaquePointer?) -> Date? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
            return nil
        }
        return Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, column))
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }
}

private extension Data {
    init?(sqliteBlobAt column: Int32, statement: OpaquePointer?) {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
            return nil
        }
        guard let bytes = sqlite3_column_blob(statement, column) else {
            return nil
        }
        let count = Int(sqlite3_column_bytes(statement, column))
        self.init(bytes: bytes, count: count)
    }
}

private extension UUID {
    init?(data: Data) {
        guard data.count == 16 else { return nil }
        let tuple = data.withUnsafeBytes { rawBuffer -> uuid_t in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            return (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            )
        }
        self.init(uuid: tuple)
    }
}
