import Foundation

// MARK: - Action handler protocol

// Typed error for action failures — replaces bare string errors.
// Convention: handlers MAY throw ActionError, the dispatcher normalizes to ActionResult.
public struct ActionError: Error, LocalizedError, Sendable {
    public let code: String
    public let message: String
    public let details: String?

    public init(code: String, message: String, details: String? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }

    public var errorDescription: String? {
        #if DEBUG
        if let details { return "[\(code)] \(message) — \(details)" }
        #endif
        return "[\(code)] \(message)"
    }
}

// Result of executing an action step.
public enum ActionResult: Sendable {
    case success
    case value(ExpressionValue)
    case error(String)

    // Convenience: create error result from ActionError.
    public static func actionError(code: String, message: String, details: String? = nil) -> ActionResult {
        .error(ActionError(code: code, message: message, details: details).errorDescription ?? message)
    }
}

// Protocol for action handlers. Each Action Primitive (entry.create, haptic, toast, etc.)
// has a handler that executes the action.
// Note: Sendable conformance is NOT required — thread-safety is guaranteed by
// ActionDispatcher (immutable after init) and @MainActor isolation on handlers.
public protocol ActionHandler {
    var type: String { get }
    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult
}

// MARK: - Action dispatcher

// Dispatches action steps to registered handlers.
// Immutable after initialization — all handlers must be registered in init.
// This eliminates data races (no mutable state after construction).
// @unchecked Sendable: Safe because `handlers` dict is `let` (immutable after init)
// and `parser` is a stateless value type. No mutable state exists.
public final class ActionDispatcher: @unchecked Sendable {

    private let handlers: [String: any ActionHandler]
    private let parser = ExpressionParser()

    public init(handlers: [any ActionHandler] = []) {
        var dict: [String: any ActionHandler] = [:]
        for h in handlers {
            dict[h.type] = h
        }
        self.handlers = dict
    }

    // Check if a handler is registered for a type.
    public func hasHandler(for type: String) -> Bool {
        handlers[type] != nil
    }

    // All registered action types.
    public var registeredTypes: [String] {
        Array(handlers.keys).sorted()
    }

    // Execute a single action step.
    public func execute(step: ActionStep, context: ExpressionContext) async throws -> ActionResult {
        guard let handler = handlers[step.type] else {
            return .error("Kein Handler registriert fuer Action-Typ: '\(step.type)'")
        }

        // Resolve expressions in properties before passing to handler
        let resolved = resolveProperties(step.properties, context: context)
        return try await handler.execute(properties: resolved, context: context)
    }

    // Execute an entire action definition (sequence of steps).
    public func execute(action: ActionDefinition, context: ExpressionContext) async throws -> ActionResult {
        var currentContext = context

        for step in action.steps {
            let result = try await execute(step: step, context: currentContext)

            switch result {
            case .error(let msg):
                return .error(msg)
            case .value(let val):
                currentContext.variables["lastResult"] = val
            case .success:
                continue
            }
        }
        return .success
    }

    // MARK: - Expression resolution

    private func resolveProperties(
        _ properties: [String: PropertyValue]?,
        context: ExpressionContext
    ) -> [String: PropertyValue] {
        guard let props = properties else { return [:] }

        var resolved: [String: PropertyValue] = [:]
        for (key, value) in props {
            resolved[key] = resolveValue(value, context: context)
        }
        return resolved
    }

    private func resolveValue(_ value: PropertyValue, context: ExpressionContext) -> PropertyValue {
        switch value {
        case .string(let s) where s.contains("{{"):
            let result = parser.evaluate(s, context: context)
            return .string(result)
        case .array(let arr):
            return .array(arr.map { resolveValue($0, context: context) })
        case .object(let obj):
            var resolved: [String: PropertyValue] = [:]
            for (k, v) in obj { resolved[k] = resolveValue(v, context: context) }
            return .object(resolved)
        default:
            return value
        }
    }
}
