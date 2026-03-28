import Foundation
import GRDB

// Phase 8: Proactive Intelligence — Pattern detection over entries.
// This is native Swift code (not JSON-driven) because pattern detection
// over thousands of entries needs direct DB access and embeddings.

// A detected pattern in the user's data.
public struct DetectedPattern: Sendable {
    public let type: PatternType
    public let description: String
    public let confidence: Double
    public let relatedEntryIds: [Int64]

    public init(type: PatternType, description: String, confidence: Double, relatedEntryIds: [Int64]) {
        self.type = type
        self.description = description
        self.confidence = confidence
        self.relatedEntryIds = relatedEntryIds
    }
}

public enum PatternType: String, Sendable {
    case frequency        // "Du erstellst jeden Montag Einträge zum Thema X"
    case neglect          // "Du hast Sarah seit 2 Wochen nicht geantwortet"
    case correlation      // "Wenn du Yoga machst, schreibst du positivere Einträge"
    case streak           // "5 Tage in Folge Tasks erledigt"
    case anomaly          // "Ungewöhnlich wenig Aktivität diese Woche"
}

// Analyses entries for patterns. Runs periodically in the background.
public struct PatternEngine: Sendable {

    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    // Run all pattern detectors and return findings.
    public func analyze() throws -> [DetectedPattern] {
        var patterns: [DetectedPattern] = []

        patterns.append(contentsOf: try detectStreaks())
        patterns.append(contentsOf: try detectNeglectedContacts())
        patterns.append(contentsOf: try detectActivityAnomalies())
        patterns.append(contentsOf: try detectTopicTrends())
        patterns.append(contentsOf: try detectProductiveHours())

        return patterns.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Streak detection

    // Find consecutive days with completed tasks.
    private func detectStreaks() throws -> [DetectedPattern] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT DATE(createdAt) as day, COUNT(*) as cnt
                FROM entries
                WHERE type = 'task' AND status = 'done' AND deletedAt IS NULL
                GROUP BY DATE(createdAt)
                ORDER BY day DESC
                LIMIT 30
                """)

            guard rows.count >= 2 else { return [] }

            // Count consecutive days from today
            var streak = 0
            let today = DateFormatters.dateOnly.string(from: Date())
            var expectedDate = today

            for row in rows {
                let day: String = row["day"]
                if day == expectedDate {
                    streak += 1
                    // Calculate previous day
                    if let date = DateFormatters.dateOnly.date(from: day) {
                        guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: date) else { break }
                        expectedDate = DateFormatters.dateOnly.string(from: prev)
                    }
                } else {
                    break
                }
            }

            guard streak >= 3 else { return [] }

            return [DetectedPattern(
                type: .streak,
                description: "\(streak) Tage in Folge Tasks erledigt",
                confidence: min(Double(streak) / 7.0, 1.0),
                relatedEntryIds: []
            )]
        }
    }

    // MARK: - Neglected contacts

    // Find people not contacted recently (based on knowledge facts from email/chat).
    private func detectNeglectedContacts() throws -> [DetectedPattern] {
        try pool.read { db in
            // Find people with email_communication facts, whose last contact is > 14 days ago
            let rows = try Row.fetchAll(db, sql: """
                SELECT subject, MAX(learnedAt) as lastContact,
                       COUNT(*) as totalInteractions
                FROM knowledgeFacts
                WHERE predicate IN ('email_communication', 'mentioned_in_chat')
                  AND subject != 'User'
                  AND subject != ''
                GROUP BY subject
                HAVING MAX(learnedAt) < datetime('now', '-14 days')
                   AND COUNT(*) >= 2
                ORDER BY MAX(learnedAt) ASC
                LIMIT 5
            """)

            return rows.compactMap { row -> DetectedPattern? in
                guard let name: String = row["subject"],
                      let lastContact: String = row["lastContact"],
                      let count: Int = row["totalInteractions"] else { return nil }
                return DetectedPattern(
                    type: .neglect,
                    description: "\(name) nicht kontaktiert — Letzter Kontakt: \(lastContact.prefix(10)). \(count) bisherige Interaktionen.",
                    confidence: 0.7,
                    relatedEntryIds: []
                )
            }
        }
    }

    // MARK: - Activity anomalies

    // Detect unusual activity levels compared to the user's baseline.
    private func detectActivityAnomalies() throws -> [DetectedPattern] {
        try pool.read { db in
            // Average entries per day over last 30 days
            let avgRow = try Row.fetchOne(db, sql: """
                SELECT AVG(daily_count) as avg_count FROM (
                    SELECT DATE(createdAt) as day, COUNT(*) as daily_count
                    FROM entries
                    WHERE deletedAt IS NULL AND createdAt > datetime('now', '-30 days')
                    GROUP BY DATE(createdAt)
                )
                """)

            let baseline: Double = avgRow?["avg_count"] ?? 0

            // Today's count
            let todayRow = try Row.fetchOne(db, sql: """
                SELECT COUNT(*) as cnt
                FROM entries
                WHERE deletedAt IS NULL AND DATE(createdAt) = DATE('now')
                """)

            let todayCount: Double = todayRow?["cnt"] ?? 0

            guard baseline > 2 else { return [] } // Need enough data

            if todayCount < baseline * 0.3 {
                return [DetectedPattern(
                    type: .anomaly,
                    description: "Ungewoehnlich wenig Aktivitaet heute",
                    confidence: 0.6,
                    relatedEntryIds: []
                )]
            }

            return []
        }
    }
    // MARK: - Topic trends

    // Detect trending topics based on frequently used tags.
    private func detectTopicTrends() throws -> [DetectedPattern] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.name, COUNT(*) as cnt
                FROM entryTags et
                JOIN tags t ON t.id = et.tagId
                JOIN entries e ON e.id = et.entryId
                WHERE e.deletedAt IS NULL
                AND e.createdAt > datetime('now', '-7 days')
                GROUP BY t.name
                HAVING cnt >= 3
                ORDER BY cnt DESC
                LIMIT 3
                """)

            return rows.compactMap { row -> DetectedPattern? in
                guard let name: String = row["name"],
                      let count: Int = row["cnt"] else { return nil }
                return DetectedPattern(
                    type: .frequency,
                    description: "Thema '\(name)' beschäftigt dich gerade (\(count) Entries diese Woche)",
                    confidence: min(Double(count) / 10.0, 0.9),
                    relatedEntryIds: []
                )
            }
        }
    }

    // MARK: - Productive hours

    // Detect the user's most productive hours.
    private func detectProductiveHours() throws -> [DetectedPattern] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT CAST(strftime('%H', createdAt) AS INTEGER) as hour, COUNT(*) as cnt
                FROM entries
                WHERE deletedAt IS NULL
                AND createdAt > datetime('now', '-14 days')
                GROUP BY hour
                ORDER BY cnt DESC
                LIMIT 3
                """)

            guard rows.count >= 2 else { return [] }

            guard let topHour: Int = rows.first?["hour"],
                  let topCount: Int = rows.first?["cnt"],
                  topCount >= 5 else { return [] }

            let hourStr = String(format: "%02d:00-%02d:00", topHour, topHour + 1)
            return [DetectedPattern(
                type: .frequency,
                description: "Deine produktivste Zeit ist \(hourStr) Uhr",
                confidence: 0.7,
                relatedEntryIds: []
            )]
        }
    }
}

// MARK: - Date formatting helpers

public enum DateFormatters: Sendable {
    // Per-call factory avoids nonisolated(unsafe) on non-Sendable formatter.
    public static var iso8601: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
