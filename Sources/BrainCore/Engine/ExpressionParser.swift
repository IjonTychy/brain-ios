import Foundation

// MARK: - Expression evaluation context

// Holds variables and provides lookup for template expressions.
public struct ExpressionContext: Sendable {
    public var variables: [String: ExpressionValue]

    public init(variables: [String: ExpressionValue] = [:]) {
        self.variables = variables
    }

    // Resolve a dotted key path like "user.name" or "items[0].title".
    public func resolve(_ keyPath: String) -> ExpressionValue? {
        let parts = keyPath.split(separator: ".").map(String.init)
        var current: ExpressionValue? = nil

        for (index, part) in parts.enumerated() {
            if index == 0 {
                current = variables[part]
            } else {
                guard case .object(let obj) = current else { return nil }
                current = obj[part]
            }
        }
        return current
    }
}

// MARK: - Expression values

// Runtime values used in template expressions.
public enum ExpressionValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([ExpressionValue])
    case object([String: ExpressionValue])
    case null

    public var stringRepresentation: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .null: return ""
        case .array(let arr): return "[\(arr.map(\.stringRepresentation).joined(separator: ", "))]"
        case .object: return "[Object]"
        }
    }

    public var isTruthy: Bool {
        switch self {
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .double(let d): return d != 0
        case .string(let s): return !s.isEmpty
        case .null: return false
        case .array(let a): return !a.isEmpty
        case .object(let o): return !o.isEmpty
        }
    }
}

// MARK: - Expression parser

// Parses and evaluates template expressions in the {{...}} syntax.
// Supports: variable lookup, dotted paths, comparison operators, pipe filters.
//
// Examples:
//   "{{user.name}}"                → variable lookup
//   "Hello {{user.name}}"          → string interpolation
//   "{{count > 0}}"                → comparison (returns bool)
//   "{{count + 1}}"                → arithmetic
//   "{{date | relative}}"          → pipe filter (future)
//   "{{items | count}}"            → collection pipe
public struct ExpressionParser: Sendable {

    // Cached regex — compiled once, reused on every evaluate() call.
    // NSRegularExpression is thread-safe for matching operations after init.
    // Pattern is hardcoded and always valid — fatalError documents this invariant.
    private static let templateRegex: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(pattern: "\\{\\{(.+?)\\}\\}") else {
            fatalError("Invalid hardcoded regex pattern for template expressions")
        }
        return regex
    }()

    public init() {}

    // Evaluate a template string, replacing all {{...}} expressions.
    // Returns a string with all expressions resolved.
    public func evaluate(_ template: String, context: ExpressionContext) -> String {
        var result = template
        let regex = Self.templateRegex

        let nsString = template as NSString
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: nsString.length))

        // Process matches in reverse order to preserve offsets
        for match in matches.reversed() {
            let exprRange = match.range(at: 1)
            let expression = nsString.substring(with: exprRange).trimmingCharacters(in: .whitespaces)
            let value = evaluateExpression(expression, context: context)
            let fullRange = match.range(at: 0)
            result = (result as NSString).replacingCharacters(in: fullRange, with: value.stringRepresentation)
        }

        return result
    }

    // Evaluate a single expression (without the {{ }} delimiters).
    // Returns an ExpressionValue for use in conditions and bindings.
    public func evaluateExpression(_ expr: String, context: ExpressionContext) -> ExpressionValue {
        evaluateExpression(expr, context: context, depth: 0)
    }

    private func evaluateExpression(_ expr: String, context: ExpressionContext, depth: Int) -> ExpressionValue {
        // Prevent stack overflow from deeply nested expressions
        guard depth < 20 else { return .null }

        let trimmed = expr.trimmingCharacters(in: .whitespaces)

        // Check for pipe operator (e.g. "items | count")
        if let pipeIndex = trimmed.lastIndex(of: "|") {
            let left = String(trimmed[trimmed.startIndex..<pipeIndex]).trimmingCharacters(in: .whitespaces)
            let filter = String(trimmed[trimmed.index(after: pipeIndex)...]).trimmingCharacters(in: .whitespaces)
            let value = evaluateExpression(left, context: context, depth: depth + 1)
            return applyFilter(filter, to: value)
        }

        // Check for comparison operators
        for op in ["==", "!=", ">=", "<=", ">", "<"] {
            if let range = trimmed.range(of: " \(op) ") {
                let left = evaluateExpression(String(trimmed[trimmed.startIndex..<range.lowerBound]), context: context, depth: depth + 1)
                let right = evaluateExpression(String(trimmed[range.upperBound...]), context: context, depth: depth + 1)
                return .bool(compare(left, op, right))
            }
        }

        // Check for parenthesized expression (strip outer parens and re-evaluate)
        if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
            // Verify the parens actually match (not e.g. "(a) + (b)")
            var depth2 = 0
            var matched = true
            for (i, ch) in trimmed.enumerated() {
                if ch == "(" { depth2 += 1 }
                else if ch == ")" { depth2 -= 1 }
                if depth2 == 0 && i < trimmed.count - 1 {
                    matched = false
                    break
                }
            }
            if matched {
                let inner = String(trimmed.dropFirst().dropLast())
                return evaluateExpression(inner, context: context, depth: depth + 1)
            }
        }

        // Check for arithmetic operators with correct precedence.
        // Lowest precedence first: scan for last + or - (outside parens),
        // then last * or / (outside parens). Splitting at the last occurrence
        // ensures left-to-right associativity.
        if let (op, range) = findLastOperator(in: trimmed, operators: ["+", "-"]) {
            let left = evaluateExpression(String(trimmed[trimmed.startIndex..<range.lowerBound]), context: context, depth: depth + 1)
            let right = evaluateExpression(String(trimmed[range.upperBound...]), context: context, depth: depth + 1)
            return arithmetic(left, op, right)
        }
        if let (op, range) = findLastOperator(in: trimmed, operators: ["*", "/"]) {
            let left = evaluateExpression(String(trimmed[trimmed.startIndex..<range.lowerBound]), context: context, depth: depth + 1)
            let right = evaluateExpression(String(trimmed[range.upperBound...]), context: context, depth: depth + 1)
            return arithmetic(left, op, right)
        }

        // Boolean literals
        if trimmed == "true" { return .bool(true) }
        if trimmed == "false" { return .bool(false) }

        // Numeric literal
        if let intVal = Int(trimmed) { return .int(intVal) }
        if let dblVal = Double(trimmed) { return .double(dblVal) }

        // String literal (quoted)
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
            let inner = String(trimmed.dropFirst().dropLast())
            return .string(inner)
        }
        if trimmed.hasPrefix("'") && trimmed.hasSuffix("'") {
            let inner = String(trimmed.dropFirst().dropLast())
            return .string(inner)
        }

        // Variable lookup (dotted path)
        if let value = context.resolve(trimmed) {
            return value
        }

        // Unresolved → null
        return .null
    }

    // MARK: - Comparison

    private func compare(_ left: ExpressionValue, _ op: String, _ right: ExpressionValue) -> Bool {
        switch op {
        case "==": return left == right
        case "!=": return left != right
        case ">": return numericCompare(left, right) { $0 > $1 }
        case "<": return numericCompare(left, right) { $0 < $1 }
        case ">=": return numericCompare(left, right) { $0 >= $1 }
        case "<=": return numericCompare(left, right) { $0 <= $1 }
        default: return false
        }
    }

    private func numericCompare(_ left: ExpressionValue, _ right: ExpressionValue, _ op: (Double, Double) -> Bool) -> Bool {
        guard let l = toDouble(left), let r = toDouble(right) else { return false }
        return op(l, r)
    }

    // MARK: - Arithmetic

    private func arithmetic(_ left: ExpressionValue, _ op: String, _ right: ExpressionValue) -> ExpressionValue {
        // String concatenation with +
        if op == "+", case .string(let ls) = left, case .string(let rs) = right {
            return .string(ls + rs)
        }

        guard let l = toDouble(left), let r = toDouble(right) else { return .null }
        let result: Double
        switch op {
        case "+": result = l + r
        case "-": result = l - r
        case "*": result = l * r
        case "/": result = r != 0 ? l / r : 0
        default: return .null
        }

        // Return int if both inputs were int and result is whole
        if case .int = left, case .int = right, result == result.rounded() {
            return .int(Int(result))
        }
        return .double(result)
    }

    // MARK: - Pipe filters

    private func applyFilter(_ filter: String, to value: ExpressionValue) -> ExpressionValue {
        switch filter {
        case "count":
            if case .array(let arr) = value { return .int(arr.count) }
            if case .string(let s) = value { return .int(s.count) }
            return .int(0)
        case "uppercase":
            if case .string(let s) = value { return .string(s.uppercased()) }
            return value
        case "lowercase":
            if case .string(let s) = value { return .string(s.lowercased()) }
            return value
        case "not":
            return .bool(!value.isTruthy)
        case "length":
            return applyFilter("count", to: value)
        default:
            return value
        }
    }

    // MARK: - Operator precedence helper

    // Find the last occurrence of any of the given operators (with surrounding spaces)
    // that is NOT inside parentheses. Returns the operator character and the range
    // covering " op " so callers can split left/right.
    private func findLastOperator(in expr: String, operators: [String]) -> (String, Range<String.Index>)? {
        var bestIndex: String.Index? = nil
        var bestOp: String? = nil
        var bestRange: Range<String.Index>? = nil

        for op in operators {
            let needle = " \(op) "
            var searchRange = expr.startIndex..<expr.endIndex

            while let range = expr.range(of: needle, range: searchRange) {
                // Check that this occurrence is not inside parentheses
                var parenDepth = 0
                var insideParens = false
                for i in expr.indices {
                    if i == range.lowerBound {
                        if parenDepth > 0 { insideParens = true }
                        break
                    }
                    if expr[i] == "(" { parenDepth += 1 }
                    else if expr[i] == ")" { parenDepth -= 1 }
                }

                if !insideParens {
                    // Keep the last (rightmost) match across all operators
                    if bestIndex == nil || range.lowerBound > bestIndex! {
                        bestIndex = range.lowerBound
                        bestOp = op
                        bestRange = range
                    }
                }

                // Continue searching after this match
                searchRange = range.upperBound..<expr.endIndex
            }
        }

        if let op = bestOp, let range = bestRange {
            return (op, range)
        }
        return nil
    }

    // MARK: - Helpers

    private func toDouble(_ value: ExpressionValue) -> Double? {
        switch value {
        case .int(let i): return Double(i)
        case .double(let d): return d
        case .string(let s): return Double(s)
        default: return nil
        }
    }
}
