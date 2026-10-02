import Foundation

struct NotificationRecord: Sendable {
    let recordID: Int64
    let bundleIdentifier: String
    let deliveredAt: Date?
    let requestedAt: Date?
    let presented: Bool
    let systemUUID: UUID?
    let title: String?
    let subtitle: String?
    let body: String?
    let category: String?
    let threadIdentifier: String?
    let sourceIdentifier: String?

    var trackingKey: String {
        if let systemUUID {
            return "uuid:\(systemUUID.uuidString.lowercased())"
        }
        return "rec:\(recordID)"
    }
}

struct ForwardNotification: Codable, Sendable {
    let recordID: Int64
    let bundleIdentifier: String
    let deliveredAt: String?
    let requestedAt: String?
    let title: String?
    let subtitle: String?
    let body: String?
    let category: String?
    let threadIdentifier: String?
    let sourceIdentifier: String?
    let systemUUID: String?

    init(record: NotificationRecord) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        self.recordID = record.recordID
        self.bundleIdentifier = record.bundleIdentifier
        self.deliveredAt = record.deliveredAt.map { formatter.string(from: $0) }
        self.requestedAt = record.requestedAt.map { formatter.string(from: $0) }
        self.title = record.title
        self.subtitle = record.subtitle
        self.body = record.body
        self.category = record.category
        self.threadIdentifier = record.threadIdentifier
        self.sourceIdentifier = record.sourceIdentifier
        self.systemUUID = record.systemUUID?.uuidString
    }
}
