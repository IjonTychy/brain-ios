import Testing
import Foundation
@testable import BrainApp

// MARK: - LocalizationService Tests

@Suite("LocalizationService")
struct LocalizationServiceTests {

    @Test("L() resolves known key to German value")
    @MainActor func resolveKnownKey() {
        let service = LocalizationService.shared
        let result = service.resolve("tab.home")
        #expect(result == "Home")
    }

    @Test("L() returns key itself for nonexistent key")
    @MainActor func resolveUnknownKey() {
        let service = LocalizationService.shared
        let result = service.resolve("nonexistent.key")
        #expect(result == "nonexistent.key")
    }

    @Test("L() returns key for completely arbitrary string")
    @MainActor func resolveArbitraryString() {
        let service = LocalizationService.shared
        let result = service.resolve("this.does.not.exist.at.all")
        #expect(result == "this.does.not.exist.at.all")
    }

    @Test("All built-in German keys are non-empty strings")
    func builtInGermanKeysNonEmpty() {
        let labels = LocalizationService.builtInGerman
        #expect(!labels.isEmpty, "Built-in German dictionary should not be empty")
        for (key, value) in labels {
            #expect(!key.isEmpty, "Key should not be empty")
            #expect(!value.isEmpty, "Value for '\(key)' should not be empty")
        }
    }

    @Test("Built-in German has minimum expected key count")
    func builtInGermanMinimumCount() {
        let labels = LocalizationService.builtInGerman
        // We know there are tabs, buttons, settings, chat, search, types, common, onboarding, mail, skills, graph, errors
        #expect(labels.count >= 70, "Expected at least 70 built-in keys, got \(labels.count)")
    }

    @Test("All built-in German keys use dotted notation")
    func builtInGermanKeyFormat() {
        let labels = LocalizationService.builtInGerman
        for key in labels.keys {
            #expect(key.contains("."), "Key '\(key)' should use dotted notation (e.g. 'tab.home')")
        }
    }

    @Test("Key categories cover all expected sections")
    func builtInGermanCategories() {
        let labels = LocalizationService.builtInGerman
        let prefixes = Set(labels.keys.compactMap { $0.split(separator: ".").first.map(String.init) })

        let expectedCategories = ["tab", "button", "settings", "chat", "search", "type", "common", "onboarding", "mail", "skills", "graph", "error"]
        for category in expectedCategories {
            #expect(prefixes.contains(category), "Missing localization category: '\(category)'")
        }
    }

    @Test("Specific German translations are correct")
    @MainActor func specificTranslations() {
        let service = LocalizationService.shared
        #expect(service.resolve("button.save") == "Speichern")
        #expect(service.resolve("button.cancel") == "Abbrechen")
        #expect(service.resolve("button.delete") == "Loeschen")
        #expect(service.resolve("settings.title") == "Einstellungen")
        #expect(service.resolve("chat.placeholder") == "Nachricht an Brain...")
        #expect(service.resolve("onboarding.welcome") == "Willkommen bei Brain")
        #expect(service.resolve("common.noTitle") == "Ohne Titel")
        #expect(service.resolve("error.network") == "Keine Internetverbindung")
    }

    @Test("All entry type keys have translations")
    @MainActor func entryTypeTranslations() {
        let service = LocalizationService.shared
        let typeKeys = ["type.thought", "type.task", "type.note", "type.event",
                        "type.email", "type.contact", "type.bookmark", "type.habit"]
        for key in typeKeys {
            let value = service.resolve(key)
            #expect(value != key, "Entry type '\(key)' should have a translation, got key back")
        }
    }

    @Test("All mail folder keys have translations")
    @MainActor func mailFolderTranslations() {
        let service = LocalizationService.shared
        let mailKeys = ["mail.inbox", "mail.sent", "mail.drafts", "mail.archive", "mail.trash", "mail.spam"]
        for key in mailKeys {
            let value = service.resolve(key)
            #expect(value != key, "Mail key '\(key)' should have a translation")
        }
    }
}

// MARK: - Label Parsing Logic Tests

@Suite("LocalizationService Label Parsing")
struct LocalizationLabelParsingTests {

    @Test("Parsing valid 'key: value' lines extracts dotted keys")
    func parseValidLines() {
        // Simulate the parsing logic used in loadLabels(from:)
        let markdown = """
        ---
        id: brain-language-en
        ---
        # English Translation

        tab.home: Home
        tab.search: Search
        button.save: Save
        """
        let parsed = parseLabels(from: markdown)
        #expect(parsed["tab.home"] == "Home")
        #expect(parsed["tab.search"] == "Search")
        #expect(parsed["button.save"] == "Save")
    }

    @Test("Parsing skips YAML frontmatter delimiters")
    func parseSkipsFrontmatter() {
        let markdown = """
        ---
        id: brain-language-en
        name: English
        ---
        tab.home: Dashboard
        """
        let parsed = parseLabels(from: markdown)
        // Should not contain "id" or "name" as they lack dots
        #expect(parsed["id"] == nil)
        #expect(parsed["name"] == nil)
        #expect(parsed["tab.home"] == "Dashboard")
    }

    @Test("Parsing skips headers and list items")
    func parseSkipsHeadersAndLists() {
        let markdown = """
        # Section Header
        - list item: with colon

        tab.chat: Chat
        """
        let parsed = parseLabels(from: markdown)
        #expect(parsed.count == 1)
        #expect(parsed["tab.chat"] == "Chat")
    }

    @Test("Parsing skips empty lines")
    func parseSkipsEmptyLines() {
        let markdown = """

        tab.home: Home

        tab.chat: Chat

        """
        let parsed = parseLabels(from: markdown)
        #expect(parsed.count == 2)
    }

    @Test("Parsing strips quotes from values")
    func parseStripsQuotes() {
        let markdown = """
        tab.home: "Dashboard"
        button.save: "Save Now"
        """
        let parsed = parseLabels(from: markdown)
        #expect(parsed["tab.home"] == "Dashboard")
        #expect(parsed["button.save"] == "Save Now")
    }

    @Test("Parsing handles colons in values")
    func parseColonsInValues() {
        let markdown = """
        chat.placeholder: Message to Brain: type here
        """
        let parsed = parseLabels(from: markdown)
        #expect(parsed["chat.placeholder"] == "Message to Brain: type here")
    }

    @Test("Parsing rejects keys without dots")
    func parseRejectsNonDottedKeys() {
        let markdown = """
        simplekey: should be ignored
        dotted.key: should be included
        """
        let parsed = parseLabels(from: markdown)
        #expect(parsed["simplekey"] == nil)
        #expect(parsed["dotted.key"] == "should be included")
    }

    @Test("Parsing handles lines with leading/trailing whitespace")
    func parseHandlesWhitespace() {
        let markdown = """
           tab.home: Home
          button.save: Save
        """
        let parsed = parseLabels(from: markdown)
        #expect(parsed["tab.home"] == "Home")
        #expect(parsed["button.save"] == "Save")
    }

    // Helper: replicate the parsing logic from LocalizationService.loadLabels(from:)
    private func parseLabels(from markdown: String) -> [String: String] {
        var parsed: [String: String] = [:]
        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("---"),
                  !trimmed.hasPrefix("#"),
                  !trimmed.hasPrefix("-"),
                  trimmed.contains(": ")
            else { continue }

            let parts = trimmed.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if key.contains(".") {
                parsed[key] = value
            }
        }
        return parsed
    }
}
