import Foundation
import BrainCore

// OpenAI GPT provider with streaming and tool-use support.
// Supports GPT-5.4, GPT-4.1, and all OpenAI chat models.
final class OpenAIProvider: ToolUseProvider, @unchecked Sendable {
    // @unchecked Sendable: Safe because all stored properties are immutable after init.
    let name = "GPT"
    let supportsStreaming = true
    let isOnDevice = false
    let contextWindow = 1_000_000  // GPT-5.4: 1M tokens

    private let apiKey: String
    private let model: String
    private let baseURL: String

    var isAvailable: Bool { !apiKey.isEmpty }

    init(apiKey: String, model: String = "gpt-4o") {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = "https://api.openai.com/v1/chat/completions"
    }

    // MARK: - Non-streaming completion

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        let urlRequest = try buildRequest(request, tools: nil, stream: false)
        let (data, response) = try await PinnedURLSession.shared.session.data(for: urlRequest)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMProviderError.apiError(statusCode: code, body: body)
        }

        return try parseResponse(data)
    }

    // MARK: - Streaming with Tool-Use

    func streamWithTools(
        _ request: LLMRequest,
        tools: [[String: Any]],
        executeToolCall: @escaping @Sendable (String, [String: Any]) async throws -> String
    ) -> AsyncThrowingStream<ToolStreamEvent, Error> {
        nonisolated(unsafe) let capturedTools = tools
        let capturedSelf = self
        let capturedRequest = request
        return AsyncThrowingStream { continuation in
            Task { @Sendable in
                do {
                    var currentMessages = capturedSelf.buildMessages(capturedRequest)
                    var round = 0
                    let maxRounds = 10

                    while round < maxRounds {
                        round += 1
                        let urlRequest = try capturedSelf.buildStreamRequest(
                            messages: currentMessages,
                            systemPrompt: capturedRequest.systemPrompt,
                            tools: capturedTools,
                            maxTokens: capturedRequest.maxTokens
                        )

                        let (streamBytes, streamResponse) = try await PinnedURLSession.shared.session.bytes(for: urlRequest)
                        guard let http = streamResponse as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                            let code = (streamResponse as? HTTPURLResponse)?.statusCode ?? 0
                            throw LLMProviderError.apiError(statusCode: code, body: "OpenAI API Fehler")
                        }

                        var fullContent = ""
                        var toolCalls: [ToolCallAccumulator] = []

                        for try await line in streamBytes.lines {
                            guard !Task.isCancelled else { break }
                            guard line.hasPrefix("data: ") else { continue }
                            let payload = String(line.dropFirst(6))
                            if payload == "[DONE]" { break }

                            guard let jsonData = payload.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                  let choices = json["choices"] as? [[String: Any]],
                                  let delta = choices.first?["delta"] as? [String: Any] else {
                                continue
                            }

                            // Text content
                            if let content = delta["content"] as? String {
                                fullContent += content
                                continuation.yield(.text(content))
                            }

                            // Tool calls (incremental)
                            if let deltaTools = delta["tool_calls"] as? [[String: Any]] {
                                for tc in deltaTools {
                                    let index = tc["index"] as? Int ?? 0
                                    while toolCalls.count <= index {
                                        toolCalls.append(ToolCallAccumulator())
                                    }
                                    if let id = tc["id"] as? String { toolCalls[index].id = id }
                                    if let fn = tc["function"] as? [String: Any] {
                                        if let name = fn["name"] as? String { toolCalls[index].name = name }
                                        if let args = fn["arguments"] as? String { toolCalls[index].arguments += args }
                                    }
                                }
                            }

                            // Usage
                            if let usage = json["usage"] as? [String: Any] {
                                let input = usage["prompt_tokens"] as? Int ?? 0
                                let output = usage["completion_tokens"] as? Int ?? 0
                                if input > 0 || output > 0 {
                                    continuation.yield(.usage(inputTokens: input, outputTokens: output))
                                }
                            }
                        }

                        // No tool calls → done
                        if toolCalls.isEmpty || toolCalls.allSatisfy({ $0.name.isEmpty }) {
                            break
                        }

                        // Execute tool calls
                        var toolResults: [[String: Any]] = []
                        // Add assistant message with tool calls
                        var assistantMsg: [String: Any] = ["role": "assistant"]
                        if !fullContent.isEmpty { assistantMsg["content"] = fullContent }
                        assistantMsg["tool_calls"] = toolCalls.map { tc -> [String: Any] in
                            ["id": tc.id, "type": "function", "function": ["name": tc.name, "arguments": tc.arguments]]
                        }
                        currentMessages.append(assistantMsg)

                        for tc in toolCalls where !tc.name.isEmpty {
                            continuation.yield(.toolStart(name: tc.name))
                            let args = (try? JSONSerialization.jsonObject(with: Data(tc.arguments.utf8))) as? [String: Any] ?? [:]
                            let result = try await executeToolCall(tc.name, args)
                            continuation.yield(.toolResult(name: tc.name, result: result))
                            toolResults.append([
                                "role": "tool",
                                "tool_call_id": tc.id,
                                "content": result
                            ])
                        }
                        currentMessages.append(contentsOf: toolResults)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Request Building

    private func buildMessages(_ request: LLMRequest) -> [[String: Any]] {
        var messages: [[String: Any]] = []
        if let sys = request.systemPrompt, !sys.isEmpty {
            messages.append(["role": "system", "content": sys])
        }
        messages.append(contentsOf: request.messages.map { ["role": $0.role, "content": $0.content] })
        return messages
    }

    private func buildRequest(_ request: LLMRequest, tools: [[String: Any]]?, stream: Bool) throws -> URLRequest {
        guard let url = URL(string: baseURL) else {
            throw LLMProviderError.apiError(statusCode: 0, body: "Ungültige API-URL")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = 600

        var body: [String: Any] = [
            "model": model,
            "max_tokens": request.maxTokens ?? 4096,
            "messages": buildMessages(request),
            "stream": stream,
        ]
        if stream { body["stream_options"] = ["include_usage": true] }
        if let tools = tools, !tools.isEmpty { body["tools"] = tools }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    private func buildStreamRequest(
        messages: [[String: Any]],
        systemPrompt: String?,
        tools: [[String: Any]],
        maxTokens: Int?
    ) throws -> URLRequest {
        guard let url = URL(string: baseURL) else {
            throw LLMProviderError.apiError(statusCode: 0, body: "Ungültige API-URL")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = 600

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens ?? 4096,
            "messages": messages,
            "stream": true,
            "stream_options": ["include_usage": true],
        ]
        if !tools.isEmpty { body["tools"] = tools }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> LLMResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMProviderError.apiError(statusCode: 0, body: "Ungültige OpenAI-Antwort")
        }

        let usage = json["usage"] as? [String: Any]
        let inputTokens = usage?["prompt_tokens"] as? Int ?? 0
        let outputTokens = usage?["completion_tokens"] as? Int ?? 0

        return LLMResponse(
            content: content,
            providerName: name,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            model: model
        )
    }
}

// Accumulates incremental tool call data from streaming chunks.
private struct ToolCallAccumulator {
    var id: String = ""
    var name: String = ""
    var arguments: String = ""
}
