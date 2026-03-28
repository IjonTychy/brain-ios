import GRDB

// A tag that can be applied to entries. Supports nested naming (e.g. "project/brain/ios").
public struct Tag: Codable, Sendable, Identifiable {
    public var id: Int64?
    public var name: String
    public var color: String?

    public init(id: Int64? = nil, name: String, color: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
    }
}

extension Tag: FetchableRecord, MutablePersistableRecord {
    public static var databaseTableName: String { "tags" }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// Join table record for the many-to-many relationship between entries and tags.
public struct EntryTag: Codable, Sendable {
    public var entryId: Int64
    public var tagId: Int64

    public init(entryId: Int64, tagId: Int64) {
        self.entryId = entryId
        self.tagId = tagId
    }
}

extension EntryTag: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "entryTags" }

    static let tagRelation = belongsTo(Tag.self)
    static let entryRelation = belongsTo(Entry.self)
}
