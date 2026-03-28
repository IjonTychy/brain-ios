import Testing
import Foundation
@testable import BrainCore

@Suite("Expression Parser")
struct ExpressionParserTests {

    let parser = ExpressionParser()

    private func ctx(_ vars: [String: ExpressionValue]) -> ExpressionContext {
        ExpressionContext(variables: vars)
    }

    // MARK: - Variable lookup

    @Test("Simple variable lookup")
    func simpleLookup() {
        let context = ctx(["name": .string("Max")])
        let result = parser.evaluate("{{name}}", context: context)
        #expect(result == "Max")
    }

    @Test("Dotted path lookup")
    func dottedPath() {
        let context = ctx(["user": .object(["name": .string("Max"), "age": .int(30)])])
        let result = parser.evaluate("{{user.name}}", context: context)
        #expect(result == "Max")
    }

    @Test("Missing variable returns empty")
    func missingVariable() {
        let context = ctx([:])
        let result = parser.evaluate("{{missing}}", context: context)
        #expect(result == "")
    }

    // MARK: - String interpolation

    @Test("Interpolation with surrounding text")
    func interpolation() {
        let context = ctx(["name": .string("Max")])
        let result = parser.evaluate("Hallo {{name}}, willkommen!", context: context)
        #expect(result == "Hallo Andy, willkommen!")
    }

    @Test("Multiple expressions in one string")
    func multipleExpressions() {
        let context = ctx(["first": .string("Max"), "last": .string("Testuser")])
        let result = parser.evaluate("{{first}} {{last}}", context: context)
        #expect(result == "Test User")
    }

    @Test("No expressions returns original string")
    func noExpressions() {
        let result = parser.evaluate("No expressions here", context: ctx([:]))
        #expect(result == "No expressions here")
    }

    // MARK: - Comparisons

    @Test("Equality comparison")
    func equality() {
        let context = ctx(["status": .string("done")])
        let result = parser.evaluateExpression("status == \"done\"", context: context)
        #expect(result == .bool(true))
    }

    @Test("Numeric comparison")
    func numericComparison() {
        let context = ctx(["count": .int(5)])

        #expect(parser.evaluateExpression("count > 0", context: context) == .bool(true))
        #expect(parser.evaluateExpression("count < 10", context: context) == .bool(true))
        #expect(parser.evaluateExpression("count >= 5", context: context) == .bool(true))
        #expect(parser.evaluateExpression("count <= 5", context: context) == .bool(true))
        #expect(parser.evaluateExpression("count == 5", context: context) == .bool(true))
        #expect(parser.evaluateExpression("count != 3", context: context) == .bool(true))
    }

    // MARK: - Arithmetic

    @Test("Addition")
    func addition() {
        let context = ctx(["a": .int(3), "b": .int(4)])
        let result = parser.evaluateExpression("a + b", context: context)
        #expect(result == .int(7))
    }

    @Test("Multiplication")
    func multiplication() {
        let context = ctx(["price": .double(10.0), "qty": .int(3)])
        let result = parser.evaluateExpression("price * qty", context: context)
        #expect(result == .double(30.0))
    }

    @Test("Division by zero returns zero")
    func divisionByZero() {
        let context = ctx(["a": .int(10), "b": .int(0)])
        let result = parser.evaluateExpression("a / b", context: context)
        #expect(result == .int(0))
    }

    @Test("String concatenation with +")
    func stringConcat() {
        let context = ctx(["first": .string("Hello"), "second": .string(" World")])
        let result = parser.evaluateExpression("first + second", context: context)
        #expect(result == .string("Hello World"))
    }

    // MARK: - Operator precedence

    @Test("Multiplication before addition: 1 + 2 * 3 = 7")
    func mulBeforeAdd() {
        let context = ctx([:])
        let result = parser.evaluateExpression("1 + 2 * 3", context: context)
        #expect(result == .int(7))
    }

    @Test("Multiplication before subtraction: 10 - 2 * 3 = 4")
    func mulBeforeSub() {
        let context = ctx([:])
        let result = parser.evaluateExpression("10 - 2 * 3", context: context)
        #expect(result == .int(4))
    }

    @Test("Parentheses override precedence: (1 + 2) * 3 = 9")
    func parensOverride() {
        let context = ctx([:])
        let result = parser.evaluateExpression("(1 + 2) * 3", context: context)
        #expect(result == .int(9))
    }

    @Test("Division then addition: 10 / 2 + 3 = 8")
    func divThenAdd() {
        let context = ctx([:])
        let result = parser.evaluateExpression("10 / 2 + 3", context: context)
        #expect(result == .int(8))
    }

    @Test("Multiple multiplications and additions: 2 * 3 + 4 * 5 = 26")
    func multiMulAdd() {
        let context = ctx([:])
        let result = parser.evaluateExpression("2 * 3 + 4 * 5", context: context)
        #expect(result == .int(26))
    }

    // MARK: - Pipe filters

    @Test("Count filter on array")
    func countFilter() {
        let context = ctx(["items": .array([.string("a"), .string("b"), .string("c")])])
        let result = parser.evaluateExpression("items | count", context: context)
        #expect(result == .int(3))
    }

    @Test("Uppercase filter")
    func uppercaseFilter() {
        let context = ctx(["name": .string("andy")])
        let result = parser.evaluateExpression("name | uppercase", context: context)
        #expect(result == .string("ANDY"))
    }

    @Test("Lowercase filter")
    func lowercaseFilter() {
        let context = ctx(["name": .string("ANDY")])
        let result = parser.evaluateExpression("name | lowercase", context: context)
        #expect(result == .string("andy"))
    }

    @Test("Not filter")
    func notFilter() {
        let context = ctx(["flag": .bool(true)])
        let result = parser.evaluateExpression("flag | not", context: context)
        #expect(result == .bool(false))
    }

    // MARK: - Literals

    @Test("Boolean literals")
    func boolLiterals() {
        let context = ctx([:])
        #expect(parser.evaluateExpression("true", context: context) == .bool(true))
        #expect(parser.evaluateExpression("false", context: context) == .bool(false))
    }

    @Test("Numeric literals")
    func numericLiterals() {
        let context = ctx([:])
        #expect(parser.evaluateExpression("42", context: context) == .int(42))
        #expect(parser.evaluateExpression("3.14", context: context) == .double(3.14))
    }

    @Test("String literals")
    func stringLiterals() {
        let context = ctx([:])
        #expect(parser.evaluateExpression("\"hello\"", context: context) == .string("hello"))
        #expect(parser.evaluateExpression("'world'", context: context) == .string("world"))
    }

    // MARK: - Truthiness

    @Test("Truthiness of values")
    func truthiness() {
        #expect(ExpressionValue.bool(true).isTruthy == true)
        #expect(ExpressionValue.bool(false).isTruthy == false)
        #expect(ExpressionValue.int(1).isTruthy == true)
        #expect(ExpressionValue.int(0).isTruthy == false)
        #expect(ExpressionValue.string("hi").isTruthy == true)
        #expect(ExpressionValue.string("").isTruthy == false)
        #expect(ExpressionValue.null.isTruthy == false)
        #expect(ExpressionValue.array([]).isTruthy == false)
        #expect(ExpressionValue.array([.int(1)]).isTruthy == true)
    }
}
