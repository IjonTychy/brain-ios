// Protocol defining the interface for all LLM providers.
// Concrete implementations (Anthropic, OpenAI, Ollama, MLX, etc.)
// will be added in later phases.
public protocol LLMProvider: Sendable {
    var name: String { get }
    var isAvailable: Bool { get }
    var supportsStreaming: Bool { get }
    var isOnDevice: Bool { get }
    var contextWindow: Int { get }

    func complete(_ request: LLMRequest) async throws -> LLMResponse
}

// Streaming event from a tool-use enabled provider.
public enum ToolStreamEvent: Sendable {
    case text(String)
    case toolStart(name: String)
    case toolResult(name: String, result: String)
    case usage(inputTokens: Int, outputTokens: Int)
}

// Extended protocol for providers that support tool-use with streaming.
// The ChatService uses this to enable LLM-driven tool execution.
public protocol ToolUseProvider: LLMProvider {
    func streamWithTools(
        _ request: LLMRequest,
        tools: [[String: Any]],
        executeToolCall: @escaping @Sendable (String, [String: Any]) async throws -> String
    ) -> AsyncThrowingStream<ToolStreamEvent, Error>
}

// Set of tool names whose results contain sensitive data (PII, credentials, location).
// When any of these tools are invoked, the request should be flagged as sensitive.
public let sensitiveDataTools: Set<String> = [
    "contact_search", "contact_read", "contact_create",
    "email_list", "email_fetch", "email_search", "email_send",
    "calendar_list", "calendar_create", "calendar_delete",
    "location_current"
]
