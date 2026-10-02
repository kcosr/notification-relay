import Foundation

struct PendingNotifications {
    var state: StoredState
    var notifications: [NotificationRecord]
}

final class NotificationMonitor {
    private let config: AppConfig
    private let database: NotificationDatabase
    private let stateStore: StateStore

    init(config: AppConfig) {
        self.config = config
        self.database = NotificationDatabase(path: config.resolvedDatabasePath)
        self.stateStore = StateStore(path: config.resolvedCheckpointPath)
    }

    func resetState() throws {
        try stateStore.reset()
    }

    func pendingNotifications() throws -> PendingNotifications {
        var state = try stateStore.load()
        let existingTrackingKeys = try database.fetchExistingTrackingKeys()
        state.forwardedNotificationKeys = state.forwardedNotificationKeys.filter { existingTrackingKeys.contains($0) }

        let lookbackDate: Date? = config.resolvedInitialLookbackSeconds > 0
            ? Date().addingTimeInterval(-config.resolvedInitialLookbackSeconds)
            : nil

        let forwardedKeys = Set(state.forwardedNotificationKeys)
        let filtered = try database.fetchNotifications(
            deliveredAfter: lookbackDate,
            limit: config.resolvedMaxNotificationsPerRun
        ) { notification in
            !forwardedKeys.contains(notification.trackingKey)
                && !FilterEngine.filter([notification], includeRules: config.resolvedIncludeRules,
                                        excludeRules: config.resolvedExcludeRules).isEmpty
        }

        return PendingNotifications(
            state: state,
            notifications: filtered
        )
    }

    func runOnce() throws {
        guard config.resolvedMonitoringEnabled, !config.relay.executable.isEmpty else {
            throw ConfigurationError.invalid("Monitoring is paused. Choose a script and enable monitoring in Settings.")
        }
        var pending = try pendingNotifications()

        if pending.notifications.isEmpty {
            print("No new matching notifications.")
            try stateStore.save(pending.state)
            return
        }

        let summary = SummaryBuilder.build(notifications: pending.notifications, config: config.resolvedSummary)
        try RelayRunner.run(relay: config.relay, notifications: pending.notifications, summary: summary)
        pending.state.forwardedNotificationKeys.append(contentsOf: pending.notifications.map(\.trackingKey))
        pending.state.forwardedNotificationKeys = Array(Set(pending.state.forwardedNotificationKeys)).sorted()
        try stateStore.save(pending.state)
        print("Forwarded \(pending.notifications.count) notification\(pending.notifications.count == 1 ? "" : "s").")
    }
}
