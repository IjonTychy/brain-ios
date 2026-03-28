import Foundation
import BrainCore
import GRDB
import os.log

// MARK: - Semantic Search

@MainActor final class SemanticSearchHandler: ActionHandler {
    let type = "search.semantic"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let query = properties["query"]?.stringValue ?? ""
        let limit = properties["limit"]?.intValue ?? 10
        guard !query.isEmpty else { return .error("search.semantic: query fehlt") }

        let bridge = EmbeddingBridge(pool: data.databasePool)
        let results = try bridge.hybridSearch(query: query, limit: limit)
        let items = results.map { r -> ExpressionValue in
            .object([
                "id": .int(Int(r.entry.id ?? 0)),
                "title": .string(r.entry.title ?? ""),
                "type": .string(r.entry.type.rawValue),
                "similarity": .double(Double(r.similarity)),
                "body": .string(String((r.entry.body ?? "").prefix(200))),
            ])
        }
        return .value(.array(items))
    }
}

@MainActor final class EntrySimilarHandler: ActionHandler {
    let type = "entry.similar"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let entryId = properties["entry_id"]?.intValue
        let limit = properties["limit"]?.intValue ?? 5
        guard let entryId else { return .error("entry.similar: entry_id fehlt") }

        let service = SemanticSearchService(pool: data.databasePool)
        let results = try service.findSimilar(to: Int64(entryId), limit: limit)
        let items = results.map { r -> ExpressionValue in
            .object([
                "id": .int(Int(r.entry.id ?? 0)),
                "title": .string(r.entry.title ?? ""),
                "type": .string(r.entry.type.rawValue),
                "similarity": .double(Double(r.similarity)),
                "body": .string(String((r.entry.body ?? "").prefix(200))),
            ])
        }
        return .value(.array(items))
    }
}

// MARK: - Conversation Memory Handlers

// Helper to convert Entry to ExpressionValue (broken out to help type-checker).
private func entryToExpressionValue(_ entry: Entry) -> ExpressionValue {
    let id: ExpressionValue = .int(Int(entry.id ?? 0))
    let title: ExpressionValue = .string(entry.title ?? "(ohne Titel)")
    let type: ExpressionValue = .string(entry.type.rawValue)
    let date: ExpressionValue = .string(entry.createdAt ?? "")
    let snippet: ExpressionValue = .string(String((entry.body ?? "").prefix(200)))
    return .object(["id": id, "title": title, "type": type, "date": date, "snippet": snippet])
}

// Handlers use DatabasePool directly with nonisolated ConversationMemory methods.
@MainActor final class MemorySearchPersonHandler: ActionHandler {
    let type = "memory.searchPerson"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let name = properties["name"]?.stringValue else {
            return .actionError(code: "memory.missing_name", message: "Name ist erforderlich")
        }
        let limit = properties["limit"]?.intValue ?? 10
        let memory = ConversationMemory(pool: data.databasePool)
        let entries = try memory.entriesAboutPerson(name, limit: limit)
        let results = entries.map(entryToExpressionValue)
        return .value(.object([
            "person": .string(name),
            "count": .int(results.count),
            "entries": .array(results)
        ]))
    }
}

@MainActor final class MemorySearchTopicHandler: ActionHandler {
    let type = "memory.searchTopic"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let topic = properties["topic"]?.stringValue else {
            return .actionError(code: "memory.missing_topic", message: "Thema ist erforderlich")
        }
        let limit = properties["limit"]?.intValue ?? 10
        let memory = ConversationMemory(pool: data.databasePool)
        let entries = try memory.entriesAboutTopic(topic, limit: limit)
        let results = entries.map(entryToExpressionValue)
        return .value(.object([
            "topic": .string(topic),
            "count": .int(results.count),
            "entries": .array(results)
        ]))
    }
}

@MainActor final class MemoryFactsHandler: ActionHandler {
    let type = "memory.facts"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let subject = properties["subject"]?.stringValue else {
            return .actionError(code: "memory.missing_subject", message: "Subjekt ist erforderlich")
        }
        let memory = ConversationMemory(pool: data.databasePool)
        let facts = try memory.factsAbout(subject: subject)
        var results: [ExpressionValue] = []
        for fact in facts {
            let subj: ExpressionValue = .string(fact.subject ?? "")
            let pred: ExpressionValue = .string(fact.predicate ?? "")
            let obj: ExpressionValue = .string(fact.object ?? "")
            let conf: ExpressionValue = .double(fact.confidence)
            results.append(.object(["subject": subj, "predicate": pred, "object": obj, "confidence": conf]))
        }
        return .value(.object([
            "subject": .string(subject),
            "count": .int(results.count),
            "facts": .array(results)
        ]))
    }
}

// MARK: - On This Day Handler

@MainActor final class OnThisDayHandler: ActionHandler {
    let type = "onthisday.list"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let limit = properties["limit"]?.intValue ?? 20
        let pool = data.databasePool

        let entries = try await pool.read { db in
            try Entry.fetchAll(db, sql: """
                SELECT * FROM entries
                WHERE deletedAt IS NULL
                AND strftime('%m-%d', createdAt) = strftime('%m-%d', 'now')
                AND DATE(createdAt) != DATE('now')
                ORDER BY createdAt DESC
                LIMIT ?
            """, arguments: [limit])
        }

        let items = entries.map { entry -> ExpressionValue in
            .object([
                "id": .int(Int(entry.id ?? 0)),
                "title": .string(entry.title ?? ""),
                "type": .string(entry.type.rawValue),
                "body": .string(String((entry.body ?? "").prefix(200))),
                "createdAt": .string(entry.createdAt ?? ""),
            ])
        }
        return .value(.object([
            "entries": .array(items),
            "count": .int(entries.count),
        ]))
    }
}

// MARK: - User Profile Handler

/// Returns the full user profile (Brain profile markdown + all knowledge facts about User).
/// This is the "pull" counterpart to the lean system prompt — the LLM calls this
/// when it needs more context about the user instead of having everything pre-loaded.
@MainActor final class UserProfileHandler: ActionHandler {
    let type = "user.profile"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let pool = data.databasePool

        // Brain profile markdown (user-written)
        let brainProfile = UserDefaults.standard.string(forKey: "brainProfileMarkdown") ?? ""

        // User profile markdown (user-written)
        let userProfile = UserDefaults.standard.string(forKey: "userProfileMarkdown") ?? ""

        // All knowledge facts about the user (higher limit than system prompt)
        let facts: [ExpressionValue] = try await pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT subject, predicate, object, confidence FROM knowledgeFacts
                WHERE confidence >= 0.5
                ORDER BY confidence DESC
                LIMIT 100
                """)
            return rows.compactMap { row -> ExpressionValue? in
                guard let subj: String = row[0],
                      let pred: String = row[1],
                      let obj: String = row[2] else { return nil }
                let conf: Double = row[3] ?? 0.5
                return .object([
                    "subject": .string(subj),
                    "predicate": .string(pred),
                    "object": .string(obj),
                    "confidence": .double(conf)
                ])
            }
        }

        return .value(.object([
            "brainProfile": .string(brainProfile),
            "userProfile": .string(userProfile),
            "knowledgeFacts": .array(facts),
            "factCount": .int(facts.count),
        ]))
    }
}

// MARK: - Backup Export Handler

@MainActor final class BackupExportHandler: ActionHandler {
    let type = "backup.export"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let pool = data.databasePool

        let entries = try await pool.read { db in try Entry.fetchAll(db) }
        let tags = try await pool.read { db in try Tag.fetchAll(db) }

        let data: [String: Any] = [
            "version": "1.0",
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "entries": entries.count,
            "tags": tags.count,
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let json = String(data: jsonData, encoding: .utf8) {
            return .value(.object([
                "status": .string("success"),
                "summary": .string("Export: \(entries.count) Entries, \(tags.count) Tags"),
                "json": .string(json),
            ]))
        }
        return .error("backup.export: JSON-Serialisierung fehlgeschlagen")
    }
}
