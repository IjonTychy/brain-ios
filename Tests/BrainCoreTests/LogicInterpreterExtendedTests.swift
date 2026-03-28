import Testing
import Foundation
@testable import BrainCore

// Erweiterte Tests fuer LogicInterpreter - set-Fix und Kontext-Propagation
@Suite("Logic Interpreter Erweitert")
struct LogicInterpreterExtendedTests {

    private func makeInterpreter() -> (LogicInterpreter, MockHandler) {
        let mock = MockHandler(type: "test-action")
        let dispatcher = ActionDispatcher(handlers: [mock])
        let interpreter = LogicInterpreter(dispatcher: dispatcher)
        return (interpreter, mock)
    }

    // MARK: - set mit Expression-Wert

    @Test("set mit Expression-Wert wertet Ausdruck aus")
    func setWithExpression() async throws {
        let (interpreter, _) = makeInterpreter()
        let step = ActionStep(type: "set", properties: [
            "name": .string("doubled"),
            "value": .string("{{count * 2}}")
        ])
        let context = ExpressionContext(variables: ["count": .int(5)])
        let result = try await interpreter.execute(step: step, context: context)
        if case .value(let val) = result, case .object(let obj) = val {
            #expect(obj["doubled"] == .int(10))
        } else {
            Issue.record("Erwartete .value(.object([doubled: .int(10)]))")
        }
    }

    @Test("set mit String-Literal")
    func setWithStringLiteral() async throws {
        let (interpreter, _) = makeInterpreter()
        let step = ActionStep(type: "set", properties: [
            "name": .string("greeting"),
            "value": .string("Hallo")
        ])
        let result = try await interpreter.execute(step: step, context: ExpressionContext())
        if case .value(let val) = result, case .object(let obj) = val {
            #expect(obj["greeting"] == .string("Hallo"))
        } else {
            Issue.record("Erwartete .value(.object([greeting: .string(Hallo)]))")
        }
    }

    @Test("set mit bool Literal")
    func setWithBoolLiteral() async throws {
        let (interpreter, _) = makeInterpreter()
        let step = ActionStep(type: "set", properties: [
            "name": .string("flag"),
            "value": .bool(true)
        ])
        let result = try await interpreter.execute(step: step, context: ExpressionContext())
        if case .value(let val) = result, case .object(let obj) = val {
            #expect(obj["flag"] == .bool(true))
        } else {
            Issue.record("Erwartete .bool(true)")
        }
    }

    @Test("set mit double Literal")
    func setWithDoubleLiteral() async throws {
        let (interpreter, _) = makeInterpreter()
        let step = ActionStep(type: "set", properties: [
            "name": .string("pi"),
            "value": .double(3.14)
        ])
        let result = try await interpreter.execute(step: step, context: ExpressionContext())
        if case .value(let val) = result, case .object(let obj) = val {
            #expect(obj["pi"] == .double(3.14))
        } else {
            Issue.record("Erwartete .double(3.14)")
        }
    }

    @Test("set ohne value Property gibt Fehler zurueck")
    func setWithoutValue() async throws {
        let (interpreter, _) = makeInterpreter()
        let step = ActionStep(type: "set", properties: ["name": .string("x")])
        let result = try await interpreter.execute(step: step, context: ExpressionContext())
        if case .error(let msg) = result {
            #expect(msg.contains("value"))
        } else {
            Issue.record("Erwartete Fehler wegen fehlendem value")
        }
    }

    // MARK: - Kontext-Propagation nach set

    @Test("Variable nach set in nachfolgenden Steps verfuegbar")
    func setVariableAvailableInSubsequentSteps() async throws {
        let mock = MockHandler(type: "test-action")
        let dispatcher = ActionDispatcher(handlers: [mock])
        let interpreter = LogicInterpreter(dispatcher: dispatcher)
        let action = ActionDefinition(
            steps: [
                ActionStep(type: "set", properties: [
                    "name": .string("myVar"),
                    "value": .int(42)
                ]),
                ActionStep(type: "if", properties: [
                    "condition": .string("myVar > 10"),
                    "then": .array([
                        .object(["type": .string("test-action")])
                    ])
                ])
            ]
        )
        _ = try await interpreter.execute(action: action, context: ExpressionContext())
        #expect(mock.callCount == 1)
    }

    @Test("set ueberschreibt bestehende Variable")
    func setOverwritesExistingVariable() async throws {
        let mock = MockHandler(type: "test-action")
        let dispatcher = ActionDispatcher(handlers: [mock])
        let interpreter = LogicInterpreter(dispatcher: dispatcher)
        let action = ActionDefinition(
            steps: [
                ActionStep(type: "set", properties: ["name": .string("flag"), "value": .bool(false)]),
                ActionStep(type: "set", properties: ["name": .string("flag"), "value": .bool(true)]),
                ActionStep(type: "if", properties: [
                    "condition": .string("flag"),
                    "then": .array([.object(["type": .string("test-action")])])
                ])
            ]
        )
        _ = try await interpreter.execute(action: action, context: ExpressionContext())
        #expect(mock.callCount == 1)
    }

    @Test("set mit Expression wertet aktuellen Kontext aus")
    func setEvaluatesCurrentContext() async throws {
        let mock = MockHandler(type: "test-action")
        let dispatcher = ActionDispatcher(handlers: [mock])
        let interpreter = LogicInterpreter(dispatcher: dispatcher)
        let action = ActionDefinition(
            steps: [
                ActionStep(type: "set", properties: ["name": .string("counter"), "value": .int(0)]),
                ActionStep(type: "set", properties: [
                    "name": .string("counter"),
                    "value": .string("{{counter + 1}}")
                ]),
                ActionStep(type: "if", properties: [
                    "condition": .string("counter > 0"),
                    "then": .array([.object(["type": .string("test-action")])])
                ])
            ]
        )
        _ = try await interpreter.execute(action: action, context: ExpressionContext())
        #expect(mock.callCount == 1)
    }

    @Test("Anfangs-Kontext-Variablen sind in set-Expression verfuegbar")
    func initialContextVariablesAvailableInSet() async throws {
        let (interpreter, _) = makeInterpreter()
        let step = ActionStep(type: "set", properties: [
            "name": .string("computed"),
            "value": .string("{{base * factor}}")
        ])
        let context = ExpressionContext(variables: ["base": .int(6), "factor": .int(7)])
        let actionResult = try await interpreter.execute(step: step, context: context)
        if case .value(let val) = actionResult, case .object(let obj) = val {
            #expect(obj["computed"] == .int(42))
        } else {
            Issue.record("Erwartete .int(42)")
        }
    }

    // MARK: - forEach Randfaelle

    @Test("forEach iteriert korrekt mit 3 Elementen")
    func forEachIteratesCorrectly() async throws {
        let (interpreter, mock) = makeInterpreter()
        let step = ActionStep(type: "forEach", properties: [
            "data": .string("items"),
            "as": .string("item"),
            "do": .array([.object(["type": .string("test-action")])])
        ])
        let context = ExpressionContext(variables: [
            "items": .array([.string("x"), .string("y"), .string("z")])
        ])
        _ = try await interpreter.execute(step: step, context: context)
        #expect(mock.callCount == 3)
    }

    @Test("forEach mit nicht-Array gibt Fehler zurueck")
    func forEachWithNonArray() async throws {
        let (interpreter, _) = makeInterpreter()
        let step = ActionStep(type: "forEach", properties: [
            "data": .string("scalar"),
            "as": .string("item"),
            "do": .array([.object(["type": .string("test-action")])])
        ])
        let context = ExpressionContext(variables: ["scalar": .int(42)])
        let result = try await interpreter.execute(step: step, context: context)
        if case .error = result {} else {
            Issue.record("Erwartete Fehler weil data kein Array ist")
        }
    }

    // MARK: - Fehler bricht Action-Ausfuehrung ab

    @Test("Fehler in Schritt bricht nachfolgende Schritte ab")
    func errorStopsExecution() async throws {
        let mock = MockHandler(type: "test-action")
        let dispatcher = ActionDispatcher(handlers: [mock])
        let interpreter = LogicInterpreter(dispatcher: dispatcher)
        let action = ActionDefinition(
            steps: [
                ActionStep(type: "unknown-will-error", properties: nil),
                ActionStep(type: "test-action", properties: nil)
            ]
        )
        let result = try await interpreter.execute(action: action, context: ExpressionContext())
        if case .error = result {} else {
            Issue.record("Erwartete Fehler durch unbekannten Action-Typ")
        }
        #expect(mock.callCount == 0)
    }

    @Test("if ohne condition gibt Fehler zurueck")
    func ifMissingCondition() async throws {
        let (interpreter, _) = makeInterpreter()
        let step = ActionStep(type: "if", properties: [:])
        let result = try await interpreter.execute(step: step, context: ExpressionContext())
        if case .error(let msg) = result {
            #expect(msg.contains("condition"))
        } else {
            Issue.record("Erwartete Fehler")
        }
    }
}
