import Foundation

struct NotificationRule: Codable, Sendable {
    var name: String
    var bundleIdentifiers: [String]?
    var title: [StringMatcher]?
    var subtitle: [StringMatcher]?
    var body: [StringMatcher]?
    var anyField: [StringMatcher]?
    var threadIdentifier: [StringMatcher]?
    var category: [StringMatcher]?

    func matches(_ notification: NotificationRecord) -> Bool {
        if let bundleIdentifiers, !bundleIdentifiers.contains(notification.bundleIdentifier) {
            return false
        }

        if !matchesField(notification.title, matchers: title) { return false }
        if !matchesField(notification.subtitle, matchers: subtitle) { return false }
        if !matchesField(notification.body, matchers: body) { return false }
        if !matchesField(notification.threadIdentifier, matchers: threadIdentifier) { return false }
        if !matchesField(notification.category, matchers: category) { return false }

        if let anyField {
            let haystacks = [notification.title, notification.subtitle, notification.body].compactMap { $0 }
            let anyMatched = haystacks.contains { value in
                anyField.contains { matcher in matcher.matches(value) }
            }
            if !anyMatched {
                return false
            }
        }

        return true
    }

    private func matchesField(_ value: String?, matchers: [StringMatcher]?) -> Bool {
        guard let matchers else { return true }
        guard let value, !value.isEmpty else { return false }
        return matchers.contains { $0.matches(value) }
    }
}

struct StringMatcher: Codable, Sendable {
    var type: MatcherType?
    var value: String
    var caseSensitive: Bool?

    func matches(_ input: String) -> Bool {
        let isCaseSensitive = caseSensitive ?? false

        switch type ?? .contains {
        case .contains:
            return compare(input, against: value, caseSensitive: isCaseSensitive, operation: { $0.contains($1) })
        case .equals:
            return compare(input, against: value, caseSensitive: isCaseSensitive, operation: ==)
        case .prefix:
            return compare(input, against: value, caseSensitive: isCaseSensitive, operation: { $0.hasPrefix($1) })
        case .suffix:
            return compare(input, against: value, caseSensitive: isCaseSensitive, operation: { $0.hasSuffix($1) })
        case .regex:
            let options: NSRegularExpression.Options = isCaseSensitive ? [] : [.caseInsensitive]
            guard let regex = try? NSRegularExpression(pattern: value, options: options) else {
                return false
            }
            let range = NSRange(input.startIndex..<input.endIndex, in: input)
            return regex.firstMatch(in: input, options: [], range: range) != nil
        }
    }

    private func compare(
        _ input: String,
        against pattern: String,
        caseSensitive: Bool,
        operation: (String, String) -> Bool
    ) -> Bool {
        if caseSensitive {
            return operation(input, pattern)
        }
        return operation(input.lowercased(), pattern.lowercased())
    }
}

enum MatcherType: String, Codable {
    case contains
    case equals
    case prefix
    case suffix
    case regex
}

enum FilterEngine {
    static func filter(
        _ notifications: [NotificationRecord],
        includeRules: [NotificationRule],
        excludeRules: [NotificationRule]
    ) -> [NotificationRecord] {
        notifications.filter { notification in
            let included = includeRules.isEmpty || includeRules.contains { $0.matches(notification) }
            let excluded = excludeRules.contains { $0.matches(notification) }
            return included && !excluded
        }
    }
}

