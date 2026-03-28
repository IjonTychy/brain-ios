import Foundation

// Interprets logic primitives (if, forEach, set, sequence, parallel).
// Provides control flow within action workflows.
// Deliberately limited (not Turing-complete) for App Store compliance.
public struct LogicInterpreter: Sendable {

    private let parser = ExpressionParser()
    private let dispatcher: ActionDispatcher

    /// Maximum recursion depth for nested logic steps.
    public static let maxRecursionDepth = 20

    /// Maximum number of iterations in a forEach loop.
    public static let maxForEachIterations = 1000

    /// H7: Maximum number of variables in a single scope.
    public static let maxVariableCount = 1000

    /// Reserved variable names that cannot be used with the 'set' action.
    public static let reservedNames: Set<String> = [
        "system", "context", "result", "input", "output",
        "env", "config", "settings", "admin", "root", "user"
    ]

    public init(dispatcher: ActionDispatcher) {
        self.dispatcher = dispatcher
    }

    // Execute a logic-aware action step. Delegates non-logic steps to the dispatcher.
    public func execute(step: ActionStep, context: ExpressionContext, depth: Int = 0) async throws -> ActionResult {
        guard depth <= Self.maxRecursionDepth else {
            throw LogicInterpreterError.recursionDepthExceeded(depth: depth)
        }

        switch step.type {
        case "if":
            return try await executeIf(step, context: context, depth: depth)
        case "forEach":
            return try await executeForEach(step, context: context, depth: depth)
        case "set":
            return executeSet(step, context: context)
        case "sequence":
            return try await executeSequence(step, context: context, depth: depth)
        case "try":
            return try await executeTry(step, context: context, depth: depth)
        case "delay":
            return try await executeDelay(step, context: context, depth: depth)
        case "map":
            return executeMap(step, context: context)
        case "filter":
            return executeFilter(step, context: context)
        case "parallel":
            return try await executeParallel(step, context: context, depth: depth)
        default:
            // Delegate to action dispatcher for non-logic primitives
            return try await dispatcher.execute(step: step, context: context)
        }
    }

    // Execute a complete action definition through the logic interpreter.
    public func execute(action: ActionDefinition, context: ExpressionContext) async throws -> ActionResult {
        var currentContext = context

        for step in action.steps {
            let result = try await execute(step: step, context: currentContext)

            switch result {
            case .error:
                return result
            case .value(let val):
                // If the value is an object from a 'set' action, merge keys into context
                if case .object(let dict) = val {
                    for (key, value) in dict {
                        currentContext.variables[key] = value
                    }
                }
                currentContext.variables["lastResult"] = val
            case .success:
                continue
            }
        }
        return .success
    }

    // MARK: - Logic primitives

    // if: Evaluate condition, execute "then" or "else" branch.
    // Properties: condition (expression), then (ActionStep array), else (ActionStep array, optional)
    private func executeIf(_ step: ActionStep, context: ExpressionContext, depth: Int) async throws -> ActionResult {
        guard let condExpr = step.properties?["condition"]?.stringValue else {
            return .error("'if' benoetigt eine 'condition'-Eigenschaft")
        }

        let condValue = parser.evaluateExpression(condExpr, context: context)

        if condValue.isTruthy {
            if let thenSteps = decodeSteps(step.properties?["then"]) {
                for s in thenSteps {
                    let result = try await execute(step: s, context: context, depth: depth + 1)
                    if case .error = result { return result }
                }
            }
        } else {
            if let elseSteps = decodeSteps(step.properties?["else"]) {
                for s in elseSteps {
                    let result = try await execute(step: s, context: context, depth: depth + 1)
                    if case .error = result { return result }
                }
            }
        }

        return .success
    }

    // forEach: Iterate over an array, executing steps for each item.
    // Properties: data (expression resolving to array), as (variable name), do (ActionStep array)
    private func executeForEach(_ step: ActionStep, context: ExpressionContext, depth: Int) async throws -> ActionResult {
        guard let dataExpr = step.properties?["data"]?.stringValue,
              let asName = step.properties?["as"]?.stringValue
        else {
            return .error("'forEach' benoetigt 'data'- und 'as'-Eigenschaften")
        }

        let dataValue = parser.evaluateExpression(dataExpr, context: context)
        guard case .array(let items) = dataValue else {
            return .error("'forEach' data muss zu einem Array aufloesen")
        }

        guard let doSteps = decodeSteps(step.properties?["do"]) else {
            return .success
        }

        // Cap iteration count to prevent runaway loops (F-13)
        let cappedItems = items.prefix(Self.maxForEachIterations)

        for (index, item) in cappedItems.enumerated() {
            try Task.checkCancellation()

            var iterContext = context
            iterContext.variables[asName] = item
            iterContext.variables["index"] = .int(index)

            for s in doSteps {
                let result = try await execute(step: s, context: iterContext, depth: depth + 1)
                if case .error = result { return result }
            }
        }

        return .success
    }

    // set: Set a variable in the context.
    // Supports:
    // - name + value
    // - key + value
    // - single bare property pair: { "foo": ... }
    // Returns a .value(.object([name: value])) which the caller merges into context.
    private func executeSet(_ step: ActionStep, context: ExpressionContext) -> ActionResult {
        guard let properties = step.properties else {
            return .error("'set' benoetigt Eigenschaften")
        }

        let assignment: (name: String, rawValue: PropertyValue)?
        if let name = properties["name"]?.stringValue, let value = properties["value"] {
            assignment = (name, value)
        } else if let name = properties["key"]?.stringValue, let value = properties["value"] {
            assignment = (name, value)
        } else {
            let barePairs = properties.filter { key, _ in
                key != "name" && key != "key" && key != "value"
            }
            if barePairs.count == 1, let first = barePairs.first {
                assignment = (first.key, first.value)
            } else {
                assignment = nil
            }
        }

        guard let assignment else {
            return .error("'set' benoetigt 'name'/'key' + 'value' oder genau ein einzelnes Feld")
        }
        let name = assignment.name

        // H7: Check variable count limit
        if context.variables.count >= Self.maxVariableCount {
            return .error("Variablen-Limit ueberschritten: maximal \(Self.maxVariableCount) Variablen")
        }

        // Validate variable name: must be alphanumeric (plus underscore) (F-23)
        let validNamePattern = name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        if name.isEmpty || !validNamePattern {
            return .error("'set' Variablenname muss alphanumerisch sein (plus Unterstrich): '\(name)'")
        }

        // Check reserved names (F-23)
        if Self.reservedNames.contains(name.lowercased()) {
            return .error("'set' kann keinen reservierten Variablennamen verwenden: '\(name)'")
        }

        let resolvedValue: ExpressionValue
        if case .string(let valueExpr) = assignment.rawValue, valueExpr.contains("{{") {
            let exprContent = valueExpr
                .replacingOccurrences(of: "{{", with: "")
                .replacingOccurrences(of: "}}", with: "")
                .trimmingCharacters(in: .whitespaces)
            resolvedValue = parser.evaluateExpression(exprContent, context: context)
        } else {
            resolvedValue = propertyToExpression(assignment.rawValue)
        }

        // Return as object so the caller can merge into context
        return .value(.object([name: resolvedValue]))
    }

    // sequence: Execute steps in order.
    // Properties: steps (ActionStep array)
    private func executeSequence(_ step: ActionStep, context: ExpressionContext, depth: Int) async throws -> ActionResult {
        guard let steps = decodeSteps(step.properties?["steps"]) else {
            return .success
        }

        for s in steps {
            let result = try await execute(step: s, context: context, depth: depth + 1)
            if case .error = result { return result }
        }
        return .success
    }

    // try: Execute steps, catch errors and run fallback.
    // Properties: steps (ActionStep array), catch (ActionStep array)
    private func executeTry(_ step: ActionStep, context: ExpressionContext, depth: Int) async throws -> ActionResult {
        let trySteps = decodeSteps(step.properties?["steps"]) ?? []
        let catchSteps = decodeSteps(step.properties?["catch"])

        for s in trySteps {
            let result = try await execute(step: s, context: context, depth: depth + 1)
            if case .error(let msg) = result {
                // Error occurred — run catch steps if available
                if let catchSteps {
                    var catchContext = context
                    catchContext.variables["error"] = .string(msg)
                    for cs in catchSteps {
                        let _ = try await execute(step: cs, context: catchContext, depth: depth + 1)
                    }
                }
                return .success // Error was handled
            }
        }
        return .success
    }

    // delay: Wait, then execute steps.
    // Properties: ms (milliseconds), then (ActionStep array)
    // Capped at 10 seconds to prevent abuse.
    private func executeDelay(_ step: ActionStep, context: ExpressionContext, depth: Int) async throws -> ActionResult {
        let ms = step.properties?["ms"]?.intValue ?? 500
        let capped = min(max(ms, 0), 10_000) // 0-10s
        try await Task.sleep(for: .milliseconds(capped))

        if let thenSteps = decodeSteps(step.properties?["then"]) {
            for s in thenSteps {
                let result = try await execute(step: s, context: context, depth: depth + 1)
                if case .error = result { return result }
            }
        }
        return .success
    }

    // map: Transform an array. Returns a new array.
    // Properties: data (expression → array), to (expression evaluated per item)
    private func executeMap(_ step: ActionStep, context: ExpressionContext) -> ActionResult {
        guard let dataExpr = step.properties?["data"]?.stringValue,
              let toExpr = step.properties?["to"]?.stringValue
        else {
            return .error("'map' benoetigt 'data'- und 'to'-Eigenschaften")
        }

        let dataValue = parser.evaluateExpression(dataExpr, context: context)
        guard case .array(let items) = dataValue else {
            return .error("'map' data muss zu einem Array aufloesen")
        }

        let mapped: [ExpressionValue] = items.prefix(Self.maxForEachIterations).map { item in
            var itemContext = context
            itemContext.variables["item"] = item
            return parser.evaluateExpression(toExpr, context: itemContext)
        }
        return .value(.array(mapped))
    }

    // filter: Filter an array by condition. Returns a new array.
    // Properties: data (expression → array), where (condition per item)
    private func executeFilter(_ step: ActionStep, context: ExpressionContext) -> ActionResult {
        guard let dataExpr = step.properties?["data"]?.stringValue,
              let whereExpr = step.properties?["where"]?.stringValue
        else {
            return .error("'filter' benoetigt 'data'- und 'where'-Eigenschaften")
        }

        let dataValue = parser.evaluateExpression(dataExpr, context: context)
        guard case .array(let items) = dataValue else {
            return .error("'filter' data muss zu einem Array aufloesen")
        }

        let filtered: [ExpressionValue] = items.prefix(Self.maxForEachIterations).filter { item in
            var itemContext = context
            itemContext.variables["item"] = item
            let result = parser.evaluateExpression(whereExpr, context: itemContext)
            return result.isTruthy
        }
        return .value(.array(filtered))
    }

    // parallel: Execute steps concurrently. Waits for all to complete.
    // Properties: steps (ActionStep array)
    // Errors in any branch don't stop others, but the first error is returned.
    private func executeParallel(_ step: ActionStep, context: ExpressionContext, depth: Int) async throws -> ActionResult {
        guard let steps = decodeSteps(step.properties?["steps"]) else {
            return .success
        }

        let results = try await withThrowingTaskGroup(of: ActionResult.self, returning: [ActionResult].self) { group in
            for s in steps {
                group.addTask {
                    try await self.execute(step: s, context: context, depth: depth + 1)
                }
            }
            var collected: [ActionResult] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }

        // Return first error if any
        if let error = results.first(where: { if case .error = $0 { return true }; return false }) {
            return error
        }
        return .success
    }

    // MARK: - Helpers

    // Decode steps from a PropertyValue (expected to be an encoded array of ActionStep).
    private func decodeSteps(_ value: PropertyValue?) -> [ActionStep]? {
        guard let value else { return nil }

        // If it's already an array of objects, try to decode
        if case .array(let arr) = value {
            return arr.compactMap { item -> ActionStep? in
                guard case .object(let obj) = item,
                      let typeVal = obj["type"],
                      case .string(let type) = typeVal
                else { return nil }

                var properties: [String: PropertyValue]?
                if let propsVal = obj["properties"], case .object(let props) = propsVal {
                    properties = props
                }
                return ActionStep(type: type, properties: properties)
            }
        }
        return nil
    }

    // Convert a PropertyValue to an ExpressionValue.
    private func propertyToExpression(_ value: PropertyValue) -> ExpressionValue {
        switch value {
        case .string(let s): return .string(s)
        case .int(let i): return .int(i)
        case .double(let d): return .double(d)
        case .bool(let b): return .bool(b)
        case .array(let arr): return .array(arr.map { propertyToExpression($0) })
        case .object(let obj):
            var result: [String: ExpressionValue] = [:]
            for (k, v) in obj { result[k] = propertyToExpression(v) }
            return .object(result)
        }
    }
}

// MARK: - Errors

public enum LogicInterpreterError: Error, Sendable {
    case recursionDepthExceeded(depth: Int)
}
