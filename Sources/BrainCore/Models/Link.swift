import GRDB

// Relation types for links between entries.
public enum LinkRelation: String, Codable, Sendable, DatabaseValueConvertible {
    case related, parent, blocks, references
}

// A directed link between two entries. Bi-directionality is achieved
// by querying both source and target columns for a given entry.
public struct Link: Codable, Sendable, Identifiable {
    public var id: Int64?
    public var sourceId: Int64
    public var targetId: Int64
    public var relation: LinkRelation
    public var createdAt: String?

    public init(
        id: Int64? = nil,
        sourceId: Int64,
        targetId: Int64,
        relation: LinkRelation = .related,
        createdAt: String? = nil
    ) {
        self.id = id
        self.sourceId = sourceId
        self.targetId = targetId
        self.relation = relation
        self.createdAt = createdAt
    }
}

extension Link: FetchableRecord, MutablePersistableRecord {
    public static var databaseTableName: String { "links" }

    // Foreign keys for association declarations.
    static let sourceForeignKey = ForeignKey(["sourceId"])
    static let targetForeignKey = ForeignKey(["targetId"])

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
