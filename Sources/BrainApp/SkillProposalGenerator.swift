import Foundation
import BrainCore
import GRDB
#if canImport(os)
import os
#endif

// Generates autonomous skill proposals based on detected patterns and findings.
// Called at the end of each PeriodicAnalysisService cycle.
// Deterministic logic — no LLM calls. The LLM is only involved when the user
// accepts a proposal (via ProposalView → ChatService).
@MainActor
struct SkillProposalGenerator {
    #if canImport(os)
    private static let logger = Logger(subsystem: "com.example.brain-ios", category: "SkillProposal")
    #endif

    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    // MARK: - Public API

    /// Evaluate patterns and findings, generate proposals if appropriate.
    /// Max 1 proposal per day to avoid being annoying.
    func generate(
        patterns: [DetectedPattern],
        findings: [PeriodicAnalysisService.AnalysisFinding]
    ) {
        // Frequency limit: max 1 skill proposal per day
        guard !hasRecentSkillProposal() else { return }

        let installedSkills = (try? SkillService(pool: pool).list()) ?? []
        let installedIds = Set(installedSkills.map(\.id))

        // Try pattern-based proposals (higher priority)
        for pattern in patterns where pattern.confidence >= 0.6 {
            if let proposal = proposalForPattern(pattern, installedIds: installedIds) {
                createProposal(proposal)
                return // Max 1 per cycle
            }
        }

        // Try finding-based proposals
        let findingCounts = countFindingTypes(findings)
        for (type, count) in findingCounts where count >= 3 {
            if let proposal = proposalForFindingType(type, count: count, installedIds: installedIds) {
                createProposal(proposal)
                return
            }
        }
    }

    // MARK: - Pattern → Proposal Mapping

    private func proposalForPattern(_ pattern: DetectedPattern, installedIds: Set<String>) -> SkillProposal? {
        switch pattern.type {
        case .streak:
            guard !installedIds.contains("streak-tracker") else { return nil }
            return SkillProposal(
                title: "Streak-Tracker installieren?",
                description: pattern.description + " Soll ich einen Streak-Tracker erstellen, der deine Serien visualisiert?",
                suggestedSkillPrompt: """
                Erstelle einen Skill 'streak-tracker' mit dem Namen 'Streak Tracker'. \
                Er zeigt die aktuelle Task-Streak als grosse Zahl (stat-card), \
                einen motivierenden Text basierend auf der Streak-Laenge, \
                und eine Liste der letzten erledigten Tasks. \
                Data source: entries mit type=task und status=done, sortiert nach createdAt DESC, limit 30.
                """,
                triggerPattern: "streak"
            )

        case .frequency:
            guard !installedIds.contains("topic-tracker") else { return nil }
            return SkillProposal(
                title: "Themen-Tracker erstellen?",
                description: pattern.description + " Soll ich einen Tracker für deine häufigsten Themen erstellen?",
                suggestedSkillPrompt: """
                Erstelle einen Skill 'topic-tracker' mit dem Namen 'Themen Tracker'. \
                Er zeigt die häufigsten Tags als Liste mit Zähler (badge), \
                die neuesten Einträge dazu, und einen Chart der Tag-Verteilung. \
                Data source: tags fuer die Tag-Liste, entries fuer die neuesten Einträge.
                """,
                triggerPattern: "frequency"
            )

        case .neglect:
            guard !installedIds.contains("contact-reminder") else { return nil }
            return SkillProposal(
                title: "Kontakt-Reminder erstellen?",
                description: pattern.description + " Soll ich einen Skill erstellen, der dich an vernachlässigte Kontakte erinnert?",
                suggestedSkillPrompt: """
                Erstelle einen Skill 'contact-reminder' mit dem Namen 'Kontakt Reminder'. \
                Er zeigt eine Liste von Kontakten, mit denen länger nicht kommuniziert wurde. \
                Nutze knowledgeFacts mit predicate 'contacted' fuer die Daten. \
                Zeige Name, letztes Kontakt-Datum, und einen Button zum Erstellen einer Erinnerung.
                """,
                triggerPattern: "neglect"
            )

        case .anomaly:
            guard !installedIds.contains("activity-monitor") else { return nil }
            return SkillProposal(
                title: "Aktivitäts-Monitor erstellen?",
                description: pattern.description + " Soll ich einen Skill erstellen, der deine Aktivität überwacht?",
                suggestedSkillPrompt: """
                Erstelle einen Skill 'activity-monitor' mit dem Namen 'Aktivitaets Monitor'. \
                Er zeigt die Anzahl Einträge pro Tag der letzten Woche als Chart, \
                den Durchschnitt als stat-card, und Tage mit ungewöhnlich wenig Aktivität markiert. \
                Data source: entries sortiert nach createdAt DESC, limit 100.
                """,
                triggerPattern: "anomaly"
            )

        case .correlation:
            // Correlations are too complex for a generic skill template
            return nil
        }
    }

    // MARK: - Finding → Proposal Mapping

    private func proposalForFindingType(
        _ type: PeriodicAnalysisService.AnalysisFinding.FindingType,
        count: Int,
        installedIds: Set<String>
    ) -> SkillProposal? {
        switch type {
        case .unansweredEmail:
            guard !installedIds.contains("email-followup") else { return nil }
            return SkillProposal(
                title: "E-Mail Follow-Up Skill erstellen?",
                description: "Du hast regelmässig unbeantwortete E-Mails (\(count) erkannt). Soll ich einen Follow-Up-Skill erstellen?",
                suggestedSkillPrompt: """
                Erstelle einen Skill 'email-followup' mit dem Namen 'E-Mail Follow-Up'. \
                Er zeigt unbeantwortete E-Mails als Liste mit Absender, Betreff und Datum. \
                Data source: emailCache mit filter isRead=false, sortiert nach date DESC, limit 20. \
                Jede E-Mail hat einen Button 'Antwort verfassen' der navigate.tab zu mail ausfuehrt.
                """,
                triggerPattern: "unansweredEmail"
            )

        case .communicationPattern:
            guard !installedIds.contains("comm-dashboard") else { return nil }
            return SkillProposal(
                title: "Kommunikations-Dashboard erstellen?",
                description: "Ich erkenne Kommunikationsmuster in deinen Daten. Soll ich ein Dashboard dafür erstellen?",
                suggestedSkillPrompt: """
                Erstelle einen Skill 'comm-dashboard' mit dem Namen 'Kommunikation'. \
                Er zeigt eine Übersicht der Kommunikation: Anzahl E-Mails (stat-card), \
                häufigste Kontakte (Liste), und ungelesene E-Mails. \
                Data source: emailCache fuer E-Mails, knowledgeFacts mit predicate 'contacted' fuer Kontakte.
                """,
                triggerPattern: "communicationPattern"
            )

        default:
            return nil
        }
    }

    // MARK: - Helpers

    private func hasRecentSkillProposal() -> Bool {
        let proposals: [Proposal]
        do {
            proposals = try pool.read { db in
                try Proposal.order(Column("createdAt").desc).limit(20).fetchAll(db)
            }
        } catch {
            return false
        }
        let todayPrefix = String(BrainDateFormatting.iso8601Now().prefix(10))
        return proposals.contains { proposal in
            guard let spec = proposal.changeSpec,
                  spec.contains("skill_suggestion"),
                  let created = proposal.createdAt else { return false }
            return created.hasPrefix(todayPrefix)
        }
    }

    private func countFindingTypes(
        _ findings: [PeriodicAnalysisService.AnalysisFinding]
    ) -> [PeriodicAnalysisService.AnalysisFinding.FindingType: Int] {
        var counts: [PeriodicAnalysisService.AnalysisFinding.FindingType: Int] = [:]
        for finding in findings {
            counts[finding.type, default: 0] += 1
        }
        return counts
    }

    private func createProposal(_ proposal: SkillProposal) {
        let changeSpec: String
        do {
            let specData = try JSONEncoder().encode([
                "type": "skill_suggestion",
                "trigger": proposal.triggerPattern,
                "suggestedSkillPrompt": proposal.suggestedSkillPrompt,
            ])
            changeSpec = String(data: specData, encoding: .utf8) ?? "{}"
        } catch {
            changeSpec = "{}"
        }

        do {
            try pool.write { db in
                var p = Proposal(
                    title: proposal.title,
                    description: proposal.description,
                    category: "C",
                    changeSpec: changeSpec
                )
                try p.insert(db)
            }
        } catch {
            #if canImport(os)
            Self.logger.error("Failed to create skill proposal: \(error)")
            #endif
        }

        #if canImport(os)
        Self.logger.info("Generated skill proposal: \(proposal.title)")
        #endif
    }
}

// Internal proposal representation before persisting to DB.
private struct SkillProposal {
    let title: String
    let description: String
    let suggestedSkillPrompt: String
    let triggerPattern: String
}
