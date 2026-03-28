import Testing
import SwiftUI
@testable import BrainApp

// MARK: - BrainTheme Color Tests

@Suite("BrainTheme Entry Type Colors")
struct BrainThemeColorTests {

    @Test("Known entry types return non-gray colors")
    func knownTypesReturnDistinctColors() {
        let knownTypes = ["task", "event", "note", "thought", "email", "contact", "habit"]
        let gray = Color.gray

        for type in knownTypes {
            let color = BrainTheme.entryTypeColor(type)
            #expect(color != gray, "Entry type '\(type)' should not return gray")
        }
    }

    @Test("Unknown entry types return gray")
    func unknownTypeReturnsGray() {
        #expect(BrainTheme.entryTypeColor("unknown") == .gray)
        #expect(BrainTheme.entryTypeColor("") == .gray)
        #expect(BrainTheme.entryTypeColor("foobar") == .gray)
    }

    @Test("Task type is blue")
    func taskIsBlue() {
        #expect(BrainTheme.entryTypeColor("task") == .blue)
    }

    @Test("Event type is orange")
    func eventIsOrange() {
        #expect(BrainTheme.entryTypeColor("event") == .orange)
    }

    @Test("Note and thought types share the same color")
    func noteAndThoughtSameColor() {
        #expect(BrainTheme.entryTypeColor("note") == BrainTheme.entryTypeColor("thought"))
    }

    @Test("Note type is purple")
    func noteIsPurple() {
        #expect(BrainTheme.entryTypeColor("note") == .purple)
    }

    @Test("Email type is cyan")
    func emailIsCyan() {
        #expect(BrainTheme.entryTypeColor("email") == .cyan)
    }

    @Test("Contact type is green")
    func contactIsGreen() {
        #expect(BrainTheme.entryTypeColor("contact") == .green)
    }

    @Test("Habit type is mint")
    func habitIsMint() {
        #expect(BrainTheme.entryTypeColor("habit") == .mint)
    }

    @Test("Distinct entry types have distinct colors (except note/thought)")
    func distinctTypesHaveDistinctColors() {
        // note and thought intentionally share purple
        let distinctTypes = ["task", "event", "note", "email", "contact", "habit"]
        var colorMap: [String: Color] = [:]

        for type in distinctTypes {
            let color = BrainTheme.entryTypeColor(type)
            // Check this color hasn't been seen from a different type
            for (existingType, existingColor) in colorMap {
                #expect(
                    color != existingColor,
                    "'\(type)' and '\(existingType)' should have different colors"
                )
            }
            colorMap[type] = color
        }
    }

    @Test("Entry type color is case-sensitive")
    func colorIsCaseSensitive() {
        // The switch uses lowercase literals; uppercase should fall through to gray
        #expect(BrainTheme.entryTypeColor("Task") == .gray)
        #expect(BrainTheme.entryTypeColor("EVENT") == .gray)
        #expect(BrainTheme.entryTypeColor("Note") == .gray)
    }
}

// MARK: - BrainTheme Spacing Tests

@Suite("BrainTheme Spacing")
struct BrainThemeSpacingTests {

    @Test("All spacing constants are positive")
    func spacingsArePositive() {
        #expect(BrainTheme.spacingXS > 0)
        #expect(BrainTheme.spacingSM > 0)
        #expect(BrainTheme.spacingMD > 0)
        #expect(BrainTheme.spacingLG > 0)
        #expect(BrainTheme.spacingXL > 0)
    }

    @Test("Spacing constants are in ascending order")
    func spacingsAreAscending() {
        #expect(BrainTheme.spacingXS < BrainTheme.spacingSM)
        #expect(BrainTheme.spacingSM < BrainTheme.spacingMD)
        #expect(BrainTheme.spacingMD < BrainTheme.spacingLG)
        #expect(BrainTheme.spacingLG < BrainTheme.spacingXL)
    }

    @Test("Specific spacing values match design spec")
    func spacingValues() {
        #expect(BrainTheme.spacingXS == 4)
        #expect(BrainTheme.spacingSM == 8)
        #expect(BrainTheme.spacingMD == 12)
        #expect(BrainTheme.spacingLG == 16)
        #expect(BrainTheme.spacingXL == 24)
    }
}

// MARK: - BrainTheme Corner Radius Tests

@Suite("BrainTheme Corner Radius")
struct BrainThemeCornerRadiusTests {

    @Test("All corner radius constants are positive")
    func radiiArePositive() {
        #expect(BrainTheme.cornerRadiusSM > 0)
        #expect(BrainTheme.cornerRadiusMD > 0)
        #expect(BrainTheme.cornerRadiusLG > 0)
        #expect(BrainTheme.cornerRadiusFull > 0)
    }

    @Test("Corner radius constants are in ascending order")
    func radiiAreAscending() {
        #expect(BrainTheme.cornerRadiusSM < BrainTheme.cornerRadiusMD)
        #expect(BrainTheme.cornerRadiusMD < BrainTheme.cornerRadiusLG)
        #expect(BrainTheme.cornerRadiusLG < BrainTheme.cornerRadiusFull)
    }

    @Test("Capsule radius is large enough for full rounding")
    func capsuleRadiusIsLarge() {
        #expect(BrainTheme.cornerRadiusFull >= 50, "Capsule radius should be large enough to create pill shapes")
    }

    @Test("Specific corner radius values match design spec")
    func cornerRadiusValues() {
        #expect(BrainTheme.cornerRadiusSM == 8)
        #expect(BrainTheme.cornerRadiusMD == 12)
        #expect(BrainTheme.cornerRadiusLG == 16)
        #expect(BrainTheme.cornerRadiusFull == 100)
    }
}

// MARK: - BrainTheme Card Padding Tests

@Suite("BrainTheme Card Padding")
struct BrainThemeCardPaddingTests {

    @Test("Card padding has positive values on all edges")
    func cardPaddingPositive() {
        let padding = BrainTheme.cardPadding
        #expect(padding.top > 0)
        #expect(padding.leading > 0)
        #expect(padding.bottom > 0)
        #expect(padding.trailing > 0)
    }

    @Test("Card padding is symmetric vertically and horizontally")
    func cardPaddingSymmetric() {
        let padding = BrainTheme.cardPadding
        #expect(padding.top == padding.bottom, "Vertical padding should be symmetric")
        #expect(padding.leading == padding.trailing, "Horizontal padding should be symmetric")
    }
}

// MARK: - BrainTheme Static Color Properties Tests

@Suite("BrainTheme Static Colors")
struct BrainThemeStaticColorTests {

    @Test("Destructive color is red")
    func destructiveIsRed() {
        #expect(BrainTheme.destructive == Color.red)
    }

    @Test("Success color is green")
    func successIsGreen() {
        #expect(BrainTheme.success == Color.green)
    }

    @Test("Secondary text color is Color.secondary")
    func secondaryTextIsSecondary() {
        #expect(BrainTheme.secondaryText == Color.secondary)
    }
}
