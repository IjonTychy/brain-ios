import Testing
import Foundation
@testable import BrainCore
import GRDB

// MARK: - MockDataProvider

// In-memory DataProviding implementation for handler unit tests.
final class MockDataProvider: DataProviding, @unchecked Sendable {
    let databasePool: DatabasePool

    // Tracking calls for verification
    private(set) var createdEntries: [(title: String, type: String, body: String?)] = []
    private(set) var fetchedIds: [Int64] = []
    private(set) var deletedIds: [Int64] = []
    private(set) var searchQueries: [(query: String, limit: Int)] = []
    private(set) var addedTags: [(entryId: Int64, tagName: String)] = []
    private(set) var removedTags: [(entryId: Int64, tagName: String)] = []
    private(set) var savedFacts: [(subject: String, predicate: String, object: String)] = []
    private(set) var installedSkills: [Skill] = []

    // Configurable return values
    var stubbedEntry: Entry?
    var stubbedEntries: [Entry] = []
    var stubbedTags: [BrainCore.Tag] = []
    var stubbedSkills: [Skill] = []

    private var nextEntryId: Int64 = 1

    init() throws {
        // In-memory database for pool requirement
        let db = try DatabaseManager.temporary()
        databasePool = db.pool
    }

    func createEntry(title: String, type: String, body: String?) throws -> Entry {
        createdEntries.append((title: title, type: type, body: body))
        let id = nextEntryId
        nextEntryId += 1
        return Entry(
            id: id,
            type: EntryType(rawValue: type) ?? .thought,
            title: title,
            body: body
        )
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

    func deleteEntry(id: Int64) throws {
        deletedIds.append(id)
    }

    func searchEntries(query: String, limit: Int) throws -> [Entry] {
        searchQueries.append((query: query, limit: limit))
        return stubbedEntries
    }

    func listEntries(limit: Int) throws -> [Entry] {
        Array(stubbedEntries.prefix(limit))
    }

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
        Link(id: 1, sourceId: sourceId, targetId: targetId, relation: LinkRelation(rawValue: relation) ?? .related)
    }

    func deleteLink(sourceId: Int64, targetId: Int64) throws {}

    func linkedEntries(for entryId: Int64) throws -> [Entry] {
        stubbedEntries
    }

    func addTag(entryId: Int64, tagName: String) throws {
        addedTags.append((entryId: entryId, tagName: tagName))
    }

    func removeTag(entryId: Int64, tagName: String) throws {
        removedTags.append((entryId: entryId, tagName: tagName))
    }

    func listTags() throws -> [BrainCore.Tag] {
        stubbedTags
    }

    func tagCounts() throws -> [(tag: BrainCore.Tag, count: Int)] {
        stubbedTags.map { ($0, 5) }
    }

    func autocomplete(prefix: String, limit: Int) throws -> [Entry] {
        stubbedEntries.filter { ($0.title ?? "").hasPrefix(prefix) }
    }

    func listSkills() throws -> [Skill] {
        stubbedSkills
    }

    func installSkill(_ skill: Skill) throws -> Skill {
        installedSkills.append(skill)
        return skill
    }

    func evaluateRules(trigger: String, entryType: String?) throws -> [RuleMatch] {
        []
    }

    func listProposals(status: ProposalStatus?) throws -> [Proposal] {
        []
    }

    func applyProposal(id: Int64) throws -> Proposal? {
        nil
    }

    func rejectProposal(id: Int64) throws -> Proposal? {
        nil
    }

    func saveKnowledgeFact(subject: String, predicate: String, object: String,
                           confidence: Double, sourceEntryId: Int64?) throws -> KnowledgeFact {
        savedFacts.append((subject: subject, predicate: predicate, object: object))
        return KnowledgeFact(
            id: Int64(savedFacts.count),
            subject: subject, predicate: predicate, object: object,
            confidence: confidence, sourceEntryId: sourceEntryId
        )
    }

    func buildLLMProvider() async -> (any LLMProvider)? {
        MockLLMProvider()
    }
}

// Minimal LLM provider for tests.
private struct MockLLMProvider: LLMProvider {
    let name = "mock"
    let isAvailable = true
    let supportsStreaming = false
    let isOnDevice = true
    let contextWindow = 4096

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        LLMResponse(content: "Mock response", providerName: "mock", inputTokens: 10, outputTokens: 5)
    }
}

// MARK: - Protocol conformance tests

@Suite("DataProviding Protocol")
struct DataProvidingTests {
    @Test("MockDataProvider creates entries with incrementing IDs")
    func createEntry() throws {
        let mock = try MockDataProvider()
        let entry1 = try mock.createEntry(title: "First", type: "thought", body: nil)
        let entry2 = try mock.createEntry(title: "Second", type: "task", body: "Details")

        #expect(entry1.id == 1)
        #expect(entry2.id == 2)
        #expect(entry1.title == "First")
        #expect(entry2.type == .task)
        #expect(mock.createdEntries.count == 2)
    }

    @Test("MockDataProvider tracks fetched IDs")
    func fetchEntry() throws {
        let mock = try MockDataProvider()
        mock.stubbedEntry = Entry(id: 42, type: .note, title: "Test")

        let result = try mock.fetchEntry(id: 42)
        #expect(result?.id == 42)
        #expect(mock.fetchedIds == [42])
    }

    @Test("MockDataProvider tracks deletions")
    func deleteEntry() throws {
        let mock = try MockDataProvider()
        try mock.deleteEntry(id: 7)
        try mock.deleteEntry(id: 13)
        #expect(mock.deletedIds == [7, 13])
    }

    @Test("MockDataProvider search tracks queries")
    func searchEntries() throws {
        let mock = try MockDataProvider()
        mock.stubbedEntries = [
            Entry(id: 1, type: .thought, title: "Match"),
        ]

        let results = try mock.searchEntries(query: "test", limit: 10)
        #expect(results.count == 1)
        #expect(mock.searchQueries.first?.query == "test")
        #expect(mock.searchQueries.first?.limit == 10)
    }

    @Test("MockDataProvider tag operations")
    func tagOperations() throws {
        let mock = try MockDataProvider()
        try mock.addTag(entryId: 1, tagName: "important")
        try mock.removeTag(entryId: 1, tagName: "old")

        #expect(mock.addedTags.count == 1)
        #expect(mock.addedTags.first?.tagName == "important")
        #expect(mock.removedTags.count == 1)
        #expect(mock.removedTags.first?.tagName == "old")
    }

    @Test("MockDataProvider knowledge facts")
    func knowledgeFacts() throws {
        let mock = try MockDataProvider()
        let fact = try mock.saveKnowledgeFact(
            subject: "User", predicate: "lives_in", object: "Zürich",
            confidence: 0.9, sourceEntryId: nil
        )

        #expect(fact.subject == "User")
        #expect(fact.predicate == "lives_in")
        #expect(fact.object == "Zürich")
        #expect(mock.savedFacts.count == 1)
    }

    @Test("MockDataProvider LLM provider is available")
    func llmProvider() async throws {
        let mock = try MockDataProvider()
        let provider = await mock.buildLLMProvider()
        #expect(provider != nil)
        #expect(provider?.isAvailable == true)
        #expect(provider?.name == "mock")
    }

    @Test("MockDataProvider skill operations")
    func skillOperations() throws {
        let mock = try MockDataProvider()
        mock.stubbedSkills = [
            Skill(id: "test-skill", name: "Test", screens: "{}"),
        ]

        let skills = try mock.listSkills()
        #expect(skills.count == 1)
        #expect(skills.first?.id == "test-skill")

        let installed = try mock.installSkill(Skill(id: "new", name: "New", screens: "{}"))
        #expect(installed.id == "new")
        #expect(mock.installedSkills.count == 1)
    }

    @Test("MockDataProvider markDone changes status")
    func markDone() throws {
        let mock = try MockDataProvider()
        mock.stubbedEntry = Entry(id: 5, type: .task, title: "Do it")

        let result = try mock.markDone(id: 5)
        #expect(result?.status == .done)
    }

    @Test("MockDataProvider listEntries respects limit")
    func listEntriesLimit() throws {
        let mock = try MockDataProvider()
        mock.stubbedEntries = (1...10).map { Entry(id: Int64($0), type: .thought, title: "Entry \($0)") }

        let limited = try mock.listEntries(limit: 3)
        #expect(limited.count == 3)
    }

    @Test("MockDataProvider link operations")
    func linkOperations() throws {
        let mock = try MockDataProvider()
        let link = try mock.createLink(sourceId: 1, targetId: 2, relation: "related")
        #expect(link.sourceId == 1)
        #expect(link.targetId == 2)
        #expect(link.relation == .related)
    }
}
