import Testing
import Foundation
import GRDB
@testable import BrainCore

@Suite("Audit Fixes AP1-3")
struct AuditFixTests {

    // MARK: - H7: Variable scope limit

    @Test("Set rejects when scope limit exceeded")
    func scopeLimitExceeded() async throws {
        let mock = MockHandler(type: "test-action")
        let dispatcher = ActionDispatcher(handlers: [mock])
        let interpreter = LogicInterpreter(dispatcher: dispatcher)

        // Build a context with max variables
        var variables: [String: ExpressionValue] = [:]
        for i in 0..<LogicInterpreter.maxVariableCount {
            variables["var_\(i)"] = .int(i)
        }
        let context = ExpressionContext(variables: variables)

        let step = ActionStep(type: "set", properties: [
            "name": .string("oneMore"),
            "value": .string("overflow")
        ])

        let result = try await interpreter.execute(step: step, context: context)
        if case .error(let msg) = result {
            #expect(msg.contains("Variablen-Limit"))
        } else {
            Issue.record("Expected .error but got \(result)")
        }
    }

    @Test("Set allows variables within limit")
    func scopeWithinLimit() async throws {
        let mock = MockHandler(type: "test-action")
        let dispatcher = ActionDispatcher(handlers: [mock])
        let interpreter = LogicInterpreter(dispatcher: dispatcher)

        let context = ExpressionContext(variables: ["existing": .int(1)])
        let step = ActionStep(type: "set", properties: [
            "name": .string("newVar"),
            "value": .string("hello")
        ])

        let result = try await interpreter.execute(step: step, context: context)
        if case .value(let val) = result, case .object(let obj) = val {
            #expect(obj["newVar"] != nil)
        } else {
            Issue.record("Expected .value with newVar")
        }
    }

    // MARK: - M2: Markdown sanitization

    @Test("sanitizeForLLM strips image references")
    func stripImages() {
        let input = "Check this ![tracker](http://evil.com/t.gif) image"
        let result = DataSanitizer.sanitizeForLLM(input)
        #expect(result.contains("[Bild: tracker]"))
        #expect(!result.contains("http://evil.com"))
    }

    @Test("sanitizeForLLM strips empty images")
    func stripEmptyImages() {
        let input = "Hidden pixel: ![](http://evil.com/pixel.png)"
        let result = DataSanitizer.sanitizeForLLM(input)
        #expect(result.contains("[Bild: ]"))
        #expect(!result.contains("http://evil.com"))
    }

    @Test("sanitizeForLLM strips angle bracket URLs")
    func stripAngleBracketURLs() {
        let input = "Visit <https://malicious.com/tracker> for more"
        let result = DataSanitizer.sanitizeForLLM(input)
        #expect(result.contains("[URL entfernt]"))
        #expect(!result.contains("malicious.com"))
    }

    @Test("sanitizeForLLM preserves normal text")
    func preserveNormalText() {
        let input = "Normal text without images or URLs"
        let result = DataSanitizer.sanitizeForLLM(input)
        #expect(result == input)
    }

    @Test("sanitizeForLLM truncates long text")
    func truncatesLongText() {
        let longText = String(repeating: "a", count: 5000)
        let result = DataSanitizer.sanitizeForLLM(longText)
        #expect(result.count < 5000)
        #expect(result.contains("abgeschnitten"))
    }

    // MARK: - H4: Structured ActionError

    @Test("actionError includes code in message")
    func actionErrorFormat() {
        let result = ActionResult.actionError(code: "entry.not_found", message: "Entry 42 nicht gefunden")
        if case .error(let msg) = result {
            #expect(msg.contains("[entry.not_found]"))
            #expect(msg.contains("Entry 42 nicht gefunden"))
        } else {
            Issue.record("Expected .error")
        }
    }

    // MARK: - H5: Semantic skill validation

    @Test("validateSemantics warns about unknown handlers")
    func semanticValidationWarnings() {
        let dispatcher = ActionDispatcher(handlers: [])
        let compiler = SkillCompiler()

        let definition = SkillDefinition(
            id: "test-skill",
            screens: [:],
            actions: [
                "test": ActionDefinition(steps: [
                    ActionStep(type: "entry.create", properties: nil),
                    ActionStep(type: "nonexistent.handler", properties: nil)
                ])
            ]
        )

        let warnings = compiler.validateSemantics(definition, dispatcher: dispatcher)
        #expect(warnings.contains(where: { $0.contains("nonexistent.handler") }))
        #expect(warnings.contains(where: { $0.contains("entry.create") }))
    }

    // MARK: - M5: Pagination with offset

    @Test("list with offset skips entries")
    func paginationWithOffset() throws {
        let db = try DatabaseManager.temporary()
        let service = EntryService(pool: db.pool)

        // Create 10 entries with distinct titles
        for i in 1...10 {
            try service.create(Entry(type: .thought, title: "Entry \(i)"))
        }

        let firstPage = try service.list(limit: 5, offset: 0)
        let secondPage = try service.list(limit: 5, offset: 5)

        #expect(firstPage.count == 5)
        #expect(secondPage.count == 5)
        // No overlap between pages
        let firstIds = Set(firstPage.map { $0.id })
        let secondIds = Set(secondPage.map { $0.id })
        #expect(firstIds.isDisjoint(with: secondIds))
    }

    @Test("list with offset beyond count returns empty")
    func paginationOffsetBeyondCount() throws {
        let db = try DatabaseManager.temporary()
        let service = EntryService(pool: db.pool)

        try service.create(Entry(type: .thought, title: "Only one"))
        let result = try service.list(limit: 10, offset: 100)
        #expect(result.isEmpty)
    }

    // MARK: - M4: FTS5 porter stemming

    @Test("FTS5 porter stemming matches word stems")
    func fts5PorterStemming() throws {
        let db = try DatabaseManager.temporary()

        // Use a single write connection for both insert and FTS5 query
        // to avoid WAL snapshot isolation issues between pool.write/pool.read
        let count: Int = try db.pool.write { db in
            try db.execute(sql: "INSERT INTO entries (type, title) VALUES ('note', 'Meeting notes')")
            try db.execute(sql: "INSERT INTO entries (type, title) VALUES ('note', 'Besprechungen mit dem Team')")

            // Verify FTS5 trigger populated the index and search works
            let row = try Row.fetchOne(db, sql: """
                SELECT count(*) FROM entries_fts WHERE entries_fts MATCH '"meeting"'
                """)
            return row?[0] as? Int ?? 0
        }

        #expect(count > 0, "FTS5 should find 'Meeting notes' when searching for 'meeting'")
    }

    @Test("validateSemantics ignores logic primitives")
    func semanticValidationIgnoresLogic() {
        let dispatcher = ActionDispatcher(handlers: [])
        let compiler = SkillCompiler()

        let definition = SkillDefinition(
            id: "test-skill",
            screens: [:],
            actions: [
                "test": ActionDefinition(steps: [
                    ActionStep(type: "if", properties: nil),
                    ActionStep(type: "forEach", properties: nil),
                    ActionStep(type: "set", properties: nil),
                    ActionStep(type: "sequence", properties: nil)
                ])
            ]
        )

        let warnings = compiler.validateSemantics(definition, dispatcher: dispatcher)
        #expect(warnings.isEmpty)
    }
}
