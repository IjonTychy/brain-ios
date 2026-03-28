import Foundation

// Dynamic model registry that fetches available models from provider APIs.
// Falls back to hardcoded defaults if API calls fail (offline, no key, etc.).
struct AvailableModels {

    struct Model: Identifiable, Equatable {
        let id: String
        let label: String
        let cost: String
        let provider: String
    }

    // MARK: - Fallback models (late March 2026, used when API fetch fails)

    private static let fallbackAnthropic: [Model] = [
        Model(id: "claude-opus-4-6", label: "Claude Opus 4.6 ($5/$25)", cost: "$$$$", provider: "Anthropic"),
        Model(id: "claude-sonnet-4-6", label: "Claude Sonnet 4.6 ($3/$15)", cost: "$$$", provider: "Anthropic"),
        Model(id: "claude-haiku-4-5-20251001", label: "Claude Haiku 4.5 ($1/$5)", cost: "$", provider: "Anthropic"),
    ]

    private static let fallbackOpenAI: [Model] = [
        Model(id: "gpt-5.4", label: "GPT-5.4 ($2.50/$15)", cost: "$$$", provider: "OpenAI"),
        Model(id: "gpt-5.4-mini", label: "GPT-5.4 Mini ($0.75/$4.50)", cost: "$$", provider: "OpenAI"),
        Model(id: "gpt-5.4-nano", label: "GPT-5.4 Nano ($0.20/$1.25)", cost: "$", provider: "OpenAI"),
        Model(id: "gpt-4.1", label: "GPT-4.1 ($2/$8)", cost: "$$", provider: "OpenAI"),
    ]

    private static let fallbackGemini: [Model] = [
        Model(id: "gemini-2.5-pro-preview-05-06", label: "Gemini 2.5 Pro ($2/$12)", cost: "$$$", provider: "Google"),
        Model(id: "gemini-2.5-flash-preview-05-20", label: "Gemini 2.5 Flash ($0.50/$3)", cost: "$$", provider: "Google"),
        Model(id: "gemini-2.0-flash-lite", label: "Gemini 2.0 Flash-Lite ($0.25/$1.50)", cost: "$", provider: "Google"),
    ]

    private static let fallbackXAI: [Model] = [
        Model(id: "grok-4", label: "Grok 4 ($3/$15)", cost: "$$$", provider: "xAI"),
        Model(id: "grok-4.1-fast", label: "Grok 4.1 Fast ($0.20/$0.50)", cost: "$", provider: "xAI"),
    ]

    private static let onDeviceModels: [Model] = [
        Model(id: "on-device", label: "Auf dem Gerät (kostenlos)", cost: "-", provider: "Lokal"),
    ]

    // MARK: - Cache

    private static let cacheKey = "cachedLLMModels"
    private static let cacheTimestampKey = "cachedLLMModelsTimestamp"
    private static let cacheDuration: TimeInterval = 3600 // 1 hour

    // MARK: - Synchronous (cached or fallback)

    // Returns all models whose provider has a configured API key.
    // Uses cached API results if available, otherwise hardcoded fallbacks.
    static func available() -> [Model] {
        let keychain = KeychainService()
        var models: [Model] = []

        let hasAnthropic = keychain.exists(key: KeychainKeys.anthropicAPIKey)
        let hasProxy = keychain.exists(key: KeychainKeys.brainAPIRefreshToken)
        if hasAnthropic || hasProxy {
            models.append(contentsOf: cachedModels(for: "Anthropic") ?? fallbackAnthropic)
        }

        if keychain.exists(key: KeychainKeys.openAIAPIKey) {
            models.append(contentsOf: cachedModels(for: "OpenAI") ?? fallbackOpenAI)
        }

        let hasGeminiKey = keychain.exists(key: KeychainKeys.geminiAPIKey)
        let hasGoogleOAuth = keychain.read(key: GoogleOAuthKeys.refreshToken) != nil
        if hasGeminiKey || hasGoogleOAuth {
            models.append(contentsOf: cachedModels(for: "Google") ?? fallbackGemini)
        }

        if keychain.exists(key: KeychainKeys.xaiAPIKey) {
            models.append(contentsOf: cachedModels(for: "xAI") ?? fallbackXAI)
        }

        // Custom OpenAI-compatible endpoints
        if let configs = loadCustomEndpoints() {
            for config in configs {
                models.append(Model(id: config.model, label: "\(config.model) (\(config.name))", cost: "?", provider: config.name))
            }
        }

        models.append(contentsOf: onDeviceModels)
        models.append(contentsOf: loadCustomModels())
        return models
    }

    // MARK: - Async fetch from APIs

    // Fetches current model lists from all configured providers.
    // Call this when the settings view appears to refresh the cache.
    static func refreshFromAPIs() async {
        let keychain = KeychainService()

        // Check if cache is still fresh
        if let ts = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date,
           Date().timeIntervalSince(ts) < cacheDuration {
            return
        }

        async let anthropicTask: Void = {
            if let key = keychain.read(key: KeychainKeys.anthropicAPIKey) {
                if let models = await fetchAnthropicModels(apiKey: key) {
                    cacheModels(models, for: "Anthropic")
                }
            }
        }()

        async let openAITask: Void = {
            if let key = keychain.read(key: KeychainKeys.openAIAPIKey) {
                if let models = await fetchOpenAIModels(apiKey: key) {
                    cacheModels(models, for: "OpenAI")
                }
            }
        }()

        async let geminiTask: Void = {
            let geminiKey = keychain.read(key: KeychainKeys.geminiAPIKey)
            if geminiKey != nil || keychain.read(key: GoogleOAuthKeys.refreshToken) != nil {
                if let models = await fetchGeminiModels(apiKey: geminiKey) {
                    cacheModels(models, for: "Google")
                }
            }
        }()

        async let xaiTask: Void = {
            if let key = keychain.read(key: KeychainKeys.xaiAPIKey) {
                if let models = await fetchOpenAICompatibleModels(baseURL: "https://api.x.ai", apiKey: key, providerName: "xAI") {
                    cacheModels(models, for: "xAI")
                }
            }
        }()

        _ = await (anthropicTask, openAITask, geminiTask, xaiTask)
        UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
    }

    // Force refresh (ignores cache TTL).
    static func forceRefresh() async {
        UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
        await refreshFromAPIs()
    }

    // MARK: - Anthropic API

    private static func fetchAnthropicModels(apiKey: String) async -> [Model]? {
        guard let url = URL(string: "https://api.anthropic.com/v1/models?limit=50") else { return nil }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            return nil
        }

        let models = dataArray.compactMap { obj -> Model? in
            guard let id = obj["id"] as? String,
                  let displayName = obj["display_name"] as? String else { return nil }
            // Skip very old or deprecated models
            if id.contains("claude-1") || id.contains("claude-2") || id.contains("claude-3-") { return nil }
            let cost = estimateCost(id)
            return Model(id: id, label: displayName, cost: cost, provider: "Anthropic")
        }
        return models.isEmpty ? nil : models
    }

    // MARK: - OpenAI API

    private static func fetchOpenAIModels(apiKey: String) async -> [Model]? {
        guard let url = URL(string: "https://api.openai.com/v1/models") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            return nil
        }

        // Filter to chat-capable models only
        let chatPrefixes = ["gpt-4", "gpt-3.5", "o1", "o3", "o4", "chatgpt"]
        let excluded = ["instruct", "realtime", "audio", "search", "tts", "whisper", "dall-e", "embedding"]

        let models = dataArray.compactMap { obj -> Model? in
            guard let id = obj["id"] as? String else { return nil }
            let lower = id.lowercased()
            guard chatPrefixes.contains(where: { lower.hasPrefix($0) }) else { return nil }
            guard !excluded.contains(where: { lower.contains($0) }) else { return nil }
            let cost = estimateCost(id)
            return Model(id: id, label: formatModelName(id, provider: "OpenAI"), cost: cost, provider: "OpenAI")
        }
        .sorted { $0.id > $1.id } // Newest first (lexicographic for versioned names)

        return models.isEmpty ? nil : Array(models.prefix(10))
    }

    // MARK: - Gemini API

    private static func fetchGeminiModels(apiKey: String?) async -> [Model]? {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models") else { return nil }
        var request = URLRequest(url: url)
        if let key = apiKey {
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        }
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsArray = json["models"] as? [[String: Any]] else {
            return nil
        }

        let models = modelsArray.compactMap { obj -> Model? in
            guard let name = obj["name"] as? String,
                  let displayName = obj["displayName"] as? String else { return nil }
            // name is "models/gemini-2.5-pro" — extract ID
            let id = name.replacingOccurrences(of: "models/", with: "")
            // Only include generateContent-capable models
            guard let methods = obj["supportedGenerationMethods"] as? [String],
                  methods.contains("generateContent") else { return nil }
            // Skip embedding-only or very old models
            if id.contains("embedding") || id.contains("aqa") || id.contains("gemini-1.0") { return nil }
            let cost = estimateCost(id)
            return Model(id: id, label: displayName, cost: cost, provider: "Google")
        }
        .sorted { $0.id > $1.id }

        return models.isEmpty ? nil : Array(models.prefix(10))
    }

    // MARK: - Helpers

    private static func estimateCost(_ modelId: String) -> String {
        let id = modelId.lowercased()
        if id.contains("opus") || id.contains("o3") && !id.contains("mini") { return "$$$$" }
        if id.contains("pro") || id.contains("4o") && !id.contains("mini") || id.contains("4.1") && !id.contains("mini") { return "$$$" }
        if id.contains("sonnet") || id.contains("flash") || id.contains("mini") { return "$$" }
        if id.contains("haiku") || id.contains("nano") { return "$" }
        return "$$"
    }

    private static func formatModelName(_ id: String, provider: String) -> String {
        // Make model IDs more readable
        var name = id
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "gpt ", with: "GPT-")
        // Capitalize first letter of each word
        name = name.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        return name
    }

    // MARK: - Cache storage

    private static func cacheModels(_ models: [Model], for provider: String) {
        let entries = models.map { CachedModel(id: $0.id, label: $0.label, cost: $0.cost, provider: $0.provider) }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: "\(cacheKey).\(provider)")
        }
    }

    private static func cachedModels(for provider: String) -> [Model]? {
        guard let data = UserDefaults.standard.data(forKey: "\(cacheKey).\(provider)"),
              let entries = try? JSONDecoder().decode([CachedModel].self, from: data) else {
            return nil
        }
        return entries.map { Model(id: $0.id, label: $0.label, cost: $0.cost, provider: $0.provider) }
    }

    private struct CachedModel: Codable {
        let id: String
        let label: String
        let cost: String
        let provider: String
    }

    // MARK: - Custom Models

    private static let customModelsKey = "customLLMModels"

    private static func loadCustomModels() -> [Model] {
        guard let data = UserDefaults.standard.data(forKey: customModelsKey),
              let array = try? JSONDecoder().decode([CustomModelEntry].self, from: data) else {
            return []
        }
        return array.map { Model(id: $0.id, label: $0.label, cost: $0.cost, provider: $0.provider) }
    }

    static func addCustomModel(id: String, label: String, cost: String, provider: String) {
        var existing = loadCustomModelEntries()
        existing.removeAll { $0.id == id }
        existing.append(CustomModelEntry(id: id, label: label, cost: cost, provider: provider))
        if let data = try? JSONEncoder().encode(existing) {
            UserDefaults.standard.set(data, forKey: customModelsKey)
        }
    }

    static func removeCustomModel(id: String) {
        var existing = loadCustomModelEntries()
        existing.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(existing) {
            UserDefaults.standard.set(data, forKey: customModelsKey)
        }
    }

    private static func loadCustomModelEntries() -> [CustomModelEntry] {
        guard let data = UserDefaults.standard.data(forKey: customModelsKey),
              let array = try? JSONDecoder().decode([CustomModelEntry].self, from: data) else {
            return []
        }
        return array
    }

    private struct CustomModelEntry: Codable {
        let id: String
        let label: String
        let cost: String
        let provider: String
    }

    // MARK: - Grouped

    static func availableGrouped() -> [(provider: String, models: [Model])] {
        let all = available()
        var groups: [(provider: String, models: [Model])] = []
        var seen = Set<String>()
        for model in all {
            if !seen.contains(model.provider) {
                seen.insert(model.provider)
                groups.append((provider: model.provider, models: all.filter { $0.provider == model.provider }))
            }
        }
        return groups
    }

    static func shortLabel(for modelId: String) -> String {
        let all = available()
        if let model = all.first(where: { $0.id == modelId }) {
            let label = model.label
            if label.hasPrefix("Claude ") { return String(label.dropFirst(7)) }
            return label
        }
        return modelId
    }

    // MARK: - OpenAI-compatible model fetch (xAI, Ollama, Mistral, Deepseek, etc.)

    private static func fetchOpenAICompatibleModels(baseURL: String, apiKey: String?, providerName: String) async -> [Model]? {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: "\(base)/v1/models") else { return nil }
        var request = URLRequest(url: url)
        if let key = apiKey { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            return nil
        }

        let excluded = ["embed", "tts", "whisper", "dall-e", "moderation"]
        let models = dataArray.compactMap { obj -> Model? in
            guard let id = obj["id"] as? String else { return nil }
            if excluded.contains(where: { id.lowercased().contains($0) }) { return nil }
            let cost = estimateCost(id)
            return Model(id: id, label: id, cost: cost, provider: providerName)
        }
        .sorted { $0.id > $1.id }

        return models.isEmpty ? nil : Array(models.prefix(15))
    }

    // MARK: - Custom Endpoints (user-configurable OpenAI-compatible servers)

    private static let customEndpointsKey = "customLLMEndpoints"
    private static let keychain = KeychainService()

    /// Stored in UserDefaults (non-sensitive metadata).
    /// API keys are stored separately in Keychain under "customEndpoint.{name}.apiKey".
    struct CustomEndpoint: Codable {
        let name: String       // Display name (e.g. "Ollama lokal", "Deepseek")
        let baseURL: String    // Server URL (e.g. "http://localhost:11434")
        let model: String      // Default model (e.g. "llama3.2")
        // Kept for Codable backward-compatibility during migration; new saves always use nil.
        let apiKey: String?
    }

    /// Returns the API key for a custom endpoint from Keychain, with UserDefaults migration fallback.
    static func apiKey(for endpointName: String) -> String? {
        let keychainKey = "customEndpoint.\(endpointName).apiKey"
        if let key = keychain.read(key: keychainKey), !key.isEmpty {
            return key
        }
        // Migration fallback: check if the key is still in the Codable struct (pre-AP5)
        if let endpoints = loadCustomEndpoints(),
           let ep = endpoints.first(where: { $0.name == endpointName }),
           let legacyKey = ep.apiKey, !legacyKey.isEmpty {
            // Migrate to Keychain
            try? keychain.save(key: keychainKey, value: legacyKey)
            // Re-save without the key in UserDefaults
            let cleaned = endpoints.map { e in
                e.name == endpointName
                    ? CustomEndpoint(name: e.name, baseURL: e.baseURL, model: e.model, apiKey: nil)
                    : e
            }
            saveCustomEndpoints(cleaned)
            return legacyKey
        }
        return nil
    }

    static func loadCustomEndpoints() -> [CustomEndpoint]? {
        guard let data = UserDefaults.standard.data(forKey: customEndpointsKey),
              let configs = try? JSONDecoder().decode([CustomEndpoint].self, from: data),
              !configs.isEmpty else { return nil }
        return configs
    }

    static func saveCustomEndpoints(_ endpoints: [CustomEndpoint]) {
        if let data = try? JSONEncoder().encode(endpoints) {
            UserDefaults.standard.set(data, forKey: customEndpointsKey)
        }
    }

    static func addCustomEndpoint(_ endpoint: CustomEndpoint) {
        // Store API key in Keychain, not in UserDefaults JSON
        if let key = endpoint.apiKey, !key.isEmpty {
            try? keychain.save(key: "customEndpoint.\(endpoint.name).apiKey", value: key)
        }
        let sanitized = CustomEndpoint(name: endpoint.name, baseURL: endpoint.baseURL, model: endpoint.model, apiKey: nil)

        var existing = loadCustomEndpoints() ?? []
        existing.removeAll { $0.name == endpoint.name }
        existing.append(sanitized)
        saveCustomEndpoints(existing)
    }

    static func removeCustomEndpoint(name: String) {
        keychain.delete(key: "customEndpoint.\(name).apiKey")
        var existing = loadCustomEndpoints() ?? []
        existing.removeAll { $0.name == name }
        saveCustomEndpoints(existing)
    }
}
