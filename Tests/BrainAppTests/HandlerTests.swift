import Testing
import Foundation
@testable import BrainCore
@testable import BrainApp
import GRDB

// MARK: - MockDataProvider (shared with BrainCoreTests pattern)

final class AppMockDataProvider: DataProviding, @unchecked Sendable {
    let databasePool: DatabasePool

    private(set) var createdEntries: [(title: String, type: String, body: String?)] = []
    private(set) var fetchedIds: [Int64] = []
    private(set) var deletedIds: [Int64] = []
    private(set) var searchQueries: [(query: String, limit: Int)] = []
    private(set) var addedTags: [(entryId: Int64, tagName: String)] = []
    private(set) var removedTags: [(entryId: Int64, tagName: String)] = []
    private(set) var savedFacts: [(subject: String, predicate: String, object: String)] = []
    private(set) var installedSkills: [Skill] = []

    var stubbedEntry: Entry?
    var stubbedEntries: [Entry] = []
    var stubbedTags: [Tag] = []
    var stubbedSkills: [Skill] = []

    private var nextEntryId: Int64 = 1

    init() throws {
        let db = try DatabaseManager.temporary()
        databasePool = db.pool
    }

    func createEntry(title: String, type: String, body: String?) throws -> Entry {
        createdEntries.append((title: title, type: type, body: body))
        let id = nextEntryId
        nextEntryId += 1
        return Entry(id: id, type: EntryType(rawValue: type) ?? .thought, title: title, body: body)
    }

    func fetchEntry(id: Int64) throws -> Entry? {
        fetchedIds.append(id)
        return stubbedEntry ?? stubbedEntries.first { $0.id == id }
    }

    func updateEntry(id: Int64, title: String?, body: String?) throws -> Entry? {
        var entry = try fetchEntry(id: id)
        if let title { entry?.title = title }
        if let body { entry?.body = body }
        return entry
    }

    func deleteEntry(id: Int64) throws { deletedIds.append(id) }

    func searchEntries(query: String, limit: Int) throws -> [Entry] {
        searchQueries.append((query: query, limit: limit))
        return stubbedEntries
    }

    func listEntries(limit: Int) throws -> [Entry] { Array(stubbedEntries.prefix(limit)) }

    func markDone(id: Int64) throws -> Entry? {
        var entry = try fetchEntry(id: id)
        entry?.status = .done
        return entry
    }

    func archiveEntry(id: Int64) throws -> Entry? {
        var entry = try fetchEntry(id: id)
        entry?.status = .archived
        return entry
    }

    func restoreEntry(id: Int64) throws -> Entry? {
        var entry = try fetchEntry(id: id)
        entry?.status = .active
        return entry
    }

    func createLink(sourceId: Int64, targetId: Int64, relation: String) throws -> Link {
        Link(id: 1, sourceId: sourceId, targetId: targetId, relation: relation)
    }

    func deleteLink(sourceId: Int64, targetId: Int64) throws {}
    func linkedEntries(for entryId: Int64) throws -> [Entry] { stubbedEntries }

    func addTag(entryId: Int64, tagName: String) throws {
        addedTags.append((entryId: entryId, tagName: tagName))
    }

    func removeTag(entryId: Int64, tagName: String) throws {
        removedTags.append((entryId: entryId, tagName: tagName))
    }

    func listTags() throws -> [Tag] { stubbedTags }
    func tagCounts() throws -> [(tag: Tag, count: Int)] { stubbedTags.map { ($0, 5) } }
    func autocomplete(prefix: String, limit: Int) throws -> [Entry] {
        stubbedEntries.filter { ($0.title ?? "").hasPrefix(prefix) }
    }

    func listSkills() throws -> [Skill] { stubbedSkills }
    func installSkill(_ skill: Skill) throws -> Skill {
        installedSkills.append(skill)
        return skill
    }

    func evaluateRules(trigger: String, entryType: String?) throws -> [RuleMatch] { [] }
    func listProposals(status: ProposalStatus?) throws -> [Proposal] { [] }
    func applyProposal(id: Int64) throws -> Proposal? { nil }
    func rejectProposal(id: Int64) throws -> Proposal? { nil }

    func saveKnowledgeFact(subject: String, predicate: String, object: String,
                           confidence: Double, sourceEntryId: Int64?) throws -> KnowledgeFact {
        savedFacts.append((subject: subject, predicate: predicate, object: object))
        return KnowledgeFact(id: Int64(savedFacts.count), subject: subject,
                             predicate: predicate, object: object,
                             confidence: confidence, sourceEntryId: sourceEntryId)
    }

    func buildLLMProvider() async -> (any LLMProvider)? { AppMockLLMProvider() }
}

private struct AppMockLLMProvider: LLMProvider {
    let name = "mock"
    let isAvailable = true
    let supportsStreaming = false
    let isOnDevice = true
    let contextWindow = 4096

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        LLMResponse(content: "Mock response", providerName: "mock", inputTokens: 10, outputTokens: 5)
    }
}

// MARK: - Entry Handler Tests

@Suite("EntryCreateHandler")
struct EntryCreateHandlerTests {
    @Test("Creates entry with title and type")
    @MainActor func createBasic() async throws {
        let mock = try AppMockDataProvider()
        let handler = EntryCreateHandler(data: mock)

        let result = try await handler.execute(
            properties: [
                "title": .string("Test Entry"),
                "type": .string("task"),
                "body": .string("Some body text"),
            ],
            context: ExpressionContext()
        )

        #expect(mock.createdEntries.count == 1)
        #expect(mock.createdEntries.first?.title == "Test Entry")
        #expect(mock.createdEntries.first?.type == "task")
        #expect(mock.createdEntries.first?.body == "Some body text")

        if case .value(let val) = result,
           case .object(let dict) = val {
            #expect(dict["id"] == .int(1))
            #expect(dict["title"] == .string("Test Entry"))
        } else {
            Issue.record("Expected .value(.object(...))")
        }
    }

    @Test("Uses defaults for missing fields")
    @MainActor func createDefaults() async throws {
        let mock = try AppMockDataProvider()
        let handler = EntryCreateHandler(data: mock)

        _ = try await handler.execute(properties: [:], context: ExpressionContext())

        #expect(mock.createdEntries.first?.title == "Ohne Titel")
        #expect(mock.createdEntries.first?.type == "thought")
    }
}

@Suite("EntrySearchHandler")
struct EntrySearchHandlerTests {
    @Test("Searches with query and limit")
    @MainActor func searchWithQuery() async throws {
        let mock = try AppMockDataProvider()
        mock.stubbedEntries = [
            Entry(id: 1, type: .thought, title: "Found it"),
        ]
        let handler = EntrySearchHandler(data: mock)

        let result = try await handler.execute(
            properties: [
                "query": .string("test query"),
                "limit": .int(5),
            ],
            context: ExpressionContext()
        )

        #expect(mock.searchQueries.count == 1)
        #expect(mock.searchQueries.first?.query == "test query")
        #expect(mock.searchQueries.first?.limit == 5)

        if case .value(let val) = result, case .array(let arr) = val {
            #expect(arr.count == 1)
        } else {
            Issue.record("Expected .value(.array(...))")
        }
    }
}

@Suite("EntryDeleteHandler")
struct EntryDeleteHandlerTests {
    @Test("Deletes entry by ID")
    @MainActor func deleteEntry() async throws {
        let mock = try AppMockDataProvider()
        let handler = EntryDeleteHandler(data: mock)

        let result = try await handler.execute(
            properties: ["id": .int(42)],
            context: ExpressionContext()
        )

        #expect(mock.deletedIds == [42])
        if case .success = result {
            // OK
        } else {
            Issue.record("Expected .success")
        }
    }

    @Test("Returns error without ID")
    @MainActor func deleteWithoutId() async throws {
        let mock = try AppMockDataProvider()
        let handler = EntryDeleteHandler(data: mock)

        let result = try await handler.execute(properties: [:], context: ExpressionContext())

        #expect(mock.deletedIds.isEmpty)
        if case .error = result {
            // OK — expected error
        } else {
            Issue.record("Expected .error for missing ID")
        }
    }
}

@Suite("EntryMarkDoneHandler")
struct EntryMarkDoneHandlerTests {
    @Test("Marks entry as done")
    @MainActor func markDone() async throws {
        let mock = try AppMockDataProvider()
        mock.stubbedEntry = Entry(id: 5, type: .task, title: "My Task")
        let handler = EntryMarkDoneHandler(data: mock)

        let result = try await handler.execute(
            properties: ["id": .int(5)],
            context: ExpressionContext()
        )

        if case .value(let val) = result, case .object(let dict) = val {
            #expect(dict["status"] == .string("done"))
        } else {
            Issue.record("Expected .value(.object(...))")
        }
    }
}

@Suite("EntryListHandler")
struct EntryListHandlerTests {
    @Test("Lists entries with default limit")
    @MainActor func listDefault() async throws {
        let mock = try AppMockDataProvider()
        mock.stubbedEntries = (1...5).map { Entry(id: Int64($0), type: .thought, title: "E\($0)") }
        let handler = EntryListHandler(data: mock)

        let result = try await handler.execute(properties: [:], context: ExpressionContext())

        if case .value(let val) = result, case .array(let arr) = val {
            #expect(arr.count == 5)
        } else {
            Issue.record("Expected .value(.array(...))")
        }
    }
}

// MARK: - Link & Tag Handler Tests

@Suite("LinkCreateHandler")
struct LinkCreateHandlerTests {
    @Test("Creates link between entries")
    @MainActor func createLink() async throws {
        let mock = try AppMockDataProvider()
        let handler = LinkCreateHandler(data: mock)

        let result = try await handler.execute(
            properties: [
                "sourceId": .int(1),
                "targetId": .int(2),
                "relation": .string("references"),
            ],
            context: ExpressionContext()
        )

        if case .value(let val) = result, case .object(let dict) = val {
            #expect(dict["sourceId"] == .int(1))
            #expect(dict["targetId"] == .int(2))
        } else {
            Issue.record("Expected .value(.object(...))")
        }
    }
}

@Suite("TagAddHandler")
struct TagAddHandlerTests {
    @Test("Adds tag to entry")
    @MainActor func addTag() async throws {
        let mock = try AppMockDataProvider()
        let handler = TagAddHandler(data: mock)

        _ = try await handler.execute(
            properties: [
                "entryId": .int(1),
                "tagName": .string("important"),
            ],
            context: ExpressionContext()
        )

        #expect(mock.addedTags.count == 1)
        #expect(mock.addedTags.first?.tagName == "important")
    }
}

@Suite("KnowledgeSaveHandler")
struct KnowledgeSaveHandlerTests {
    @Test("Saves knowledge fact")
    @MainActor func saveFact() async throws {
        let mock = try AppMockDataProvider()
        let handler = KnowledgeSaveHandler(data: mock)

        let result = try await handler.execute(
            properties: [
                "subject": .string("User"),
                "predicate": .string("likes"),
                "object": .string("Coffee"),
            ],
            context: ExpressionContext()
        )

        #expect(mock.savedFacts.count == 1)
        #expect(mock.savedFacts.first?.subject == "User")
        #expect(mock.savedFacts.first?.predicate == "likes")
        #expect(mock.savedFacts.first?.object == "Coffee")

        if case .value(let val) = result, case .object(let dict) = val {
            #expect(dict["status"] == .string("saved"))
        } else {
            Issue.record("Expected .value(.object(...))")
        }
    }
}

// MARK: - Skill Handler Tests

@Suite("SkillListHandler")
struct SkillListHandlerTests {
    @Test("Lists installed skills")
    @MainActor func listSkills() async throws {
        let mock = try AppMockDataProvider()
        mock.stubbedSkills = [
            Skill(id: "timer", name: "Timer", screens: "{}"),
            Skill(id: "notes", name: "Notes", screens: "{}"),
        ]
        let handler = SkillListHandler(data: mock)

        let result = try await handler.execute(properties: [:], context: ExpressionContext())

        if case .value(let val) = result, case .array(let arr) = val {
            #expect(arr.count == 2)
        } else {
            Issue.record("Expected .value(.array(...))")
        }
    }
}

// MARK: - AI Handler Tests

@Suite("AISummarizeHandler")
struct AISummarizeHandlerTests {
    @Test("Summarizes entry text via LLM")
    @MainActor func summarize() async throws {
        let mock = try AppMockDataProvider()
        mock.stubbedEntry = Entry(id: 1, type: .note, title: "Long Note", body: "A very long text that needs summarizing...")
        let handler = AISummarizeHandler(data: mock)

        let result = try await handler.execute(
            properties: ["id": .int(1)],
            context: ExpressionContext()
        )

        // MockLLMProvider returns "Mock response"
        if case .value(let val) = result, case .object(let dict) = val {
            #expect(dict["summary"] == .string("Mock response"))
        } else {
            Issue.record("Expected .value(.object(...))")
        }
    }

    @Test("Returns error for missing entry")
    @MainActor func summarizeMissing() async throws {
        let mock = try AppMockDataProvider()
        let handler = AISummarizeHandler(data: mock)

        let result = try await handler.execute(
            properties: ["id": .int(999)],
            context: ExpressionContext()
        )

        if case .error = result {
            // Expected
        } else {
            Issue.record("Expected .error for missing entry")
        }
    }
}

@Suite("LLMCompleteHandler")
struct LLMCompleteHandlerTests {
    @Test("Completes LLM request with prompt")
    @MainActor func complete() async throws {
        let mock = try AppMockDataProvider()
        let handler = LLMCompleteHandler(data: mock)

        let result = try await handler.execute(
            properties: ["prompt": .string("Hello")],
            context: ExpressionContext()
        )

        if case .value(let val) = result, case .string(let text) = val {
            #expect(text == "Mock response")
        } else {
            Issue.record("Expected .value(.string(...))")
        }
    }

    @Test("Returns error without prompt")
    @MainActor func completeMissingPrompt() async throws {
        let mock = try AppMockDataProvider()
        let handler = LLMCompleteHandler(data: mock)

        let result = try await handler.execute(properties: [:], context: ExpressionContext())

        if case .error = result {
            // Expected
        } else {
            Issue.record("Expected .error for missing prompt")
        }
    }
}
