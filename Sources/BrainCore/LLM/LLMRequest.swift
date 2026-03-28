// Request and response types for the LLM abstraction layer.

// Complexity level used by the router to select an appropriate provider.
public enum LLMComplexity: Sendable {
    case low, medium, high
}

// A message in an LLM conversation.
public struct LLMMessage: Sendable {
    public var role: String  // "user", "assistant", "system"
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

// A request to an LLM provider.
public struct LLMRequest: Sendable {
    public var messages: [LLMMessage]
    public var systemPrompt: String?
    public var complexity: LLMComplexity
    public var containsSensitiveData: Bool
    public var maxTokens: Int?
    // Phase 31: Privacy zone restriction from tagged entries.
    // When set, the router enforces the level before selecting a provider.
    public var privacyLevel: PrivacyLevel

    public init(
        messages: [LLMMessage],
        systemPrompt: String? = nil,
        complexity: LLMComplexity = .medium,
        containsSensitiveData: Bool = false,
        maxTokens: Int? = nil,
        privacyLevel: PrivacyLevel = .unrestricted
    ) {
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.complexity = complexity
        self.containsSensitiveData = containsSensitiveData
        self.maxTokens = maxTokens
        self.privacyLevel = privacyLevel
    }
}

// A response from an LLM provider.
public struct LLMResponse: Sendable {
    public var content: String
    public var providerName: String
    public var tokensUsed: Int?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var model: String?

    public init(
        content: String,
        providerName: String,
        tokensUsed: Int? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        model: String? = nil
    ) {
        self.content = content
        self.providerName = providerName
        self.tokensUsed = tokensUsed
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.model = model
    }
}
