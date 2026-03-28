import Testing
import GRDB
@testable import BrainCore

@Suite("Rules Engine")
struct RulesEngineTests {

    private func makeEngine() throws -> (RulesEngine, DatabasePool) {
        let db = try DatabaseManager.temporary()
        return (RulesEngine(pool: db.pool), db.pool)
    }

    private func insertRule(
        _ pool: DatabasePool,
        name: String,
        category: String = "behavior",
        condition: String? = nil,
        action: String = "{\"type\":\"test\"}",
        priority: Int = 0,
        enabled: Bool = true
    ) throws {
        try pool.write { db in
            var rule = Rule(
                category: category,
                name: name,
                condition: condition,
                action: action,
                priority: priority,
                enabled: enabled
            )
            try rule.insert(db)
        }
    }

    @Test("Rule with no condition matches everything")
    func noCondition() throws {
        let (engine, pool) = try makeEngine()
        try insertRule(pool, name: "always_match", condition: nil)

        let matches = try engine.evaluate(context: RuleContext(trigger: "anything"))
        #expect(matches.count == 1)
    }

    @Test("Rule matches on trigger")
    func triggerMatch() throws {
        let (engine, pool) = try makeEngine()
        try insertRule(pool, name: "on_open", condition: "{\"trigger\":\"app_open\"}")

        let open = try engine.evaluate(context: RuleContext(trigger: "app_open"))
        #expect(open.count == 1)

        let other = try engine.evaluate(context: RuleContext(trigger: "entry_created"))
        #expect(other.isEmpty)
    }

    @Test("Rule matches on time range")
    func timeRange() throws {
        let (engine, pool) = try makeEngine()
        try insertRule(pool, name: "morning", condition: "{\"time\":\"07:00-09:00\"}")

        let inRange = try engine.evaluate(context: RuleContext(trigger: "app_open", timeOfDay: "08:30"))
        #expect(inRange.count == 1)

        let outOfRange = try engine.evaluate(context: RuleContext(trigger: "app_open", timeOfDay: "12:00"))
        #expect(outOfRange.isEmpty)
    }

    @Test("Rule matches on entry type")
    func entryType() throws {
        let (engine, pool) = try makeEngine()
        try insertRule(pool, name: "task_rule", condition: "{\"entryType\":\"task\"}")

        let task = try engine.evaluate(context: RuleContext(trigger: "entry_created", entryType: "task"))
        #expect(task.count == 1)

        let thought = try engine.evaluate(context: RuleContext(trigger: "entry_created", entryType: "thought"))
        #expect(thought.isEmpty)
    }

    @Test("Disabled rules are skipped")
    func disabledRules() throws {
        let (engine, pool) = try makeEngine()
        try insertRule(pool, name: "disabled_rule", enabled: false)

        let matches = try engine.evaluate(context: RuleContext(trigger: "any"))
        #expect(matches.isEmpty)
    }

    @Test("Rules are sorted by priority descending")
    func priorityOrder() throws {
        let (engine, pool) = try makeEngine()
        try insertRule(pool, name: "low_priority", priority: 1)
        try insertRule(pool, name: "high_priority", priority: 10)
        try insertRule(pool, name: "mid_priority", priority: 5)

        let matches = try engine.evaluate(context: RuleContext(trigger: "any"))
        #expect(matches.count == 3)
        #expect(matches[0].rule.name == "high_priority")
        #expect(matches[1].rule.name == "mid_priority")
        #expect(matches[2].rule.name == "low_priority")
    }

    @Test("Combined conditions must all match")
    func combinedConditions() throws {
        let (engine, pool) = try makeEngine()
        try insertRule(pool, name: "combined", condition: "{\"trigger\":\"app_open\",\"time\":\"07:00-09:00\"}")

        // Both match
        let both = try engine.evaluate(context: RuleContext(trigger: "app_open", timeOfDay: "08:00"))
        #expect(both.count == 1)

        // Trigger matches but time doesn't
        let wrongTime = try engine.evaluate(context: RuleContext(trigger: "app_open", timeOfDay: "12:00"))
        #expect(wrongTime.isEmpty)

        // Time matches but trigger doesn't
        let wrongTrigger = try engine.evaluate(context: RuleContext(trigger: "entry_created", timeOfDay: "08:00"))
        #expect(wrongTrigger.isEmpty)
    }
}
