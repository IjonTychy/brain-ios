import Foundation
import BrainCore

// Google Gemini API provider.
// Supports Gemini 2.0 Flash and 2.5 Pro models.
// Uses the generateContent REST API with function calling for tool use.
final class GeminiProvider: ToolUseProvider, @unchecked Sendable {
    // @unchecked Sendable: Safe because all stored properties are immutable after init.
    let name = "Gemini"
    let supportsStreaming = true
    let isOnDevice = false
    let contextWindow = 1000000  // Gemini 2.0 Flash: 1M tokens

    private let apiKey: String
    private let oauthToken: String?
    private let model: String
    private let baseURL: String

    var isAvailable: Bool { !apiKey.isEmpty || (oauthToken != nil) }

    init(apiKey: String, model: String = "gemini-2.5-flash-preview-05-20") {
        self.apiKey = apiKey
        self.oauthToken = nil
        self.model = model
        self.baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    }

    // OAuth-based init — uses Bearer token instead of API key header.
    init(oauthToken: String, model: String = "gemini-2.5-flash-preview-05-20") {
        self.apiKey = ""
        self.oauthToken = oauthToken
        self.model = model
        self.baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    }

    // MARK: - LLMProvider

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        return try await withNetworkRetry {
            guard let url = URL(string: "\(self.baseURL)/\(self.model):generateContent") else {
                throw LLMProviderError.apiError(statusCode: 0, body: "Ungültige Gemini-URL")
            }
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            self.applyAuth(to: &urlRequest)
            urlRequest.timeoutInterval = 600

            let body = self.buildRequestBody(request, tools: nil)
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

            let session = PinnedURLSession.shared.session
            let (data, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMProviderError.apiError(statusCode: 0, body: "Keine HTTP-Antwort")
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "Unbekannter Fehler"
                throw LLMProviderError.apiError(statusCode: httpResponse.statusCode, body: body)
            }

            return try self.parseResponse(data)
        }
    }

    // MARK: - ToolUseProvider (Streaming with Function Calling)

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
                    // Gemini uses streamGenerateContent for streaming
                    guard let url = URL(string: "\(self.baseURL)/\(self.model):streamGenerateContent?alt=sse") else {
                        throw LLMProviderError.apiError(statusCode: 0, body: "Ungültige Gemini-URL")
                    }
                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    self.applyAuth(to: &urlRequest)
                    urlRequest.timeoutInterval = 600

                    // Convert OpenAI-style tools to Gemini function declarations
                    let geminiTools = self.convertToolsToGemini(capturedTools)
                    let body = self.buildRequestBody(capturedRequest, tools: geminiTools)
                    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let session = PinnedURLSession.shared.session
                    let (bytes, response) = try await session.bytes(for: urlRequest)

                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                        throw LLMProviderError.apiError(statusCode: statusCode, body: "Gemini API Fehler")
                    }

                    var fullContent = ""
                    var pendingToolCalls: [(name: String, args: [String: Any])] = []

                    for try await line in bytes.lines {
                        guard !Task.isCancelled else { break }

                        // SSE format: "data: {...}"
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        guard let jsonData = jsonStr.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                              let candidates = json["candidates"] as? [[String: Any]],
                              let content = candidates.first?["content"] as? [String: Any],
                              let parts = content["parts"] as? [[String: Any]] else {
                            continue
                        }

                        for part in parts {
                            if let text = part["text"] as? String {
                                fullContent += text
                                continuation.yield(.text(text))
                            } else if let functionCall = part["functionCall"] as? [String: Any],
                                      let funcName = functionCall["name"] as? String {
                                let args = functionCall["args"] as? [String: Any] ?? [:]
                                pendingToolCalls.append((name: funcName, args: args))
                            }
                        }

                        // Check usage metadata
                        if let usageMetadata = json["usageMetadata"] as? [String: Any] {
                            let input = usageMetadata["promptTokenCount"] as? Int ?? 0
                            let output = usageMetadata["candidatesTokenCount"] as? Int ?? 0
                            continuation.yield(.usage(inputTokens: input, outputTokens: output))
                        }
                    }

                    // Execute any pending tool calls
                    if !pendingToolCalls.isEmpty {
                        var functionResponses: [[String: Any]] = []

                        for toolCall in pendingToolCalls {
                            continuation.yield(.toolStart(name: toolCall.name))
                            let result = try await executeToolCall(toolCall.name, toolCall.args)
                            continuation.yield(.toolResult(name: toolCall.name, result: result))
                            functionResponses.append([
                                "functionResponse": [
                                    "name": toolCall.name,
                                    "response": ["result": result]
                                ]
                            ])
                        }

                        // Send function results back and get final response
                        var followUpRequest = capturedRequest
                        // Add the assistant's function call + our results as context
                        var updatedMessages = request.messages
                        updatedMessages.append(LLMMessage(role: "assistant", content: fullContent.isEmpty ? "[Tool-Aufrufe ausgeführt]" : fullContent))
                        updatedMessages.append(LLMMessage(role: "user", content: "Tool-Ergebnisse verarbeitet. Bitte antworte basierend auf den Ergebnissen."))
                        followUpRequest = LLMRequest(
                            messages: updatedMessages,
                            systemPrompt: capturedRequest.systemPrompt,
                            maxTokens: capturedRequest.maxTokens
                        )

                        // Make follow-up call for final response
                        guard let followUpURL = URL(string: "\(self.baseURL)/\(self.model):streamGenerateContent?alt=sse") else {
                            throw LLMProviderError.apiError(statusCode: 0, body: "Ungültige Gemini-URL")
                        }
                        var followUpReq = URLRequest(url: followUpURL)
                        followUpReq.httpMethod = "POST"
                        followUpReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        self.applyAuth(to: &followUpReq)
                        followUpReq.timeoutInterval = 600

                        let followUpBody = self.buildRequestBody(followUpRequest, tools: geminiTools)
                        followUpReq.httpBody = try JSONSerialization.data(withJSONObject: followUpBody)

                        let (followBytes, _) = try await session.bytes(for: followUpReq)
                        for try await line in followBytes.lines {
                            guard !Task.isCancelled else { break }
                            guard line.hasPrefix("data: ") else { continue }
                            let jsonStr = String(line.dropFirst(6))
                            guard let jsonData = jsonStr.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                  let candidates = json["candidates"] as? [[String: Any]],
                                  let content = candidates.first?["content"] as? [String: Any],
                                  let parts = content["parts"] as? [[String: Any]] else {
                                continue
                            }
                            for part in parts {
                                if let text = part["text"] as? String {
                                    continuation.yield(.text(text))
                                }
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

    // MARK: - Auth

    // Apply the appropriate authentication header to a request.
    private func applyAuth(to request: inout URLRequest) {
        if let token = oauthToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        }
    }

    // MARK: - Request Building

    private func buildRequestBody(_ request: LLMRequest, tools: [[String: Any]]?) -> [String: Any] {
        var contents: [[String: Any]] = []

        // System instruction (Gemini uses separate field)
        var body: [String: Any] = [:]
        if let systemPrompt = request.systemPrompt, !systemPrompt.isEmpty {
            body["systemInstruction"] = [
                "parts": [["text": systemPrompt]]
            ]
        }

        // Messages
        for msg in request.messages {
            let role = msg.role == "assistant" ? "model" : "user"
            contents.append([
                "role": role,
                "parts": [["text": msg.content]]
            ])
        }
        body["contents"] = contents

        // Generation config
        var generationConfig: [String: Any] = [:]
        if let maxTokens = request.maxTokens {
            generationConfig["maxOutputTokens"] = maxTokens
        }
        body["generationConfig"] = generationConfig

        // Tools (function declarations)
        if let tools = tools, !tools.isEmpty {
            body["tools"] = [["functionDeclarations": tools]]
        }

        return body
    }

    // MARK: - Tool Conversion

    /// Convert OpenAI-style tool definitions to Gemini function declarations.
    private func convertToolsToGemini(_ tools: [[String: Any]]) -> [[String: Any]] {
        return tools.compactMap { tool -> [String: Any]? in
            // OpenAI format: { type: "function", function: { name, description, parameters } }
            guard let function = tool["function"] as? [String: Any],
                  let name = function["name"] as? String else {
                return nil
            }
            var decl: [String: Any] = ["name": name]
            if let description = function["description"] as? String {
                decl["description"] = description
            }
            if let parameters = function["parameters"] as? [String: Any] {
                decl["parameters"] = parameters
            }
            return decl
        }
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> LLMResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw LLMProviderError.apiError(statusCode: 0, body: "Ungültige Gemini-Antwort")
        }

        let text = parts.compactMap { $0["text"] as? String }.joined()

        var inputTokens = 0
        var outputTokens = 0
        if let usageMetadata = json["usageMetadata"] as? [String: Any] {
            inputTokens = usageMetadata["promptTokenCount"] as? Int ?? 0
            outputTokens = usageMetadata["candidatesTokenCount"] as? Int ?? 0
        }

        return LLMResponse(
            content: text,
            providerName: name,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            model: model
        )
    }
}
