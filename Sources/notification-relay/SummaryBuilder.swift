import Foundation

enum SummaryBuilder {
    static func build(notifications: [NotificationRecord], config: SummaryConfig) -> String {
        guard !notifications.isEmpty else { return "" }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let totalCount = notifications.count
        let shownNotifications = Array(notifications.prefix(config.resolvedMaxItems))
        var lines: [String] = []
        lines.append("Forwarded \(totalCount) macOS notification\(totalCount == 1 ? "" : "s")")

        for notification in shownNotifications {
            var parts: [String] = []
            parts.append(shortAppName(for: notification.bundleIdentifier))

            if config.resolvedIncludeDeliveredAt, let deliveredAt = notification.deliveredAt {
                parts.append(formatter.string(from: deliveredAt))
            }

            let content = compactContent(for: notification, maxBodyLength: config.resolvedMaxBodyLength)
            if !content.isEmpty {
                parts.append(content)
            }

            lines.append("- " + parts.joined(separator: " | "))
        }

        let remainingCount = totalCount - shownNotifications.count
        if remainingCount > 0 {
            lines.append("- +\(remainingCount) more")
        }

        return lines.joined(separator: "\n")
    }

    private static func shortAppName(for bundleIdentifier: String) -> String {
        let lastComponent = bundleIdentifier.split(separator: ".").last.map(String.init)
        return lastComponent?.isEmpty == false ? lastComponent! : bundleIdentifier
    }

    private static func compactContent(for notification: NotificationRecord, maxBodyLength: Int) -> String {
        let body = truncate(notification.body, maxLength: maxBodyLength)
        let pieces = [notification.title, notification.subtitle, body]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return pieces.joined(separator: " | ")
    }

    private static func truncate(_ value: String?, maxLength: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: maxLength - 1)
        return String(trimmed[..<endIndex]) + "…"
    }
}

