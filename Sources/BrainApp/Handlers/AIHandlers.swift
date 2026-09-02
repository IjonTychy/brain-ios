import Foundation
import BrainCore
import GRDB
import os.log

// MARK: - AI helper

private func aiComplete(provider: any LLMProvider, systemPrompt: String, userContent: String, maxTokens: Int = 2048) async throws -> String {
    let request = LLMRequest(
        messages: [
            LLMMessage(role: "user", content: "\(systemPrompt)\n\n\(userContent)")
        ],
        complexity: .high,
        maxTokens: maxTokens
    )
    let response = try await provider.complete(request)
    return response.content
}

// Strictest privacy zone level across the entries feeding a prompt.
// Raw-text inputs have no entry provenance and default to .unrestricted.
private func strictestPrivacyLevel(forEntryIds ids: [Int64], data: any DataProviding) -> PrivacyLevel {
    guard !ids.isEmpty else { return .unrestricted }
    let service = PrivacyZoneService(pool: data.databasePool)
    return (try? service.strictestLevel(forEntryIds: ids)) ?? .unrestricted
}

// Uniform error when no provider satisfies the constraints (privacy zone,
// offline, or missing key). All AI handlers are @MainActor, so the live
// connectivity read is safe here.
@MainActor private func noProviderError(privacyLevel: PrivacyLevel) -> ActionResult {
    .error(LLMProviderFactory.unavailableMessage(
        privacyLevel: privacyLevel,
        isConnected: NetworkMonitor.shared.isConnected
    ))
}

// MARK: - AI-powered handlers

@MainActor final class AISummarizeHandler: ActionHandler {
    let type = "ai.summarize"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        // Resolve the input first so entry provenance can drive the privacy zone.
        let text: String
        var sourceEntryIds: [Int64] = []
        if let bodyText = properties["text"]?.stringValue {
            text = bodyText
        } else if let id = properties["entryId"]?.intValue.flatMap({ Int64($0) }),
                  let entry = try data.fetchEntry(id: id) {
            text = "\(entry.title ?? "")\n\n\(entry.body ?? "")"
            sourceEntryIds = [id]
        } else {
            return .error("ai.summarize: text oder entryId erforderlich")
        }

        let privacyLevel = strictestPrivacyLevel(forEntryIds: sourceEntryIds, data: data)
        guard let provider = await data.buildLLMProvider(privacyLevel: privacyLevel), provider.isAvailable else {
            return noProviderError(privacyLevel: privacyLevel)
        }

        let summary = try await aiComplete(
            provider: provider,
            systemPrompt: "Fasse den folgenden Text kurz und praegnant zusammen. Antworte auf Deutsch.",
            userContent: text,
            maxTokens: 512
        )
        return .value(.string(summary))
    }
}

@MainActor final class AIExtractTasksHandler: ActionHandler {
    let type = "ai.extractTasks"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        // Resolve the input first so entry provenance can drive the privacy zone.
        let text: String
        var sourceEntryIds: [Int64] = []
        if let bodyText = properties["text"]?.stringValue {
            text = bodyText
        } else if let id = properties["entryId"]?.intValue.flatMap({ Int64($0) }),
                  let entry = try data.fetchEntry(id: id) {
            text = "\(entry.title ?? "")\n\n\(entry.body ?? "")"
            sourceEntryIds = [id]
        } else {
            return .error("ai.extractTasks: text oder entryId erforderlich")
        }

        let privacyLevel = strictestPrivacyLevel(forEntryIds: sourceEntryIds, data: data)
        guard let provider = await data.buildLLMProvider(privacyLevel: privacyLevel), provider.isAvailable else {
            return noProviderError(privacyLevel: privacyLevel)
        }

        let result = try await aiComplete(
            provider: provider,
            systemPrompt: """
                Extrahiere alle Aufgaben/Tasks aus dem folgenden Text.
                Antworte als JSON-Array mit Objekten: [{"title": "...", "priority": 0}]
                priority: 0=normal, 1=hoch, 2=dringend.
                Nur das JSON-Array, kein weiterer Text.
                """,
            userContent: text,
            maxTokens: 1024
        )

        // Parse JSON response into ExpressionValue
        if let data = result.data(using: .utf8),
           let tasks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let values = tasks.map { task -> ExpressionValue in
                .object([
                    "title": .string(task["title"] as? String ?? ""),
                    "priority": .int(task["priority"] as? Int ?? 0),
                ])
            }
            return .value(.array(values))
        }
        // Fallback: return raw text if JSON parsing fails
        return .value(.string(result))
    }
}

@MainActor final class AIBriefingHandler: ActionHandler {
    let type = "ai.briefing"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        // Gather context: recent entries, open tasks, calendar
        let recentEntries = try data.listEntries(limit: 10)
        let openTasks = recentEntries.filter { $0.type == .task && $0.status == .active }

        // The briefing prompt carries titles from these entries — honor the
        // strictest privacy zone among them.
        let privacyLevel = strictestPrivacyLevel(forEntryIds: recentEntries.compactMap(\.id), data: data)
        guard let provider = await data.buildLLMProvider(privacyLevel: privacyLevel), provider.isAvailable else {
            return noProviderError(privacyLevel: privacyLevel)
        }

        let todayEvents = await MainActor.run {
            let bridge = EventKitBridge()
            return bridge.todayEvents()
        }

        var contextParts: [String] = []

        if !openTasks.isEmpty {
            let taskList = openTasks.map { "- \($0.title ?? "Ohne Titel")" }.joined(separator: "\n")
            contextParts.append("Offene Aufgaben:\n\(taskList)")
        }

        if !todayEvents.isEmpty {
            let eventList = todayEvents.map { "- \($0.title) (\($0.isAllDay ? "Ganztaegig" : Self.timeFormatter.string(from: $0.startDate)))" }.joined(separator: "\n")
            contextParts.append("Heutige Termine:\n\(eventList)")
        }

        let recentNotes = recentEntries.filter { $0.type != .task }
        if !recentNotes.isEmpty {
            let noteList = recentNotes.prefix(5).map { "- \($0.title ?? "Ohne Titel")" }.joined(separator: "\n")
            contextParts.append("Letzte Einträge:\n\(noteList)")
        }

        let contextText = contextParts.isEmpty ? "Keine Daten vorhanden." : contextParts.joined(separator: "\n\n")

        let briefing = try await aiComplete(
            provider: provider,
            systemPrompt: """
                Du bist Brain, ein persoenlicher Assistent. Erstelle ein kurzes Morgen-Briefing auf Deutsch.
                Fasse zusammen: Was steht heute an? Welche Aufgaben sind offen? Welche Termine?
                Sei knapp und hilfreich. Maximal 5-6 Saetze.
                """,
            userContent: contextText,
            maxTokens: 512
        )
        return .value(.string(briefing))
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

@MainActor final class AIDraftReplyHandler: ActionHandler {
    let type = "ai.draftReply"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        // Raw text input — no entry provenance, so no privacy zone applies.
        guard let provider = await data.buildLLMProvider(), provider.isAvailable else {
            return noProviderError(privacyLevel: .unrestricted)
        }

        guard let originalText = properties["text"]?.stringValue else {
            return .error("ai.draftReply: text erforderlich")
        }
        let tone = properties["tone"]?.stringValue ?? "freundlich und professionell"
        let instructions = properties["instructions"]?.stringValue ?? ""

        var prompt = "Schreibe eine Antwort auf die folgende Nachricht. Ton: \(tone)."
        if !instructions.isEmpty {
            prompt += " Zusätzliche Anweisungen: \(instructions)"
        }
        prompt += " Antworte auf Deutsch."

        let reply = try await aiComplete(
            provider: provider,
            systemPrompt: prompt,
            userContent: originalText,
            maxTokens: 1024
        )
        return .value(.string(reply))
    }
}

@MainActor final class CrossRefHandler: ActionHandler {
    let type = "entry.crossref"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let entryId = properties["entryId"]?.intValue.flatMap({ Int64($0) }),
              let entry = try data.fetchEntry(id: entryId) else {
            return .error("entry.crossref: entryId fehlt oder Entry nicht gefunden")
        }

        // Get other entries for comparison
        let candidates = try data.listEntries(limit: 30)
            .filter { $0.id != entryId }

        if candidates.isEmpty {
            return .value(.array([]))
        }

        // The prompt carries the source entry AND candidate excerpts — honor
        // the strictest privacy zone across all of them.
        let involvedIds = [entryId] + candidates.compactMap(\.id)
        let privacyLevel = strictestPrivacyLevel(forEntryIds: involvedIds, data: data)
        guard let provider = await data.buildLLMProvider(privacyLevel: privacyLevel), provider.isAvailable else {
            return noProviderError(privacyLevel: privacyLevel)
        }

        let candidateList = candidates.compactMap { e -> String? in
            guard let id = e.id else { return nil }
            return "ID:\(id) | \(e.title ?? "Ohne Titel") | \(e.body?.prefix(100) ?? "")"
        }.joined(separator: "\n")

        let result = try await aiComplete(
            provider: provider,
            systemPrompt: """
                Finde verwandte Einträge zum Quell-Eintrag. Antworte als JSON-Array mit IDs
                der verwandten Einträge und einem Grund:
                [{"id": 123, "reason": "Gleiches Thema"}]
                Maximal 5 Ergebnisse. Nur das JSON-Array.
                """,
            userContent: "Quell-Eintrag: \(entry.title ?? "") | \(entry.body ?? "")\n\nKandidaten:\n\(candidateList)",
            maxTokens: 512
        )

        if let data = result.data(using: .utf8),
           let refs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let values = refs.map { ref -> ExpressionValue in
                .object([
                    "id": .int(ref["id"] as? Int ?? 0),
                    "reason": .string(ref["reason"] as? String ?? ""),
                ])
            }
            return .value(.array(values))
        }
        return .value(.string(result))
    }
}

// MARK: - LLM primitives

@MainActor final class LLMCompleteHandler: ActionHandler {
    let type = "llm.complete"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let prompt = properties["prompt"]?.stringValue else {
            return .error("llm.complete: prompt fehlt")
        }
        guard let provider = await data.buildLLMProvider() else {
            return noProviderError(privacyLevel: .unrestricted)
        }
        let system = properties["system"]?.stringValue
        let messages = [LLMMessage(role: "user", content: prompt)]
        let response = try await provider.complete(LLMRequest(messages: messages, systemPrompt: system))
        return .value(.string(response.content))
    }
}

@MainActor final class LLMStreamHandler: ActionHandler {
    let type = "llm.stream"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        // In action context, streaming collects full response (streaming UI is in ChatView)
        guard let prompt = properties["prompt"]?.stringValue else {
            return .error("llm.stream: prompt fehlt")
        }
        guard let provider = await data.buildLLMProvider() else {
            return noProviderError(privacyLevel: .unrestricted)
        }
        let messages = [LLMMessage(role: "user", content: prompt)]
        let response = try await provider.complete(LLMRequest(messages: messages))
        return .value(.string(response.content))
    }
}

@MainActor final class LLMEmbedHandler: ActionHandler {
    let type = "llm.embed"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let text = properties["text"]?.stringValue else {
            return .error("llm.embed: text fehlt")
        }
        let bridge = EmbeddingBridge(pool: data.databasePool)
        guard let embedding = bridge.embed(text: text) else {
            return .error("llm.embed: Embedding-Generierung fehlgeschlagen")
        }
        return .value(.object([
            "dimensions": .int(embedding.count),
            "status": .string("ok"),
        ]))
    }
}

@MainActor final class LLMClassifyHandler: ActionHandler {
    let type = "llm.classify"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let text = properties["text"]?.stringValue,
              let categories = properties["categories"]?.stringValue else {
            return .error("llm.classify: text und categories erforderlich")
        }
        guard let provider = await data.buildLLMProvider() else {
            return noProviderError(privacyLevel: .unrestricted)
        }
        let prompt = "Klassifiziere den folgenden Text in eine der Kategorien: \(categories)\n\nText: \(text)\n\nAntwort (nur die Kategorie):"
        let messages = [LLMMessage(role: "user", content: prompt)]
        let response = try await provider.complete(LLMRequest(messages: messages))
        return .value(.object([
            "category": .string(response.content.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]))
    }
}

@MainActor final class LLMExtractHandler: ActionHandler {
    let type = "llm.extract"
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let text = properties["text"]?.stringValue,
              let schema = properties["schema"]?.stringValue else {
            return .error("llm.extract: text und schema erforderlich")
        }
        guard let provider = await data.buildLLMProvider() else {
            return noProviderError(privacyLevel: .unrestricted)
        }
        let prompt = "Extrahiere die folgenden Felder aus dem Text als JSON: \(schema)\n\nText: \(text)\n\nJSON:"
        let messages = [LLMMessage(role: "user", content: prompt)]
        let response = try await provider.complete(LLMRequest(messages: messages, systemPrompt: "Du bist ein Datenextraktor. Antworte nur mit validem JSON."))
        return .value(.string(response.content))
    }
}
