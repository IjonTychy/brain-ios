import Foundation
import GRDB

// GRDB record for storing entry embeddings as BLOBs.
public struct EntryEmbedding: Codable, Sendable, FetchableRecord {
    public var entryId: Int64
    public var embedding: Data
    public var model: String
    public var updatedAt: String?

    public init(entryId: Int64, embedding: Data, model: String) {
        self.entryId = entryId
        self.embedding = embedding
        self.model = model
    }
}

// Stores and retrieves embeddings from SQLite via GRDB.
public struct EmbeddingStore: Sendable {

    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    // Save or update an embedding for an entry (INSERT OR REPLACE).
    public func save(entryId: Int64, vector: [Float], model: String) throws {
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO entryEmbeddings (entryId, embedding, model, updatedAt)
                    VALUES (?, ?, ?, datetime('now'))
                    """,
                arguments: [entryId, VectorMath.serialize(vector), model]
            )
        }
    }

    // Save multiple embeddings in a single transaction.
    public func saveBatch(_ items: [(entryId: Int64, vector: [Float])], model: String) throws {
        try pool.write { db in
            for item in items {
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO entryEmbeddings (entryId, embedding, model, updatedAt)
                        VALUES (?, ?, ?, datetime('now'))
                        """,
                    arguments: [item.entryId, VectorMath.serialize(item.vector), model]
                )
            }
        }
    }

    // Fetch the embedding for a single entry.
    public func fetch(entryId: Int64) throws -> [Float]? {
        try pool.read { db in
            guard let record = try EntryEmbedding.fetchOne(
                db,
                sql: "SELECT * FROM entryEmbeddings WHERE entryId = ?",
                arguments: [entryId]
            ) else {
                return nil
            }
            return VectorMath.deserialize(record.embedding)
        }
    }

    // Fetch all embeddings (for brute-force KNN).
    public func fetchAll() throws -> [(entryId: Int64, vector: [Float])] {
        try pool.read { db in
            let records = try EntryEmbedding.fetchAll(db, sql: "SELECT * FROM entryEmbeddings")
            return records.map { (entryId: $0.entryId, vector: VectorMath.deserialize($0.embedding)) }
        }
    }

    // Delete embedding for an entry.
    public func delete(entryId: Int64) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM entryEmbeddings WHERE entryId = ?", arguments: [entryId])
        }
    }

    // Count of stored embeddings.
    public func count() throws -> Int {
        try pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entryEmbeddings") ?? 0
        }
    }

    // Entry IDs that have no embedding yet.
    public func entriesWithoutEmbedding(limit: Int = 100) throws -> [Entry] {
        try pool.read { db in
            let sql = """
                SELECT e.* FROM entries e
                LEFT JOIN entryEmbeddings ee ON ee.entryId = e.id
                WHERE ee.entryId IS NULL AND e.deletedAt IS NULL
                ORDER BY e.createdAt DESC
                LIMIT ?
                """
            return try Entry.fetchAll(db, sql: sql, arguments: [limit])
        }
    }
}
