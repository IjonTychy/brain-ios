import Foundation
import BrainCore

// Anthropic Claude API provider.
// NOTE: Session keys from claude.ai (Max plan) are accepted as API keys.
// Anthropic officially warns about third-party usage but does not enforce for personal use.
// Session keys expire after ~30 days — user must refresh periodically in Settings.
final class AnthropicProvider: ToolUseProvider, @unchecked Sendable {
    // @unchecked Sendable: Safe because all stored properties are immutable after init.
    let name = "Claude"
    let supportsStreaming = true
    let isOnDevice = false
    let contextWindow = 200000

    private enum AuthMode {
        case apiKey(String)
        case maxSessionKey(String)
        case proxy(bearerToken: String?)
    }

    private let authMode: AuthMode
    private let model: String
    private let baseURL: String

    // Legacy computed properties for compatibility
    private var useProxy: Bool {
        if case .proxy = authMode { return true }
        return false
    }

    var isAvailable: Bool {
        switch authMode {
        case .apiKey(let key): return !key.isEmpty
        case .maxSessionKey(let key): return !key.isEmpty
        case .proxy: return true
        }
    }

    // Standard API mode (sk-ant-... key)
    init(apiKey: String, model: String = "claude-opus-4-6") {
        self.authMode = .apiKey(apiKey)
        self.model = model
        self.baseURL = "https://api.anthropic.com/v1/messages"
    }

    // Max mode: Claude Max subscription via api.claude.ai.
    // The session key is extracted from the browser (cookie "sessionKey" on claude.ai).
    // Valid for ~30 days. Uses Anthropic message format with Bearer auth.
    init(sessionKey: String, model: String = "claude-opus-4-6") {
        self.authMode = .maxSessionKey(sessionKey)
        self.model = model
        self.baseURL = "https://api.claude.ai/v1/messages"
    }

    // Proxy mode: User-configurable VPS proxy (OpenAI-compatible format).
    // Use cases: self-hosted LLMs (Ollama, vLLM), VPS with LiteLLM, or any
    // OpenAI-compatible endpoint. Optional bearerToken for JWT-authenticated proxies.
    init(proxyURL: String, model: String = "claude-opus-4-6", bearerToken: String? = nil) {
        self.authMode = .proxy(bearerToken: bearerToken)
        self.model = model
        let base = proxyURL.hasSuffix("/") ? String(proxyURL.dropLast()) : proxyURL
        self.baseURL = base + "/v1/chat/completions"
    }

    // MARK: - Non-streaming completion

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        // M3: Retry transient errors (429, 503, timeout)
        return try await withNetworkRetry {
            let urlRequest = try self.buildRequest(request, stream: false)

            let (data, response) = try await PinnedURLSession.shared.session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw LLMProviderError.apiError(statusCode: statusCode, body: String(data: data, encoding: .utf8) ?? "")
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            if self.useProxy {
                // OpenAI format: choices[0].message.content
                let choices = json?["choices"] as? [[String: Any]]
                let message = choices?.first?["message"] as? [String: Any]
                let content = message?["content"] as? String ?? ""
                let usage = json?["usage"] as? [String: Any]
                let promptTokens = usage?["prompt_tokens"] as? Int ?? 0
                let completionTokens = usage?["completion_tokens"] as? Int ?? 0
                return LLMResponse(content: content, providerName: self.name, tokensUsed: promptTokens + completionTokens, inputTokens: promptTokens, outputTokens: completionTokens, model: self.model)
            } else {
                // Anthropic format: content[0].text
                let content = (json?["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
                let usage = json?["usage"] as? [String: Any]
                let inputTokens = usage?["input_tokens"] as? Int ?? 0
                let outputTokens = usage?["output_tokens"] as? Int ?? 0
                return LLMResponse(content: content, providerName: self.name, tokensUsed: inputTokens + outputTokens, inputTokens: inputTokens, outputTokens: outputTokens, model: self.model)
            }
        }
    }

    // MARK: - Streaming completion

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        let capturedRequest = request
        return AsyncThrowingStream { continuation in
            Task { @Sendable in
                do {
                    let urlRequest = try self.buildRequest(capturedRequest, stream: true)

                    let (bytes, response) = try await PinnedURLSession.shared.session.bytes(for: urlRequest)

                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                        throw LLMProviderError.apiError(statusCode: statusCode, body: "HTTP \(statusCode)")
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))

                        guard jsonStr != "[DONE]",
                              let jsonData = jsonStr.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                        else { continue }

                        if self.useProxy {
                            // OpenAI streaming: choices[0].delta.content
                            if let choices = event["choices"] as? [[String: Any]],
                               let delta = choices.first?["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
                            }
                            // Check finish_reason
                            if let choices = event["choices"] as? [[String: Any]],
                               let finishReason = choices.first?["finish_reason"] as? String,
                               finishReason == "stop" {
                                break
                            }
                        } else {
                            // Anthropic streaming: content_block_delta
                            let eventType = event["type"] as? String

                            if eventType == "content_block_delta",
                               let delta = event["delta"] as? [String: Any],
                               let text = delta["text"] as? String {
                                continuation.yield(text)
                            }

                            if eventType == "message_stop" {
                                break
                            }

                            if eventType == "error",
                               let error = event["error"] as? [String: Any],
                               let message = error["message"] as? String {
                                throw LLMProviderError.apiError(statusCode: 0, body: message)
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Tool-Use Streaming (multi-turn with tool calls)

    // Streams a conversation that may include tool calls.
    // When Claude returns tool_use blocks, calls the handler and continues the conversation.
    // Yields ToolStreamEvent so the caller can display both text and tool activity.
    func streamWithTools(
        _ request: LLMRequest,
        tools: [[String: Any]],
        executeToolCall: @escaping @Sendable (String, [String: Any]) async throws -> String
    ) -> AsyncThrowingStream<ToolStreamEvent, Error> {
        // Copy non-Sendable values before entering @Sendable closure
        nonisolated(unsafe) let capturedTools = tools
        let capturedRequest = request
        return AsyncThrowingStream { continuation in
            Task { @Sendable in
                do {
                    // Build mutable conversation from request
                    var conversationMessages: [[String: Any]] = capturedRequest.messages.map { msg in
                        ["role": msg.role, "content": msg.content]
                    }

                    // Allow up to 3 tool-call rounds (F-11: reduced from 10 to limit blast radius)
                    for _ in 0..<3 {
                        let urlRequest = try self.buildToolRequest(
                            systemPrompt: capturedRequest.systemPrompt,
                            messages: conversationMessages,
                            tools: capturedTools,
                            maxTokens: capturedRequest.maxTokens ?? 4096,
                            stream: true
                        )

                        let (bytes, response) = try await PinnedURLSession.shared.session.bytes(for: urlRequest)

                        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                            throw LLMProviderError.apiError(statusCode: statusCode, body: "HTTP \(statusCode)")
                        }

                        var textContent = ""
                        var toolUseBlocks: [(id: String, name: String, inputJSON: String)] = []
                        var stopReason: String?

                        if self.useProxy {
                            // OpenAI streaming format
                            var currentToolCalls: [String: (name: String, arguments: String)] = [:]

                            for try await line in bytes.lines {
                                if Task.isCancelled { break }
                                guard line.hasPrefix("data: ") else { continue }
                                let jsonStr = String(line.dropFirst(6))
                                guard jsonStr != "[DONE]",
                                      let jsonData = jsonStr.data(using: .utf8),
                                      let event = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                                else { continue }

                                guard let choices = event["choices"] as? [[String: Any]],
                                      let choice = choices.first else { continue }

                                let finishReason = choice["finish_reason"] as? String

                                if let delta = choice["delta"] as? [String: Any] {
                                    // Text content
                                    if let content = delta["content"] as? String {
                                        textContent += content
                                        continuation.yield(.text(content))
                                    }

                                    // Tool calls (streamed incrementally)
                                    if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                                        for tc in toolCalls {
                                            let index = tc["index"] as? Int ?? 0
                                            let key = "\(index)"

                                            if let function = tc["function"] as? [String: Any] {
                                                if let name = function["name"] as? String {
                                                    // New tool call starting
                                                    let id = tc["id"] as? String ?? "call_\(index)"
                                                    currentToolCalls[key] = (name: name, arguments: "")
                                                    toolUseBlocks.append((id: id, name: name, inputJSON: ""))
                                                    continuation.yield(.toolStart(name: name))
                                                }
                                                if let args = function["arguments"] as? String {
                                                    if var existing = currentToolCalls[key] {
                                                        existing.arguments += args
                                                        currentToolCalls[key] = existing
                                                        // Update the last matching tool block
                                                        if let idx = toolUseBlocks.lastIndex(where: { $0.name == existing.name }) {
                                                            toolUseBlocks[idx] = (
                                                                id: toolUseBlocks[idx].id,
                                                                name: existing.name,
                                                                inputJSON: existing.arguments
                                                            )
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Extract usage from OpenAI streaming (some providers include it)
                                if let usage = event["usage"] as? [String: Any] {
                                    let input = usage["prompt_tokens"] as? Int ?? 0
                                    let output = usage["completion_tokens"] as? Int ?? 0
                                    if input > 0 || output > 0 {
                                        continuation.yield(.usage(inputTokens: input, outputTokens: output))
                                    }
                                }

                                if let reason = finishReason {
                                    stopReason = reason
                                    if reason == "stop" || reason == "tool_calls" {
                                        break
                                    }
                                }
                            }
                        } else {
                            // Anthropic streaming format
                            var currentToolId = ""
                            var currentToolName = ""
                            var currentToolInput = ""

                            for try await line in bytes.lines {
                                if Task.isCancelled { break }
                                guard line.hasPrefix("data: ") else { continue }
                                let jsonStr = String(line.dropFirst(6))
                                guard jsonStr != "[DONE]",
                                      let jsonData = jsonStr.data(using: .utf8),
                                      let event = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                                else { continue }

                                let eventType = event["type"] as? String

                                switch eventType {
                                case "content_block_start":
                                    if let contentBlock = event["content_block"] as? [String: Any],
                                       contentBlock["type"] as? String == "tool_use" {
                                        currentToolId = contentBlock["id"] as? String ?? ""
                                        currentToolName = contentBlock["name"] as? String ?? ""
                                        currentToolInput = ""
                                        continuation.yield(.toolStart(name: currentToolName))
                                    }

                                case "content_block_delta":
                                    if let delta = event["delta"] as? [String: Any] {
                                        let deltaType = delta["type"] as? String
                                        if deltaType == "text_delta", let text = delta["text"] as? String {
                                            textContent += text
                                            continuation.yield(.text(text))
                                        } else if deltaType == "input_json_delta",
                                                  let partial = delta["partial_json"] as? String {
                                            currentToolInput += partial
                                        }
                                    }

                                case "content_block_stop":
                                    if !currentToolId.isEmpty {
                                        toolUseBlocks.append((id: currentToolId, name: currentToolName, inputJSON: currentToolInput))
                                        currentToolId = ""
                                        currentToolName = ""
                                        currentToolInput = ""
                                    }

                                case "message_delta":
                                    if let delta = event["delta"] as? [String: Any] {
                                        stopReason = delta["stop_reason"] as? String
                                    }
                                    // Extract streaming usage from message_delta
                                    if let usage = event["usage"] as? [String: Any] {
                                        let input = usage["input_tokens"] as? Int ?? 0
                                        let output = usage["output_tokens"] as? Int ?? 0
                                        if input > 0 || output > 0 {
                                            continuation.yield(.usage(inputTokens: input, outputTokens: output))
                                        }
                                    }

                                case "message_stop":
                                    break

                                case "error":
                                    if let error = event["error"] as? [String: Any],
                                       let message = error["message"] as? String {
                                        throw LLMProviderError.apiError(statusCode: 0, body: message)
                                    }

                                default:
                                    break
                                }
                            }
                        }

                        // Check if tools were called (OpenAI: "tool_calls", Anthropic: "tool_use")
                        // Some OpenAI-compatible proxies return "stop" even when tool calls are present,
                        // so for proxy mode we check the blocks directly rather than relying on finish_reason.
                        let hasToolCalls = self.useProxy
                            ? !toolUseBlocks.isEmpty
                            : stopReason == "tool_use" && !toolUseBlocks.isEmpty

                        if hasToolCalls {
                            if self.useProxy {
                                // OpenAI format: assistant message with tool_calls array
                                var assistantMsg: [String: Any] = ["role": "assistant"]
                                if !textContent.isEmpty {
                                    assistantMsg["content"] = textContent
                                }
                                var toolCallsArray: [[String: Any]] = []
                                for tool in toolUseBlocks {
                                    toolCallsArray.append([
                                        "id": tool.id,
                                        "type": "function",
                                        "function": [
                                            "name": tool.name,
                                            "arguments": tool.inputJSON
                                        ]
                                    ])
                                }
                                assistantMsg["tool_calls"] = toolCallsArray
                                conversationMessages.append(assistantMsg)

                                // Execute tools and add results as tool messages
                                for tool in toolUseBlocks {
                                    let inputObj = (try? JSONSerialization.jsonObject(
                                        with: Data(tool.inputJSON.utf8))) as? [String: Any] ?? [:]
                                    do {
                                        let result = try await executeToolCall(tool.name, inputObj)
                                        continuation.yield(.toolResult(name: tool.name, result: result))
                                        conversationMessages.append([
                                            "role": "tool",
                                            "tool_call_id": tool.id,
                                            "content": result
                                        ])
                                    } catch {
                                        let errorMsg = "Fehler: \(error.localizedDescription)"
                                        continuation.yield(.toolResult(name: tool.name, result: errorMsg))
                                        conversationMessages.append([
                                            "role": "tool",
                                            "tool_call_id": tool.id,
                                            "content": errorMsg
                                        ])
                                    }
                                }
                            } else {
                                // Anthropic format: assistant message with content array + user tool_result
                                var assistantContent: [[String: Any]] = []
                                if !textContent.isEmpty {
                                    assistantContent.append(["type": "text", "text": textContent])
                                }
                                for tool in toolUseBlocks {
                                    let inputObj = (try? JSONSerialization.jsonObject(
                                        with: Data(tool.inputJSON.utf8))) as? [String: Any] ?? [:]
                                    assistantContent.append([
                                        "type": "tool_use",
                                        "id": tool.id,
                                        "name": tool.name,
                                        "input": inputObj
                                    ])
                                }
                                conversationMessages.append(["role": "assistant", "content": assistantContent])

                                var toolResults: [[String: Any]] = []
                                for tool in toolUseBlocks {
                                    let inputObj = (try? JSONSerialization.jsonObject(
                                        with: Data(tool.inputJSON.utf8))) as? [String: Any] ?? [:]
                                    do {
                                        let result = try await executeToolCall(tool.name, inputObj)
                                        continuation.yield(.toolResult(name: tool.name, result: result))
                                        toolResults.append([
                                            "type": "tool_result",
                                            "tool_use_id": tool.id,
                                            "content": result
                                        ])
                                    } catch {
                                        let errorMsg = "Fehler: \(error.localizedDescription)"
                                        continuation.yield(.toolResult(name: tool.name, result: errorMsg))
                                        toolResults.append([
                                            "type": "tool_result",
                                            "tool_use_id": tool.id,
                                            "content": errorMsg,
                                            "is_error": true
                                        ])
                                    }
                                }
                                conversationMessages.append(["role": "user", "content": toolResults])
                            }
                            textContent = ""
                            // Loop continues — Claude will respond to tool results
                        } else {
                            // No tool use — conversation is done
                            break
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Auth

    private func applyAuth(_ request: inout URLRequest) {
        switch authMode {
        case .apiKey(let key):
            // Standard API: x-api-key header
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .maxSessionKey(let sessionKey):
            // Max mode: Bearer auth on api.claude.ai (same Anthropic message format)
            request.setValue("Bearer \(sessionKey)", forHTTPHeaderField: "Authorization")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .proxy(let bearerToken):
            // Proxy mode: optional JWT bearer token
            if let token = bearerToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }
    }

    // MARK: - Request builders

    private func buildRequest(_ request: LLMRequest, stream: Bool) throws -> URLRequest {
        guard let url = URL(string: baseURL) else {
            throw LLMProviderError.apiError(statusCode: 0, body: "Ungültige API-URL")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&urlRequest)

        var body: [String: Any]

        if useProxy {
            // OpenAI format
            var messages = request.messages.map { [
                "role": $0.role,
                "content": $0.content
            ] as [String: Any] }
            // Prepend system message
            if let systemPrompt = request.systemPrompt, !systemPrompt.isEmpty {
                messages.insert(["role": "system", "content": systemPrompt], at: 0)
            }
            body = [
                "model": model,
                "max_tokens": request.maxTokens ?? 4096,
                "messages": messages
            ]
        } else {
            // Anthropic format
            body = [
                "model": model,
                "max_tokens": request.maxTokens ?? 4096,
                "messages": request.messages.map { [
                    "role": $0.role,
                    "content": $0.content
                ] }
            ]
            if let systemPrompt = request.systemPrompt, !systemPrompt.isEmpty {
                body["system"] = systemPrompt
            }
        }

        if stream {
            body["stream"] = true
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    private func buildToolRequest(
        systemPrompt: String?,
        messages: [[String: Any]],
        tools: [[String: Any]],
        maxTokens: Int,
        stream: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: baseURL) else {
            throw LLMProviderError.apiError(statusCode: 0, body: "Ungültige API-URL")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&urlRequest)

        var body: [String: Any]

        if useProxy {
            // OpenAI format: system as message, tools as functions
            var openAIMessages = messages
            if let systemPrompt, !systemPrompt.isEmpty {
                openAIMessages.insert(["role": "system", "content": systemPrompt], at: 0)
            }
            // Convert Anthropic tool format to OpenAI function format
            let openAITools = tools.map { tool -> [String: Any] in
                [
                    "type": "function",
                    "function": [
                        "name": tool["name"] as? String ?? "",
                        "description": tool["description"] as? String ?? "",
                        "parameters": tool["input_schema"] ?? [:] as [String: Any]
                    ]
                ]
            }
            body = [
                "model": model,
                "max_tokens": maxTokens,
                "messages": openAIMessages,
                "tools": openAITools
            ]
        } else {
            // Anthropic format
            body = [
                "model": model,
                "max_tokens": maxTokens,
                "messages": messages,
                "tools": tools
            ]
            if let systemPrompt, !systemPrompt.isEmpty {
                body["system"] = systemPrompt
            }
        }

        if stream {
            body["stream"] = true
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }
}

// ToolStreamEvent is now defined in BrainCore/LLM/LLMProvider.swift

// M3: Retry helper for transient network errors (429, 503, timeout).
// Retries up to maxAttempts with exponential backoff.
// Non-transient errors (401, 400) are thrown immediately.
func withNetworkRetry<T>(maxAttempts: Int = 3, operation: () async throws -> T) async throws -> T {
    var lastError: Error?
    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch let error as URLError where error.code == .timedOut || error.code == .networkConnectionLost {
            lastError = error
        } catch let error as LLMProviderError {
            if case .apiError(let statusCode, _) = error, [429, 503, 502].contains(statusCode) {
                lastError = error
            } else {
                throw error // Non-transient — throw immediately
            }
        }
        if attempt < maxAttempts {
            let delay = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000
            try await Task.sleep(nanoseconds: delay)
        }
    }
    throw lastError ?? LLMProviderError.noResponse
}

enum LLMProviderError: Error, LocalizedError {
    case apiError(statusCode: Int, body: String)
    case noResponse

    var errorDescription: String? {
        switch self {
        case .apiError(let code, let body):
            return "API-Fehler (Status \(code)): \(body)"
        case .noResponse:
            return "Keine Antwort vom Server"
        }
    }
}
