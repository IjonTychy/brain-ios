import Foundation
import BrainCore
import GRDB

// Phase 24: Conversation Memory — Cross-references between people, topics,
// and time. Enables queries like "Was hat Sarah letzte Woche gesagt?"
// and "Welche Themen waren im Januar wichtig?"

// No @MainActor needed — all methods are nonisolated and only access thread-safe pool.
// No @Observable needed — isAnalyzing is never observed by any view.
final class ConversationMemory: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    // MARK: - Person-Topic Cross-Reference

    // Find all entries mentioning a specific person.
    nonisolated func entriesAboutPerson(_ name: String, limit: Int = 20) throws -> [Entry] {
        try pool.read { db in
            try Entry
                .filter(Column("deletedAt") == nil)
                .filter(
                    Column("title").like("%\(name.escapedForLIKE())%", escape: "\\") ||
                    Column("body").like("%\(name.escapedForLIKE())%", escape: "\\")
                )
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // Find entries about a topic (via tags or text search).
    nonisolated func entriesAboutTopic(_ topic: String, limit: Int = 20) throws -> [Entry] {
        try pool.read { db in
            // First try FTS search
            let ftsResults = try Row.fetchAll(db, sql: """
                SELECT e.* FROM entries e
                JOIN entries_fts f ON f.rowid = e.id
                WHERE entries_fts MATCH ?
                AND e.deletedAt IS NULL
                ORDER BY e.createdAt DESC
                LIMIT ?
                """, arguments: [topic, limit])

            return ftsResults.compactMap { row -> Entry? in
                try? Entry(row: row)
            }
        }
    }

    // Find entries in a specific time range.
    nonisolated func entriesInTimeRange(from: Date, to: Date, limit: Int = 50) throws -> [Entry] {
        let formatter = DateFormatters.iso8601
        let fromStr = formatter.string(from: from)
        let toStr = formatter.string(from: to)

        return try pool.read { db in
            try Entry
                .filter(Column("deletedAt") == nil)
                .filter(Column("createdAt") >= fromStr)
                .filter(Column("createdAt") <= toStr)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Knowledge Graph Queries

    // Get all knowledge facts about a subject.
    nonisolated func factsAbout(subject: String) throws -> [KnowledgeFact] {
        try pool.read { db in
            try KnowledgeFact
                .filter(Column("subject").like("%\(subject.escapedForLIKE())%", escape: "\\"))
                .order(Column("confidence").desc)
                .fetchAll(db)
        }
    }

    // Find related topics through co-occurrence in entries.
    nonisolated func relatedTopics(for topic: String, limit: Int = 10) throws -> [(tag: String, count: Int)] {
        try pool.read { db in
            // Find entries matching the topic, then get their tags
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.name, COUNT(*) as cnt
                FROM tags t
                JOIN entryTags et ON et.tagId = t.id
                JOIN entries e ON e.id = et.entryId
                WHERE e.deletedAt IS NULL
                AND (e.title LIKE ? ESCAPE '\\' OR e.body LIKE ? ESCAPE '\\')
                GROUP BY t.name
                ORDER BY cnt DESC
                LIMIT ?
                """, arguments: ["%\(topic.escapedForLIKE())%", "%\(topic.escapedForLIKE())%", limit])

            return rows.compactMap { row -> (String, Int)? in
                guard let name: String = row["name"],
                      let count: Int = row["cnt"] else { return nil }
                return (name, count)
            }
        }
    }

    // MARK: - Timeline View Data

    struct TimelineEntry: Identifiable, Sendable {
        let id: Int64
        let title: String
        let type: String
        let date: Date
        let body: String?
    }

    // Get a timeline of entries for a specific month.
    nonisolated func timeline(year: Int, month: Int, limit: Int = 100) throws -> [TimelineEntry] {
        let startDate = String(format: "%04d-%02d-01", year, month)
        let endMonth = month == 12 ? 1 : month + 1
        let endYear = month == 12 ? year + 1 : year
        let endDate = String(format: "%04d-%02d-01", endYear, endMonth)

        return try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, title, type, createdAt, body
                FROM entries
                WHERE deletedAt IS NULL
                AND createdAt >= ? AND createdAt < ?
                ORDER BY createdAt DESC
                LIMIT ?
                """, arguments: [startDate, endDate, limit])

            let formatter = DateFormatters.iso8601

            return rows.compactMap { row -> TimelineEntry? in
                guard let id: Int64 = row["id"],
                      let title: String = row["title"],
                      let type: String = row["type"],
                      let dateStr: String = row["createdAt"] else { return nil }

                // Try multiple date formats
                let date = formatter.date(from: dateStr) ?? {
                    let f = DateFormatter()
                    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                    return f.date(from: dateStr) ?? Date()
                }()

                return TimelineEntry(
                    id: id,
                    title: title,
                    type: type,
                    date: date,
                    body: row["body"]
                )
            }
        }
    }

    // MARK: - Person Extraction from Entries

    // Extract frequently mentioned people from recent entries.
    nonisolated func frequentPeople(days: Int = 30, limit: Int = 10) throws -> [(name: String, count: Int)] {
        let entries = try pool.read { db in
            try Entry
                .filter(Column("deletedAt") == nil)
                .filter(sql: "createdAt > datetime('now', '-\(days) days')")
                .fetchAll(db)
        }

        // Extract names from all entries
        var nameCounts: [String: Int] = [:]
        for entry in entries {
            let text = [entry.title, entry.body].compactMap { $0 }.joined(separator: " ")
            let names = OnDeviceProvider.extractPersonNames(from: text)
            for name in names {
                nameCounts[name, default: 0] += 1
            }
        }

        return nameCounts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { ($0.key, $0.value) }
    }

    // MARK: - Skill Import Support

    // Import a .brainskill.md file from a URL or file path.
    nonisolated func importSkill(from content: String) throws -> Skill {
        // Parse YAML frontmatter
        let parts = content.components(separatedBy: "---")
        guard parts.count >= 3 else {
            throw SkillImportError.invalidFormat
        }

        let yamlSection = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let _ = parts.dropFirst(2).joined(separator: "---")

        // Simple YAML parsing for key fields
        var meta: [String: String] = [:]
        for line in yamlSection.split(separator: "\n") {
            let pair = line.split(separator: ":", maxSplits: 1)
            if pair.count == 2 {
                let key = String(pair[0]).trimmingCharacters(in: .whitespaces)
                let value = String(pair[1]).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                meta[key] = value
            }
        }

        guard let id = meta["id"], let name = meta["name"] else {
            throw SkillImportError.missingRequiredFields
        }

        let skill = Skill(
            id: id,
            name: name,
            description: meta["description"],
            version: meta["version"] ?? "1.0",
            screens: "{}",  // Will be compiled by the Skill Engine
            sourceMarkdown: content,
            createdBy: .import,
            enabled: true
        )

        return try pool.write { db in
            // Check for existing skill with same id
            if try Skill.fetchOne(db, key: id) != nil {
                throw SkillImportError.alreadyExists
            }
            let mutableSkill = skill
            try mutableSkill.insert(db)
            return mutableSkill
        }
    }
}

// MARK: - Errors

enum SkillImportError: Error, LocalizedError {
    case invalidFormat
    case missingRequiredFields
    case alreadyExists

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Ungültiges Skill-Format. Erwartet: YAML Frontmatter zwischen --- Markern."
        case .missingRequiredFields:
            return "Pflichtfelder fehlen: id und name sind erforderlich."
        case .alreadyExists:
            return "Ein Skill mit dieser ID existiert bereits."
        }
    }
}
