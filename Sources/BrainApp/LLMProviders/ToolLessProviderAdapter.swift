import Foundation
import BrainCore

// Adapts a plain LLMProvider (no tool support) to the ToolUseProvider
// interface that ChatService drives: tool definitions are ignored and the
// full completion is emitted as a single text event. This makes on-device
// providers (Apple Foundation Models, Gemma) usable in the chat UI — without
// tools, which is the expected trade-off for offline inference.
struct ToolLessProviderAdapter: ToolUseProvider, @unchecked Sendable {

    let base: any LLMProvider

    var name: String { base.name }
    var isAvailable: Bool { base.isAvailable }
    var supportsStreaming: Bool { false }
    var isOnDevice: Bool { base.isOnDevice }
    var contextWindow: Int { base.contextWindow }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        try await base.complete(request)
    }

    func streamWithTools(
        _ request: LLMRequest,
        tools: [[String: Any]],
        executeToolCall: @escaping @Sendable (String, [String: Any]) async throws -> String
    ) -> AsyncThrowingStream<ToolStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let provider = base
            Task {
                do {
                    let response = try await provider.complete(request)
                    continuation.yield(.text(response.content))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
