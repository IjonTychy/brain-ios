import Foundation

// MARK: - Expression evaluation context

// Holds variables and provides lookup for template expressions.
public struct ExpressionContext: Sendable {
    public var variables: [String: ExpressionValue]

    public init(variables: [String: ExpressionValue] = [:]) {
        self.variables = variables
    }

    // Resolve a dotted key path like "user.name" or "items[0].title".
    // Array indexing is supported on any segment: "a[0].b[1][2].c".
    public func resolve(_ keyPath: String) -> ExpressionValue? {
        let parts = keyPath.split(separator: ".").map(String.init)
        guard !parts.isEmpty else { return nil }
        var current: ExpressionValue? = nil

        for (index, part) in parts.enumerated() {
            let (name, indices) = Self.parseIndexedSegment(part)
            guard let name else { return nil }

            if index == 0 {
                current = variables[name]
            } else {
                guard case .object(let obj) = current else { return nil }
                current = obj[name]
            }

            for idx in indices {
                guard case .array(let arr) = current, idx >= 0, idx < arr.count else { return nil }
                current = arr[idx]
            }
        }
        return current
    }

    // Split a path segment like "items[0][1]" into its base name and index list.
    // Returns nil name for malformed segments (e.g. unbalanced brackets).
    private static func parseIndexedSegment(_ segment: String) -> (String?, [Int]) {
        guard let bracket = segment.firstIndex(of: "[") else { return (segment, []) }
        let name = String(segment[..<bracket])
        guard !name.isEmpty else { return (nil, []) }

        var indices: [Int] = []
        var rest = segment[bracket...]
        while rest.hasPrefix("[") {
            guard let close = rest.firstIndex(of: "]"),
                  let idx = Int(rest[rest.index(after: rest.startIndex)..<close])
            else { return (nil, []) }
            indices.append(idx)
            rest = rest[rest.index(after: close)...]
        }
        guard rest.isEmpty else { return (nil, []) }
        return (name, indices)
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
        case .object(let obj):
            // Internal duration values render as their second count
            if case .int(let s)? = obj[ExpressionParser.durationKey], obj.count == 1 {
                return String(s)
            }
            return "[Object]"
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
//
// Supported vocabulary (keep ARCHITECTURE.md and the skill-creator prompt in sync):
//   "{{user.name}}"                 → variable lookup (dotted paths)
//   "{{items[0].title}}"            → array indexing
//   "Hello {{user.name}}"           → string interpolation
//   "{{count > 0}}"                 → comparison (== != >= <= > <)
//   "{{count + 1}}"                 → arithmetic (+ - * /)
//   "{{a and b}}", "{{a or b}}"     → boolean logic (aliases: && ||)
//   "{{not done}}"                  → negation
//   "{{tags contains \"x\"}}"       → array/string membership
//   "{{title matches \"^A.*\"}}"    → regex match
//   "{{now}}"                       → current timestamp (DB format, UTC)
//   "{{now + 7d}}"                  → date math (durations: 30s 5m 2h 7d 1w)
//   "{{items | count}}"             → pipe filters:
//       count/length, uppercase, lowercase, not,
//       truncate(80), relative, format('dd.MM.yyyy'), short, currency('CHF')
public struct ExpressionParser: Sendable {

    // Internal marker key for duration values produced by literals like "7d".
    public static let durationKey = "__durationSeconds"

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

        // Boolean OR (loosest binding), then AND
        if let (_, range) = findLastOperator(in: trimmed, operators: ["or", "||"]) {
            let left = evaluateExpression(String(trimmed[trimmed.startIndex..<range.lowerBound]), context: context, depth: depth + 1)
            if left.isTruthy { return .bool(true) }
            let right = evaluateExpression(String(trimmed[range.upperBound...]), context: context, depth: depth + 1)
            return .bool(right.isTruthy)
        }
        if let (_, range) = findLastOperator(in: trimmed, operators: ["and", "&&"]) {
            let left = evaluateExpression(String(trimmed[trimmed.startIndex..<range.lowerBound]), context: context, depth: depth + 1)
            if !left.isTruthy { return .bool(false) }
            let right = evaluateExpression(String(trimmed[range.upperBound...]), context: context, depth: depth + 1)
            return .bool(right.isTruthy)
        }

        // Prefix negation: "not <expr>"
        if trimmed.hasPrefix("not ") {
            let inner = String(trimmed.dropFirst(4))
            return .bool(!evaluateExpression(inner, context: context, depth: depth + 1).isTruthy)
        }

        // Comparison operators (quote/paren aware, rightmost match → left associativity)
        if let (op, range) = findLastOperator(in: trimmed, operators: ["==", "!=", ">=", "<=", ">", "<"]) {
            let left = evaluateExpression(String(trimmed[trimmed.startIndex..<range.lowerBound]), context: context, depth: depth + 1)
            let right = evaluateExpression(String(trimmed[range.upperBound...]), context: context, depth: depth + 1)
            return .bool(compare(left, op, right))
        }

        // Membership and regex operators
        if let (_, range) = findLastOperator(in: trimmed, operators: ["contains"]) {
            let left = evaluateExpression(String(trimmed[trimmed.startIndex..<range.lowerBound]), context: context, depth: depth + 1)
            let right = evaluateExpression(String(trimmed[range.upperBound...]), context: context, depth: depth + 1)
            return .bool(contains(left, right))
        }
        if let (_, range) = findLastOperator(in: trimmed, operators: ["matches"]) {
            let left = evaluateExpression(String(trimmed[trimmed.startIndex..<range.lowerBound]), context: context, depth: depth + 1)
            let right = evaluateExpression(String(trimmed[range.upperBound...]), context: context, depth: depth + 1)
            return .bool(matches(left, right))
        }

        // Pipe filters (e.g. "items | count", "date | format('dd.MM.yyyy')")
        if let pipeIndex = findLastPipe(in: trimmed) {
            let left = String(trimmed[trimmed.startIndex..<pipeIndex]).trimmingCharacters(in: .whitespaces)
            let filter = String(trimmed[trimmed.index(after: pipeIndex)...]).trimmingCharacters(in: .whitespaces)
            let value = evaluateExpression(left, context: context, depth: depth + 1)
            return applyFilter(filter, to: value)
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

        // Duration literal (30s, 5m, 2h, 7d, 1w) for date math
        if let seconds = Self.durationLiteralSeconds(trimmed) {
            return .object([Self.durationKey: .int(seconds)])
        }

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

        // Built-in "now" keyword (only when not shadowed by a variable)
        if trimmed == "now" {
            return .string(Self.dbDateString(from: Date()))
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

    // MARK: - Membership & regex

    // "haystack contains needle" — arrays check element equality,
    // strings check substring, objects check key presence.
    private func contains(_ haystack: ExpressionValue, _ needle: ExpressionValue) -> Bool {
        switch haystack {
        case .array(let arr):
            return arr.contains(needle)
        case .string(let s):
            return s.contains(needle.stringRepresentation)
        case .object(let obj):
            if case .string(let key) = needle { return obj[key] != nil }
            return false
        default:
            return false
        }
    }

    // "text matches pattern" — regex search anywhere in the string.
    private func matches(_ value: ExpressionValue, _ pattern: ExpressionValue) -> Bool {
        guard case .string(let text) = value, case .string(let regexPattern) = pattern,
              let regex = try? NSRegularExpression(pattern: regexPattern)
        else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    // MARK: - Arithmetic

    private func arithmetic(_ left: ExpressionValue, _ op: String, _ right: ExpressionValue) -> ExpressionValue {
        // String concatenation with +
        if op == "+", case .string(let ls) = left, case .string(let rs) = right {
            return .string(ls + rs)
        }

        // Date math: date ± duration → date, duration ± duration → duration
        let leftDuration = durationSeconds(of: left)
        let rightDuration = durationSeconds(of: right)
        if let rightDuration {
            if case .string(let ls) = left, let date = Self.parseDateString(ls) {
                switch op {
                case "+": return .string(Self.dbDateString(from: date.addingTimeInterval(TimeInterval(rightDuration))))
                case "-": return .string(Self.dbDateString(from: date.addingTimeInterval(-TimeInterval(rightDuration))))
                default: break
                }
            }
            if let leftDuration {
                switch op {
                case "+": return .object([Self.durationKey: .int(leftDuration + rightDuration)])
                case "-": return .object([Self.durationKey: .int(leftDuration - rightDuration)])
                default: break
                }
            }
        }
        if let leftDuration, op == "+", case .string(let rs) = right, let date = Self.parseDateString(rs) {
            return .string(Self.dbDateString(from: date.addingTimeInterval(TimeInterval(leftDuration))))
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

    private func applyFilter(_ filterSpec: String, to value: ExpressionValue) -> ExpressionValue {
        let (name, args) = Self.parseFilterCall(filterSpec)

        switch name {
        case "count", "length":
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

        case "truncate":
            guard case .string(let s) = value else { return value }
            let limit = args.first.flatMap(Int.init) ?? 100
            guard limit > 0, s.count > limit else { return value }
            return .string(String(s.prefix(limit)).trimmingCharacters(in: .whitespaces) + "...")

        case "relative":
            guard case .string(let s) = value, let date = Self.parseDateString(s) else { return value }
            return .string(Self.relativeString(from: date))

        case "format":
            guard case .string(let s) = value, let date = Self.parseDateString(s),
                  let pattern = args.first
            else { return value }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_CH")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = pattern
            return .string(formatter.string(from: date))

        case "short":
            return applyFilter("format('dd.MM.yyyy')", to: value)

        case "currency":
            guard let amount = toDouble(value) else { return value }
            let code = args.first ?? "CHF"
            return .string(Self.currencyString(amount: amount, code: code))

        default:
            return value
        }
    }

    // Parse a filter call like "truncate(80)" or "format('dd.MM.yyyy')" into
    // its name and unquoted argument list.
    private static func parseFilterCall(_ spec: String) -> (name: String, args: [String]) {
        guard let open = spec.firstIndex(of: "("), spec.hasSuffix(")") else {
            return (spec, [])
        }
        let name = String(spec[..<open]).trimmingCharacters(in: .whitespaces)
        let inner = String(spec[spec.index(after: open)..<spec.index(before: spec.endIndex)])

        var args: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        for ch in inner {
            if ch == "'" && !inDouble { inSingle.toggle(); continue }
            if ch == "\"" && !inSingle { inDouble.toggle(); continue }
            if ch == "," && !inSingle && !inDouble {
                args.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            }
            current.append(ch)
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(current.trimmingCharacters(in: .whitespaces))
        }
        return (name, args)
    }

    // MARK: - Operator precedence helper

    // Find the last occurrence of any of the given operators (with surrounding spaces)
    // that is NOT inside parentheses or string literals. Returns the operator and the
    // range covering " op " so callers can split left/right.
    private func findLastOperator(in expr: String, operators: [String]) -> (String, Range<String.Index>)? {
        var bestIndex: String.Index? = nil
        var bestOp: String? = nil
        var bestRange: Range<String.Index>? = nil

        for op in operators {
            let needle = " \(op) "
            var searchRange = expr.startIndex..<expr.endIndex

            while let range = expr.range(of: needle, range: searchRange) {
                if !isInsideParensOrQuotes(expr, at: range.lowerBound) {
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

    // Find the last "|" that is outside parentheses and string literals.
    private func findLastPipe(in expr: String) -> String.Index? {
        var inSingle = false
        var inDouble = false
        var parenDepth = 0
        var last: String.Index? = nil

        for i in expr.indices {
            let ch = expr[i]
            if ch == "\"" && !inSingle { inDouble.toggle() }
            else if ch == "'" && !inDouble { inSingle.toggle() }
            else if !inSingle && !inDouble {
                if ch == "(" { parenDepth += 1 }
                else if ch == ")" { parenDepth -= 1 }
                else if ch == "|" && parenDepth == 0 { last = i }
            }
        }
        return last
    }

    // Scan the prefix up to `position` tracking paren depth and quote state.
    private func isInsideParensOrQuotes(_ expr: String, at position: String.Index) -> Bool {
        var inSingle = false
        var inDouble = false
        var parenDepth = 0

        for i in expr.indices {
            if i == position {
                return parenDepth > 0 || inSingle || inDouble
            }
            let ch = expr[i]
            if ch == "\"" && !inSingle { inDouble.toggle() }
            else if ch == "'" && !inDouble { inSingle.toggle() }
            else if !inSingle && !inDouble {
                if ch == "(" { parenDepth += 1 }
                else if ch == ")" { parenDepth -= 1 }
            }
        }
        return false
    }

    // MARK: - Date & duration helpers

    // Parse a duration literal like "30s", "5m", "2h", "7d", "1w" into seconds.
    static func durationLiteralSeconds(_ literal: String) -> Int? {
        guard literal.count >= 2, let unit = literal.last else { return nil }
        let digits = literal.dropLast()
        guard digits.allSatisfy(\.isNumber), let amount = Int(digits) else { return nil }
        switch unit {
        case "s": return amount
        case "m": return amount * 60
        case "h": return amount * 3600
        case "d": return amount * 86_400
        case "w": return amount * 604_800
        default: return nil
        }
    }

    private func durationSeconds(of value: ExpressionValue) -> Int? {
        if case .object(let obj) = value, case .int(let s)? = obj[Self.durationKey], obj.count == 1 {
            return s
        }
        return nil
    }

    // Parse date strings in DB format ("yyyy-MM-dd HH:mm:ss", UTC — matches
    // SQLite's datetime('now')), plain dates ("yyyy-MM-dd") and ISO 8601.
    static func parseDateString(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard s.count >= 10, s.prefix(4).allSatisfy(\.isNumber) else { return nil }

        let db = DateFormatter()
        db.locale = Locale(identifier: "en_US_POSIX")
        db.timeZone = TimeZone(identifier: "UTC")
        db.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = db.date(from: s) { return d }

        db.dateFormat = "yyyy-MM-dd"
        if let d = db.date(from: s) { return d }

        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }

        return nil
    }

    // Format a Date back into the DB format (UTC).
    static func dbDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    // German relative time ("vor 3 Stunden", "in 2 Tagen", "gerade eben").
    static func relativeString(from date: Date, reference: Date = Date()) -> String {
        let delta = reference.timeIntervalSince(date)
        let past = delta >= 0
        let seconds = abs(delta)

        func phrase(_ value: Int, _ singular: String, _ plural: String) -> String {
            let noun = value == 1 ? singular : plural
            return past ? "vor \(value) \(noun)" : "in \(value) \(noun)"
        }

        if seconds < 60 { return past ? "gerade eben" : "gleich" }
        if seconds < 3600 { return phrase(Int(seconds / 60), "Minute", "Minuten") }
        if seconds < 86_400 { return phrase(Int(seconds / 3600), "Stunde", "Stunden") }
        if seconds < 604_800 { return phrase(Int(seconds / 86_400), "Tag", "Tagen") }
        if seconds < 2_592_000 { return phrase(Int(seconds / 604_800), "Woche", "Wochen") }
        if seconds < 31_536_000 { return phrase(Int(seconds / 2_592_000), "Monat", "Monaten") }
        return phrase(Int(seconds / 31_536_000), "Jahr", "Jahren")
    }

    // Swiss-style currency formatting: "CHF 1'234.50".
    static func currencyString(amount: Double, code: String) -> String {
        let negative = amount < 0
        let cents = Int((abs(amount) * 100).rounded())
        let whole = cents / 100
        let fraction = cents % 100

        var digits = String(whole)
        var grouped = ""
        while digits.count > 3 {
            grouped = "'" + digits.suffix(3) + grouped
            digits = String(digits.dropLast(3))
        }
        grouped = digits + grouped

        let sign = negative ? "-" : ""
        return "\(code) \(sign)\(grouped).\(String(format: "%02d", fraction))"
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
