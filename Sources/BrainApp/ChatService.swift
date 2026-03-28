import Foundation
import BrainCore
import GRDB

// Manages chat conversations with tool-use support.
// When the user sends a message, Brain can use tools (entry.create, calendar.list, etc.)
// to actually perform actions, not just talk about them.
@MainActor @Observable
final class ChatService {
    private(set) var messages: [ChatMessage] = []
    private(set) var isStreaming = false
    private(set) var streamingContent = ""
    private(set) var activeToolCalls: [ToolCallStatus] = []
    private(set) var elapsedSeconds: Int = 0
    private(set) var liveInputTokens: Int = 0
    private(set) var liveOutputTokens: Int = 0
    private var streamingTimer: Task<Void, Never>?
    // K2: Guard against concurrent send() calls
    private(set) var isSending = false
    var error: String?
    // Set by Siri/Shortcuts to pre-fill the next message.
    var pendingInput: String?
    // Extra context injected into system prompt (set by BrainAssistantSheet)
    var contextPromptExtra: String?
    // When true, uses .skillCreation context instead of .chat
    var isSkillCreatorMode = false

    private let pool: DatabasePool
    private let memory: ConversationMemory
    private let keychain = KeychainService()
    private var currentTask: Task<Void, Never>?
    private var router: LLMRouter?

    // Action handlers for executing tool calls
    private var handlers: [String: any ActionHandler] = [:]

    // Confirmation callback for destructive tool calls.
    // Receives (toolName, humanReadableDescription) and returns true to proceed.
    // If nil, destructive tools are blocked by default.
    var behaviorTracker: BehaviorTracker?
    var confirmationHandler: (@Sendable (String, String) async -> Bool)?

    // Tools that require explicit user confirmation before execution.
    // nonisolated: accessed from @Sendable closures in streamWithTools.
    // Tools requiring user confirmation before execution.
    // Configurable via UserDefaults("destructiveTools") — Brain or user can add/remove.
    // Default: irreversible or externally-visible actions.
    nonisolated static var destructiveTools: Set<String> {
        if let custom = UserDefaults.standard.stringArray(forKey: "destructiveTools") {
            return Set(custom)
        }
        return defaultDestructiveTools
    }

    private nonisolated static let defaultDestructiveTools: Set<String> = [
        "email_send",       // sends to external recipient — irreversible
        "entry_delete",     // soft-delete, but user expects confirmation
        "calendar_delete",  // deletes from system calendar
        "contact_delete",   // deletes from iOS contacts
    ]

    init(pool: DatabasePool) {
        self.pool = pool
        self.memory = ConversationMemory(pool: pool)
        loadMessages()
    }

    // Register action handlers so the chat can execute tools.
    func setHandlers(_ handlerList: [any ActionHandler]) {
        for handler in handlerList {
            handlers[handler.type] = handler
        }
    }

    // Configure the LLM router for provider selection.
    func setRouter(_ router: LLMRouter) {
        self.router = router
    }

    // MARK: - Message loading

    func loadMessages() {
        do {
            messages = try pool.read { db in
                try ChatMessage
                    .order(Column("createdAt").asc)
                    .fetchAll(db)
            }
        } catch {
            self.error = "Nachrichten laden fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    // MARK: - Send message (with tool-use streaming)

    /// The model override for the next message (set by ChatView's model picker).
    /// If nil, uses the global selectedModel from UserDefaults.
    var chatModelOverride: String?

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // K2: Prevent concurrent send calls (double-tap protection)
        guard !isSending else { return }
        isSending = true

        // Save user message
        var userMsg = ChatMessage(role: .user, content: trimmed)
        do {
            try pool.write { db in
                try userMsg.insert(db)
            }
            messages.append(userMsg)
        } catch {
            self.error = "Nachricht speichern fehlgeschlagen"
            self.isSending = false
            return
        }

        // Send to LLM with tool-use streaming
        currentTask?.cancel()
        currentTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            self.isStreaming = true
            self.streamingContent = ""
            self.activeToolCalls = []
            self.error = nil
            self.elapsedSeconds = 0
            self.liveInputTokens = 0
            self.liveOutputTokens = 0
            // Start elapsed-time counter
            self.streamingTimer?.cancel()
            self.streamingTimer = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { break }
                    self?.elapsedSeconds += 1
                }
            }

            do {
                // Build conversation (last 20 messages)
                let recentMessages = Array(self.messages.suffix(20))
                let llmMessages = recentMessages.map { msg in
                    LLMMessage(role: msg.role.rawValue, content: msg.content)
                }

                // Phase 31: Determine privacy level from conversation context.
                // Check if any recently referenced tags have privacy restrictions.
                let privacyLevel = self.detectPrivacyLevel()

                // Build memory context from user's latest message (off main thread)
                let capturedMemory = self.memory
                let memoryContext = await Task.detached {
                    ChatService.buildMemoryContext(for: trimmed, memory: capturedMemory)
                }.value

                let complexity = self.detectComplexity(trimmed)
                let request = LLMRequest(
                    messages: llmMessages,
                    systemPrompt: self.isSkillCreatorMode ? SystemPromptBuilder(pool: self.pool).build(for: .skillCreation) : SystemPromptBuilder(pool: self.pool).build(memoryContext: memoryContext, contextExtra: self.contextPromptExtra),
                    complexity: complexity,
                    maxTokens: 4096,
                    privacyLevel: privacyLevel
                )

                // Auto-route model based on complexity if enabled and no manual override
                if self.chatModelOverride == nil,
                   UserDefaults.standard.bool(forKey: "autoRouteModels") {
                    let modelKey: String
                    switch complexity {
                    case .low: modelKey = "model.low"
                    case .medium: modelKey = "model.medium"
                    case .high: modelKey = "model.high"
                    }
                    if privacyLevel == .onDeviceOnly {
                        self.chatModelOverride = UserDefaults.standard.string(forKey: "model.private") ?? "on-device"
                    } else if let routedModel = UserDefaults.standard.string(forKey: modelKey) {
                        self.chatModelOverride = routedModel
                    }
                }

                guard let provider = await self.buildProvider(for: request) else {
                    self.error = "Kein API-Key konfiguriert. Bitte in den Einstellungen hinterlegen."
                    self.isStreaming = false
                    self.isSending = false
                    self.streamingTimer?.cancel()
                    return
                }

                // Phase 30: Budget check before LLM call
                let budgetLimit = UserDefaults.standard.double(forKey: "llmMonthlyBudget")
                if budgetLimit > 0 {
                    let costTracker = CostTracker(pool: self.pool)
                    let remaining = try? costTracker.remainingBudget(monthlyLimitEuros: budgetLimit)
                    if let remaining, remaining <= 0 {
                        self.error = "Monatsbudget (\(String(format: "%.2f", budgetLimit))€) aufgebraucht. Erhöhe das Limit in den Einstellungen."
                        self.isStreaming = false
                        self.isSending = false
                        return
                    }
                }

                // Build tools array for API
                let tools = BrainTools.all.map { $0.toJSON() }

                // Stream with tool-use support
                var fullContent = ""
                var totalInputTokens = 0
                var totalOutputTokens = 0
                // Mirror running totals to live UI properties (inlined below)
                // nonisolated(unsafe): handlers dict is captured as a snapshot, not mutated during streaming.
                // The @Sendable closure in streamWithTools requires Sendable captures, but [String: any ActionHandler]
                // is not Sendable since ActionHandler no longer requires it. Safe because handlers are immutable after setup.
                nonisolated(unsafe) let capturedHandlers = self.handlers
                let capturedConfirmHandler = self.confirmationHandler

                for try await event in provider.streamWithTools(request, tools: tools, executeToolCall: { toolName, toolInput in
                    // Execute tool call via ActionHandler
                    guard let handlerType = BrainTools.toolNameToHandlerType[toolName],
                          let handler = capturedHandlers[handlerType] else {
                        return "{\"error\": \"Unknown tool: \(toolName)\"}"
                    }

                    // Gate: require user confirmation for destructive tools
                    if ChatService.destructiveTools.contains(toolName) {
                        let description = BrainTools.describeToolCall(toolName, input: toolInput)
                        if let confirm = capturedConfirmHandler {
                            let approved = await confirm(toolName, description)
                            if !approved {
                                return "{\"error\": \"Aktion vom Benutzer abgelehnt: \(toolName)\"}"
                            }
                        } else {
                            // No confirmation handler set — block by default
                            return "{\"error\": \"Destruktive Aktion blockiert (kein Bestätigungsdialog konfiguriert): \(toolName)\"}"
                        }
                    }

                    let properties = BrainTools.convertInput(toolInput)
                    let context = ExpressionContext(variables: [:])
                    let result = try await handler.execute(properties: properties, context: context)
                // Track tool usage for behavior learning
                await MainActor.run {
                    self.behaviorTracker?.recordToolUsed(toolName: toolName)
                }
                    return BrainTools.resultToString(result)
                }) {
                    guard !Task.isCancelled else { return }
                    switch event {
                    case .text(let token):
                        fullContent += token
                        self.streamingContent = fullContent
                        // Rough estimate: ~4 chars per token for output
                        totalOutputTokens = max(totalOutputTokens, fullContent.count / 4)
                        self.liveInputTokens = totalInputTokens
                        self.liveOutputTokens = totalOutputTokens
                    case .toolStart(let name):
                        self.activeToolCalls.append(ToolCallStatus(name: name, isRunning: true))
                    case .toolResult(let name, let result):
                        // Mark tool as completed
                        if let idx = self.activeToolCalls.lastIndex(where: { $0.name == name && $0.isRunning }) {
                            self.activeToolCalls[idx].isRunning = false
                            self.activeToolCalls[idx].result = String(result.prefix(200))
                        }
                    case .usage(let input, let output):
                        totalInputTokens += input
                        totalOutputTokens += output
                    }
                }

                guard !Task.isCancelled else { return }

                // Save assistant message (full text content)
                let usedModel = self.chatModelOverride ?? UserDefaults.standard.string(forKey: "selectedModel") ?? "claude-opus-4-6"
                if !fullContent.isEmpty {
                    let assistantMsg = ChatMessage(role: .assistant, content: fullContent, model: usedModel)
                    try await self.pool.write { [assistantMsg] db in
                        var msg = assistantMsg
                        try msg.insert(db)
                    }
                    self.messages.append(assistantMsg)
                }

                // Also save a summary of tool calls if there were any
                if !self.activeToolCalls.isEmpty && fullContent.isEmpty {
                    // Claude only used tools without text — save a placeholder
                    let toolSummary = self.activeToolCalls.map { "[\($0.name)]" }.joined(separator: " ")
                    let assistantMsg = ChatMessage(role: .assistant, content: "Erledigt. (Tools: \(toolSummary))", model: usedModel)
                    try await self.pool.write { [assistantMsg] db in
                        var msg = assistantMsg
                        try msg.insert(db)
                    }
                    self.messages.append(assistantMsg)
                }

                self.streamingContent = ""

                // Extract knowledge from chat (both user message and assistant response)
                Task.detached { [pool = self.pool, userText = trimmed, assistantText = fullContent] in
                    ChatKnowledgeExtractor.extractFromConversation(
                        userMessage: userText,
                        assistantResponse: assistantText,
                        pool: pool
                    )
                }

                // Phase 30: Track LLM usage costs
                if totalInputTokens > 0 || totalOutputTokens > 0 {
                    let costTracker = CostTracker(pool: self.pool)
                    let providerName = provider.name
                    let selectedModelId = UserDefaults.standard.string(forKey: "selectedModel") ?? "claude-opus-4-6"
                    let modelName = (provider as? AnthropicProvider != nil) ? selectedModelId : providerName
                    try? costTracker.record(
                        provider: providerName,
                        model: modelName,
                        inputTokens: totalInputTokens,
                        outputTokens: totalOutputTokens,
                        requestType: self.activeToolCalls.isEmpty ? "chat" : "tool"
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "Fehler: \(error.localizedDescription)"
            }

            self.isStreaming = false
            self.isSending = false
            self.streamingTimer?.cancel()
        }
    }

    // MARK: - Cancel

    func cancelStream() {
        currentTask?.cancel()
        isStreaming = false
        isSending = false
        streamingContent = ""
        activeToolCalls = []
        streamingTimer?.cancel()
    }

    // Retry the last user message (after an error).
    func retryLastMessage() {
        guard let lastUserMsg = messages.last(where: { $0.role == .user }) else { return }
        // Remove the failed assistant message if it's the last one
        if let lastMsg = messages.last, lastMsg.role == .assistant {
            messages.removeLast()
        }
        send(lastUserMsg.content)
    }

    // MARK: - Clear history

    func clearHistory() {
        do {
            _ = try pool.write { db in
                try ChatMessage.deleteAll(db)
            }
            messages = []
        } catch {
            self.error = "Verlauf löschen fehlgeschlagen"
        }
    }

    // MARK: - Provider

    private func buildProvider(for request: LLMRequest) async -> (any ToolUseProvider)? {
        // Try router first (F-04: use LLMRouter for sensitivity-aware routing)
        if let router = self.router,
           let provider = router.route(request) as? any ToolUseProvider {
            return provider
        }
        let selectedModel = chatModelOverride ?? UserDefaults.standard.string(forKey: "selectedModel") ?? "claude-opus-4-6"

        // Route to On-Device provider if explicitly selected or auto-routed via privacy zones.
        // OnDeviceProvider conforms to LLMProvider but not ToolUseProvider (no tool-use support).
        // When on-device is requested but not available, fall through to cloud providers.
        // TODO: Add ToolUseProvider conformance to OnDeviceProvider (stub that disables tools)
        //       or refactor buildProvider() to return (any LLMProvider)? for tool-less chat.
        if selectedModel == "on-device" || selectedModel.hasPrefix("on-device") {
            let provider = OnDeviceProvider()
            if provider.isAvailable, let toolProvider = provider as? any ToolUseProvider {
                return toolProvider
            }
            // On-device not available or doesn't support tools — fall through to cloud
        }

        // Cache API keys once to avoid redundant Keychain reads (each read triggers Face ID)
        let cachedAnthropicKey = keychain.read(key: KeychainKeys.anthropicAPIKey) ?? ""
        let cachedGeminiKey = selectedModel.hasPrefix("gemini")
            ? (keychain.read(key: KeychainKeys.geminiAPIKey) ?? "") : ""

        // Route to Gemini if a Gemini model is selected
        if selectedModel.hasPrefix("gemini") {
            if !cachedGeminiKey.isEmpty {
                return GeminiProvider(apiKey: cachedGeminiKey, model: selectedModel)
            }
            if let token = try? await GoogleOAuthService().getValidToken() {
                return GeminiProvider(oauthToken: token, model: selectedModel)
            }
        }

        // Route to OpenAI if a GPT/o-series model is selected
        if selectedModel.hasPrefix("gpt-") || selectedModel.hasPrefix("o") {
            let openAIKey = keychain.read(key: KeychainKeys.openAIAPIKey) ?? ""
            if !openAIKey.isEmpty {
                return OpenAIProvider(apiKey: openAIKey, model: selectedModel)
            }
        }

        // Route to xAI if a Grok model is selected
        if selectedModel.hasPrefix("grok") {
            let xaiKey = keychain.read(key: KeychainKeys.xaiAPIKey) ?? ""
            if !xaiKey.isEmpty {
                return OpenAICompatibleProvider(
                    baseURL: "https://api.x.ai",
                    model: selectedModel,
                    apiKey: xaiKey,
                    providerName: "Grok"
                )
            }
        }

        // Route to custom endpoint if model matches
        if let endpoints = AvailableModels.loadCustomEndpoints() {
            for endpoint in endpoints where endpoint.model == selectedModel {
                // API key is stored in Keychain (AP5), not in the endpoint struct.
                let customApiKey = AvailableModels.apiKey(for: endpoint.name)
                return OpenAICompatibleProvider(
                    baseURL: endpoint.baseURL,
                    model: endpoint.model,
                    apiKey: customApiKey,
                    providerName: endpoint.name
                )
            }
        }

        // Claude (default): Check configured mode, then auto-detect
        let mode = UserDefaults.standard.string(forKey: "anthropicMode") ?? "api"
        switch mode {
        case "proxy":
            if let provider = await buildProxyProvider() { return provider }
        case "max":
            if let sessionKey = keychain.read(key: KeychainKeys.anthropicMaxSessionKey), !sessionKey.isEmpty {
                return AnthropicProvider(sessionKey: sessionKey, model: selectedModel)
            }
        case "api":
            let provider = AnthropicProvider(apiKey: cachedAnthropicKey, model: selectedModel)
            if provider.isAvailable { return provider }
        default:
            break
        }
        // Fallback chain: proxy → max → api
        if let provider = await buildProxyProvider() { return provider }
        if let sessionKey = keychain.read(key: KeychainKeys.anthropicMaxSessionKey), !sessionKey.isEmpty {
            return AnthropicProvider(sessionKey: sessionKey, model: selectedModel)
        }
        let provider = AnthropicProvider(apiKey: cachedAnthropicKey, model: selectedModel)
        return provider.isAvailable ? provider : nil
    }

    /// Build proxy provider with JWT auth token from BrainAPIAuthService.
    /// Appends /claude-proxy to the base URL since the VPS routes LLM calls through that path.
    private func buildProxyProvider() async -> AnthropicProvider? {
        guard let baseURL = keychain.read(key: KeychainKeys.anthropicProxyURL), !baseURL.isEmpty else {
            return nil
        }
        let selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "claude-opus-4-6"
        let token = await BrainAPIAuthService.shared.getValidToken()
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let proxyURL = base + "/claude-proxy"
        return AnthropicProvider(proxyURL: proxyURL, model: selectedModel, bearerToken: token)
    }

    // MARK: - Privacy Zone Detection

    // Determine the strictest privacy level from recent tool call results.
    // Checks if any tool calls referenced entries with privacy-restricted tags.
    // Also scans for tag mentions in the last user message (e.g. "#medizinisch").
    private func detectPrivacyLevel() -> PrivacyLevel {
        let service = PrivacyZoneService(pool: pool)

        // Strategy 1: Check tag names mentioned in recent messages (hashtag pattern).
        let recentContent = messages.suffix(5).map(\.content).joined(separator: " ")
        let tagPattern = try? NSRegularExpression(pattern: "#([\\w/]+)", options: [])
        var mentionedTags: [String] = []
        if let tagPattern {
            let range = NSRange(recentContent.startIndex..., in: recentContent)
            let matches = tagPattern.matches(in: recentContent, range: range)
            for match in matches {
                if let tagRange = Range(match.range(at: 1), in: recentContent) {
                    mentionedTags.append(String(recentContent[tagRange]))
                }
            }
        }

        if !mentionedTags.isEmpty,
           let level = try? service.strictestLevel(forTagNames: mentionedTags),
           level != .unrestricted {
            return level
        }

        // Strategy 2: Check tool results from active tool calls that returned entry data.
        // If tool calls touched entries with restricted tags, honor that.
        // This is a best-effort heuristic — exact entry IDs from tool results
        // would require parsing JSON, so we rely on tag mentions for now.

        return .unrestricted
    }

    // MARK: - Complexity Detection

    /// Heuristic to determine task complexity from the user's message.
    /// Simple queries → .low (cheap model), multi-step requests → .high (powerful model).
    /// Keywords are configurable via UserDefaults for self-tuning by Brain.
    private func detectComplexity(_ text: String) -> LLMComplexity {
        let lower = text.lowercased()

        // High complexity indicators (configurable)
        let highIndicators = Self.loadKeywords(key: "complexityKeywords.high", defaults: [
            "erstelle einen skill", "erstelle ein skill", "skill erstellen",
            "analysiere", "fasse zusammen", "vergleiche",
            "schreibe einen", "erstelle einen plan",
            "erkläre ausführlich", "was meinst du",
        ])
        if highIndicators.contains(where: { lower.contains($0) }) { return .high }
        if text.count > 500 { return .high }
        if activeToolCalls.count >= 3 { return .high }

        // Low complexity indicators (configurable)
        let lowIndicators = Self.loadKeywords(key: "complexityKeywords.low", defaults: [
            "was ist", "wie heisst", "wann", "wo ist",
            "zeig mir", "liste", "wie viele", "zähle",
        ])
        if lowIndicators.contains(where: { lower.contains($0) }) && text.count < 100 {
            return .low
        }

        return .medium
    }

    // Load configurable keyword list with built-in fallback.
    private nonisolated static func loadKeywords(key: String, defaults: [String]) -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? defaults
    }

    // MARK: - Conversation Memory Context

    // Analyze the user's message and fetch relevant context from the database.
    // Extracts person names, topics, and time references to build a memory context.
    // Static + nonisolated to run off the main thread via Task.detached.
    private nonisolated static func buildMemoryContext(for userMessage: String, memory: ConversationMemory) -> String {
        var sections: [String] = []

        // Extract person names from the message
        let names = OnDeviceProvider.extractPersonNames(from: userMessage)
        for name in names.prefix(3) {
            if let entries = try? memory.entriesAboutPerson(name, limit: 5), !entries.isEmpty {
                let entrySummaries = entries.prefix(5).map { entry in
                    let title = entry.title ?? "(ohne Titel)"
                    let date = entry.createdAt ?? ""
                    let bodySnippet = (entry.body ?? "").prefix(100)
                    return "  - [\(date)] \(title): \(bodySnippet)"
                }.joined(separator: "\n")
                sections.append("### Einträge über \(name)\n\(entrySummaries)")
            }

            if let facts = try? memory.factsAbout(subject: name), !facts.isEmpty {
                let factLines = facts.prefix(5).map { fact in
                    "  - \(fact.subject ?? "") \(fact.predicate ?? "") \(fact.object ?? "")"
                }.joined(separator: "\n")
                sections.append("### Fakten über \(name)\n\(factLines)")
            }
        }

        // Extract key topics (words with 4+ chars, not common stopwords)
        let stopwords: Set<String> = [
            "aber", "alle", "also", "andere", "auch", "bitte", "brain",
            "dass", "dein", "deine", "diese", "dieser", "dieses",
            "doch", "eine", "einem", "einen", "einer", "einige",
            "gibt", "habe", "haben", "hast", "heute", "hier",
            "ich", "immer", "jetzt", "kann", "kannst", "keine",
            "mache", "machen", "mein", "meine", "mich", "mehr",
            "nach", "nicht", "noch", "oder", "schon", "sehr",
            "sein", "seine", "sich", "sind", "soll", "über",
            "viel", "warum", "was", "wenn", "wer", "wie",
            "will", "wird", "wurde", "zeig", "zeige"
        ]
        let words = userMessage.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !stopwords.contains($0) }
        let uniqueTopics = Array(Set(words)).prefix(2)

        for topic in uniqueTopics {
            if let entries = try? memory.entriesAboutTopic(topic, limit: 3), !entries.isEmpty {
                let entrySummaries = entries.prefix(3).map { entry in
                    let title = entry.title ?? "(ohne Titel)"
                    let date = entry.createdAt ?? ""
                    return "  - [\(date)] \(title)"
                }.joined(separator: "\n")
                sections.append("### Relevante Einträge zu \"\(topic)\"\n\(entrySummaries)")
            }
        }

        guard !sections.isEmpty else { return "" }
        return "\n## Erinnerungskontext (aus Deinem Gedächtnis)\n" + sections.joined(separator: "\n\n")
    }

    // System prompt is now built by SystemPromptBuilder (extracted for maintainability).
    // The old buildSystemPrompt() method was ~250 lines in ChatService.
    // Future: Allow customization via UserDefaults("customSystemPromptOverride").
    // See: SystemPromptBuilder.swift

    // Old buildSystemPrompt() (250 lines) moved to SystemPromptBuilder.swift
    // Old buildUserKnowledgeSection() + buildBrainProfileSection() also moved there
    // Future: customizable via UserDefaults("customSystemPromptOverride")
}

// Old buildSystemPrompt (250 lines) was here — now in SystemPromptBuilder.swift.
// Removed: buildUserKnowledgeSection, buildBrainProfileSection, buildSystemPrompt.

// Status of an active tool call (for UI display).
struct ToolCallStatus: Identifiable {
    let id = UUID()
    let name: String
    var isRunning: Bool
    var result: String?
}

// MARK: - Chat Knowledge Extractor

// Extracts knowledge facts from chat conversations and saves them to the DB.
// Runs in background (Task.detached) to avoid blocking the chat UI.
enum ChatKnowledgeExtractor {
    // Patterns that indicate personal facts worth saving
    private static let personalPatterns: [(pattern: String, predicate: String)] = [
        ("heiss[et] ", "name"),
        ("wohne? in ", "lives_in"),
        ("arbeite[t]? (?:bei|fuer|als) ", "works_at"),
        ("geboren ", "born"),
        ("geburtstag ", "birthday"),
        ("verheiratet", "marital_status"),
        ("kind(?:er)?", "family"),
        ("tochter|sohn", "family"),
        ("frau |mann |partner", "family"),
        ("hobby|hobbies|hobbys", "interests"),
        ("mag |liebe?|bevorzuge?", "preferences"),
        ("allergi", "health"),
        ("sprache|spreche", "languages"),
    ]

    static func extractFromConversation(userMessage: String, assistantResponse: String, pool: DatabasePool) {
        let combined = userMessage + " " + assistantResponse

        // Extract person names mentioned
        let personNames = extractPersonNames(from: combined)
        for name in personNames {
            saveFact(subject: name, predicate: "mentioned_in_chat",
                     object: "Erwähnt im Chat: \(userMessage.prefix(100))",
                     sourceType: "chat", pool: pool)
        }

        // Extract personal facts from user messages (higher value — user shares info about themselves)
        for (pattern, predicate) in personalPatterns {
            if let _ = userMessage.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                saveFact(subject: "User", predicate: predicate,
                         object: userMessage.prefix(500).description,
                         sourceType: "chat_personal", pool: pool)
                break // One fact per message is enough
            }
        }

        // If assistant learned something explicitly (e.g., "Ich merke mir...")
        if assistantResponse.contains("merke mir") || assistantResponse.contains("notiert") ||
           assistantResponse.contains("gespeichert") {
            saveFact(subject: "User", predicate: "noted_by_brain",
                     object: userMessage.prefix(500).description,
                     sourceType: "chat_noted", pool: pool)
        }
    }

    private static func extractPersonNames(from text: String) -> [String] {
        var names: [String] = []
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        for i in 0..<(words.count - 1) {
            let w1 = words[i]
            let w2 = words[i + 1]
            if w1.count > 1 && w2.count > 1 &&
               w1.first?.isUppercase == true && w2.first?.isUppercase == true &&
               !w1.hasSuffix(".") && !w1.hasSuffix(":") && !w1.hasSuffix(",") {
                let skipWords: Set<String> = ["Brain", "Chat", "Guten", "Morgen", "Abend", "Nacht",
                    "Keine", "Alle", "Diese", "Mein", "Dein", "Eine", "Sehr", "Bitte", "Danke"]
                if !skipWords.contains(w1) {
                    names.append("\(w1) \(w2)")
                }
            }
        }
        return Array(Set(names)).prefix(3).map { String($0) }
    }

    private static func saveFact(subject: String, predicate: String, object: String,
                                 sourceType: String, pool: DatabasePool) {
        do {
            try pool.write { db in
                // Check duplicate cap (max 50 per subject/predicate)
                let count = try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM knowledgeFacts WHERE subject = ? AND predicate = ?
                    """, arguments: [subject, predicate]) ?? 0
                guard count < 50 else { return }

                // Check for exact duplicate
                let exists = try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM knowledgeFacts WHERE subject = ? AND predicate = ? AND object = ?
                    """, arguments: [subject, predicate, object]) ?? 0
                guard exists == 0 else { return }

                try db.execute(sql: """
                    INSERT INTO knowledgeFacts (subject, predicate, object, confidence, sourceType)
                    VALUES (?, ?, ?, 0.8, ?)
                    """, arguments: [subject, predicate, object, sourceType])
            }
        } catch {
            // Silently ignore — knowledge extraction should never block chat
        }
    }
}
