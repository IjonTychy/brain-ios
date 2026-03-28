import Foundation
import BrainCore
import GRDB
import os.log
import UserNotifications

// Proactive intelligence service: Morgen-Briefing, Abend-Zusammenfassung,
// Pattern Detection, "On This Day", and contextual suggestions.
// Runs on app launch and periodically via background tasks.
@MainActor @Observable
final class ProactiveService {

    private let logger = Logger(subsystem: "com.example.brain-ios", category: "ProactiveService")

    private(set) var morningBriefing: BrainBriefing?
    private(set) var eveningRecap: BrainRecap?
    private(set) var detectedPatterns: [DetectedPattern] = []
    private(set) var onThisDayEntries: [Entry] = []
    private(set) var isAnalyzing = false

    private let pool: DatabasePool
    private let patternEngine: PatternEngine

    init(pool: DatabasePool) {
        self.pool = pool
        self.patternEngine = PatternEngine(pool: pool)
    }

    // MARK: - Morning Briefing

    // Generate a morning briefing with today's tasks, events, and insights.
    func generateMorningBriefing() {
        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            // Open tasks
            let openTasks = try pool.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT id, title, priority FROM entries
                    WHERE type = 'task' AND status = 'active' AND deletedAt IS NULL
                    ORDER BY priority DESC, createdAt ASC
                    LIMIT 10
                """)
            }

            // Overdue tasks (created > 7 days ago and still active)
            let overdueTasks = try pool.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT id, title FROM entries
                    WHERE type = 'task' AND status = 'active' AND deletedAt IS NULL
                    AND createdAt < datetime('now', '-7 days')
                    ORDER BY createdAt ASC
                    LIMIT 5
                """)
            }

            // Recent entries from yesterday
            let yesterdayEntries = try pool.read { db in
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM entries
                    WHERE deletedAt IS NULL AND DATE(createdAt) = DATE('now', '-1 day')
                """)
            } ?? 0

            // Total stats
            let totalEntries = try pool.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE deletedAt IS NULL")
            } ?? 0

            // Email stats
            let unreadEmails = try pool.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM emailCache WHERE isRead = 0")
            } ?? 0

            // Patterns (including email patterns)
            var patterns = try patternEngine.analyze()
            let emailPatterns = (try? analyzeEmailPatterns()) ?? []
            patterns.append(contentsOf: emailPatterns)
            self.detectedPatterns = patterns

            // On This Day
            loadOnThisDay()

            // Build briefing
            let tasks = openTasks.map { row -> BriefingItem in
                BriefingItem(
                    id: row["id"] as Int64? ?? 0,
                    title: row["title"] as String? ?? "Ohne Titel",
                    subtitle: nil
                )
            }

            let overdue = overdueTasks.map { row -> BriefingItem in
                BriefingItem(
                    id: row["id"] as Int64? ?? 0,
                    title: row["title"] as String? ?? "Ohne Titel",
                    subtitle: "Überfällig"
                )
            }

            let patternInsights = patterns.map { p in
                BriefingInsight(
                    type: p.type.rawValue,
                    message: p.description,
                    confidence: p.confidence
                )
            }

            morningBriefing = BrainBriefing(
                greeting: greetingForTimeOfDay(),
                date: formattedDate(),
                openTasks: tasks,
                overdueTasks: overdue,
                todayEvents: [], // Will be filled by EventKit
                insights: patternInsights,
                yesterdayCount: yesterdayEntries,
                totalEntries: totalEntries,
                unreadEmails: unreadEmails,
                onThisDay: onThisDayEntries.prefix(3).map { entry in
                    BriefingItem(
                        id: entry.id ?? 0,
                        title: entry.title ?? "Ohne Titel",
                        subtitle: formatRelativeDate(entry.createdAt)
                    )
                }
            )
        } catch {
            logger.error("Morning briefing failed: \(error)")
        }
    }

    // MARK: - Evening Recap

    // Generate an evening recap of today's activity.
    func generateEveningRecap() {
        do {
            let todayEntries = try pool.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT id, title, type, status FROM entries
                    WHERE deletedAt IS NULL AND DATE(createdAt) = DATE('now')
                    ORDER BY createdAt DESC
                """)
            }

            let completedToday = try pool.read { db in
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM entries
                    WHERE type = 'task' AND status = 'done'
                    AND DATE(updatedAt) = DATE('now')
                    AND deletedAt IS NULL
                """)
            } ?? 0

            let stillOpen = try pool.read { db in
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM entries
                    WHERE type = 'task' AND status = 'active'
                    AND deletedAt IS NULL
                """)
            } ?? 0

            let items = todayEntries.map { row -> RecapItem in
                RecapItem(
                    title: row["title"] as String? ?? "Ohne Titel",
                    type: row["type"] as String? ?? "thought",
                    status: row["status"] as String? ?? "active"
                )
            }

            eveningRecap = BrainRecap(
                date: formattedDate(),
                entriesCreated: todayEntries.count,
                tasksCompleted: completedToday,
                tasksStillOpen: stillOpen,
                items: items
            )
        } catch {
            logger.error("Evening recap failed: \(error)")
        }
    }

    // MARK: - On This Day

    // Find entries from the same day in previous weeks/months/years.
    func loadOnThisDay() {
        do {
            let entries = try pool.read { db -> [Entry] in
                // Entries from same day-of-year in previous years
                let rows = try Entry.fetchAll(db, sql: """
                    SELECT * FROM entries
                    WHERE deletedAt IS NULL
                    AND strftime('%m-%d', createdAt) = strftime('%m-%d', 'now')
                    AND DATE(createdAt) != DATE('now')
                    ORDER BY createdAt DESC
                    LIMIT 10
                """)
                return rows
            }
            // Also find entries from exactly 1 week and 1 month ago
            let weekAgo = try pool.read { db in
                try Entry.fetchAll(db, sql: """
                    SELECT * FROM entries
                    WHERE deletedAt IS NULL
                    AND DATE(createdAt) = DATE('now', '-7 days')
                    ORDER BY createdAt DESC
                    LIMIT 3
                """)
            }
            let monthAgo = try pool.read { db in
                try Entry.fetchAll(db, sql: """
                    SELECT * FROM entries
                    WHERE deletedAt IS NULL
                    AND DATE(createdAt) = DATE('now', '-30 days')
                    ORDER BY createdAt DESC
                    LIMIT 3
                """)
            }

            // Combine and deduplicate
            var allEntries = entries
            for entry in weekAgo + monthAgo {
                if !allEntries.contains(where: { $0.id == entry.id }) {
                    allEntries.append(entry)
                }
            }
            self.onThisDayEntries = Array(allEntries.prefix(10))
        } catch {
            logger.error("On This Day query failed: \(error)")
            onThisDayEntries = []
        }
    }

    // MARK: - Pattern Detection (standalone, called periodically)

    func runPatternAnalysis() {
        do {
            detectedPatterns = try patternEngine.analyze()
            // Also analyze emails for patterns
            let emailPatterns = try analyzeEmailPatterns()
            detectedPatterns.append(contentsOf: emailPatterns)
        } catch {
            logger.error("Pattern analysis failed: \(error)")
            detectedPatterns = []
        }
    }

    // MARK: - Email Pattern Analysis

    // Analyze cached emails for patterns: top senders, unread trends, response needs.
    private func analyzeEmailPatterns() throws -> [DetectedPattern] {
        var patterns: [DetectedPattern] = []

        // Unread email count
        let unreadCount = try pool.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM emailCache WHERE isRead = 0
            """)
        } ?? 0

        if unreadCount > 10 {
            patterns.append(DetectedPattern(
                type: .anomaly,
                description: "\(unreadCount) ungelesene E-Mails im Posteingang.",
                confidence: 0.9,
                relatedEntryIds: []
            ))
        }

        // Top senders (most frequent in last 7 days)
        let topSenders = try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT fromAddr, COUNT(*) as cnt FROM emailCache
                WHERE date > datetime('now', '-7 days') AND fromAddr IS NOT NULL
                GROUP BY fromAddr
                ORDER BY cnt DESC
                LIMIT 3
            """)
        }

        for sender in topSenders {
            let addr: String = sender["fromAddr"] ?? ""
            let count: Int = sender["cnt"] ?? 0
            if count >= 5 {
                patterns.append(DetectedPattern(
                    type: .frequency,
                    description: "\(addr) hat dir diese Woche \(count) E-Mails geschickt.",
                    confidence: 0.8,
                    relatedEntryIds: []
                ))
            }
        }

        // Emails that might need a reply (received > 2 days ago, from known contacts, not read)
        let needReply = try pool.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM emailCache
                WHERE isRead = 0 AND folder = 'INBOX'
                AND date < datetime('now', '-2 days')
                AND date > datetime('now', '-14 days')
            """)
        } ?? 0

        if needReply > 0 {
            patterns.append(DetectedPattern(
                type: .anomaly,
                description: "\(needReply) E-Mail\(needReply == 1 ? "" : "s") seit über 2 Tagen unbeantwortet.",
                confidence: 0.7,
                relatedEntryIds: []
            ))
        }

        return patterns
    }

    // MARK: - Self-Modifier: Auto-evaluate rules on app events

    // Evaluate rules for a specific trigger and execute matching actions.
    func evaluateRules(trigger: String, entryType: String? = nil) {
        do {
            let rulesEngine = RulesEngine(pool: pool)
            let hour = Calendar.current.component(.hour, from: Date())
            let minute = Calendar.current.component(.minute, from: Date())
            let timeOfDay = String(format: "%02d:%02d", hour, minute)
            let matches = try rulesEngine.evaluate(
                context: RuleContext(trigger: trigger, entryType: entryType, timeOfDay: timeOfDay)
            )

            for match in matches {
                logger.info("Rule matched: \(match.rule.name) (trigger: \(trigger))")
                // Parse and execute the action
                if let actionData = match.actionJSON.data(using: .utf8),
                   let action = try? JSONSerialization.jsonObject(with: actionData) as? [String: Any],
                   let actionType = action["type"] as? String {
                    executeRuleAction(type: actionType, config: action, ruleName: match.rule.name)
                }
            }

            if !matches.isEmpty {
                logger.info("Self-Modifier: \(matches.count) Regel(n) ausgelöst für Trigger '\(trigger)'")
            }
        } catch {
            logger.error("Rule evaluation failed for trigger '\(trigger)': \(error)")
        }
    }

    // Execute a single rule action based on its type.
    private func executeRuleAction(type: String, config: [String: Any], ruleName: String) {
        switch type {
        case "generate_briefing":
            generateMorningBriefing()
        case "generate_recap":
            generateEveningRecap()
        case "run_patterns":
            runPatternAnalysis()
        case "notification":
            if let message = config["message"] as? String {
                scheduleLocalNotification(title: "Brain: \(ruleName)", body: message)
            }
        case "log":
            let message = config["message"] as? String ?? ruleName
            logger.info("Rule action log: \(message)")
        default:
            logger.info("Unknown rule action type: \(type) for rule: \(ruleName)")
        }
    }

    private func scheduleLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "rule-\(UUID().uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                Task { @MainActor in
                    self?.logger.error("Notification scheduling failed: \(error)")
                }
            }
        }
    }

    // MARK: - Contextual check: Should show briefing?

    var shouldShowMorningBriefing: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 6 && hour <= 10 && morningBriefing == nil
    }

    var shouldShowEveningRecap: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 18 && hour <= 23 && eveningRecap == nil
    }

    // MARK: - Helpers

    private func greetingForTimeOfDay() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Guten Morgen"
        case 12..<17: return "Guten Tag"
        case 17..<22: return "Guten Abend"
        default: return "Gute Nacht"
        }
    }

    private func formattedDate() -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "de_CH")
        fmt.dateFormat = "EEEE, d. MMMM yyyy"
        return fmt.string(from: Date())
    }

    private func formatRelativeDate(_ dateStr: String?) -> String {
        guard let dateStr,
              let date = DateFormatters.iso8601.date(from: dateStr) else { return "" }

        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 7 { return "Vor \(days) Tagen" }
        if days < 30 { return "Vor \(days / 7) Wochen" }
        if days < 365 { return "Vor \(days / 30) Monaten" }
        return "Vor \(days / 365) Jahren"
    }
}

// MARK: - Briefing Data Models

struct BrainBriefing {
    let greeting: String
    let date: String
    let openTasks: [BriefingItem]
    let overdueTasks: [BriefingItem]
    let todayEvents: [BriefingItem]
    let insights: [BriefingInsight]
    let yesterdayCount: Int
    let totalEntries: Int
    let unreadEmails: Int
    let onThisDay: [BriefingItem]
}

struct BriefingItem: Identifiable {
    let id: Int64
    let title: String
    let subtitle: String?
}

struct BriefingInsight: Identifiable {
    let id = UUID()
    let type: String
    let message: String
    let confidence: Double
}

struct BrainRecap {
    let date: String
    let entriesCreated: Int
    let tasksCompleted: Int
    let tasksStillOpen: Int
    let items: [RecapItem]
}

struct RecapItem: Identifiable {
    let id = UUID()
    let title: String
    let type: String
    let status: String
}
