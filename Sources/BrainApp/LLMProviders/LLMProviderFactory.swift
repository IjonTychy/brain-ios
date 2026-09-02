import Foundation
import BrainCore

// Central LLM provider selection, shared by the chat path
// (ChatService.buildProvider) and the AI-handler path
// (DataBridge.buildLLMProvider). Resolving a model choice to a concrete
// provider and enforcing privacy zones / offline routing lives here and
// nowhere else.
enum LLMProviderFactory {

    // Resolve the provider for an explicit model choice — no routing yet.
    // Returns tool-capable providers only; on-device backends are wrapped in
    // ToolLessProviderAdapter so every result can serve the chat interface.
    static func userSelectedProvider(model selectedModel: String) async -> (any ToolUseProvider)? {
        let keychain = KeychainService()

        // Route to an on-device provider if explicitly selected. Availability
        // decides which one: Apple Foundation Models first, then the best
        // downloaded GGUF model (Gemma). Both run tool-less through the adapter.
        // When nothing on-device is usable, fall through to cloud providers.
        if selectedModel == "on-device" || selectedModel.hasPrefix("on-device") {
            let apple = OnDeviceProvider()
            if apple.isAvailable {
                return ToolLessProviderAdapter(base: apple)
            }
            if let gemma = GemmaProvider.bestAvailable(), gemma.isAvailable {
                return ToolLessProviderAdapter(base: gemma)
            }
            // Nothing on-device available — fall through to cloud
        }

        // Route to Gemini if a Gemini model is selected
        if selectedModel.hasPrefix("gemini") {
            let geminiKey = keychain.read(key: KeychainKeys.geminiAPIKey) ?? ""
            if !geminiKey.isEmpty {
                return GeminiProvider(apiKey: geminiKey, model: selectedModel)
            }
            if let token = try? await GoogleOAuthService().getValidToken() {
                return GeminiProvider(oauthToken: token, model: selectedModel)
            }
        }

        // Route to OpenAI if a GPT/o-series model is selected.
        // "on-device" also starts with "o" but is not an OpenAI model — it
        // falls through to the Anthropic chain when nothing local is usable.
        if selectedModel.hasPrefix("gpt-")
            || (selectedModel.hasPrefix("o") && !selectedModel.hasPrefix("on-device")) {
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

        // Claude (default): check configured mode, then fall through the chain.
        // The API key is read once, only in this Anthropic section — it can be
        // biometry-gated, so no read happens for non-Anthropic models.
        let anthropicKey = keychain.read(key: KeychainKeys.anthropicAPIKey) ?? ""
        let mode = UserDefaults.standard.string(forKey: "anthropicMode") ?? "api"
        switch mode {
        case "proxy":
            if let provider = proxyProvider(model: selectedModel, keychain: keychain) {
                return provider
            }
        case "max":
            if let sessionKey = keychain.read(key: KeychainKeys.anthropicMaxSessionKey), !sessionKey.isEmpty {
                return AnthropicProvider(sessionKey: sessionKey, model: selectedModel)
            }
        case "api":
            let provider = AnthropicProvider(apiKey: anthropicKey, model: selectedModel)
            if provider.isAvailable { return provider }
        default:
            break
        }
        // Fallback chain: proxy → max → api
        if let provider = proxyProvider(model: selectedModel, keychain: keychain) {
            return provider
        }
        if let sessionKey = keychain.read(key: KeychainKeys.anthropicMaxSessionKey), !sessionKey.isEmpty {
            return AnthropicProvider(sessionKey: sessionKey, model: selectedModel)
        }
        let provider = AnthropicProvider(apiKey: anthropicKey, model: selectedModel)
        return provider.isAvailable ? provider : nil
    }

    /// Provider for the user-configured OpenAI-compatible proxy. The URL comes
    /// from the Keychain; AnthropicProvider appends /v1/chat/completions.
    private static func proxyProvider(model: String, keychain: KeychainService) -> AnthropicProvider? {
        guard let baseURL = keychain.read(key: KeychainKeys.anthropicProxyURL), !baseURL.isEmpty else {
            return nil
        }
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        return AnthropicProvider(proxyURL: base, model: model)
    }

    // Adapter-wrapped on-device candidates (Apple Foundation Models, Gemma).
    static func onDeviceCandidates() -> [any ToolUseProvider] {
        var candidates: [any ToolUseProvider] = []
        let apple = OnDeviceProvider()
        if apple.isAvailable {
            candidates.append(ToolLessProviderAdapter(base: apple))
        }
        if let gemma = GemmaProvider.bestAvailable(), gemma.isAvailable {
            candidates.append(ToolLessProviderAdapter(base: gemma))
        }
        return candidates
    }

    // Resolve a provider and run it through LLMRouter so privacy zones and
    // offline routing are enforced. Returns the provider plus the model that
    // actually serves the request. nil = the constraints cannot be satisfied —
    // callers must fail loudly, never fall back to cloud on their own.
    static func routedProvider(
        model selectedModel: String,
        privacyLevel: PrivacyLevel,
        containsSensitiveData: Bool = false,
        isConnected: Bool
    ) async -> (provider: any ToolUseProvider, model: String)? {
        let userProvider = await userSelectedProvider(model: selectedModel)

        var candidates = onDeviceCandidates()
        // The user's pick can itself be one of the on-device adapters above —
        // skip the duplicate so the candidate list stays unambiguous.
        if let userProvider, !candidates.contains(where: { $0.name == userProvider.name }) {
            candidates.append(userProvider)
        }
        guard !candidates.isEmpty else { return nil }

        // Complexity-based model choice is the opt-in autoRouteModels feature
        // and happens before this call; the router only enforces privacy zones,
        // sensitivity, and connectivity (ARCHITECTURE: "Chat → User-Präferenz").
        let routingRequest = LLMRequest(
            messages: [],
            complexity: .medium,
            containsSensitiveData: containsSensitiveData,
            privacyLevel: privacyLevel
        )
        let router = LLMRouter(
            providers: candidates.map { $0 as any LLMProvider },
            isConnected: { isConnected }
        )
        guard let routed = router.route(routingRequest) as? any ToolUseProvider else {
            return nil
        }
        // Cloud picks keep the resolved model id; when the router (or the user)
        // landed on a local model, report the on-device provider's name instead.
        let servedModel = routed.isOnDevice ? routed.name : selectedModel
        return (routed, servedModel)
    }

    // Explain why no provider could be selected: privacy gate, offline, or no key.
    static func unavailableMessage(privacyLevel: PrivacyLevel, isConnected: Bool) -> String {
        if privacyLevel == .onDeviceOnly {
            return "Privacy Zone aktiv: Diese Daten dürfen das Gerät nicht verlassen, es ist aber kein On-Device-Modell verfügbar."
        }
        if !isConnected {
            return "Offline: Kein On-Device-Modell verfügbar. Internetverbindung herstellen oder ein lokales Modell in den Einstellungen laden."
        }
        return "Kein API-Key konfiguriert. Bitte in den Einstellungen hinterlegen."
    }
}
