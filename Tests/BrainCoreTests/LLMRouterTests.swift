import Testing
@testable import BrainCore

// Mock LLM provider for testing routing logic.
struct MockProvider: LLMProvider, Sendable {
    var name: String
    var isAvailable: Bool
    var supportsStreaming: Bool
    var isOnDevice: Bool
    var contextWindow: Int

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        LLMResponse(content: "mock", providerName: name)
    }
}

@Suite("LLM Router")
struct LLMRouterTests {

    private let cloudProvider = MockProvider(
        name: "Claude",
        isAvailable: true,
        supportsStreaming: true,
        isOnDevice: false,
        contextWindow: 200_000
    )

    private let onDeviceSmall = MockProvider(
        name: "Llama-3B",
        isAvailable: true,
        supportsStreaming: true,
        isOnDevice: true,
        contextWindow: 4_096
    )

    private let onDeviceLarge = MockProvider(
        name: "Llama-7B",
        isAvailable: true,
        supportsStreaming: true,
        isOnDevice: true,
        contextWindow: 8_192
    )

    @Test("No internet routes to on-device")
    func offlineRouting() {
        let router = LLMRouter(
            providers: [cloudProvider, onDeviceSmall],
            isConnected: { false }
        )

        let request = LLMRequest(messages: [LLMMessage(role: "user", content: "hi")])
        let provider = router.route(request)
        #expect(provider?.name == "Llama-3B")
    }

    @Test("Sensitive data prefers on-device")
    func sensitiveData() {
        let router = LLMRouter(
            providers: [cloudProvider, onDeviceSmall],
            isConnected: { true }
        )

        let request = LLMRequest(
            messages: [LLMMessage(role: "user", content: "medical info")],
            containsSensitiveData: true
        )
        let provider = router.route(request)
        #expect(provider?.name == "Llama-3B")
    }

    @Test("High complexity routes to cloud")
    func highComplexity() {
        let router = LLMRouter(
            providers: [cloudProvider, onDeviceSmall],
            isConnected: { true }
        )

        let request = LLMRequest(
            messages: [LLMMessage(role: "user", content: "complex analysis")],
            complexity: .high
        )
        let provider = router.route(request)
        #expect(provider?.name == "Claude")
    }

    @Test("Low complexity prefers on-device")
    func lowComplexity() {
        let router = LLMRouter(
            providers: [cloudProvider, onDeviceSmall],
            isConnected: { true }
        )

        let request = LLMRequest(
            messages: [LLMMessage(role: "user", content: "tag this")],
            complexity: .low
        )
        let provider = router.route(request)
        #expect(provider?.name == "Llama-3B")
    }

    @Test("Medium complexity defaults to cloud")
    func mediumComplexity() {
        let router = LLMRouter(
            providers: [cloudProvider, onDeviceSmall],
            isConnected: { true }
        )

        let request = LLMRequest(
            messages: [LLMMessage(role: "user", content: "summarize")],
            complexity: .medium
        )
        let provider = router.route(request)
        #expect(provider?.name == "Claude")
    }

    @Test("No available providers returns nil")
    func noProviders() {
        let unavailable = MockProvider(
            name: "Down",
            isAvailable: false,
            supportsStreaming: false,
            isOnDevice: false,
            contextWindow: 0
        )
        let router = LLMRouter(providers: [unavailable])

        let request = LLMRequest(messages: [])
        let provider = router.route(request)
        #expect(provider == nil)
    }

    @Test("Best on-device selects largest context window")
    func bestOnDevice() {
        let router = LLMRouter(
            providers: [cloudProvider, onDeviceSmall, onDeviceLarge],
            isConnected: { false }
        )

        let request = LLMRequest(messages: [LLMMessage(role: "user", content: "hi")])
        let provider = router.route(request)
        #expect(provider?.name == "Llama-7B")
    }

    @Test("Sensitive data falls back to cloud if no on-device")
    func sensitiveDataFallback() {
        let router = LLMRouter(
            providers: [cloudProvider],
            isConnected: { true }
        )

        let request = LLMRequest(
            messages: [LLMMessage(role: "user", content: "medical")],
            containsSensitiveData: true
        )
        let provider = router.route(request)
        #expect(provider?.name == "Claude")
    }
}
