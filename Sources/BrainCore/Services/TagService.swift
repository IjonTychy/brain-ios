import GRDB

// CRUD and association operations for tags.
public struct TagService: Sendable {

    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    // Create a new tag.
    @discardableResult
    public func create(_ tag: Tag) throws -> Tag {
        try pool.write { db in
            var record = tag
            try record.insert(db)
            return record
        }
    }

    // Fetch a tag by id.
    public func fetch(id: Int64) throws -> Tag? {
        try pool.read { db in
            try Tag.fetchOne(db, key: id)
        }
    }

    // Fetch a tag by name.
    public func fetch(name: String) throws -> Tag? {
        try pool.read { db in
            try Tag.filter(Column("name") == name).fetchOne(db)
        }
    }

    // List all tags ordered by name.
    public func list() throws -> [Tag] {
        try pool.read { db in
            try Tag.order(Column("name")).fetchAll(db)
        }
    }

    // Attach a tag to an entry.
    public func attach(tagId: Int64, to entryId: Int64) throws {
        try pool.write { db in
            let record = EntryTag(entryId: entryId, tagId: tagId)
            try record.insert(db)
        }
    }

    // Detach a tag from an entry.
    public func detach(tagId: Int64, from entryId: Int64) throws {
        try pool.write { db in
            try db.execute(
                sql: "DELETE FROM entryTags WHERE entryId = ? AND tagId = ?",
                arguments: [entryId, tagId]
            )
        }
    }

    // List all tags for a given entry.
    public func tags(for entryId: Int64) throws -> [Tag] {
        try pool.read { db in
            try Tag
                .joining(required: Tag.hasMany(EntryTag.self).filter(Column("entryId") == entryId))
                .fetchAll(db)
        }
    }

    // Delete a tag (cascades through entryTags).
    public func delete(id: Int64) throws {
        try pool.write { db in
            _ = try Tag.deleteOne(db, key: id)
        }
    }

    // MARK: - Hierarchical queries

    // Find all tags whose name starts with the given prefix.
    // e.g. "projekt/" returns "projekt/brain", "projekt/brain/ios", etc.
    public func tagsUnder(prefix: String) throws -> [Tag] {
        try pool.read { db in
            try Tag
                .filter(Column("name").like("\(prefix.escapedForLIKE())%", escape: "\\"))
                .order(Column("name"))
                .fetchAll(db)
        }
    }

    // Find entries that have any tag matching the given prefix.
    public func entriesWithTagPrefix(_ prefix: String, limit: Int = 50) throws -> [Entry] {
        try pool.read { db in
            try Entry
                .filter(Column("deletedAt") == nil)
                .joining(required: Entry.entryTagsRelation
                    .joining(required: EntryTag.tagRelation
                        .filter(Column("name").like("\(prefix.escapedForLIKE())%", escape: "\\"))))
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // Count how many entries each tag has. Returns tuples sorted by count descending.
    public func tagCounts() throws -> [(tag: Tag, count: Int)] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.*, COUNT(e.id) AS entryCount
                FROM tags t
                LEFT JOIN entryTags et ON et.tagId = t.id
                LEFT JOIN entries e ON e.id = et.entryId AND e.deletedAt IS NULL
                GROUP BY t.id
                ORDER BY entryCount DESC, t.name ASC
                """)

            return try rows.map { row in
                let tag = try Tag(row: row)
                let count: Int = row["entryCount"]
                return (tag: tag, count: count)
            }
        }
    }
}
