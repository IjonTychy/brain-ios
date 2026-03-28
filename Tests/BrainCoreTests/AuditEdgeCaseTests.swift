import Testing
import Foundation
import GRDB
@testable import BrainCore

// AP 7+9 L2/L3: Additional edge-case tests for engine components, services, and security boundaries.
@Suite("Audit Edge Cases")
struct AuditEdgeCaseTests {

    // MARK: - LogicInterpreter: Recursion Depth

    @Test("Recursion depth limit throws error")
    func recursionDepthLimit() async throws {
        let mock = MockHandler(type: "test-action")
        let dispatcher = ActionDispatcher(handlers: [mock])
        let interpreter = LogicInterpreter(dispatcher: dispatcher)

        // Build deeply nested if-then chain
        func nestedIf(depth: Int) -> ActionStep {
            if depth <= 0 {
                return ActionStep(type: "test-action", properties: nil)
            }
            return ActionStep(type: "if", properties: [
                "condition": .string("true"),
                "then": .array([
                    .object([
                        "type": .string("if"),
                        "properties": .object([
                            "condition": .string("true"),
                            "then": .array([
                                .object(["type": .string("test-action")])
                            ])
                        ])
                    ])
                ])
            ])
        }

        // Execute at max depth should throw
        do {
            _ = try await interpreter.execute(
                step: nestedIf(depth: 1),
                context: ExpressionContext(),
                depth: LogicInterpreter.maxRecursionDepth + 1
            )
            Issue.record("Expected recursionDepthExceeded error")
        } catch is LogicInterpreterError {
            // Expected
        }
    }

    // MARK: - LogicInterpreter: Reserved Variable Names

    @Test("Set rejects reserved variable name 'system'")
    func setRejectsReservedSystem() async throws {
        let dispatcher = ActionDispatcher(handlers: [])
        let interpreter = LogicInterpreter(dispatcher: dispatcher)

        let step = ActionStep(type: "set", properties: [
            "name": .string("system"),
            "value": .string("hacked")
        ])

        let result = try await interpreter.execute(step: step, context: ExpressionContext())
        if case .error(let msg) = result {
            #expect(msg.contains("reservierten"))
        } else {
            Issue.record("Expected error for reserved name")
        }
    }

    @Test("Set rejects reserved variable name 'admin'")
    func setRejectsReservedAdmin() async throws {
        let dispatcher = ActionDispatcher(handlers: [])
        let interpreter = LogicInterpreter(dispatcher: dispatcher)

        let step = ActionStep(type: "set", properties: [
            "name": .string("admin"),
            "value": .bool(true)
        ])

        let result = try await interpreter.execute(step: step, context: ExpressionContext())
        if case .error(let msg) = result {
            #expect(msg.contains("reservierten"))
        } else {
            Issue.record("Expected error for reserved name")
        }
    }

    // MARK: - LogicInterpreter: Invalid Variable Names

    @Test("Set rejects empty variable name")
    func setRejectsEmptyName() async throws {
        let dispatcher = ActionDispatcher(handlers: [])
        let interpreter = LogicInterpreter(dispatcher: dispatcher)

        let step = ActionStep(type: "set", properties: [
            "name": .string(""),
            "value": .int(1)
        ])

        let result = try await interpreter.execute(step: step, context: ExpressionContext())
        if case .error = result {} else {
            Issue.record("Expected error for empty name")
        }
    }

    @Test("Set rejects variable name with special characters")
    func setRejectsSpecialChars() async throws {
        let dispatcher = ActionDispatcher(handlers: [])
        let interpreter = LogicInterpreter(dispatcher: dispatcher)

        let step = ActionStep(type: "set", properties: [
            "name": .string("var.name"),
            "value": .int(1)
        ])

        let result = try await interpreter.execute(step: step, context: ExpressionContext())
        if case .error(let msg) = result {
            #expect(msg.contains("alphanumerisch"))
        } else {
            Issue.record("Expected error for special chars in name")
        }
    }

    @Test("Set accepts underscore in variable name")
    func setAcceptsUnderscore() async throws {
        let dispatcher = ActionDispatcher(handlers: [])
        let interpreter = LogicInterpreter(dispatcher: dispatcher)

        let step = ActionStep(type: "set", properties: [
            "name": .string("my_var"),
            "value": .int(42)
        ])

        let result = try await interpreter.execute(step: step, context: ExpressionContext())
        if case .value(let val) = result, case .object(let obj) = val {
            #expect(obj["my_var"] == .int(42))
        } else {
            Issue.record("Expected value with my_var")
        }
    }

    // MARK: - LogicInterpreter: forEach Iteration Cap

    @Test("forEach caps at maxForEachIterations")
    func forEachIterationCap() async throws {
        let mock = MockHandler(type: "test-action")
        let dispatcher = ActionDispatcher(handlers: [mock])
        let interpreter = LogicInterpreter(dispatcher: dispatcher)

        // Create array larger than max
        let oversizedArray = (0..<(LogicInterpreter.maxForEachIterations + 50))
            .map { ExpressionValue.int($0) }

        let step = ActionStep(type: "forEach", properties: [
            "data": .string("items"),
            "as": .string("item"),
            "do": .array([.object(["type": .string("test-action")])])
        ])

        let context = ExpressionContext(variables: [
            "items": .array(oversizedArray)
        ])
        _ = try await interpreter.execute(step: step, context: context)

        // Should be capped at maxForEachIterations
        #expect(mock.callCount == LogicInterpreter.maxForEachIterations)
    }

    // MARK: - SearchService: FTS5 Injection Prevention

    @Test("Search sanitizes FTS5 operators")
    func searchSanitizesFTS5() throws {
        let db = try DatabaseManager.temporary()
        let entryService = EntryService(pool: db.pool)
        let searchService = SearchService(pool: db.pool)

        try entryService.create(Entry(type: .note, title: "Normal entry"))

        // FTS5 operators should be sanitized, not cause SQL errors
        let results1 = try searchService.search(query: "NOT normal", limit: 10)
        // Should not crash — operators are quoted
        _ = results1

        let results2 = try searchService.search(query: "title:injection", limit: 10)
        _ = results2

        let results3 = try searchService.search(query: "test OR 1=1", limit: 10)
        _ = results3
    }

    @Test("Search with empty query returns empty results")
    func searchEmptyQuery() throws {
        let db = try DatabaseManager.temporary()
        let searchService = SearchService(pool: db.pool)

        let results = try searchService.search(query: "", limit: 10)
        #expect(results.isEmpty)
    }

    @Test("Search with whitespace-only query returns empty results")
    func searchWhitespaceQuery() throws {
        let db = try DatabaseManager.temporary()
        let searchService = SearchService(pool: db.pool)

        let results = try searchService.search(query: "   ", limit: 10)
        #expect(results.isEmpty)
    }

    // MARK: - EntryService: Soft Delete Semantics

    @Test("Soft-deleted entry not returned by fetch")
    func softDeletedNotFetched() throws {
        let db = try DatabaseManager.temporary()
        let service = EntryService(pool: db.pool)

        let entry = try service.create(Entry(type: .thought, title: "Delete me"))
        try service.delete(id: entry.id!)

        let fetched = try service.fetch(id: entry.id!)
        #expect(fetched == nil)
    }

    @Test("Soft-deleted entry not returned by list")
    func softDeletedNotListed() throws {
        let db = try DatabaseManager.temporary()
        let service = EntryService(pool: db.pool)

        let entry = try service.create(Entry(type: .thought, title: "Delete me"))
        try service.create(Entry(type: .thought, title: "Keep me"))
        try service.delete(id: entry.id!)

        let all = try service.list()
        #expect(all.count == 1)
        #expect(all.first?.title == "Keep me")
    }

    @Test("List filters by type correctly")
    func listFiltersByType() throws {
        let db = try DatabaseManager.temporary()
        let service = EntryService(pool: db.pool)

        try service.create(Entry(type: .thought, title: "Thought"))
        try service.create(Entry(type: .task, title: "Task"))
        try service.create(Entry(type: .event, title: "Event"))

        let tasks = try service.list(type: .task)
        #expect(tasks.count == 1)
        #expect(tasks.first?.type == .task)
    }

    @Test("List filters by status correctly")
    func listFiltersByStatus() throws {
        let db = try DatabaseManager.temporary()
        let service = EntryService(pool: db.pool)

        try service.create(Entry(type: .task, title: "Active", status: .active))
        try service.create(Entry(type: .task, title: "Done", status: .done))

        let done = try service.list(status: .done)
        #expect(done.count == 1)
        #expect(done.first?.title == "Done")
    }

    // MARK: - EntryService: Status Transitions

    @Test("markDone sets status to done")
    func markDoneSetsStatus() throws {
        let db = try DatabaseManager.temporary()
        let service = EntryService(pool: db.pool)

        let entry = try service.create(Entry(type: .task, title: "Task", status: .active))
        try service.markDone(id: entry.id!)

        let fetched = try service.fetch(id: entry.id!)
        #expect(fetched?.status == .done)
    }

    @Test("archive sets status to archived")
    func archiveSetsStatus() throws {
        let db = try DatabaseManager.temporary()
        let service = EntryService(pool: db.pool)

        let entry = try service.create(Entry(type: .thought, title: "Archive me"))
        try service.archive(id: entry.id!)

        let fetched = try service.fetch(id: entry.id!)
        #expect(fetched?.status == .archived)
    }

    @Test("restore from archived sets status to active")
    func restoreFromArchived() throws {
        let db = try DatabaseManager.temporary()
        let service = EntryService(pool: db.pool)

        let entry = try service.create(Entry(type: .thought, title: "Restore me"))
        try service.archive(id: entry.id!)
        try service.restore(id: entry.id!)

        let fetched = try service.fetch(id: entry.id!)
        #expect(fetched?.status == .active)
    }

    // MARK: - ExpressionContext: Deep Nested Paths

    @Test("Resolve 3-level deep dotted path")
    func deepNestedPath() {
        let context = ExpressionContext(variables: [
            "a": .object([
                "b": .object([
                    "c": .string("deep")
                ])
            ])
        ])
        let result = context.resolve("a.b.c")
        #expect(result == .string("deep"))
    }

    @Test("Resolve path through missing intermediate returns nil")
    func missingIntermediatePath() {
        let context = ExpressionContext(variables: [
            "a": .object(["x": .int(1)])
        ])
        let result = context.resolve("a.b.c")
        #expect(result == nil)
    }

    // MARK: - RulesEngine: Edge Cases

    @Test("Rule with malformed JSON condition is skipped")
    func malformedJsonCondition() throws {
        let db = try DatabaseManager.temporary()
        let engine = RulesEngine(pool: db.pool)

        try db.pool.write { db in
            var rule = Rule(
                category: "behavior",
                name: "bad_json",
                condition: "{ not valid json }}}",
                action: "{\"type\":\"test\"}"
            )
            try rule.insert(db)
        }

        // Should not crash, just skip the rule
        let matches = try engine.evaluate(context: RuleContext(trigger: "test"))
        #expect(matches.isEmpty)
    }

    @Test("Multiple rules match in priority order")
    func multipleRulesMatchInOrder() throws {
        let db = try DatabaseManager.temporary()
        let engine = RulesEngine(pool: db.pool)

        for i in 1...5 {
            try db.pool.write { db in
                var rule = Rule(
                    category: "behavior",
                    name: "rule_\(i)",
                    condition: nil,
                    action: "{\"type\":\"test\"}",
                    priority: i * 10
                )
                try rule.insert(db)
            }
        }

        let matches = try engine.evaluate(context: RuleContext(trigger: "any"))
        #expect(matches.count == 5)
        // Highest priority first
        #expect(matches[0].rule.priority == 50)
        #expect(matches[4].rule.priority == 10)
    }

    // MARK: - SkillCompiler: Edge Cases

    @Test("Skill ID with spaces and special chars is accepted by parser")
    func skillIdWithSpaces() throws {
        let compiler = SkillCompiler()
        let md = """
        ---
        id: my skill with spaces
        name: Test
        ---
        Body
        """
        let source = try compiler.parseSource(md)
        #expect(source.id == "my skill with spaces")
    }

    @Test("Skill with all optional fields populated")
    func skillAllOptionalFields() throws {
        let compiler = SkillCompiler()
        let md = """
        ---
        id: full-skill
        name: Full Skill
        description: A complete skill
        version: 3.5
        icon: star.fill
        color: "#00FF00"
        created_by: brain-self-modifier
        permissions: [calendar, contacts, notifications, location]
        ---

        # Full Skill

        This skill has everything.
        """
        let source = try compiler.parseSource(md)
        #expect(source.id == "full-skill")
        #expect(source.description == "A complete skill")
        #expect(source.version == "3.5")
        #expect(source.icon == "star.fill")
        #expect(source.color == "#00FF00")
        #expect(source.permissions.count == 4)
        #expect(source.markdownBody.contains("# Full Skill"))
    }

    @Test("Validate catches deeply nested unknown primitive")
    func validateDeepNested() {
        let compiler = SkillCompiler()
        let def = SkillDefinition(
            id: "test",
            screens: [
                "main": ScreenNode(
                    type: "stack",
                    children: [
                        ScreenNode(type: "text", properties: ["value": .string("OK")]),
                        ScreenNode(
                            type: "stack",
                            children: [
                                ScreenNode(type: "unknown_deep_widget")
                            ]
                        )
                    ]
                )
            ]
        )
        let errors = compiler.validate(def)
        #expect(!errors.isEmpty)
        #expect(errors.contains { $0.contains("unknown_deep_widget") })
    }

    // MARK: - ActionResult: Structured Errors

    @Test("actionError with details in DEBUG includes details")
    func actionErrorWithDetails() {
        let result = ActionResult.actionError(
            code: "entry.create_failed",
            message: "Could not create entry",
            details: "Constraint violation on title"
        )
        if case .error(let msg) = result {
            #expect(msg.contains("[entry.create_failed]"))
            #expect(msg.contains("Could not create entry"))
            // In DEBUG, details should be included
            #if DEBUG
            #expect(msg.contains("Constraint violation"))
            #endif
        } else {
            Issue.record("Expected .error")
        }
    }

    @Test("actionError without details has clean message")
    func actionErrorWithoutDetails() {
        let result = ActionResult.actionError(
            code: "tag.not_found",
            message: "Tag does not exist"
        )
        if case .error(let msg) = result {
            #expect(msg.contains("[tag.not_found]"))
            #expect(msg.contains("Tag does not exist"))
        } else {
            Issue.record("Expected .error")
        }
    }

    // MARK: - ActionDispatcher: Handler Registration

    @Test("hasHandler returns true for registered handler")
    func hasHandlerTrue() {
        let mock = MockHandler(type: "entry.create")
        let dispatcher = ActionDispatcher(handlers: [mock])
        #expect(dispatcher.hasHandler(for: "entry.create"))
    }

    @Test("hasHandler returns false for unregistered handler")
    func hasHandlerFalse() {
        let dispatcher = ActionDispatcher(handlers: [])
        #expect(!dispatcher.hasHandler(for: "nonexistent"))
    }

    // MARK: - Tag Service: Edge Cases

    @Test("Tag names are unique")
    func tagNamesUnique() throws {
        let db = try DatabaseManager.temporary()
        let tagService = TagService(pool: db.pool)

        try tagService.create(Tag(name: "test-tag"))
        // Second create with same name should throw
        #expect(throws: (any Error).self) {
            try tagService.create(Tag(name: "test-tag"))
        }
    }

    @Test("Hierarchical tag prefix query")
    func hierarchicalTagPrefix() throws {
        let db = try DatabaseManager.temporary()
        let tagService = TagService(pool: db.pool)

        try tagService.create(Tag(name: "project/brain/ios"))
        try tagService.create(Tag(name: "project/brain/api"))
        try tagService.create(Tag(name: "project/other"))
        try tagService.create(Tag(name: "personal"))

        let brainTags = try tagService.tagsUnder(prefix: "project/brain")
        #expect(brainTags.count == 2)
    }

    // MARK: - Link Service: Bidirectional

    @Test("Link is bidirectional")
    func linkBidirectional() throws {
        let db = try DatabaseManager.temporary()
        let entryService = EntryService(pool: db.pool)
        let linkService = LinkService(pool: db.pool)

        let e1 = try entryService.create(Entry(type: .thought, title: "A"))
        let e2 = try entryService.create(Entry(type: .thought, title: "B"))

        try linkService.create(sourceId: e1.id!, targetId: e2.id!)

        let linksFromA = try linkService.links(for: e1.id!)
        let linksFromB = try linkService.links(for: e2.id!)

        #expect(!linksFromA.isEmpty)
        #expect(!linksFromB.isEmpty)
    }

    @Test("Duplicate link is rejected")
    func duplicateLinkRejected() throws {
        let db = try DatabaseManager.temporary()
        let entryService = EntryService(pool: db.pool)
        let linkService = LinkService(pool: db.pool)

        let e1 = try entryService.create(Entry(type: .thought, title: "A"))
        let e2 = try entryService.create(Entry(type: .thought, title: "B"))

        try linkService.create(sourceId: e1.id!, targetId: e2.id!)
        #expect(throws: (any Error).self) {
            try linkService.create(sourceId: e1.id!, targetId: e2.id!)
        }
    }
}
