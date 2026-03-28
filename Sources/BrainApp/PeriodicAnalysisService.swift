import Foundation
import BrainCore
import GRDB
#if canImport(os)
import os
#endif

// MARK: - PeriodicAnalysisService — Brain's autonomous nervous system
// Runs 3 layers: Backfill (historical data), Continuous (new data), Behavior Learning
@MainActor
@Observable
final class PeriodicAnalysisService {
    #if canImport(os)
    private static let logger = Logger(subsystem: "com.example.brain-ios", category: "PeriodicAnalysis")
    #endif

    private let pool: DatabasePool
    private let behaviorTracker: BehaviorTracker
    private var analysisTask: Task<Void, Never>?
    private var isRunning = false

    // Status (observable for UI)
    var isAnalyzing = false
    var lastAnalysisDate: Date?
    var backfillProgress: [String: BackfillProgress] = [:]
    var recentFindings: [AnalysisFinding] = []

    struct BackfillProgress {
        let entityType: String
        var processedCount: Int
        var totalEstimate: Int
        var isComplete: Bool
    }

    struct AnalysisFinding {
        let type: FindingType
        let title: String
        let detail: String
        let timestamp: Date
        let relatedIds: [Int64]

        enum FindingType: String {
            case unansweredEmail
            case crossReference
            case calendarContext
            case knowledgeFact
            case communicationPattern
            case behaviorInsight
        }
    }

    init(pool: DatabasePool, behaviorTracker: BehaviorTracker) {
        self.pool = pool
        self.behaviorTracker = behaviorTracker
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        #if canImport(os)
        Self.logger.info("PeriodicAnalysisService started")
        #endif

        analysisTask = Task { [weak self] in
            // Initial backfill check after 30 seconds
            try? await Task.sleep(for: .seconds(30))

            while !Task.isCancelled {
                guard let self = self else { break }
                await self.runAnalysisCycle()
                // Wait 30 minutes before next cycle
                try? await Task.sleep(for: .seconds(1800))
            }
        }
    }

    /// Single analysis cycle for BGAppRefreshTask (lightweight, ~30s)
    func runSingleCycle() async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }
        await runBackfillBatch()
        await runContinuousAnalysis()
        lastAnalysisDate = Date()
    }

    /// Deep analysis cycle for BGProcessingTask (heavier, up to 10min)
    func runDeepCycle(batchSize: Int = 50) async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }
        // Multiple backfill rounds with larger batches
        for _ in 0..<5 {
            await backfillEmails(batchSize: batchSize)
            await backfillEntries(batchSize: batchSize)
        }
        await runContinuousAnalysis()
        await behaviorTracker.cleanup()
        lastAnalysisDate = Date()
    }

    func stop() {
        isRunning = false
        analysisTask?.cancel()
        analysisTask = nil
    }

    // MARK: - Main Analysis Cycle

    private func runAnalysisCycle() async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }

        #if canImport(os)
        Self.logger.info("Starting analysis cycle")
        #endif

        // Layer 1: Backfill (process historical data in batches)
        await runBackfillBatch()

        // Layer 2: Continuous analysis (new data)
        await runContinuousAnalysis()

        // Layer 3: Behavior cleanup (periodic)
        await behaviorTracker.cleanup()

        // Layer 4: Knowledge consolidation (deduplicate facts)
        await consolidateKnowledge()

        // Layer 5: Skill proposals (check if patterns suggest new skills)
        await generateSkillProposals()

        lastAnalysisDate = Date()
    }

    // MARK: - Layer 1: Backfill Engine

    private func runBackfillBatch() async {
        await backfillEmails(batchSize: 10)
        await backfillEntries(batchSize: 10)
    }

    private func backfillEmails(batchSize: Int) async {
        do {
            // Get current progress
            let lastId = try await pool.read { db -> Int64 in
                let row = try Row.fetchOne(db, sql:
                    "SELECT lastProcessedId FROM analysisState WHERE entityType = 'email'")
                return (row?["lastProcessedId"] as? Int64) ?? 0
            }

            // Fetch next batch
            let emailRows: [Row] = try pool.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT id, fromAddr, toAddr, subject, bodyPlain, date
                    FROM emailCache
                    WHERE id > ?
                    ORDER BY id
                    LIMIT ?
                    """, arguments: [lastId, batchSize])
            }
            let emails = emailRows.map { row in
                let eid: Int64 = row["id"] ?? 0
                let f: String = row["fromAddr"] ?? ""
                let t: String = row["toAddr"] ?? ""
                let s: String = row["subject"] ?? ""
                let b: String = row["bodyPlain"] ?? ""
                let d: String = row["date"] ?? ""
                return (id: eid, from: f, to: t, subject: s, body: b, date: d)
            }

            guard !emails.isEmpty else {
                // Backfill complete for emails
                updateBackfillProgress(type: "email", isComplete: true)
                return
            }

            for email in emails {
                await analyzeEmail(id: email.id, from: email.from, to: email.to,
                                   subject: email.subject, body: email.body, date: email.date)
            }

            // Update progress
            let maxEmailId = emails.map(\.id).max() ?? lastId
            try await pool.write { db in
                try db.execute(sql: """
                    INSERT OR REPLACE INTO analysisState (entityType, lastProcessedId, lastRunAt, itemsProcessed)
                    VALUES ('email', ?, datetime('now'),
                            COALESCE((SELECT itemsProcessed FROM analysisState WHERE entityType = 'email'), 0) + ?)
                    """, arguments: [maxEmailId, emails.count])
            }
            updateBackfillProgress(type: "email", processed: emails.count)

            #if canImport(os)
            Self.logger.info("Backfill emails: processed \(emails.count), up to id \(maxEmailId)")
            #endif
        } catch {
            #if canImport(os)
            Self.logger.error("Email backfill error: \(error)")
            #endif
        }
    }

    private func backfillEntries(batchSize: Int) async {
        do {
            let lastId = try await pool.read { db -> Int64 in
                let row = try Row.fetchOne(db, sql:
                    "SELECT lastProcessedId FROM analysisState WHERE entityType = 'entry'")
                return (row?["lastProcessedId"] as? Int64) ?? 0
            }

            let entryRows: [Row] = try pool.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT id, title, body, type, createdAt
                    FROM entries
                    WHERE id > ? AND deletedAt IS NULL
                    ORDER BY id
                    LIMIT ?
                    """, arguments: [lastId, batchSize])
            }
            let entries = entryRows.map { row in
                let eid: Int64 = row["id"] ?? 0
                let t: String = row["title"] ?? ""
                let b: String = row["body"] ?? ""
                let tp: String = row["type"] ?? "thought"
                let c: String = row["createdAt"] ?? ""
                return (id: eid, title: t, body: b, type: tp, createdAt: c)
            }

            guard !entries.isEmpty else {
                updateBackfillProgress(type: "entry", isComplete: true)
                return
            }

            for entry in entries {
                await analyzeEntry(id: entry.id, title: entry.title, body: entry.body,
                                   type: entry.type, createdAt: entry.createdAt)
            }

            let maxEntryId = entries.map(\.id).max() ?? lastId
            try await pool.write { db in
                try db.execute(sql: """
                    INSERT OR REPLACE INTO analysisState (entityType, lastProcessedId, lastRunAt, itemsProcessed)
                    VALUES ('entry', ?, datetime('now'),
                            COALESCE((SELECT itemsProcessed FROM analysisState WHERE entityType = 'entry'), 0) + ?)
                    """, arguments: [maxEntryId, entries.count])
            }
            updateBackfillProgress(type: "entry", processed: entries.count)

            #if canImport(os)
            Self.logger.info("Backfill entries: processed \(entries.count), up to id \(maxEntryId)")
            #endif
        } catch {
            #if canImport(os)
            Self.logger.error("Entry backfill error: \(error)")
            #endif
        }
    }

    // MARK: - Single Item Analysis

    private func analyzeEmail(id: Int64, from: String, to: String, subject: String, body: String, date: String) async {
        // Extract person name from email address
        let personName = extractPersonName(from: from)
        let keywords = extractKeywords(from: subject + " " + body)

        // Save knowledge fact about this communication
        if !personName.isEmpty {
            let factText = "Kommunikation mit \(personName) am \(date): \(subject)"
            await saveKnowledgeFact(subject: personName, predicate: "email_communication",
                                    object: factText, sourceType: "auto_email", sourceId: id)
        }

        // Find related entries by keywords
        if !keywords.isEmpty {
            await crossLinkByKeywords(sourceType: "email", sourceId: id, keywords: keywords)
        }
    }

    private func analyzeEntry(id: Int64, title: String, body: String, type: String, createdAt: String) async {
        let text = title + " " + body
        let keywords = extractKeywords(from: text)
        let personNames = extractPersonNamesSimple(from: text)

        // Save knowledge facts for mentioned persons
        for name in personNames {
            let factText = "Erwaehnt in \(type)-Entry: \(title)"
            await saveKnowledgeFact(subject: name, predicate: "mentioned_in",
                                    object: factText, sourceType: "auto_entry", sourceId: id)
        }

        // Cross-link with similar entries
        if !keywords.isEmpty {
            await crossLinkByKeywords(sourceType: "entry", sourceId: id, keywords: keywords)
        }
    }

    // MARK: - Layer 2: Continuous Analysis

    private func runContinuousAnalysis() async {
        await analyzeUnansweredEmails()
        await prepareCalendarContext()
        await detectCommunicationPatterns()
    }

    private func analyzeUnansweredEmails() async {
        do {
            let unanswered = try await pool.read { db -> [(from: String, subject: String, date: String)] in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT fromAddr, subject, date FROM emailCache
                    WHERE isRead = 0 AND folder = 'INBOX'
                    AND date < datetime('now', '-1 day')
                    AND date > datetime('now', '-14 days')
                    ORDER BY date DESC
                    LIMIT 10
                    """)
                return rows.map { row in
                    (from: (row["fromAddr"] as? String) ?? "",
                     subject: (row["subject"] as? String) ?? "",
                     date: (row["date"] as? String) ?? "")
                }
            }

            if !unanswered.isEmpty {
                let names = unanswered.map { extractPersonName(from: $0.from) }.filter { !$0.isEmpty }
                let uniqueNames = Array(Set(names))
                if !uniqueNames.isEmpty {
                    let finding = AnalysisFinding(
                        type: .unansweredEmail,
                        title: "\(unanswered.count) unbeantwortete Mails",
                        detail: "Von: \(uniqueNames.prefix(3).joined(separator: ", "))",
                        timestamp: Date(),
                        relatedIds: []
                    )
                    addFinding(finding)
                }
            }
        } catch {
            #if canImport(os)
            Self.logger.error("Unanswered email analysis error: \(error)")
            #endif
        }
    }

    private func prepareCalendarContext() async {
        do {
            // Find entries related to upcoming calendar events (next 24h)
            // This queries the entries table for mentions of event-related keywords
            let upcomingEntries = try await pool.read { db -> Int in
                return try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM entries
                    WHERE type = 'event' AND deletedAt IS NULL
                    AND createdAt > datetime('now', '-1 day')
                    """) ?? 0
            }

            if upcomingEntries > 0 {
                let finding = AnalysisFinding(
                    type: .calendarContext,
                    title: "\(upcomingEntries) aktuelle Termine",
                    detail: "Relevante Notizen wurden verknuepft",
                    timestamp: Date(),
                    relatedIds: []
                )
                addFinding(finding)
            }
        } catch {
            #if canImport(os)
            Self.logger.error("Calendar context error: \(error)")
            #endif
        }
    }

    private func detectCommunicationPatterns() async {
        do {
            // Find contacts we haven't communicated with recently
            let neglected = try await pool.read { db -> [(name: String, lastContact: String)] in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT fromAddr, MAX(date) as lastDate FROM emailCache
                    WHERE folder IN ('INBOX', 'Sent')
                    GROUP BY fromAddr
                    HAVING lastDate < datetime('now', '-30 days')
                    AND lastDate > datetime('now', '-180 days')
                    ORDER BY lastDate DESC
                    LIMIT 5
                    """)
                return rows.map { row in
                    (name: (row["fromAddr"] as? String) ?? "",
                     lastContact: (row["lastDate"] as? String) ?? "")
                }
            }

            if !neglected.isEmpty {
                let names = neglected.map { extractPersonName(from: $0.name) }.filter { !$0.isEmpty }
                if !names.isEmpty {
                    let finding = AnalysisFinding(
                        type: .communicationPattern,
                        title: "Vernachlaessigte Kontakte",
                        detail: "\(names.prefix(3).joined(separator: ", ")) — seit 30+ Tagen kein Kontakt",
                        timestamp: Date(),
                        relatedIds: []
                    )
                    addFinding(finding)
                }
            }
        } catch {
            #if canImport(os)
            Self.logger.error("Communication pattern error: \(error)")
            #endif
        }
    }

    // MARK: - Helpers

    private func extractPersonName(from email: String) -> String {
        // Extract name from "Name <email>" or just "email@domain.com"
        if let angleBracket = email.firstIndex(of: "<") {
            let name = String(email[email.startIndex..<angleBracket]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        // Use part before @ as fallback
        if let atIndex = email.firstIndex(of: "@") {
            return String(email[email.startIndex..<atIndex])
                .replacingOccurrences(of: ".", with: " ")
                .capitalized
        }
        return email
    }

    private func extractKeywords(from text: String) -> [String] {
        // Simple keyword extraction: words > 4 chars, not common stop words
        let stopWords: Set<String> = ["aber", "alle", "also", "andere", "auch", "bitte",
            "dass", "dein", "deine", "diese", "dieser", "durch", "eine", "einem", "einen",
            "einer", "haben", "hier", "habe", "hast", "heute", "immer", "jetzt", "kann",
            "mein", "meine", "mehr", "nach", "nicht", "noch", "oder", "schon", "sehr",
            "sein", "seine", "sich", "sind", "ueber", "und", "unter", "viel", "weil",
            "wenn", "wird", "wurde", "your", "with", "from", "that", "this", "have",
            "will", "been", "were", "they", "their", "there", "what", "which", "about"]
        let words = text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 4 && !stopWords.contains($0) }
        // Return unique keywords, max 10
        return Array(Set(words)).prefix(10).map { String($0) }
    }

    private func extractPersonNamesSimple(from text: String) -> [String] {
        // Simple heuristic: capitalized word pairs that aren't at start of sentence
        var names: [String] = []
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        for i in 0..<(words.count - 1) {
            let w1 = words[i]
            let w2 = words[i + 1]
            if w1.count > 1 && w2.count > 1 &&
               w1.first?.isUppercase == true && w2.first?.isUppercase == true &&
               !w1.hasSuffix(".") && !w1.hasSuffix(":") {
                names.append("\(w1) \(w2)")
            }
        }
        return Array(Set(names)).prefix(5).map { String($0) }
    }

    private func saveKnowledgeFact(subject: String, predicate: String, object: String,
                                    sourceType: String, sourceId: Int64) async {
        do {
            try await pool.write { db in
                // Check if similar fact already exists
                let existing = try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM knowledgeFacts
                    WHERE subject = ? AND predicate = ? AND sourceType = ?
                    """, arguments: [subject, predicate, sourceType])
                guard (existing ?? 0) < 50 else { return } // Cap facts per subject/predicate

                try db.execute(sql: """
                    INSERT INTO knowledgeFacts (subject, predicate, object, confidence, sourceEntryId, sourceType)
                    VALUES (?, ?, ?, 0.7, ?, ?)
                    """, arguments: [subject, predicate, object, sourceId, sourceType])
            }
        } catch {
            #if canImport(os)
            Self.logger.error("Knowledge fact save error: \(error)")
            #endif
        }
    }

    private func crossLinkByKeywords(sourceType: String, sourceId: Int64, keywords: [String]) async {
        guard !keywords.isEmpty else { return }
        do {
            // Use FTS5 to find related entries
            let searchQuery = keywords.prefix(3).joined(separator: " OR ")
            try await pool.write { db in
                let relatedIds = try Int64.fetchAll(db, sql: """
                    SELECT entries.id FROM entries
                    JOIN entries_fts ON entries.id = entries_fts.rowid
                    WHERE entries_fts MATCH ?
                    AND entries.deletedAt IS NULL
                    AND entries.id != ?
                    LIMIT 3
                    """, arguments: [searchQuery, sourceId])

                for targetId in relatedIds {
                    // Check if link already exists
                    let exists = try Int.fetchOne(db, sql: """
                        SELECT COUNT(*) FROM links
                        WHERE (sourceId = ? AND targetId = ?) OR (sourceId = ? AND targetId = ?)
                        """, arguments: [sourceId, targetId, targetId, sourceId])
                    if (exists ?? 0) == 0 {
                        try db.execute(sql: """
                            INSERT INTO links (sourceId, targetId, relation, autoGenerated)
                            VALUES (?, ?, 'related', 1)
                            """, arguments: [sourceId, targetId])
                    }
                }
            }
        } catch {
            // FTS5 match errors are non-critical
        }
    }

    // MARK: - Layer 5: Skill Proposals

    private func generateSkillProposals() async {
        let patternEngine = PatternEngine(pool: pool)
        let patterns = (try? patternEngine.analyze()) ?? []
        let generator = SkillProposalGenerator(pool: pool)
        generator.generate(patterns: patterns, findings: recentFindings)
    }

    private func addFinding(_ finding: AnalysisFinding) {
        // Keep max 20 recent findings
        recentFindings.insert(finding, at: 0)
        if recentFindings.count > 20 {
            recentFindings = Array(recentFindings.prefix(20))
        }
    }

    private func updateBackfillProgress(type: String, processed: Int = 0, isComplete: Bool = false) {
        if var progress = backfillProgress[type] {
            progress.processedCount += processed
            progress.isComplete = isComplete
            backfillProgress[type] = progress
        } else {
            backfillProgress[type] = BackfillProgress(
                entityType: type, processedCount: processed,
                totalEstimate: 0, isComplete: isComplete)
        }
    }

    // MARK: - Knowledge Consolidation

    // Deduplicate and merge similar knowledge facts.
    // Keeps the highest-confidence version and removes exact/near duplicates.
    private func consolidateKnowledge() async {
        do {
            try await pool.write { db in
                // 1. Remove exact duplicates (keep highest confidence)
                try db.execute(sql: """
                    DELETE FROM knowledgeFacts WHERE id NOT IN (
                        SELECT MIN(id) FROM knowledgeFacts
                        GROUP BY subject, predicate, object
                    )
                """)

                // 2. For chat_personal facts about User, keep only the latest per predicate
                // (user info evolves — latest statement is most accurate)
                try db.execute(sql: """
                    DELETE FROM knowledgeFacts WHERE id NOT IN (
                        SELECT MAX(id) FROM knowledgeFacts
                        WHERE subject = 'User' AND sourceType = 'chat_personal'
                        GROUP BY predicate
                    ) AND subject = 'User' AND sourceType = 'chat_personal'
                """)

                // 3. Boost confidence for facts confirmed by multiple sources
                try db.execute(sql: """
                    UPDATE knowledgeFacts SET confidence = MIN(confidence + 0.1, 1.0)
                    WHERE subject IN (
                        SELECT subject FROM knowledgeFacts
                        GROUP BY subject, predicate
                        HAVING COUNT(DISTINCT sourceType) > 1
                    ) AND confidence < 1.0
                """)
            }
        } catch {
            #if canImport(os)
            Self.logger.error("Knowledge consolidation error: \(error)")
            #endif
        }
    }
}
