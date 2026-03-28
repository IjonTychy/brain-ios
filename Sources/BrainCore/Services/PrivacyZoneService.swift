import GRDB

// Manages privacy zone rules: which tags restrict LLM routing.
public struct PrivacyZoneService: Sendable {

    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    // Set the privacy level for a tag. Upserts (creates or updates).
    @discardableResult
    public func setLevel(_ level: PrivacyLevel, forTagId tagId: Int64) throws -> PrivacyZone {
        try pool.write { db in
            // Check if a zone already exists for this tag
            if var existing = try PrivacyZone
                .filter(Column("tagId") == tagId)
                .fetchOne(db) {
                existing.level = level
                try existing.update(db)
                return existing
            } else {
                var zone = PrivacyZone(tagId: tagId, level: level)
                try zone.insert(db)
                return zone
            }
        }
    }

    // Remove the privacy zone for a tag (resets to unrestricted).
    public func removeZone(forTagId tagId: Int64) throws {
        try pool.write { db in
            _ = try PrivacyZone
                .filter(Column("tagId") == tagId)
                .deleteAll(db)
        }
    }

    // Fetch the privacy zone for a specific tag.
    public func zone(forTagId tagId: Int64) throws -> PrivacyZone? {
        try pool.read { db in
            try PrivacyZone
                .filter(Column("tagId") == tagId)
                .fetchOne(db)
        }
    }

    // List all configured privacy zones with their tag names.
    public func listAll() throws -> [(zone: PrivacyZone, tagName: String)] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT pz.*, t.name AS tagName
                FROM privacyZones pz
                JOIN tags t ON t.id = pz.tagId
                ORDER BY t.name ASC
                """)
            return try rows.map { row in
                let zone = try PrivacyZone(row: row)
                let tagName: String = row["tagName"]
                return (zone: zone, tagName: tagName)
            }
        }
    }

    // Determine the strictest privacy level for an entry based on its tags.
    // Returns .unrestricted if the entry has no privacy-restricted tags.
    public func strictestLevel(forEntryId entryId: Int64) throws -> PrivacyLevel {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT pz.level
                FROM privacyZones pz
                JOIN entryTags et ON et.tagId = pz.tagId
                WHERE et.entryId = ?
                """, arguments: [entryId])

            var strictest = PrivacyLevel.unrestricted
            for row in rows {
                if let levelStr: String = row["level"],
                   let level = PrivacyLevel(rawValue: levelStr) {
                    strictest = Self.stricter(strictest, level)
                }
            }
            return strictest
        }
    }

    // Determine the strictest privacy level across multiple entry IDs.
    public func strictestLevel(forEntryIds entryIds: [Int64]) throws -> PrivacyLevel {
        guard !entryIds.isEmpty else { return .unrestricted }
        let placeholders = entryIds.map { _ in "?" }.joined(separator: ",")
        return try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT pz.level
                FROM privacyZones pz
                JOIN entryTags et ON et.tagId = pz.tagId
                WHERE et.entryId IN (\(placeholders))
                """, arguments: StatementArguments(entryIds.map { DatabaseValue(value: $0) }))

            var strictest = PrivacyLevel.unrestricted
            for row in rows {
                if let levelStr: String = row["level"],
                   let level = PrivacyLevel(rawValue: levelStr) {
                    strictest = Self.stricter(strictest, level)
                }
            }
            return strictest
        }
    }

    // Determine the strictest privacy level for a set of tag names.
    // Used when the chat mentions tags but not specific entries.
    public func strictestLevel(forTagNames tagNames: [String]) throws -> PrivacyLevel {
        guard !tagNames.isEmpty else { return .unrestricted }
        let placeholders = tagNames.map { _ in "?" }.joined(separator: ",")
        return try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT pz.level
                FROM privacyZones pz
                JOIN tags t ON t.id = pz.tagId
                WHERE t.name IN (\(placeholders))
                """, arguments: StatementArguments(tagNames.map { DatabaseValue(value: $0) }))

            var strictest = PrivacyLevel.unrestricted
            for row in rows {
                if let levelStr: String = row["level"],
                   let level = PrivacyLevel(rawValue: levelStr) {
                    strictest = Self.stricter(strictest, level)
                }
            }
            return strictest
        }
    }

    // Compare two privacy levels and return the stricter one.
    // Order: onDeviceOnly > approvedCloudOnly > unrestricted
    private static func stricter(_ a: PrivacyLevel, _ b: PrivacyLevel) -> PrivacyLevel {
        let order: [PrivacyLevel: Int] = [.unrestricted: 0, .approvedCloudOnly: 1, .onDeviceOnly: 2]
        return (order[a, default: 0] >= order[b, default: 0]) ? a : b
    }
}
