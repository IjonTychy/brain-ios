import Testing
import Foundation
@testable import BrainCore
@testable import BrainApp

// ChatService.buildProvider (BrainApp) now feeds on-device candidates
// (Apple Foundation Models, Gemma) through ToolLessProviderAdapter so they
// can sit in the same [any ToolUseProvider] candidate list as the user's
// chosen provider, then hands the whole list to BrainCore's LLMRouter on
// every send() — not only when the user explicitly picks "on-device".
// LLMRouterTests/PrivacyZoneTests (BrainCoreTests) already cover the
// router's decision tree with plain LLMProvider mocks; this suite checks
// the one thing those can't: that wrapping a provider in
// ToolLessProviderAdapter doesn't change how the router treats it.

private struct StubOnDeviceProvider: LLMProvider, Sendable {
    var name = "Stub-OnDevice"
    var isAvailable = true
    var supportsStreaming = true
    var isOnDevice = true
    var contextWindow = 4_096
    var responseContent = "stub on-device response"

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        LLMResponse(content: responseContent, providerName: name)
    }
}

private struct StubCloudProvider: LLMProvider, Sendable {
    var name = "Stub-Cloud"
    var isAvailable = true
    var supportsStreaming = true
    var isOnDevice = false
    var contextWindow = 200_000

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        LLMResponse(content: "stub cloud response", providerName: name)
    }
}

@Suite("ToolLessProviderAdapter")
struct ToolLessProviderAdapterTests {

    @Test("Adapter passes through name, isOnDevice, isAvailable and contextWindow from the base provider")
    func adapterPreservesIdentity() {
        let adapter = ToolLessProviderAdapter(base: StubOnDeviceProvider())
        #expect(adapter.name == "Stub-OnDevice")
        #expect(adapter.isOnDevice == true)
        #expect(adapter.isAvailable == true)
        #expect(adapter.contextWindow == 4_096)
    }

    @Test("Adapter reports supportsStreaming false even if the base provider supports it")
    func adapterIsAlwaysToolLess() {
        // StubOnDeviceProvider.supportsStreaming is true, but the adapter's
        // contract towards ChatService is tool-less/single-shot completion.
        let adapter = ToolLessProviderAdapter(base: StubOnDeviceProvider())
        #expect(adapter.supportsStreaming == false)
    }

    @Test("Adapter reflects an unavailable base provider")
    func adapterReflectsUnavailability() {
        let adapter = ToolLessProviderAdapter(base: StubOnDeviceProvider(isAvailable: false))
        #expect(adapter.isAvailable == false)
    }

    @Test("streamWithTools emits a single text event from complete(), ignoring tools and executeToolCall")
    func streamWithToolsBridgesCompletion() async throws {
        let adapter = ToolLessProviderAdapter(base: StubOnDeviceProvider(responseContent: "hallo vom geraet"))
        let request = LLMRequest(messages: [LLMMessage(role: "user", content: "hi")])

        var events: [ToolStreamEvent] = []
        let stream = adapter.streamWithTools(
            request,
            tools: [["name": "entry_create"]],
            executeToolCall: { _, _ in "unused" }
        )
        for try await event in stream {
            events.append(event)
        }

        #expect(events.count == 1)
        if case .text(let content) = events.first {
            #expect(content == "hallo vom geraet")
        } else {
            Issue.record("Expected a single .text event")
        }
    }
}

@Suite("LLMRouter with adapter-wrapped on-device candidates")
struct LLMRouterAdapterIntegrationTests {

    @Test("onDeviceOnly selects the adapter-wrapped on-device provider even when cloud is available")
    func onDeviceOnlyRoutesToAdapter() {
        let onDeviceAdapter = ToolLessProviderAdapter(base: StubOnDeviceProvider())
        let cloud = StubCloudProvider()

        let router = LLMRouter(providers: [cloud, onDeviceAdapter], isConnected: { true })
        let request = LLMRequest(
            messages: [LLMMessage(role: "user", content: "medizinische notiz")],
            privacyLevel: .onDeviceOnly
        )

        let selected = router.route(request)
        #expect(selected?.name == "Stub-OnDevice")
        #expect(selected?.isOnDevice == true)
    }

    @Test("Offline routes to the adapter-wrapped on-device provider")
    func offlineRoutesToAdapter() {
        let onDeviceAdapter = ToolLessProviderAdapter(base: StubOnDeviceProvider())
        let cloud = StubCloudProvider()

        let router = LLMRouter(providers: [cloud, onDeviceAdapter], isConnected: { false })
        let request = LLMRequest(messages: [LLMMessage(role: "user", content: "hi")])

        let selected = router.route(request)
        #expect(selected?.name == "Stub-OnDevice")
    }

    @Test("Unrestricted, medium-complexity requests still prefer cloud despite an adapter candidate")
    func unrestrictedStillPrefersCloud() {
        let onDeviceAdapter = ToolLessProviderAdapter(base: StubOnDeviceProvider())
        let cloud = StubCloudProvider()

        let router = LLMRouter(providers: [cloud, onDeviceAdapter], isConnected: { true })
        let request = LLMRequest(
            messages: [LLMMessage(role: "user", content: "hallo")],
            privacyLevel: .unrestricted
        )

        let selected = router.route(request)
        #expect(selected?.name == "Stub-Cloud")
    }

    @Test("onDeviceOnly returns nil when the only candidate is an adapter around an unavailable provider")
    func onDeviceOnlyWithUnavailableAdapterReturnsNil() {
        let unavailableAdapter = ToolLessProviderAdapter(base: StubOnDeviceProvider(isAvailable: false))

        let router = LLMRouter(providers: [unavailableAdapter], isConnected: { true })
        let request = LLMRequest(
            messages: [LLMMessage(role: "user", content: "medizinische notiz")],
            privacyLevel: .onDeviceOnly
        )

        #expect(router.route(request) == nil)
    }
}
