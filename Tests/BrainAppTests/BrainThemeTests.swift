import Testing
import SwiftUI
@testable import BrainCore
@testable import BrainApp

// Tests for the BrainTheme design system as implemented after the March 2026
// frontend overhaul: EntryType.color is the single source of truth for entry
// colors (the old BrainTheme.entryTypeColor() was removed), radii live in
// BrainTheme.Radius, semantic colors in BrainTheme.Colors.

// MARK: - Entry Type Colors

@Suite("EntryType Colors")
struct EntryTypeColorTests {

    @Test("Every entry type has a color")
    func everyTypeHasColor() {
        let allTypes: [EntryType] = [.thought, .task, .event, .email, .note, .document]
        for type in allTypes {
            _ = type.color  // must not crash; exhaustive switch guarantees coverage
        }
    }

    @Test("Task type is blue")
    func taskIsBlue() {
        #expect(EntryType.task.color == .blue)
    }

    @Test("Event type is purple")
    func eventIsPurple() {
        #expect(EntryType.event.color == .purple)
    }

    @Test("Email type is orange")
    func emailIsOrange() {
        #expect(EntryType.email.color == .orange)
    }

    @Test("Core entry types have distinct colors")
    func coreTypesHaveDistinctColors() {
        let types: [EntryType] = [.thought, .task, .note, .event, .email, .document]
        var seen: [String: EntryType] = [:]
        for type in types {
            let key = String(describing: type.color)
            if let existing = seen[key] {
                Issue.record("\(type) and \(existing) share the same color")
            }
            seen[key] = type
        }
    }
}

// MARK: - Spacing

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

    @Test("Nested Spacing namespace mirrors the top-level constants")
    func nestedSpacingMatches() {
        #expect(BrainTheme.Spacing.xs == BrainTheme.spacingXS)
        #expect(BrainTheme.Spacing.sm == BrainTheme.spacingSM)
        #expect(BrainTheme.Spacing.md == BrainTheme.spacingMD)
        #expect(BrainTheme.Spacing.lg == BrainTheme.spacingLG)
        #expect(BrainTheme.Spacing.xl == BrainTheme.spacingXL)
    }
}

// MARK: - Corner Radius

@Suite("BrainTheme Corner Radius")
struct BrainThemeCornerRadiusTests {

    @Test("All corner radius constants are positive")
    func radiiArePositive() {
        #expect(BrainTheme.Radius.sm > 0)
        #expect(BrainTheme.Radius.md > 0)
        #expect(BrainTheme.Radius.lg > 0)
        #expect(BrainTheme.Radius.xl > 0)
        #expect(BrainTheme.Radius.card > 0)
    }

    @Test("Corner radius constants are in ascending order")
    func radiiAreAscending() {
        #expect(BrainTheme.Radius.sm < BrainTheme.Radius.md)
        #expect(BrainTheme.Radius.md < BrainTheme.Radius.lg)
        #expect(BrainTheme.Radius.lg < BrainTheme.Radius.xl)
    }

    @Test("Top-level radius constants match the nested namespace")
    func topLevelRadiiMatch() {
        #expect(BrainTheme.cornerRadiusMD == BrainTheme.Radius.md)
        #expect(BrainTheme.cornerRadiusLG == BrainTheme.Radius.lg)
    }

    @Test("Card radius sits between md and lg")
    func cardRadiusBetween() {
        #expect(BrainTheme.Radius.card >= BrainTheme.Radius.md)
        #expect(BrainTheme.Radius.card <= BrainTheme.Radius.lg)
    }
}

// MARK: - Semantic Colors

@Suite("BrainTheme Semantic Colors")
struct BrainThemeSemanticColorTests {

    @Test("Destructive color is red")
    func destructiveIsRed() {
        #expect(BrainTheme.Colors.destructive == Color.red)
    }

    @Test("Success color is green")
    func successIsGreen() {
        #expect(BrainTheme.Colors.success == Color.green)
    }

    @Test("Warning color is orange")
    func warningIsOrange() {
        #expect(BrainTheme.Colors.warning == Color.orange)
    }

    @Test("Error equals destructive")
    func errorEqualsDestructive() {
        #expect(BrainTheme.Colors.error == BrainTheme.Colors.destructive)
    }
}

// MARK: - Greeting

@Suite("BrainTheme Greeting")
struct BrainThemeGreetingTests {

    @Test("Greeting is never empty")
    func greetingNotEmpty() {
        #expect(!BrainTheme.greeting().isEmpty)
    }
}
