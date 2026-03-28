import Foundation
import GRDB

// Context provided when evaluating rules.
public struct RuleContext: Sendable {
    public var trigger: String         // e.g. "app_open", "entry_created"
    public var entryType: String?      // e.g. "task", "thought"
    public var timeOfDay: String?      // e.g. "08:30"
    public var metadata: [String: String]

    public init(
        trigger: String,
        entryType: String? = nil,
        timeOfDay: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.trigger = trigger
        self.entryType = entryType
        self.timeOfDay = timeOfDay
        self.metadata = metadata
    }
}

// Result of evaluating a rule: the action JSON that should be executed.
public struct RuleMatch: Sendable {
    public let rule: Rule
    public let actionJSON: String
}

// Evaluates rules from the database against a given context.
// This is a config-based engine (no hot code loading) — App Store safe.
public struct RulesEngine: Sendable {

    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    // Evaluate all enabled rules against the given context.
    // Returns matching rules sorted by priority (highest first).
    public func evaluate(context: RuleContext) throws -> [RuleMatch] {
        let rules = try pool.read { db in
            try Rule
                .filter(Column("enabled") == true)
                .order(Column("priority").desc)
                .fetchAll(db)
        }

        return rules.compactMap { rule in
            if matches(rule: rule, context: context) {
                return RuleMatch(rule: rule, actionJSON: rule.action)
            }
            return nil
        }
    }

    // MARK: - Condition matching

    // Checks whether a rule's condition JSON matches the current context.
    // Condition format: {"trigger": "app_open", "time": "07:00-09:00", "entryType": "task"}
    // All specified fields must match. Missing fields in condition are ignored (wildcard).
    private func matches(rule: Rule, context: RuleContext) -> Bool {
        guard let conditionJSON = rule.condition,
              let data = conditionJSON.data(using: .utf8),
              let condition = try? JSONDecoder().decode(RuleCondition.self, from: data)
        else {
            // F-17: Unparseable conditions never match (fail closed).
            // Only rules with no condition field at all should match everything.
            if rule.condition == nil { return true }
            return false
        }

        // Check trigger
        if let trigger = condition.trigger, trigger != context.trigger {
            return false
        }

        // Check entry type
        if let entryType = condition.entryType, entryType != context.entryType {
            return false
        }

        // Check time range
        if let timeRange = condition.time, let currentTime = context.timeOfDay {
            if !isTime(currentTime, inRange: timeRange) {
                return false
            }
        }

        return true
    }

    // Parse a time range like "07:00-09:00" and check if currentTime falls within.
    private func isTime(_ current: String, inRange range: String) -> Bool {
        let parts = range.split(separator: "-")
        guard parts.count == 2 else { return false }
        let start = String(parts[0])
        let end = String(parts[1])
        return current >= start && current <= end
    }
}

// Internal model for parsing rule condition JSON.
private struct RuleCondition: Codable {
    var trigger: String?
    var entryType: String?
    var time: String?
}
