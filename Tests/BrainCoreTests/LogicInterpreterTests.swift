import Testing
import Foundation
@testable import BrainCore

@Suite("Logic Interpreter")
struct LogicInterpreterTests {

    private func makeInterpreter() -> (LogicInterpreter, ActionDispatcher, MockHandler) {
        let mock = MockHandler(type: "test-action")
        let dispatcher = ActionDispatcher(handlers: [mock])
        let interpreter = LogicInterpreter(dispatcher: dispatcher)
        return (interpreter, dispatcher, mock)
    }

    // MARK: - If/else

    @Test("If true executes then branch")
    func ifTrue() async throws {
        let (interpreter, _, mock) = makeInterpreter()

        let step = ActionStep(type: "if", properties: [
            "condition": .string("count > 0"),
            "then": .array([
                .object(["type": .string("test-action")])
            ])
        ])

        let context = ExpressionContext(variables: ["count": .int(5)])
        _ = try await interpreter.execute(step: step, context: context)

        #expect(mock.callCount == 1)
    }

    @Test("If false executes else branch")
    func ifFalse() async throws {
        let (interpreter, _, mock) = makeInterpreter()

        let step = ActionStep(type: "if", properties: [
            "condition": .string("count > 0"),
            "then": .array([
                .object(["type": .string("should-not-run")])
            ]),
            "else": .array([
                .object(["type": .string("test-action")])
            ])
        ])

        let context = ExpressionContext(variables: ["count": .int(0)])
        _ = try await interpreter.execute(step: step, context: context)

        #expect(mock.callCount == 1)
    }

    @Test("If without condition returns error")
    func ifNoCondition() async throws {
        let (interpreter, _, _) = makeInterpreter()

        let step = ActionStep(type: "if", properties: [:])
        let result = try await interpreter.execute(step: step, context: ExpressionContext())

        if case .error(let msg) = result {
            #expect(msg.contains("condition"))
        } else {
            Issue.record("Expected error")
        }
    }

    // MARK: - ForEach

    @Test("ForEach iterates over array")
    func forEach() async throws {
        let (interpreter, _, mock) = makeInterpreter()

        let step = ActionStep(type: "forEach", properties: [
            "data": .string("items"),
            "as": .string("item"),
            "do": .array([
                .object(["type": .string("test-action")])
            ])
        ])

        let context = ExpressionContext(variables: [
            "items": .array([.string("a"), .string("b"), .string("c")])
        ])
        _ = try await interpreter.execute(step: step, context: context)

        #expect(mock.callCount == 3)
    }

    @Test("ForEach with empty array does nothing")
    func forEachEmpty() async throws {
        let (interpreter, _, mock) = makeInterpreter()

        let step = ActionStep(type: "forEach", properties: [
            "data": .string("items"),
            "as": .string("item"),
            "do": .array([
                .object(["type": .string("test-action")])
            ])
        ])

        let context = ExpressionContext(variables: ["items": .array([])])
        _ = try await interpreter.execute(step: step, context: context)

        #expect(mock.callCount == 0)
    }

    @Test("ForEach missing properties returns error")
    func forEachMissing() async throws {
        let (interpreter, _, _) = makeInterpreter()

        let step = ActionStep(type: "forEach", properties: [:])
        let result = try await interpreter.execute(step: step, context: ExpressionContext())

        if case .error(let msg) = result {
            #expect(msg.contains("data"))
        } else {
            Issue.record("Expected error")
        }
    }

    // MARK: - Set

    @Test("Set with literal value")
    func setLiteral() async throws {
        let (interpreter, _, _) = makeInterpreter()

        let step = ActionStep(type: "set", properties: [
            "name": .string("count"),
            "value": .int(42)
        ])

        let result = try await interpreter.execute(step: step, context: ExpressionContext())
        if case .value(let val) = result, case .object(let obj) = val {
            #expect(obj["count"] == .int(42))
        } else {
            Issue.record("Expected value result with object")
        }
    }

    @Test("Set without name returns error")
    func setNoName() async throws {
        let (interpreter, _, _) = makeInterpreter()

        let step = ActionStep(type: "set", properties: ["value": .int(1)])
        let result = try await interpreter.execute(step: step, context: ExpressionContext())

        if case .error = result {} else {
            Issue.record("Expected error")
        }
    }

    // MARK: - Sequence

    @Test("Sequence executes all steps")
    func sequence() async throws {
        let (interpreter, _, mock) = makeInterpreter()

        let step = ActionStep(type: "sequence", properties: [
            "steps": .array([
                .object(["type": .string("test-action")]),
                .object(["type": .string("test-action")]),
            ])
        ])

        _ = try await interpreter.execute(step: step, context: ExpressionContext())
        #expect(mock.callCount == 2)
    }

    // MARK: - Delegation

    @Test("Non-logic steps delegated to dispatcher")
    func delegation() async throws {
        let (interpreter, _, mock) = makeInterpreter()

        let step = ActionStep(type: "test-action", properties: ["key": .string("value")])
        _ = try await interpreter.execute(step: step, context: ExpressionContext())

        #expect(mock.callCount == 1)
        #expect(mock.lastProperties["key"]?.stringValue == "value")
    }
}
