import GRDB

// Full-text search result with ranking score.
public struct SearchResult: Sendable {
    public let entry: Entry
    public let score: Double
}

// FTS5-based full-text search over entries.
public struct SearchService: Sendable {

    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    // Sanitize user input for FTS5 MATCH queries (F-09).
    // Wraps each token in double quotes to prevent FTS5 operator injection
    // (AND, OR, NOT, NEAR, *, column filters like title:).
    // Appends * for prefix matching so "Bra" finds "Brain".
    private func sanitizeFTS5Query(_ query: String) -> String {
        let tokens = query.split(separator: " ", omittingEmptySubsequences: true)
        guard !tokens.isEmpty else { return "\"\"" }
        return tokens.map { token in
            let cleaned = token.replacingOccurrences(of: "\"", with: "")
            return "\"\(cleaned)\"*"
        }.joined(separator: " ")
    }

    // Search entries using FTS5. Returns results ranked by relevance.
    public func search(query: String, limit: Int = 20) throws -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return try pool.read { db in
            let sql = """
                SELECT entries.*, bm25(entries_fts) AS score
                FROM entries_fts
                JOIN entries ON entries.id = entries_fts.rowid
                WHERE entries_fts MATCH ?
                  AND entries.deletedAt IS NULL
                ORDER BY score
                LIMIT ?
                """
            let rows = try Row.fetchAll(db, sql: sql, arguments: [sanitizeFTS5Query(query), min(limit, 500)])
            return try rows.map { row in
                let entry = try Entry(row: row)
                let score = row["score"] as? Double ?? 0.0
                return SearchResult(entry: entry, score: score)
            }
        }
    }

    // MARK: - Advanced search

    // Search with FTS5 and additional filters (type, status, tags).
    public func searchWithFilters(
        query: String,
        tags: [String]? = nil,
        type: EntryType? = nil,
        status: EntryStatus? = nil,
        limit: Int = 20
    ) throws -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return try pool.read { db in
            var conditions = ["entries.deletedAt IS NULL"]
            var args: [any DatabaseValueConvertible] = [sanitizeFTS5Query(query)]

            if let type {
                conditions.append("entries.type = ?")
                args.append(type.rawValue)
            }
            if let status {
                conditions.append("entries.status = ?")
                args.append(status.rawValue)
            }

            var tagJoin = ""
            if let tags, !tags.isEmpty {
                // Require entry to have at least one of the specified tags
                let placeholders = tags.map { _ in "?" }.joined(separator: ", ")
                tagJoin = """
                    AND entries.id IN (
                        SELECT et.entryId FROM entryTags et
                        JOIN tags t ON t.id = et.tagId
                        WHERE t.name IN (\(placeholders))
                    )
                    """
                args.append(contentsOf: tags)
            }

            args.append(limit)

            let sql = """
                SELECT entries.*, bm25(entries_fts) AS score
                FROM entries_fts
                JOIN entries ON entries.id = entries_fts.rowid
                WHERE entries_fts MATCH ?
                  AND \(conditions.joined(separator: " AND "))
                  \(tagJoin)
                ORDER BY score
                LIMIT ?
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return try rows.map { row in
                let entry = try Entry(row: row)
                let score: Double = row["score"] ?? 0.0
                return SearchResult(entry: entry, score: score)
            }
        }
    }

    // Search with custom BM25 weights for title vs body.
    // Lower scores = better match in FTS5 BM25.
    public func searchWithWeights(
        query: String,
        titleWeight: Double = 10.0,
        bodyWeight: Double = 1.0,
        limit: Int = 20
    ) throws -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return try pool.read { db in
            let sql = """
                SELECT entries.*, bm25(entries_fts, ?, ?) AS score
                FROM entries_fts
                JOIN entries ON entries.id = entries_fts.rowid
                WHERE entries_fts MATCH ?
                  AND entries.deletedAt IS NULL
                ORDER BY score
                LIMIT ?
                """
            let rows = try Row.fetchAll(db, sql: sql, arguments: [titleWeight, bodyWeight, sanitizeFTS5Query(query), min(limit, 500)])
            return try rows.map { row in
                let entry = try Entry(row: row)
                let score: Double = row["score"] ?? 0.0
                return SearchResult(entry: entry, score: score)
            }
        }
    }

    // Autocomplete entry titles using FTS5 prefix matching.
    public func autocomplete(prefix: String, limit: Int = 10) throws -> [Entry] {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // FTS5 prefix query: sanitize then append * for prefix matching (F-09)
        let sanitized = sanitizeFTS5Query(trimmed)
        let ftsQuery = "\(sanitized)*"

        return try pool.read { db in
            let sql = """
                SELECT entries.*
                FROM entries_fts
                JOIN entries ON entries.id = entries_fts.rowid
                WHERE entries_fts MATCH ?
                  AND entries.deletedAt IS NULL
                ORDER BY bm25(entries_fts)
                LIMIT ?
                """
            return try Entry.fetchAll(db, sql: sql, arguments: [ftsQuery, min(limit, 100)])
        }
    }
}
