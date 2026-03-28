import GRDB

// Protocol for handler dependency injection.
// DataBridge conforms to this; tests can provide MockDataProvider.
public protocol DataProviding: Sendable {
    // Database access (for handlers that need direct pool access)
    var databasePool: DatabasePool { get }

    // Entry CRUD
    func createEntry(title: String, type: String, body: String?) throws -> Entry
    func fetchEntry(id: Int64) throws -> Entry?
    func updateEntry(id: Int64, title: String?, body: String?) throws -> Entry?
    func deleteEntry(id: Int64) throws
    func searchEntries(query: String, limit: Int) throws -> [Entry]
    func listEntries(limit: Int) throws -> [Entry]
    func markDone(id: Int64) throws -> Entry?
    func archiveEntry(id: Int64) throws -> Entry?
    func restoreEntry(id: Int64) throws -> Entry?

    // Links
    func createLink(sourceId: Int64, targetId: Int64, relation: String) throws -> Link
    func deleteLink(sourceId: Int64, targetId: Int64) throws
    func linkedEntries(for entryId: Int64) throws -> [Entry]

    // Tags
    func addTag(entryId: Int64, tagName: String) throws
    func removeTag(entryId: Int64, tagName: String) throws
    func listTags() throws -> [Tag]
    func tagCounts() throws -> [(tag: Tag, count: Int)]

    // Search
    func autocomplete(prefix: String, limit: Int) throws -> [Entry]

    // Skills
    func listSkills() throws -> [Skill]
    func installSkill(_ skill: Skill) throws -> Skill

    // Rules & Proposals
    func evaluateRules(trigger: String, entryType: String?) throws -> [RuleMatch]
    func listProposals(status: ProposalStatus?) throws -> [Proposal]
    func applyProposal(id: Int64) throws -> Proposal?
    func rejectProposal(id: Int64) throws -> Proposal?

    // Knowledge
    func saveKnowledgeFact(subject: String, predicate: String, object: String,
                           confidence: Double, sourceEntryId: Int64?) throws -> KnowledgeFact

    // LLM
    func buildLLMProvider() async -> (any LLMProvider)?
}
