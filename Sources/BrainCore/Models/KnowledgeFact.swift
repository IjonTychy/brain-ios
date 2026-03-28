import GRDB

// A learned fact stored as a subject-predicate-object triple.
public struct KnowledgeFact: Codable, Sendable, Identifiable {
    public var id: Int64?
    public var subject: String?
    public var predicate: String?
    public var object: String?
    public var confidence: Double
    public var sourceEntryId: Int64?
    public var sourceType: String?
    public var learnedAt: String?

    public init(
        id: Int64? = nil,
        subject: String? = nil,
        predicate: String? = nil,
        object: String? = nil,
        confidence: Double = 1.0,
        sourceEntryId: Int64? = nil,
        sourceType: String? = nil,
        learnedAt: String? = nil
    ) {
        self.id = id
        self.subject = subject
        self.predicate = predicate
        self.object = object
        self.confidence = confidence
        self.sourceEntryId = sourceEntryId
        self.sourceType = sourceType
        self.learnedAt = learnedAt
    }
}

extension KnowledgeFact: FetchableRecord, MutablePersistableRecord {
    public static var databaseTableName: String { "knowledgeFacts" }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
