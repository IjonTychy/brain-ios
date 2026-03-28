import GRDB

// Status of an improvement proposal.
public enum ProposalStatus: String, Codable, Sendable, DatabaseValueConvertible {
    case pending, approved, applied, rejected
}

// An improvement proposal created by the self-modifier.
// Proposals describe a change that requires user approval before being applied.
public struct Proposal: Codable, Sendable, Identifiable {
    public var id: Int64?
    public var title: String
    public var description: String?
    public var category: String  // A (config), B (prompt), C (rule)
    public var changeSpec: String?  // JSON
    public var status: ProposalStatus
    public var createdAt: String?
    public var appliedAt: String?
    public var rollbackData: String?  // JSON

    public init(
        id: Int64? = nil,
        title: String,
        description: String? = nil,
        category: String,
        changeSpec: String? = nil,
        status: ProposalStatus = .pending,
        createdAt: String? = nil,
        appliedAt: String? = nil,
        rollbackData: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.changeSpec = changeSpec
        self.status = status
        self.createdAt = createdAt
        self.appliedAt = appliedAt
        self.rollbackData = rollbackData
    }
}

extension Proposal: FetchableRecord, MutablePersistableRecord {
    public static var databaseTableName: String { "improvementProposals" }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
