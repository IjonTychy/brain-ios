import Foundation
import GRDB

// MARK: - BehaviorTracker — Learns from user behavior to adapt suggestions
// @unchecked Sendable: pool is thread-safe (GRDB), no mutable state.
final class BehaviorTracker: @unchecked Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    // Build JSON context string safely (no string interpolation injection).
    private static func jsonContext(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    // MARK: - Record Signals

    func recordSearch(query: String) {
        Task.detached(priority: .background) { [pool] in
            try? await pool.write { db in
                try db.execute(
                    sql: "INSERT INTO behaviorSignals (signalType, context, positive) VALUES (?, ?, 1)",
                    arguments: ["search", query]
                )
            }
        }
    }

    func recordTagApplied(tagName: String, entryType: String) {
        Task.detached(priority: .background) { [pool] in
            try? await pool.write { db in
                let ctx = BehaviorTracker.jsonContext(["tagName": tagName, "entryType": entryType])
                try db.execute(
                    sql: "INSERT INTO behaviorSignals (signalType, context, positive) VALUES (?, ?, 1)",
                    arguments: ["tag", ctx]
                )
            }
        }
    }

    func recordSuggestionAccepted(type: String, context: String) {
        Task.detached(priority: .background) { [pool] in
            try? await pool.write { db in
                let ctx = BehaviorTracker.jsonContext(["type": type, "context": context])
                try db.execute(
                    sql: "INSERT INTO behaviorSignals (signalType, context, positive) VALUES (?, ?, 1)",
                    arguments: ["suggestion", ctx]
                )
            }
        }
    }

    func recordSuggestionDismissed(type: String, context: String) {
        Task.detached(priority: .background) { [pool] in
            try? await pool.write { db in
                let ctx = BehaviorTracker.jsonContext(["type": type, "context": context])
                try db.execute(
                    sql: "INSERT INTO behaviorSignals (signalType, context, positive) VALUES (?, ?, 0)",
                    arguments: ["suggestion", ctx]
                )
            }
        }
    }

    func recordToolUsed(toolName: String) {
        Task.detached(priority: .background) { [pool] in
            let hour = Calendar.current.component(.hour, from: Date())
            try? await pool.write { db in
                let ctx = BehaviorTracker.jsonContext(["tool": toolName, "hour": hour])
                try db.execute(
                    sql: "INSERT INTO behaviorSignals (signalType, context, positive) VALUES (?, ?, 1)",
                    arguments: ["tool_use", ctx]
                )
            }
        }
    }

    // MARK: - Analyze Behavior

    func frequentSearchTopics(days: Int = 30, limit: Int = 10) async -> [String] {
        do {
            return try await pool.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT context, COUNT(*) as cnt
                    FROM behaviorSignals
                    WHERE signalType = 'search'
                    AND createdAt > datetime('now', '-\(days) days')
                    GROUP BY context
                    ORDER BY cnt DESC
                    LIMIT ?
                    """, arguments: [limit])
                return rows.compactMap { $0["context"] as? String }
            }
        } catch {
            return []
        }
    }

    func preferredTags(forType entryType: String, limit: Int = 5) async -> [String] {
        do {
            return try await pool.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT context FROM behaviorSignals
                    WHERE signalType = 'tag'
                    AND context LIKE ?
                    AND createdAt > datetime('now', '-90 days')
                    GROUP BY context
                    ORDER BY COUNT(*) DESC
                    LIMIT ?
                    """, arguments: ["%\(entryType)%", limit])
                return rows.compactMap { $0["context"] as? String }
            }
        } catch {
            return []
        }
    }

    func activeHours(days: Int = 30) async -> [Int] {
        do {
            return try await pool.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT context FROM behaviorSignals
                    WHERE signalType = 'tool_use'
                    AND createdAt > datetime('now', '-\(days) days')
                    """)
                var hourCounts: [Int: Int] = [:]
                for row in rows {
                    if let ctx = row["context"] as? String,
                       let range = ctx.range(of: "\"hour\": ") {
                        let hourStr = ctx[range.upperBound...].prefix(while: { $0.isNumber })
                        if let hour = Int(hourStr) {
                            hourCounts[hour, default: 0] += 1
                        }
                    }
                }
                return hourCounts.sorted { $0.value > $1.value }.prefix(5).map { $0.key }
            }
        } catch {
            return []
        }
    }

    func suggestionAcceptanceRate(type: String) async -> Double {
        do {
            return try await pool.read { db in
                let total = try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM behaviorSignals
                    WHERE signalType = 'suggestion' AND context LIKE ?
                    """, arguments: ["%\(type)%"]) ?? 0
                guard total > 0 else { return 0.5 }
                let accepted = try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM behaviorSignals
                    WHERE signalType = 'suggestion' AND context LIKE ? AND positive = 1
                    """, arguments: ["%\(type)%"]) ?? 0
                return Double(accepted) / Double(total)
            }
        } catch {
            return 0.5
        }
    }

    // Cleanup old signals (>180 days)
    func cleanup() async {
        try? await pool.write { db in
            try db.execute(sql: "DELETE FROM behaviorSignals WHERE createdAt < datetime('now', '-180 days')")
        }
    }
}
