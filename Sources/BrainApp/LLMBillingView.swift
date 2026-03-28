import SwiftUI
import BrainCore

// Detailed LLM usage billing view.
// Shows token consumption per model and time period with estimated costs.
struct LLMBillingView: View {
    @Environment(DataBridge.self) private var dataBridge

    @State private var selectedPeriod: BillingPeriod = .thisMonth
    @State private var modelUsage: [ModelUsageRow] = []
    @State private var totalCostUSD: Double = 0
    @State private var totalTokens: Int = 0
    @State private var totalRequests: Int = 0
    @State private var dailyCosts: [(date: String, cost: Double)] = []
    @State private var isLoading = true

    @AppStorage("llmMonthlyBudget") private var monthlyBudget: Double = 10.0

    // Localized currency formatter based on user's locale
    private var currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        // All costs are stored in USD — convert display to user locale
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 4
        return f
    }()

    var body: some View {
        List {
            overviewSection
            if !modelUsage.isEmpty {
                modelBreakdownSection
            }
            budgetSection
        }
        .navigationTitle("Abrechnung")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("Zeitraum", selection: $selectedPeriod) {
                    ForEach(BillingPeriod.allCases) { period in
                        Text(period.label).tag(period)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .task { await loadData() }
        .onChange(of: selectedPeriod) { _, _ in
            Task { await loadData() }
        }
    }

    // MARK: - Overview

    private var overviewSection: some View {
        Section {
            if isLoading {
                ProgressView()
            } else if totalRequests == 0 {
                HStack {
                    Image(systemName: "chart.bar")
                        .foregroundStyle(.secondary)
                    Text("Keine Nutzung in diesem Zeitraum")
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 12) {
                    // Big cost number
                    Text(formatCurrency(totalCostUSD))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(totalCostUSD > monthlyBudget && selectedPeriod == .thisMonth ? .red : .primary)

                    Text(selectedPeriod.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Stats row
                    HStack(spacing: 24) {
                        statPill(value: "\(totalRequests)", label: "Anfragen")
                        statPill(value: formatTokenCount(totalTokens), label: "Tokens")
                        statPill(value: formatCurrency(totalRequests > 0 ? totalCostUSD / Double(totalRequests) : 0), label: "pro Anfrage")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
    }

    private func statPill(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Model Breakdown

    private var modelBreakdownSection: some View {
        Section("Nach Modell") {
            ForEach(modelUsage) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.model)
                                .font(.headline)
                            Text(row.provider)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(formatCurrency(row.costUSD))
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }

                    HStack(spacing: 16) {
                        Label("\(row.requests)x", systemImage: "bubble.left.and.bubble.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label(formatTokenCount(row.inputTokens) + " In", systemImage: "arrow.down.circle")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Label(formatTokenCount(row.outputTokens) + " Out", systemImage: "arrow.up.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    // Cost bar relative to most expensive model
                    if let maxCost = modelUsage.first?.costUSD, maxCost > 0 {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor.opacity(0.3))
                                .frame(width: geo.size.width * (row.costUSD / maxCost), height: 4)
                        }
                        .frame(height: 4)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Budget

    private var budgetSection: some View {
        Section("Monatsbudget") {
            HStack {
                Text("Budget")
                Spacer()
                TextField("10", value: $monthlyBudget, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                Text("USD")
                    .foregroundStyle(.secondary)
            }
            if selectedPeriod == .thisMonth && monthlyBudget > 0 {
                let progress = min(totalCostUSD / monthlyBudget, 1.0)
                let remaining = monthlyBudget - totalCostUSD
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                        .tint(remaining > 0 ? .green : .red)
                    HStack {
                        Text(remaining > 0 ? "Verbleibend: \(formatCurrency(remaining))" : "Budget ueberschritten!")
                            .font(.caption)
                            .foregroundStyle(remaining > 0 ? Color.secondary : Color.red)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        let db = dataBridge.db
        let tracker = CostTracker(pool: db.pool)

        let since = selectedPeriod.startDate

        do {
            let usage = try tracker.usageByModel(since: since)
            modelUsage = usage.map { item in
                ModelUsageRow(
                    model: item.model,
                    provider: item.provider,
                    inputTokens: item.inputTokens,
                    outputTokens: item.outputTokens,
                    costUSD: item.costUSD,
                    requests: item.requests
                )
            }
            totalCostUSD = usage.reduce(0) { $0 + $1.costUSD }
            totalTokens = usage.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
            totalRequests = usage.reduce(0) { $0 + $1.requests }
        } catch {
            modelUsage = []
        }
    }

    // MARK: - Formatting

    private func formatCurrency(_ usd: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: usd)) ?? String(format: "$%.2f", usd)
    }

    private func formatTokenCount(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1_000 {
            return String(format: "%.0fK", Double(tokens) / 1_000)
        }
        return "\(tokens)"
    }
}

// MARK: - Supporting Types

private struct ModelUsageRow: Identifiable {
    let id = UUID()
    let model: String
    let provider: String
    let inputTokens: Int
    let outputTokens: Int
    let costUSD: Double
    let requests: Int
}

enum BillingPeriod: String, CaseIterable, Identifiable {
    case today = "today"
    case thisWeek = "week"
    case thisMonth = "month"
    case last3Months = "3months"
    case allTime = "all"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Heute"
        case .thisWeek: return "Diese Woche"
        case .thisMonth: return "Dieser Monat"
        case .last3Months: return "3 Monate"
        case .allTime: return "Gesamt"
        }
    }

    var startDate: Date {
        let cal = Calendar.current
        switch self {
        case .today:
            return cal.startOfDay(for: Date())
        case .thisWeek:
            return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        case .thisMonth:
            return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        case .last3Months:
            return cal.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        case .allTime:
            return Date(timeIntervalSince1970: 0)
        }
    }
}
