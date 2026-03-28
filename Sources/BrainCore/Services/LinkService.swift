import GRDB

// Operations for bi-directional links between entries.
public struct LinkService: Sendable {

    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    // Create a link between two entries. The link is stored once but
    // queried in both directions.
    @discardableResult
    public func create(sourceId: Int64, targetId: Int64, relation: LinkRelation = .related) throws -> Link {
        guard sourceId != targetId else {
            throw LinkServiceError.selfLinkNotAllowed
        }
        return try pool.write { db in
            var link = Link(sourceId: sourceId, targetId: targetId, relation: relation)
            try link.insert(db)
            return link
        }
    }

    // Fetch all links for a given entry (where it appears as source or target).
    public func links(for entryId: Int64) throws -> [Link] {
        try pool.read { db in
            try Link
                .filter(Column("sourceId") == entryId || Column("targetId") == entryId)
                .fetchAll(db)
        }
    }

    // Batch-fetch links for multiple entries in a single query (avoids N+1).
    public func linksForEntries(_ ids: [Int64]) throws -> [Link] {
        guard !ids.isEmpty else { return [] }
        return try pool.read { db in
            try Link
                .filter(ids.contains(Column("sourceId")) || ids.contains(Column("targetId")))
                .fetchAll(db)
        }
    }

    // Fetch all entries linked to a given entry (bi-directional).
    public func linkedEntries(for entryId: Int64) throws -> [Entry] {
        try pool.read { db in
            let sql = """
                SELECT e.* FROM entries e
                WHERE e.deletedAt IS NULL
                  AND (e.id IN (SELECT targetId FROM links WHERE sourceId = ?)
                    OR e.id IN (SELECT sourceId FROM links WHERE targetId = ?))
                """
            return try Entry.fetchAll(db, sql: sql, arguments: [entryId, entryId])
        }
    }

    // Count total number of links in the database.
    public func count() throws -> Int {
        try pool.read { db in
            try Link.fetchCount(db)
        }
    }

    // Delete a link by id.
    public func delete(id: Int64) throws {
        try pool.write { db in
            _ = try Link.deleteOne(db, key: id)
        }
    }

    // Delete a link between two specific entries (in either direction).
    public func delete(between entryA: Int64, and entryB: Int64) throws {
        try pool.write { db in
            try db.execute(
                sql: """
                    DELETE FROM links
                    WHERE (sourceId = ? AND targetId = ?)
                       OR (sourceId = ? AND targetId = ?)
                    """,
                arguments: [entryA, entryB, entryB, entryA]
            )
        }
    }

    // MARK: - Extended queries

    // Fetch links for an entry, filtered by relation type.
    public func links(for entryId: Int64, relation: LinkRelation) throws -> [Link] {
        try pool.read { db in
            try Link
                .filter((Column("sourceId") == entryId || Column("targetId") == entryId)
                    && Column("relation") == relation)
                .fetchAll(db)
        }
    }

    // Count total links for an entry (bi-directional).
    public func linkCount(for entryId: Int64) throws -> Int {
        try pool.read { db in
            try Link
                .filter(Column("sourceId") == entryId || Column("targetId") == entryId)
                .fetchCount(db)
        }
    }

    // Get IDs of all entries linked to the given entry (lightweight, no Entry fetch).
    public func linkedEntryIds(for entryId: Int64) throws -> [Int64] {
        try pool.read { db in
            let links = try Link
                .filter(Column("sourceId") == entryId || Column("targetId") == entryId)
                .fetchAll(db)

            return links.map { link in
                link.sourceId == entryId ? link.targetId : link.sourceId
            }
        }
    }
}

// MARK: - Errors

public enum LinkServiceError: Error, Sendable {
    case selfLinkNotAllowed
}
