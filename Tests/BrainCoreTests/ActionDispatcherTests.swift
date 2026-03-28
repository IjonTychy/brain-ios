import Testing
import Foundation
@testable import BrainCore

// A simple test handler that records calls.
final class MockHandler: ActionHandler, @unchecked Sendable {
    let type: String
    var callCount = 0
    var lastProperties: [String: PropertyValue] = [:]
    var resultToReturn: ActionResult = .success

    init(type: String) {
        self.type = type
    }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        callCount += 1
        lastProperties = properties
        return resultToReturn
    }
}

@Suite("Action Dispatcher")
struct ActionDispatcherTests {

    @Test("Create dispatcher with handler and execute")
    func createAndExecute() async throws {
        let handler = MockHandler(type: "haptic")
        let dispatcher = ActionDispatcher(handlers: [handler])

        let step = ActionStep(type: "haptic", properties: ["style": .string("success")])
        let result = try await dispatcher.execute(step: step, context: ExpressionContext())

        #expect(handler.callCount == 1)
        #expect(handler.lastProperties["style"]?.stringValue == "success")
        if case .success = result {} else { Issue.record("Expected success") }
    }

    @Test("Unregistered type returns error")
    func unregisteredType() async throws {
        let dispatcher = ActionDispatcher()
        let step = ActionStep(type: "unknown")
        let result = try await dispatcher.execute(step: step, context: ExpressionContext())

        if case .error(let msg) = result {
            #expect(msg.contains("Kein Handler"))
        } else {
            Issue.record("Expected error")
        }
    }

    @Test("Resolves expressions in properties")
    func resolvesExpressions() async throws {
        let handler = MockHandler(type: "toast")
        let dispatcher = ActionDispatcher(handlers: [handler])

        let step = ActionStep(type: "toast", properties: ["message": .string("Hello {{name}}!")])
        let context = ExpressionContext(variables: ["name": .string("Andy")])
        _ = try await dispatcher.execute(step: step, context: context)

        #expect(handler.lastProperties["message"]?.stringValue == "Hello Andy!")
    }

    @Test("Execute action sequence")
    func executeSequence() async throws {
        let handler = MockHandler(type: "haptic")
        let dispatcher = ActionDispatcher(handlers: [handler])

        let action = ActionDefinition(steps: [
            ActionStep(type: "haptic", properties: ["style": .string("light")]),
            ActionStep(type: "haptic", properties: ["style": .string("heavy")]),
            ActionStep(type: "haptic", properties: ["style": .string("success")]),
        ])

        let result = try await dispatcher.execute(action: action, context: ExpressionContext())
        #expect(handler.callCount == 3)
        if case .success = result {} else { Issue.record("Expected success") }
    }

    @Test("Sequence stops on error")
    func sequenceStopsOnError() async throws {
        let failing = MockHandler(type: "fail")
        failing.resultToReturn = .error("boom")
        let ok = MockHandler(type: "ok")
        let dispatcher = ActionDispatcher(handlers: [failing, ok])

        let action = ActionDefinition(steps: [
            ActionStep(type: "fail"),
            ActionStep(type: "ok"),
        ])

        let result = try await dispatcher.execute(action: action, context: ExpressionContext())
        if case .error(let msg) = result {
            #expect(msg == "boom")
        } else {
            Issue.record("Expected error")
        }
        #expect(ok.callCount == 0)
    }

    @Test("Has handler check")
    func hasHandler() {
        let handler = MockHandler(type: "haptic")
        let dispatcher = ActionDispatcher(handlers: [handler])
        #expect(dispatcher.hasHandler(for: "haptic") == true)
        #expect(dispatcher.hasHandler(for: "unknown") == false)
    }

    @Test("Registered types list")
    func registeredTypes() {
        let dispatcher = ActionDispatcher(handlers: [
            MockHandler(type: "haptic"),
            MockHandler(type: "toast"),
            MockHandler(type: "alert"),
        ])
        #expect(dispatcher.registeredTypes == ["alert", "haptic", "toast"])
    }
}
