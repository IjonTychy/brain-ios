import Testing
import Foundation
@testable import BrainCore

// Tests for the extended expression vocabulary: array indexing, boolean logic,
// contains/matches, date math and pipe filters with arguments.
// This vocabulary is documented in ARCHITECTURE.md and used by LLM-generated skills.
@Suite("Expression Parser (Documented Vocabulary)")
struct ExpressionVocabularyTests {

    let parser = ExpressionParser()

    private func ctx(_ vars: [String: ExpressionValue]) -> ExpressionContext {
        ExpressionContext(variables: vars)
    }

    // MARK: - Array indexing

    @Test("Array indexing on top-level variable")
    func arrayIndexTopLevel() {
        let context = ctx(["items": .array([.string("erster"), .string("zweiter")])])
        #expect(parser.evaluate("{{items[0]}}", context: context) == "erster")
        #expect(parser.evaluate("{{items[1]}}", context: context) == "zweiter")
    }

    @Test("Array indexing with dotted path")
    func arrayIndexDottedPath() {
        let context = ctx([
            "items": .array([
                .object(["title": .string("Einkaufen")]),
                .object(["title": .string("Aufraeumen")])
            ])
        ])
        #expect(parser.evaluate("{{items[0].title}}", context: context) == "Einkaufen")
        #expect(parser.evaluate("{{items[1].title}}", context: context) == "Aufraeumen")
    }

    @Test("Nested array indexing")
    func nestedArrayIndex() {
        let context = ctx(["matrix": .array([.array([.int(1), .int(2)]), .array([.int(3), .int(4)])])])
        #expect(parser.evaluate("{{matrix[1][0]}}", context: context) == "3")
    }

    @Test("Out-of-bounds index resolves to empty")
    func outOfBoundsIndex() {
        let context = ctx(["items": .array([.string("a")])])
        #expect(parser.evaluate("{{items[5]}}", context: context) == "")
        #expect(parser.evaluate("{{items[-1]}}", context: context) == "")
    }

    // MARK: - Boolean logic

    @Test("and operator")
    func andOperator() {
        let context = ctx(["a": .bool(true), "b": .bool(false)])
        #expect(parser.evaluateExpression("a and a", context: context) == .bool(true))
        #expect(parser.evaluateExpression("a and b", context: context) == .bool(false))
        #expect(parser.evaluateExpression("a && a", context: context) == .bool(true))
    }

    @Test("or operator")
    func orOperator() {
        let context = ctx(["a": .bool(true), "b": .bool(false)])
        #expect(parser.evaluateExpression("b or a", context: context) == .bool(true))
        #expect(parser.evaluateExpression("b or b", context: context) == .bool(false))
        #expect(parser.evaluateExpression("b || a", context: context) == .bool(true))
    }

    @Test("not prefix")
    func notPrefix() {
        let context = ctx(["done": .bool(false)])
        #expect(parser.evaluateExpression("not done", context: context) == .bool(true))
        #expect(parser.evaluateExpression("not not done", context: context) == .bool(false))
    }

    @Test("Combined boolean logic with comparisons")
    func combinedLogic() {
        let context = ctx(["count": .int(5), "status": .string("open")])
        let result = parser.evaluateExpression("count > 0 and status == \"open\"", context: context)
        #expect(result == .bool(true))

        let result2 = parser.evaluateExpression("count > 10 or status == \"open\"", context: context)
        #expect(result2 == .bool(true))
    }

    @Test("Quoted strings containing operator words are not split")
    func quotedOperatorWords() {
        let context = ctx(["title": .string("Fisch and Chips")])
        let result = parser.evaluateExpression("title == \"Fisch and Chips\"", context: context)
        #expect(result == .bool(true))
    }

    // MARK: - contains / matches

    @Test("contains on arrays")
    func containsArray() {
        let context = ctx(["tags": .array([.string("wichtig"), .string("arbeit")])])
        #expect(parser.evaluateExpression("tags contains \"wichtig\"", context: context) == .bool(true))
        #expect(parser.evaluateExpression("tags contains \"privat\"", context: context) == .bool(false))
    }

    @Test("contains on strings")
    func containsString() {
        let context = ctx(["title": .string("Meeting mit Sarah")])
        #expect(parser.evaluateExpression("title contains \"Sarah\"", context: context) == .bool(true))
        #expect(parser.evaluateExpression("title contains \"Thomas\"", context: context) == .bool(false))
    }

    @Test("matches with regex")
    func matchesRegex() {
        let context = ctx(["email": .string("test@example.com")])
        #expect(parser.evaluateExpression("email matches \"^[^@]+@[^@]+$\"", context: context) == .bool(true))
        #expect(parser.evaluateExpression("email matches \"^admin\"", context: context) == .bool(false))
    }

    @Test("matches with invalid regex returns false")
    func matchesInvalidRegex() {
        let context = ctx(["text": .string("abc")])
        #expect(parser.evaluateExpression("text matches \"[unclosed\"", context: context) == .bool(false))
    }

    // MARK: - Date math

    @Test("now returns DB-format timestamp")
    func nowKeyword() {
        let result = parser.evaluate("{{now}}", context: ctx([:]))
        #expect(ExpressionParser.parseDateString(result) != nil)
    }

    @Test("now + 7d adds seven days")
    func datePlusDuration() {
        let result = parser.evaluate("{{now + 7d}}", context: ctx([:]))
        guard let date = ExpressionParser.parseDateString(result) else {
            Issue.record("Result is not a parseable date: \(result)")
            return
        }
        let expected = Date().addingTimeInterval(7 * 86_400)
        #expect(abs(date.timeIntervalSince(expected)) < 10)
    }

    @Test("date variable minus duration")
    func dateMinusDuration() {
        let context = ctx(["due": .string("2026-06-15 12:00:00")])
        let result = parser.evaluate("{{due - 2h}}", context: context)
        #expect(result == "2026-06-15 10:00:00")
    }

    @Test("Duration literals")
    func durationLiterals() {
        #expect(ExpressionParser.durationLiteralSeconds("30s") == 30)
        #expect(ExpressionParser.durationLiteralSeconds("5m") == 300)
        #expect(ExpressionParser.durationLiteralSeconds("2h") == 7200)
        #expect(ExpressionParser.durationLiteralSeconds("7d") == 604_800)
        #expect(ExpressionParser.durationLiteralSeconds("1w") == 604_800)
        #expect(ExpressionParser.durationLiteralSeconds("abc") == nil)
        #expect(ExpressionParser.durationLiteralSeconds("d") == nil)
    }

    // MARK: - Pipe filters

    @Test("truncate filter")
    func truncateFilter() {
        let context = ctx(["text": .string("Dies ist ein sehr langer Satz der gekuerzt werden soll")])
        let result = parser.evaluate("{{text | truncate(12)}}", context: context)
        #expect(result == "Dies ist ein...")

        let short = parser.evaluate("{{text | truncate(500)}}", context: context)
        #expect(short == "Dies ist ein sehr langer Satz der gekuerzt werden soll")
    }

    @Test("format filter with pattern")
    func formatFilter() {
        // Noon UTC keeps the calendar day stable across common timezones.
        let context = ctx(["date": .string("2026-01-05 12:00:00")])
        let result = parser.evaluate("{{date | format('dd.MM.yyyy')}}", context: context)
        #expect(result.hasSuffix(".01.2026"))
    }

    @Test("relative filter for past dates")
    func relativeFilterPast() {
        let threeHoursAgo = ExpressionParser.dbDateString(from: Date().addingTimeInterval(-3 * 3600 - 90))
        let context = ctx(["date": .string(threeHoursAgo)])
        let result = parser.evaluate("{{date | relative}}", context: context)
        #expect(result == "vor 3 Stunden")
    }

    @Test("relative filter for future dates")
    func relativeFilterFuture() {
        let inTwoDays = ExpressionParser.dbDateString(from: Date().addingTimeInterval(2 * 86_400 + 3600))
        let context = ctx(["date": .string(inTwoDays)])
        let result = parser.evaluate("{{date | relative}}", context: context)
        #expect(result == "in 2 Tagen")
    }

    @Test("relative filter for just now")
    func relativeFilterNow() {
        let context = ctx(["date": .string(ExpressionParser.dbDateString(from: Date()))])
        let result = parser.evaluate("{{date | relative}}", context: context)
        #expect(result == "gerade eben")
    }

    @Test("currency filter Swiss format")
    func currencyFilter() {
        let context = ctx(["price": .double(1234.5), "small": .int(49)])
        #expect(parser.evaluate("{{price | currency('CHF')}}", context: context) == "CHF 1'234.50")
        #expect(parser.evaluate("{{small | currency('CHF')}}", context: context) == "CHF 49.00")
    }

    @Test("currency filter negative and large amounts")
    func currencyEdgeCases() {
        #expect(ExpressionParser.currencyString(amount: -12.3, code: "EUR") == "EUR -12.30")
        #expect(ExpressionParser.currencyString(amount: 1_234_567.891, code: "CHF") == "CHF 1'234'567.89")
    }

    @Test("Pipe inside string literal is not split")
    func pipeInsideQuotes() {
        let result = parser.evaluateExpression("'a|b' | uppercase", context: ctx([:]))
        #expect(result == .string("A|B"))
    }

    @Test("Filter result can be compared")
    func filterThenCompare() {
        let context = ctx(["items": .array([.int(1), .int(2), .int(3)])])
        let result = parser.evaluateExpression("items | count > 2", context: context)
        #expect(result == .bool(true))
    }
}

// Tests for the executeSet template fix and recursive semantic validation.
@Suite("Logic Interpreter (Set Templates & Validation)")
struct LogicInterpreterSetTemplateTests {

    private func makeInterpreter() -> LogicInterpreter {
        LogicInterpreter(dispatcher: ActionDispatcher(handlers: []))
    }

    @Test("Set with mixed template interpolates instead of destroying it")
    func setMixedTemplate() async throws {
        let interpreter = makeInterpreter()
        let step = ActionStep(type: "set", properties: [
            "name": .string("greeting"),
            "value": .string("Hallo {{name}}!")
        ])
        let context = ExpressionContext(variables: ["name": .string("Max")])

        let result = try await interpreter.execute(step: step, context: context)
        guard case .value(.object(let obj)) = result else {
            Issue.record("Expected object result")
            return
        }
        #expect(obj["greeting"] == .string("Hallo Max!"))
    }

    @Test("Set with multiple expressions in one value")
    func setMultipleExpressions() async throws {
        let interpreter = makeInterpreter()
        let step = ActionStep(type: "set", properties: [
            "name": .string("full"),
            "value": .string("{{first}} {{last}}")
        ])
        let context = ExpressionContext(variables: [
            "first": .string("Max"), "last": .string("Testuser")
        ])

        let result = try await interpreter.execute(step: step, context: context)
        guard case .value(.object(let obj)) = result else {
            Issue.record("Expected object result")
            return
        }
        #expect(obj["full"] == .string("Max Testuser"))
    }

    @Test("Set with pure expression keeps typed value")
    func setPureExpressionKeepsType() async throws {
        let interpreter = makeInterpreter()
        let step = ActionStep(type: "set", properties: [
            "name": .string("total"),
            "value": .string("{{count + 1}}")
        ])
        let context = ExpressionContext(variables: ["count": .int(41)])

        let result = try await interpreter.execute(step: step, context: context)
        guard case .value(.object(let obj)) = result else {
            Issue.record("Expected object result")
            return
        }
        #expect(obj["total"] == .int(42))
    }

    @Test("validateSemantics accepts all logic primitives")
    func validateAllLogicPrimitives() {
        let compiler = SkillCompiler()
        let dispatcher = ActionDispatcher(handlers: [])
        let definition = SkillDefinition(
            id: "test",
            screens: [:],
            actions: [
                "run": ActionDefinition(steps: LogicInterpreter.logicStepTypes.map {
                    ActionStep(type: $0, properties: nil)
                })
            ]
        )
        let warnings = compiler.validateSemantics(definition, dispatcher: dispatcher)
        #expect(warnings.isEmpty)
    }

    @Test("validateSemantics recurses into nested steps")
    func validateNestedSteps() {
        let compiler = SkillCompiler()
        let dispatcher = ActionDispatcher(handlers: [])
        let definition = SkillDefinition(
            id: "test",
            screens: [:],
            actions: [
                "run": ActionDefinition(steps: [
                    ActionStep(type: "if", properties: [
                        "condition": .string("true"),
                        "then": .array([
                            .object(["type": .string("entry.explode")])
                        ])
                    ])
                ])
            ]
        )
        let warnings = compiler.validateSemantics(definition, dispatcher: dispatcher)
        #expect(warnings.count == 1)
        #expect(warnings[0].contains("entry.explode"))
    }
}
