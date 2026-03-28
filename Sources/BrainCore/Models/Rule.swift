import GRDB

// A rule in the self-modifier rules engine.
// Rules define automated behaviors triggered by conditions.
public struct Rule: Codable, Sendable, Identifiable {
    public var id: Int64?
    public var category: String
    public var name: String
    public var condition: String?  // JSON
    public var action: String      // JSON
    public var priority: Int
    public var enabled: Bool
    public var createdAt: String?
    public var modifiedAt: String?
    public var modifiedBy: String

    public init(
        id: Int64? = nil,
        category: String,
        name: String,
        condition: String? = nil,
        action: String,
        priority: Int = 0,
        enabled: Bool = true,
        createdAt: String? = nil,
        modifiedAt: String? = nil,
        modifiedBy: String = "system"
    ) {
        self.id = id
        self.category = category
        self.name = name
        self.condition = condition
        self.action = action
        self.priority = priority
        self.enabled = enabled
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.modifiedBy = modifiedBy
    }
}

extension Rule: FetchableRecord, MutablePersistableRecord {
    public static var databaseTableName: String { "rules" }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
