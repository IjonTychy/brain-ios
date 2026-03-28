import Foundation
import BrainCore

// Generic provider for any OpenAI-compatible API endpoint.
// Works with: Ollama, Mistral, xAI Grok, Deepseek, LiteLLM, vLLM,
// Together AI, Fireworks, Groq, or any other OpenAI-compatible server.
//
// Configuration: User provides a base URL and optional API key.
// The provider appends /v1/chat/completions to the base URL.
final class OpenAICompatibleProvider: ToolUseProvider, @unchecked Sendable {
    // @unchecked Sendable: Safe because all stored properties are immutable after init.
    let name: String
    let supportsStreaming = true
    let isOnDevice: Bool
    let contextWindow: Int

    private let apiKey: String?
    private let model: String
    private let endpointURL: String

    var isAvailable: Bool { !endpointURL.isEmpty }

    // Known API hosts that have certificate pins in PinnedURLSession.
    private static let pinnedHosts: Set<String> = [
        "api.x.ai", "api.anthropic.com", "api.openai.com",
        "generativelanguage.googleapis.com", "api.claude.ai",
    ]

    /// URLSession to use: PinnedURLSession for known API hosts, URLSession.shared for custom endpoints.
    private var urlSession: URLSession {
        if let host = URL(string: endpointURL)?.host(),
           Self.pinnedHosts.contains(host) {
            return PinnedURLSession.shared.session
        }
        // Custom endpoints (Ollama, LiteLLM, etc.) — no pins available.
        return URLSession.shared
    }

    /// - Parameters:
    ///   - baseURL: Server URL (e.g. "http://localhost:11434" for Ollama, "https://api.x.ai" for xAI)
    ///   - model: Model ID (e.g. "llama3.2", "grok-3", "deepseek-chat")
    ///   - apiKey: Optional API key (nil for local servers like Ollama)
    ///   - providerName: Display name shown in UI
    ///   - isLocal: Whether the server runs on the same device
    ///   - contextWindow: Max context window (default 128K)
    init(
        baseURL: String,
        model: String,
        apiKey: String? = nil,
        providerName: String = "OpenAI-kompatibel",
        isLocal: Bool = false,
        contextWindow: Int = 128_000
    ) {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        // Append /v1/chat/completions if not already present
        if base.hasSuffix("/v1/chat/completions") {
            self.endpointURL = base
        } else if base.hasSuffix("/v1") {
            self.endpointURL = base + "/chat/completions"
        } else {
            self.endpointURL = base + "/v1/chat/completions"
        }
        self.model = model
        self.apiKey = apiKey
        self.name = providerName
        self.isOnDevice = isLocal
        self.contextWindow = contextWindow
    }

    // MARK: - Non-streaming

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        let urlRequest = try buildRequest(messages: buildMessages(request), systemPrompt: nil, tools: nil, stream: false, maxTokens: request.maxTokens)
        let (data, response) = try await urlSession.data(for: urlRequest)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMProviderError.apiError(statusCode: code, body: body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMProviderError.apiError(statusCode: 0, body: "Ungültige Antwort")
        }

        let usage = json["usage"] as? [String: Any]
        return LLMResponse(
            content: content,
            providerName: name,
            inputTokens: usage?["prompt_tokens"] as? Int ?? 0,
            outputTokens: usage?["completion_tokens"] as? Int ?? 0,
            model: model
        )
    }

    // MARK: - Streaming with Tool-Use

    func streamWithTools(
        _ request: LLMRequest,
        tools: [[String: Any]],
        executeToolCall: @escaping @Sendable (String, [String: Any]) async throws -> String
    ) -> AsyncThrowingStream<ToolStreamEvent, Error> {
        nonisolated(unsafe) let capturedTools = tools
        let capturedRequest = request
        return AsyncThrowingStream { continuation in
            Task { @Sendable in
                do {
                    var currentMessages = self.buildMessages(capturedRequest)
                    var round = 0

                    while round < 10 {
                        round += 1
                        let urlRequest = try self.buildRequest(
                            messages: currentMessages,
                            systemPrompt: nil, // already in messages
                            tools: capturedTools,
                            stream: true,
                            maxTokens: capturedRequest.maxTokens
                        )

                        let (bytes, response) = try await urlSession.bytes(for: urlRequest)
                        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                            throw LLMProviderError.apiError(statusCode: code, body: "API Fehler")
                        }

                        var fullContent = ""
                        var toolCalls: [ToolCallAcc] = []

                        for try await line in bytes.lines {
                            guard !Task.isCancelled else { break }
                            guard line.hasPrefix("data: ") else { continue }
                            let payload = String(line.dropFirst(6))
                            if payload == "[DONE]" { break }

                            guard let jd = payload.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: jd) as? [String: Any],
                                  let choices = json["choices"] as? [[String: Any]],
                                  let delta = choices.first?["delta"] as? [String: Any] else { continue }

                            if let c = delta["content"] as? String {
                                fullContent += c
                                continuation.yield(.text(c))
                            }
                            if let tcs = delta["tool_calls"] as? [[String: Any]] {
                                for tc in tcs {
                                    let idx = tc["index"] as? Int ?? 0
                                    while toolCalls.count <= idx { toolCalls.append(ToolCallAcc()) }
                                    if let id = tc["id"] as? String { toolCalls[idx].id = id }
                                    if let fn = tc["function"] as? [String: Any] {
                                        if let n = fn["name"] as? String { toolCalls[idx].name = n }
                                        if let a = fn["arguments"] as? String { toolCalls[idx].arguments += a }
                                    }
                                }
                            }
                            if let u = json["usage"] as? [String: Any] {
                                let inp = u["prompt_tokens"] as? Int ?? 0
                                let out = u["completion_tokens"] as? Int ?? 0
                                if inp > 0 || out > 0 { continuation.yield(.usage(inputTokens: inp, outputTokens: out)) }
                            }
                        }

                        if toolCalls.isEmpty || toolCalls.allSatisfy({ $0.name.isEmpty }) { break }

                        var assistantMsg: [String: Any] = ["role": "assistant"]
                        if !fullContent.isEmpty { assistantMsg["content"] = fullContent }
                        assistantMsg["tool_calls"] = toolCalls.map { ["id": $0.id, "type": "function", "function": ["name": $0.name, "arguments": $0.arguments]] }
                        currentMessages.append(assistantMsg)

                        for tc in toolCalls where !tc.name.isEmpty {
                            continuation.yield(.toolStart(name: tc.name))
                            let args = (try? JSONSerialization.jsonObject(with: Data(tc.arguments.utf8))) as? [String: Any] ?? [:]
                            let result = try await executeToolCall(tc.name, args)
                            continuation.yield(.toolResult(name: tc.name, result: result))
                            currentMessages.append(["role": "tool", "tool_call_id": tc.id, "content": result])
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Helpers

    private func buildMessages(_ request: LLMRequest) -> [[String: Any]] {
        var messages: [[String: Any]] = []
        if let sys = request.systemPrompt, !sys.isEmpty {
            messages.append(["role": "system", "content": sys])
        }
        messages.append(contentsOf: request.messages.map { ["role": $0.role, "content": $0.content] })
        return messages
    }

    private func buildRequest(messages: [[String: Any]], systemPrompt: String?, tools: [[String: Any]]?, stream: Bool, maxTokens: Int?) throws -> URLRequest {
        guard let url = URL(string: endpointURL) else {
            throw LLMProviderError.apiError(statusCode: 0, body: "Ungültige Endpoint-URL: \(endpointURL)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        req.timeoutInterval = 600

        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": stream,
        ]
        if let max = maxTokens { body["max_tokens"] = max }
        if stream { body["stream_options"] = ["include_usage": true] }
        if let tools = tools, !tools.isEmpty { body["tools"] = tools }

        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }
}

private struct ToolCallAcc {
    var id: String = ""
    var name: String = ""
    var arguments: String = ""
}
