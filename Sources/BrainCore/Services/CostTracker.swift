import Foundation
import GRDB

// A single LLM usage record.
public struct LLMUsage: Codable, Sendable, FetchableRecord {
    public var id: Int64?
    public var provider: String
    public var model: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var totalTokens: Int
    public var costCents: Double  // Cost in USD-cents for precision
    public var requestType: String  // chat, tool, briefing, embedding
    public var createdAt: String?

    public init(
        id: Int64? = nil,
        provider: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        requestType: String = "chat"
    ) {
        self.id = id
        self.provider = provider
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = inputTokens + outputTokens
        self.costCents = Self.calculateCost(provider: provider, model: model, input: inputTokens, output: outputTokens)
        self.requestType = requestType
    }

    // Calculate cost in USD-cents based on provider pricing.
    // All prices in USD (industry standard), displayed in user's locale currency.
    public static func calculateCost(provider: String, model: String, input: Int, output: Int) -> Double {
        let pricing = ModelPricing.lookup(provider: provider, model: model)
        let inputCost = Double(input) * pricing.inputPerToken * 100  // to cents
        let outputCost = Double(output) * pricing.outputPerToken * 100
        return inputCost + outputCost
    }
}

// Pricing per token in USD (not cents).
// Updated March 2026 from official provider pricing pages.
public struct ModelPricing: Sendable {
    public let inputPerToken: Double
    public let outputPerToken: Double

    // Lookup pricing for a provider/model combination.
    // Prices in USD per token. Updated late March 2026.
    public static func lookup(provider: String, model: String) -> ModelPricing {
        let key = "\(provider.lowercased())/\(model.lowercased())"

        // --- Anthropic (March 2026) ---
        // Opus 4.6: $5 / $25 per 1M tokens
        if key.contains("opus") {
            return ModelPricing(inputPerToken: 5.0 / 1_000_000, outputPerToken: 25.0 / 1_000_000)
        }
        // Sonnet 4.5/4.6: $3 / $15 per 1M tokens
        if key.contains("sonnet") {
            return ModelPricing(inputPerToken: 3.0 / 1_000_000, outputPerToken: 15.0 / 1_000_000)
        }
        // Haiku 4.5: $1 / $5 per 1M tokens
        if key.contains("haiku") {
            return ModelPricing(inputPerToken: 1.0 / 1_000_000, outputPerToken: 5.0 / 1_000_000)
        }

        // --- OpenAI (March 2026) ---
        // GPT-5.4: $2.50 / $15 per 1M tokens
        if key.contains("gpt-5.4") && !key.contains("mini") && !key.contains("nano") {
            return ModelPricing(inputPerToken: 2.50 / 1_000_000, outputPerToken: 15.0 / 1_000_000)
        }
        // GPT-5.4 Mini: $0.75 / $4.50 per 1M tokens
        if key.contains("gpt-5.4") && key.contains("mini") {
            return ModelPricing(inputPerToken: 0.75 / 1_000_000, outputPerToken: 4.50 / 1_000_000)
        }
        // GPT-5.4 Nano: $0.20 / $1.25 per 1M tokens
        if key.contains("gpt-5.4") && key.contains("nano") {
            return ModelPricing(inputPerToken: 0.20 / 1_000_000, outputPerToken: 1.25 / 1_000_000)
        }
        // GPT-4.1: $2 / $8 per 1M tokens
        if key.contains("gpt-4.1") && !key.contains("mini") && !key.contains("nano") {
            return ModelPricing(inputPerToken: 2.0 / 1_000_000, outputPerToken: 8.0 / 1_000_000)
        }
        // GPT-4.1 Mini: $0.40 / $1.60 per 1M tokens
        if key.contains("gpt-4.1") && key.contains("mini") {
            return ModelPricing(inputPerToken: 0.40 / 1_000_000, outputPerToken: 1.60 / 1_000_000)
        }

        // --- Google Gemini (March 2026) ---
        // Gemini 3.1 Pro: $2 / $12 per 1M tokens
        if key.contains("gemini") && key.contains("pro") {
            return ModelPricing(inputPerToken: 2.0 / 1_000_000, outputPerToken: 12.0 / 1_000_000)
        }
        // Gemini 3.1 Flash-Lite: $0.25 / $1.50 per 1M tokens
        if key.contains("gemini") && key.contains("flash-lite") {
            return ModelPricing(inputPerToken: 0.25 / 1_000_000, outputPerToken: 1.50 / 1_000_000)
        }
        // Gemini 3 Flash: $0.50 / $3 per 1M tokens
        if key.contains("gemini") && key.contains("flash") {
            return ModelPricing(inputPerToken: 0.50 / 1_000_000, outputPerToken: 3.0 / 1_000_000)
        }

        // --- xAI Grok (March 2026) ---
        // Grok 4: $3 / $15 per 1M tokens
        if key.contains("grok-4") && !key.contains("fast") {
            return ModelPricing(inputPerToken: 3.0 / 1_000_000, outputPerToken: 15.0 / 1_000_000)
        }
        // Grok 4.1 Fast: $0.20 / $0.50 per 1M tokens
        if key.contains("grok") && key.contains("fast") {
            return ModelPricing(inputPerToken: 0.20 / 1_000_000, outputPerToken: 0.50 / 1_000_000)
        }

        // On-device = free
        if provider.lowercased().contains("on-device") || provider.lowercased().contains("ondevice") || provider.lowercased() == "lokal" {
            return ModelPricing(inputPerToken: 0, outputPerToken: 0)
        }

        // Default: Conservative estimate (Sonnet-level)
        return ModelPricing(inputPerToken: 3.0 / 1_000_000, outputPerToken: 15.0 / 1_000_000)
    }
}

// Tracks LLM costs over time and enforces budget limits.
public struct CostTracker: Sendable {

    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    // Record a usage event.
    public func record(
        provider: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        requestType: String = "chat"
    ) throws {
        let usage = LLMUsage(
            provider: provider,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            requestType: requestType
        )
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO llmUsage (provider, model, inputTokens, outputTokens, totalTokens, costCents, requestType, createdAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
                    """,
                arguments: [usage.provider, usage.model, usage.inputTokens, usage.outputTokens, usage.totalTokens, usage.costCents, usage.requestType]
            )
        }
    }

    // Total cost in USD for the current month.
    public func currentMonthCostUSD() throws -> Double {
        try pool.read { db in
            let sql = """
                SELECT COALESCE(SUM(costCents), 0) FROM llmUsage
                WHERE strftime('%Y-%m', createdAt) = strftime('%Y-%m', 'now')
                """
            let cents = try Double.fetchOne(db, sql: sql) ?? 0
            return cents / 100.0
        }
    }

    // Alias for backward compat
    public func currentMonthCostEuros() throws -> Double {
        try currentMonthCostUSD()
    }

    // Total tokens for the current month.
    public func currentMonthTokens() throws -> Int {
        try pool.read { db in
            let sql = """
                SELECT COALESCE(SUM(totalTokens), 0) FROM llmUsage
                WHERE strftime('%Y-%m', createdAt) = strftime('%Y-%m', 'now')
                """
            return try Int.fetchOne(db, sql: sql) ?? 0
        }
    }

    // Number of requests this month.
    public func currentMonthRequests() throws -> Int {
        try pool.read { db in
            let sql = """
                SELECT COUNT(*) FROM llmUsage
                WHERE strftime('%Y-%m', createdAt) = strftime('%Y-%m', 'now')
                """
            return try Int.fetchOne(db, sql: sql) ?? 0
        }
    }

    // Cost breakdown by provider for current month.
    public func currentMonthByProvider() throws -> [(provider: String, costEuros: Double, tokens: Int)] {
        let rows: [Row] = try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT provider, SUM(costCents) as totalCents, SUM(totalTokens) as totalTokens
                FROM llmUsage
                WHERE strftime('%Y-%m', createdAt) = strftime('%Y-%m', 'now')
                GROUP BY provider
                ORDER BY totalCents DESC
                """)
        }
        return rows.map { row in
            let p: String = row["provider"] ?? "Unknown"
            let c: Double = row["totalCents"] ?? 0
            let t: Int = row["totalTokens"] ?? 0
            return (provider: p, costEuros: c / 100.0, tokens: t)
        }
    }

    // Breakdown by model for a given time period.
    public func usageByModel(since: Date) throws -> [(model: String, provider: String, inputTokens: Int, outputTokens: Int, costUSD: Double, requests: Int)] {
        let formatter = ISO8601DateFormatter()
        let sinceStr = formatter.string(from: since)
        let rows: [Row] = try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT model, provider, SUM(inputTokens) as inp, SUM(outputTokens) as outp,
                       SUM(costCents) as cents, COUNT(*) as cnt
                FROM llmUsage
                WHERE createdAt >= ?
                GROUP BY model, provider
                ORDER BY cents DESC
                """, arguments: [sinceStr])
        }
        return rows.map { row in
            let m: String = row["model"] ?? ""
            let p: String = row["provider"] ?? ""
            let inp: Int = row["inp"] ?? 0
            let outp: Int = row["outp"] ?? 0
            let c: Double = row["cents"] ?? 0
            let r: Int = row["cnt"] ?? 0
            return (model: m, provider: p, inputTokens: inp, outputTokens: outp, costUSD: c / 100.0, requests: r)
        }
    }

    // Cost per day for the current month (for charts).
    public func dailyCosts(days: Int = 30) throws -> [(date: String, costEuros: Double)] {
        let rows: [Row] = try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT date(createdAt) as day, SUM(costCents) as totalCents
                FROM llmUsage
                WHERE createdAt >= date('now', ? || ' days')
                GROUP BY day
                ORDER BY day
                """, arguments: ["-\(max(days, 0))"])
        }
        return rows.map { row in
            let d: String = row["day"] ?? ""
            let c: Double = row["totalCents"] ?? 0
            return (date: d, costEuros: c / 100.0)
        }
    }

    // Check if under budget. Returns remaining USD (negative = over budget).
    public func remainingBudget(monthlyLimitEuros: Double) throws -> Double {
        let spent = try currentMonthCostUSD()
        return monthlyLimitEuros - spent
    }

    // Average cost per request this month.
    public func averageCostPerRequest() throws -> Double {
        let cost = try currentMonthCostUSD()
        let requests = try currentMonthRequests()
        guard requests > 0 else { return 0 }
        return cost / Double(requests)
    }

    // Total usage stats for all time.
    public func allTimeStats() throws -> (costEuros: Double, tokens: Int, requests: Int) {
        try pool.read { db in
            let sql = "SELECT COALESCE(SUM(costCents), 0), COALESCE(SUM(totalTokens), 0), COUNT(*) FROM llmUsage"
            let row = try Row.fetchOne(db, sql: sql)
            let cents: Double = row?[0] ?? 0
            let tokens: Int = row?[1] ?? 0
            let requests: Int = row?[2] ?? 0
            return (costEuros: cents / 100.0, tokens: tokens, requests: requests)
        }
    }
}
