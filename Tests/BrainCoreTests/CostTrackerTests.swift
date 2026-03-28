import Testing
import Foundation
import GRDB
@testable import BrainCore

@Suite("LLM Cost Tracking")
struct CostTrackerTests {

    private func makeTracker() throws -> CostTracker {
        let db = try DatabaseManager.temporary()
        return CostTracker(pool: db.pool)
    }

    @Test("Record usage creates entry")
    func recordUsage() throws {
        let tracker = try makeTracker()
        try tracker.record(provider: "Claude", model: "claude-sonnet-4", inputTokens: 500, outputTokens: 200)
        let requests = try tracker.currentMonthRequests()
        #expect(requests == 1)
    }

    @Test("Current month cost calculation")
    func monthCost() throws {
        let tracker = try makeTracker()
        // Claude Sonnet: 3€/1M input + 15€/1M output
        try tracker.record(provider: "Claude", model: "claude-sonnet-4", inputTokens: 1000, outputTokens: 500)
        let cost = try tracker.currentMonthCostEuros()
        // Expected: 1000 * 3/1M + 500 * 15/1M = 0.003 + 0.0075 = 0.0105€
        #expect(cost > 0.01)
        #expect(cost < 0.02)
    }

    @Test("Token counting")
    func tokenCount() throws {
        let tracker = try makeTracker()
        try tracker.record(provider: "Claude", model: "test", inputTokens: 1000, outputTokens: 500)
        try tracker.record(provider: "Claude", model: "test", inputTokens: 200, outputTokens: 100)
        let tokens = try tracker.currentMonthTokens()
        #expect(tokens == 1800) // 1500 + 300
    }

    @Test("Budget remaining")
    func budgetRemaining() throws {
        let tracker = try makeTracker()
        try tracker.record(provider: "Claude", model: "claude-sonnet-4", inputTokens: 1000, outputTokens: 500)
        let remaining = try tracker.remainingBudget(monthlyLimitEuros: 10.0)
        #expect(remaining > 9.9) // Barely any cost
        #expect(remaining < 10.0) // But some cost deducted
    }

    @Test("Provider breakdown")
    func providerBreakdown() throws {
        let tracker = try makeTracker()
        try tracker.record(provider: "Claude", model: "claude-sonnet-4", inputTokens: 1000, outputTokens: 500)
        try tracker.record(provider: "GPT", model: "gpt-4o", inputTokens: 500, outputTokens: 200)
        let breakdown = try tracker.currentMonthByProvider()
        #expect(breakdown.count == 2)
    }

    @Test("Average cost per request")
    func averageCost() throws {
        let tracker = try makeTracker()
        try tracker.record(provider: "Claude", model: "claude-sonnet-4", inputTokens: 1000, outputTokens: 500)
        try tracker.record(provider: "Claude", model: "claude-sonnet-4", inputTokens: 1000, outputTokens: 500)
        let avg = try tracker.averageCostPerRequest()
        let total = try tracker.currentMonthCostEuros()
        #expect(abs(avg * 2 - total) < 0.001)
    }

    @Test("All-time stats")
    func allTimeStats() throws {
        let tracker = try makeTracker()
        try tracker.record(provider: "Claude", model: "test", inputTokens: 100, outputTokens: 50)
        try tracker.record(provider: "Claude", model: "test", inputTokens: 200, outputTokens: 100)
        let stats = try tracker.allTimeStats()
        #expect(stats.requests == 2)
        #expect(stats.tokens == 450)
        #expect(stats.costEuros > 0)
    }

    @Test("Empty tracker returns zeros")
    func emptyTracker() throws {
        let tracker = try makeTracker()
        #expect(try tracker.currentMonthCostEuros() == 0)
        #expect(try tracker.currentMonthTokens() == 0)
        #expect(try tracker.currentMonthRequests() == 0)
        #expect(try tracker.averageCostPerRequest() == 0)
    }

    @Test("On-device provider has zero cost")
    func onDeviceFree() throws {
        let cost = LLMUsage.calculateCost(provider: "On-Device", model: "llama-3.2", input: 10000, output: 5000)
        #expect(cost == 0)
    }
}

@Suite("Model Pricing")
struct ModelPricingTests {

    @Test("Claude Sonnet pricing")
    func sonnetPricing() {
        let p = ModelPricing.lookup(provider: "Claude", model: "claude-sonnet-4")
        // 3€/1M input
        #expect(abs(p.inputPerToken - 3.0 / 1_000_000) < 1e-12)
        // 15€/1M output
        #expect(abs(p.outputPerToken - 15.0 / 1_000_000) < 1e-12)
    }

    @Test("Claude Opus pricing")
    func opusPricing() {
        let p = ModelPricing.lookup(provider: "Claude", model: "claude-opus-4")
        #expect(p.inputPerToken > ModelPricing.lookup(provider: "Claude", model: "claude-sonnet-4").inputPerToken)
    }

    @Test("Claude Haiku pricing is cheapest")
    func haikuCheapest() {
        let haiku = ModelPricing.lookup(provider: "Claude", model: "claude-haiku-3.5")
        let sonnet = ModelPricing.lookup(provider: "Claude", model: "claude-sonnet-4")
        #expect(haiku.inputPerToken < sonnet.inputPerToken)
    }

    @Test("GPT-4o pricing")
    func gpt4oPricing() {
        let p = ModelPricing.lookup(provider: "OpenAI", model: "gpt-4o")
        #expect(p.inputPerToken > 0)
        #expect(p.outputPerToken > 0)
    }
}
