import Testing
import Foundation
@testable import BrainCore

// Erweiterte Tests fuer ExpressionParser - Randfaelle
@Suite("Expression Parser Erweitert")
struct ExpressionParserExtendedTests {

    let parser = ExpressionParser()

    private func ctx(_ vars: [String: ExpressionValue] = [:]) -> ExpressionContext {
        ExpressionContext(variables: vars)
    }

    // MARK: - Leere und Whitespace-Expressions

    @Test("Leere Expression gibt null zurueck")
    func emptyExpression() {
        let result = parser.evaluateExpression("", context: ctx())
        #expect(result == .null)
    }

    @Test("Nur-Whitespace Expression gibt null zurueck")
    func whitespaceOnlyExpression() {
        let result = parser.evaluateExpression("   ", context: ctx())
        #expect(result == .null)
    }

    @Test("Leerer Template-String wird unveraendert zurueckgegeben")
    func emptyTemplate() {
        let result = parser.evaluate("", context: ctx())
        #expect(result == "")
    }

    @Test("Template mit nur Leerzeichen bleibt unveraendert")
    func whitespaceTemplate() {
        let result = parser.evaluate("   ", context: ctx())
        #expect(result == "   ")
    }

    // MARK: - ExpressionValue.stringRepresentation

    @Test("Array stringRepresentation formatiert korrekt")
    func arrayStringRepresentation() {
        let value = ExpressionValue.array([.string("a"), .int(1), .bool(true)])
        #expect(value.stringRepresentation == "[a, 1, true]")
    }

    @Test("Leeres Array stringRepresentation ist leere Klammern")
    func emptyArrayStringRepresentation() {
        let value = ExpressionValue.array([])
        #expect(value.stringRepresentation == "[]")
    }

    @Test("Object stringRepresentation ist Platzhalter-String")
    func objectStringRepresentation() {
        let value = ExpressionValue.object(["key": .string("value")])
        #expect(value.stringRepresentation == "[Object]")
    }

    @Test("Null stringRepresentation ist leerer String")
    func nullStringRepresentation() {
        #expect(ExpressionValue.null.stringRepresentation == "")
    }

    @Test("Verschachteltes Array stringRepresentation")
    func nestedArrayStringRepresentation() {
        let inner = ExpressionValue.array([.int(1), .int(2)])
        let outer = ExpressionValue.array([inner, .string("end")])
        #expect(outer.stringRepresentation == "[[1, 2], end]")
    }

    // MARK: - ExpressionValue.isTruthy Randfaelle

    @Test("Leerer String ist nicht truthy")
    func emptyStringNotTruthy() {
        #expect(ExpressionValue.string("").isTruthy == false)
    }

    @Test("String mit Leerzeichen ist truthy")
    func whitespaceStringIsTruthy() {
        #expect(ExpressionValue.string(" ").isTruthy == true)
    }

    @Test("String '0' ist truthy (kein Leerstring)")
    func stringZeroIsTruthy() {
        #expect(ExpressionValue.string("0").isTruthy == true)
    }

    @Test("Int 0 ist nicht truthy")
    func zeroIntNotTruthy() {
        #expect(ExpressionValue.int(0).isTruthy == false)
    }

    @Test("Negativer Int ist truthy")
    func negativeIntIsTruthy() {
        #expect(ExpressionValue.int(-1).isTruthy == true)
    }

    @Test("Double 0.0 ist nicht truthy")
    func zeroDoubleNotTruthy() {
        #expect(ExpressionValue.double(0.0).isTruthy == false)
    }

    @Test("Double 0.001 ist truthy")
    func smallDoubleIsTruthy() {
        #expect(ExpressionValue.double(0.001).isTruthy == true)
    }

    @Test("Null ist nicht truthy")
    func nullNotTruthy() {
        #expect(ExpressionValue.null.isTruthy == false)
    }

    @Test("Leeres Array ist nicht truthy")
    func emptyArrayNotTruthy() {
        #expect(ExpressionValue.array([]).isTruthy == false)
    }

    @Test("Array mit null-Element ist truthy")
    func arrayWithNullIsTruthy() {
        #expect(ExpressionValue.array([.null]).isTruthy == true)
    }

    @Test("Leeres Object ist nicht truthy")
    func emptyObjectNotTruthy() {
        #expect(ExpressionValue.object([:]).isTruthy == false)
    }

    @Test("Object mit einem Schluessel ist truthy")
    func nonEmptyObjectIsTruthy() {
        #expect(ExpressionValue.object(["k": .int(1)]).isTruthy == true)
    }

    // MARK: - Division durch null

    @Test("Integer-Division durch null liefert int 0")
    func intDivisionByZero() {
        let context = ctx(["a": .int(10), "b": .int(0)])
        let result = parser.evaluateExpression("a / b", context: context)
        #expect(result == .int(0))
    }

    @Test("Double-Division durch null liefert double 0")
    func doubleDivisionByZero() {
        let context = ctx(["x": .double(5.0), "zero": .double(0.0)])
        let result = parser.evaluateExpression("x / zero", context: context)
        #expect(result == .double(0.0))
    }

    // MARK: - Arithmetic mit nicht-numerischen Werten

    @Test("Arithmetik auf null gibt null zurueck")
    func arithmeticOnNull() {
        let context = ctx(["x": .null])
        let result = parser.evaluateExpression("x + 1", context: context)
        #expect(result == .null)
    }

    @Test("Subtraktion von Strings gibt null zurueck")
    func stringSubtraction() {
        let context = ctx(["a": .string("hello"), "b": .string("world")])
        let result = parser.evaluateExpression("a - b", context: context)
        #expect(result == .null)
    }

    // MARK: - Pipe filter Randfaelle

    @Test("Count-Filter auf null gibt 0 zurueck")
    func countFilterOnNull() {
        let context = ctx(["x": .null])
        let result = parser.evaluateExpression("x | count", context: context)
        #expect(result == .int(0))
    }

    @Test("Count-Filter auf Integer gibt 0 zurueck")
    func countFilterOnInt() {
        let context = ctx(["x": .int(42)])
        let result = parser.evaluateExpression("x | count", context: context)
        #expect(result == .int(0))
    }

    @Test("Uppercase-Filter auf int ist no-op")
    func uppercaseFilterOnInt() {
        let context = ctx(["x": .int(5)])
        let result = parser.evaluateExpression("x | uppercase", context: context)
        #expect(result == .int(5))
    }

    @Test("Unbekannter Filter ist no-op")
    func unknownFilterIsNoOp() {
        let context = ctx(["name": .string("andy")])
        let result = parser.evaluateExpression("name | nonexistent_filter", context: context)
        #expect(result == .string("andy"))
    }

    @Test("Length-Filter ist Alias fuer count")
    func lengthAliasForCount() {
        let context = ctx(["items": .array([.int(1), .int(2)])])
        let l = parser.evaluateExpression("items | length", context: context)
        let c = parser.evaluateExpression("items | count", context: context)
        #expect(l == c)
        #expect(l == .int(2))
    }

    @Test("Count-Filter auf String zaehlt Zeichen")
    func countFilterOnString() {
        let context = ctx(["s": .string("hello")])
        let result = parser.evaluateExpression("s | count", context: context)
        #expect(result == .int(5))
    }

    // MARK: - Dotted Path Randfaelle

    @Test("Dotted Path auf non-object gibt null zurueck")
    func dottedPathOnNonObject() {
        let context = ctx(["user": .string("andy")])
        let result = parser.evaluateExpression("user.name", context: context)
        #expect(result == .null)
    }

    @Test("Dotted Path mit fehlendem Root gibt null zurueck")
    func dottedPathMissingRoot() {
        let result = parser.evaluateExpression("missing.key", context: ctx())
        #expect(result == .null)
    }

    // MARK: - Template-Interpolation Randfaelle

    @Test("Null in Template wird zu leerem String")
    func nullInTemplate() {
        let context = ctx(["val": .null])
        let result = parser.evaluate("Wert: {{val}}", context: context)
        #expect(result == "Wert: ")
    }

    @Test("Template ohne Expressions unveraendert")
    func templateWithoutExpressions() {
        let result = parser.evaluate("Kein Template hier!", context: ctx())
        #expect(result == "Kein Template hier!")
    }

    // MARK: - Vergleichsoperatoren Randfaelle

    @Test("Groesser-Vergleich von Strings ohne numerischen Wert gibt false")
    func greaterThanNonNumericStrings() {
        let context = ctx(["a": .string("b"), "b": .string("a")])
        let result = parser.evaluateExpression("a > b", context: context)
        #expect(result == .bool(false))
    }

    @Test("Gleichheit von null und null ist true")
    func nullEquality() {
        let context = ctx(["a": .null, "b": .null])
        let result = parser.evaluateExpression("a == b", context: context)
        #expect(result == .bool(true))
    }

    @Test("Ungleichheit von null und string ist true")
    func nullNotEqualString() {
        let context = ctx(["a": .null])
        let result = parser.evaluateExpression("a != \"hello\"", context: context)
        #expect(result == .bool(true))
    }

    @Test("Bool-Gleichheit true == true")
    func boolEquality() {
        let context = ctx(["a": .bool(true), "b": .bool(true)])
        let result = parser.evaluateExpression("a == b", context: context)
        #expect(result == .bool(true))
    }

    @Test("Bool-Ungleichheit true != false")
    func boolInequality() {
        let context = ctx(["a": .bool(true), "b": .bool(false)])
        let result = parser.evaluateExpression("a != b", context: context)
        #expect(result == .bool(true))
    }
}
