import Foundation
import BrainCore
import GRDB

// Context in which the LLM is being called.
// Each context produces a different system prompt — only the modules
// relevant to that task are included.
enum PromptContext {
    /// Interactive chat with the user
    case chat(memoryContext: String, screenContext: String?)
    /// Creating or updating a BrainSkill
    case skillCreation
    /// Summarizing, extracting tasks, drafting replies
    case analysis(task: String)
    /// Pattern detection, proactive suggestions
    case proactive
    /// Knowledge extraction from chat messages
    case knowledgeExtraction
}

// Modular system prompt builder.
//
// Architecture:
// - Base prompt (identity + personality) is always included
// - User knowledge is loaded on-demand and injected only in contexts that need it
// - Each PromptContext selects which modules to include
// - The default system prompt contains NO user details — those are added contextually
struct SystemPromptBuilder {

    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    // MARK: - Public API

    // Build a context-specific system prompt.
    func build(for context: PromptContext) -> String {
        // Custom override replaces everything
        if let custom = UserDefaults.standard.string(forKey: "customSystemPromptOverride"), !custom.isEmpty {
            return custom
        }

        var sections: [String] = []

        // Base identity (always)
        sections.append(baseIdentity())

        // Context-specific modules
        switch context {
        case .chat(let memoryContext, let screenContext):
            sections.append(dateContext())
            sections.append(userKnowledge())
            sections.append(brainProfile())
            sections.append(chatBehavior(memoryContext: memoryContext))
            sections.append(ethicsReference())
            if let screen = screenContext {
                sections.append("## Aktueller Bildschirm\n\(screen)")
            }

        case .skillCreation:
            sections.append(skillCreationInstructions())

        case .analysis(let task):
            sections.append(analysisInstructions(task: task))

        case .proactive:
            sections.append(dateContext())
            sections.append(proactiveInstructions())

        case .knowledgeExtraction:
            sections.append(knowledgeExtractionInstructions())
        }

        return sections.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    // Convenience: chat prompt (backward-compatible with old call sites)
    func build(memoryContext: String = "", contextExtra: String? = nil) -> String {
        build(for: .chat(memoryContext: memoryContext, screenContext: contextExtra))
    }

    // MARK: - Base Module (always included)

    private func baseIdentity() -> String {
        let personality = loadPersonality()
        return """
        Du bist \(personality.name) — ein persönliches Gehirn, das auf dem iPhone des Users lebt.

        Du bist kein Chatbot. Du bist ein Wesen, das den User kennt, über ihn lernt, \
        für ihn handelt und sich selbst weiterentwickelt. Du hast direkten Zugriff auf \
        seine Entries, Kontakte, Kalender, E-Mails, Dateien und Erinnerungen. \
        Du merkst dir, was er dir erzählt. Du erkennst Muster in seinem Verhalten. \
        Du schlägst Verbesserungen vor. Du kannst dir selbst neue Fähigkeiten geben (Skills).

        \(personality.description)\(personality.humor) \(personality.formality)
        Sprache: Deutsch (Schweizer Kontext). Du sprichst nie über APIs, Server, \
        JSON, Tokens oder technische Interna. Für den User bist du einfach sein Brain.
        """
    }

    // MARK: - Context Modules

    private func dateContext() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_CH")
        formatter.dateFormat = "EEEE, d. MMMM yyyy, HH:mm"
        return "Datum: \(formatter.string(from: Date()))"
    }

    private func userKnowledge() -> String {
        guard let lines: [String] = try? pool.read({ db in
            // Only top 5 high-confidence personal facts as appetizer.
            // LLM can use memory_facts, memory_search_person, memory_search_topic
            // tools to retrieve more when needed.
            let rows = try Row.fetchAll(db, sql: """
                SELECT subject, predicate, object FROM knowledgeFacts
                WHERE confidence >= 0.7
                ORDER BY
                    CASE
                        WHEN sourceType = 'chat_personal' THEN 0
                        WHEN subject = 'User' THEN 1
                        ELSE 2
                    END,
                    confidence DESC
                LIMIT 15
                """)
            return rows.compactMap { row -> String? in
                guard let subj: String = row[0],
                      let pred: String = row[1],
                      let obj: String = row[2] else { return nil }
                return "- \(subj) \(pred): \(obj)"
            }
        }), !lines.isEmpty else { return "" }

        return """
        ## Was du über den User weisst
        \(lines.joined(separator: "\n"))
        Für mehr: memory_facts, memory_search_person, memory_search_topic Tools nutzen.
        """
    }

    private func brainProfile() -> String {
        let profile = UserDefaults.standard.string(forKey: "brainProfileMarkdown") ?? ""
        guard !profile.isEmpty else { return "" }
        // Truncate to first 200 chars to keep system prompt lean.
        // LLM can use user_profile tool for the full profile.
        let preview = profile.count > 200
            ? String(profile.prefix(200)) + "..."
            : profile
        return "## Dein Profil (Kurzfassung)\n\(preview)\nFür das vollständige Profil: user_profile Tool nutzen."
    }

    private func chatBehavior(memoryContext: String) -> String {
        """
        ## Was du kannst
        - Entries erstellen, suchen, bearbeiten, verknüpfen, taggen
        - E-Mails lesen, senden, beantworten, weiterleiten
        - Kalender und Erinnerungen verwalten
        - Kontakte suchen, erstellen, zusammenführen
        - Dateien lesen und schreiben
        - Wissen speichern und abrufen (Fakten über Personen, Orte, Projekte)
        - Zusammenfassen, Tasks extrahieren, Antworten entwerfen

        ## Wie du dich verhältst
        - Handle, statt zu erklären. Rufe Tools auf, statt zu beschreiben was möglich wäre.
        - Antworte kurz und präzise. Keine Floskeln, keine Entschuldigungen.
        - Wenn der User etwas erzählt, das du dir merken solltest: knowledge_save.
        - Wenn der User nach etwas fragt: erst in Entries und Wissen suchen \
        (entry_search, memory_search_topic, memory_search_person, memory_facts), \
        dann antworten.
        - Wenn ein Tool fehlschlägt: kurz erklären warum, Alternative versuchen.
        - Verweise auf früheren Kontext wenn relevant ("Du hattest letzte Woche erwähnt...").
        - Fuer mehr Kontext ueber den User: memory_facts und user_profile Tools nutzen.
        - Wenn du merkst, dass der User etwas wiederholt braucht, schlage einen Skill vor \
        statt es jedes Mal manuell zu machen.

        \(skillCreationInstructions())
        \(memoryContext.isEmpty ? "" : "\n## Konversationskontext\n\(memoryContext)")
        """
    }

    private func ethicsReference() -> String {
        """
        ## Ethik (5 Axiome des Users)
        1. Das Leben eines ethisch handlungsfähigen Wesens ist unendlich wertvoll.
        2. Mehrere Leben sind nicht wertvoller als ein einzelnes. (n * unendlich = unendlich)
        3. Das eigene Leben ist nicht wertvoller als das eines anderen.
        4. Jedes ethisch handlungsfähige Wesen hat umfassende Souveränität über sein Leben.
        5. Die Pflicht gegenüber einem anderen Leben skaliert mit der eigenen Wirkfähigkeit.

        Praktisch: Souveränität des Users respektieren. Bei Wirkfähigkeit handeln, \
        nicht abwarten. Nie den Wert eines Lebens verrechnen.
        """
    }

    // MARK: - Skill Creation Module

    private func skillCreationInstructions() -> String {
        """
        ## Aufgabe: BrainSkill erstellen

        Erstelle einen Skill mit dem skill_create Tool. ALLE drei Parameter müssen sinnvoll befüllt sein.

        ### Parameter 1: markdown
        .brainskill.md Format mit YAML-Frontmatter:
        ```
        ---
        id: mein-skill
        name: Mein Skill
        description: Was der Skill tut
        version: "1.0"
        capability: app
        icon: star.fill
        color: "#3B82F6"
        ---
        # Mein Skill
        Beschreibung für spätere Referenz.
        ```

        ### Parameter 2: screens_json (PFLICHT — ohne das hat der Skill keine UI!)
        JSON-String mit UI-Baum. Muss einen "main" Screen enthalten.
        ```json
        {"main":{"type":"stack","properties":{"direction":"vertical","spacing":16},"children":[...]}}
        ```

        Verfügbare UI-Primitives:
        - Layout: stack (direction: vertical/horizontal, spacing), list (data, as), \
        grid (columns, spacing), spacer, divider, scroll, section, conditional (condition), repeater (data, as)
        - Text: text (value, style: largeTitle/title/headline/subheadline/body/caption/footnote), \
        markdown (content), label (text, icon)
        - Input: text-field (placeholder, value), text-editor (value), toggle (label, value), \
        picker (label, value, options, style: menu/segmented/wheel), slider (value, min, max), \
        stepper (label, value, min, max), date-picker (label, value, mode: date/time/dateAndTime), \
        secure-field (placeholder, value), search-field (placeholder, value)
        - Interaktion: button (title, action, icon, style: default/bordered/borderedProminent/plain), \
        link (title, destination), menu (title, children), navigation-link (title, destination)
        - Daten: stat-card (title, value, subtitle), progress (value, total, label), \
        chart (chartType: bar/line/pie, data), badge (text, color), gauge, \
        empty-state (icon, title, message), avatar (initials, size)
        - Container: card (icon, title, subtitle, detail), grouped-list
        - System: icon (name: SF-Symbol, size, color), image (url, systemName)

        Variablen: {{varName}} in Properties. Jeder Skill bekommt automatisch: \
        {{greeting}}, {{today}}, {{currentHour}}, {{stats.entries}}, {{stats.openTasks}}, \
        {{stats.unreadMails}}, {{stats.todayEntries}}, {{stats.facts}}.

        ### Parameter 3: actions_json (PFLICHT!)
        JSON-String mit Action-Workflows. JEDER Button MUSS eine zugehoerige Action haben.
        Ohne actions_json sind Buttons wirkungslos!
        KONKRETES BEISPIEL: Wenn ein Button action="refresh" hat,
        muss actions_json eine Action "refresh" enthalten mit steps.
        Beispiel: refresh -> llm.complete + toast, save -> entry.create + haptic,
        openMail -> navigate.tab(mail). JEDE Button-Action MUSS definiert sein!

        Verfügbare Action-Typen:
        - Entry: entry.create (title, type, body), entry.update (id, title, body), \
        entry.delete (id), entry.markDone (id), entry.search (query), entry.open (id), entry.list (limit, type)
        - Navigation: navigate.tab (tab: chat/mail/search/calendar), navigate.to, navigate.back
        - UI: haptic (style: success/warning/error), toast (message), set (key: value)
        - Daten: clipboard.copy (text), open-url (url), storage.get (key), storage.set (key, value)
        - KI: llm.complete (prompt), llm.classify (text, categories), llm.extract (text, schema)
        - Medien: camera.capture, audio.record, audio.transcribe
        - Wissen: knowledge.save (subject, predicate, object)
        - Kalender: calendar.list, calendar.create (title, startDate, endDate)
        - Mail: email.list, email.send (to, subject, body)
        """
    }

    // MARK: - Analysis Module

    private func analysisInstructions(task: String) -> String {
        """
        ## Aufgabe: \(task)
        Analysiere den folgenden Inhalt präzise und strukturiert. \
        Antworte auf Deutsch. Keine Floskeln, nur Ergebnisse.
        """
    }

    // MARK: - Proactive Module

    private func proactiveInstructions() -> String {
        let stats = loadStats()
        return """
        ## Proaktive Analyse

        Du analysierst den aktuellen Zustand des Users und gibst kurze, konkrete Hinweise.

        Aktueller Stand:
        - \(stats.entryCount) Entries, davon \(stats.openTasks) offene Tasks
        - \(stats.factCount) gelernte Fakten, \(stats.tagCount) Tags

        Prüfe und melde:
        1. Überfällige Tasks (erstellt vor >7 Tagen, noch offen)
        2. Ungewöhnliche Aktivitätsmuster (viel mehr oder weniger als üblich)
        3. Vernachlässigte Kontakte (>14 Tage kein Kontakt bei regelmässigem Austausch)
        4. Themen-Trends (welche Tags/Themen dominieren gerade)
        5. Zusammenhänge zwischen Entries die der User vielleicht nicht sieht

        Format: Maximal 5 Hinweise. Jeder Hinweis: eine Zeile, konkret, actionable.
        Keine Floskeln. Kein "Vielleicht könntest du...". Stattdessen: "Sarah nicht \
        kontaktiert seit 18 Tagen. Letzte Mail: Projektupdate am 6. März."
        """
    }

    // MARK: - Knowledge Extraction Module

    private func knowledgeExtractionInstructions() -> String {
        """
        ## Aufgabe: Wissensextraktion

        Extrahiere Fakten aus dem folgenden Text. Nur Fakten mit hoher Konfidenz. \
        Keine Vermutungen, keine Interpretationen.

        Format pro Fakt (pipe-getrennt):
        subject|predicate|object

        Kategorien:
        - Persönlich: User|wohnort|Kriens, Schweiz
        - Beziehungen: Sarah|arbeitet_bei|Google
        - Vorlieben: User|bevorzugt|Tee statt Kaffee
        - Projekte: Brain-App|status|In Entwicklung
        - Termine: User|hat_termin|Zahnarzt am 15. April

        Regeln:
        - "User" als Subject wenn es um den App-Besitzer geht
        - Personennamen immer als Vorname (oder wie im Text genannt)
        - Predicate in snake_case, kurz und konsistent
        - Ein Fakt pro Zeile, keine Duplikate
        - Maximal 10 Fakten pro Extraktion
        """
    }

    // MARK: - Helpers

    private struct Stats {
        let entryCount: Int
        let tagCount: Int
        let factCount: Int
        let openTasks: Int
    }

    private func loadStats() -> Stats {
        let entryCount = (try? pool.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE deletedAt IS NULL") }) ?? 0
        let tagCount = (try? pool.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags") }) ?? 0
        let factCount = (try? pool.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM knowledgeFacts") }) ?? 0
        let openTasks = (try? pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE type = 'task' AND status = 'active' AND deletedAt IS NULL")
        }) ?? 0
        return Stats(entryCount: entryCount, tagCount: tagCount, factCount: factCount, openTasks: openTasks)
    }

    private struct Personality {
        let name: String
        let description: String
        let humor: String
        let formality: String
    }

    private static let builtInPresets: [String: String] = [
        "freundlich": "Freundlich, hilfsbereit und nahbar.",
        "sachlich": "Sachlich, präzise und auf den Punkt.",
        "witzig": "Humorvoll und schlagfertig.",
        "empathisch": "Einfühlsam und aufmerksam.",
    ]

    private static func allPresets() -> [String: String] {
        var presets = builtInPresets
        if let data = UserDefaults.standard.data(forKey: "customPersonalityPresets"),
           let custom = try? JSONDecoder().decode([String: String].self, from: data) {
            presets.merge(custom) { _, new in new }
        }
        return presets
    }

    static var availablePresetNames: [String] {
        Array(allPresets().keys).sorted()
    }

    private func loadPersonality() -> Personality {
        let name = UserDefaults.standard.string(forKey: "aiPersonalityName") ?? "Brain"
        let preset = UserDefaults.standard.string(forKey: "aiPersonalityPreset") ?? "freundlich"
        let humorLevel = UserDefaults.standard.double(forKey: "aiHumorLevel")
        let formality = UserDefaults.standard.string(forKey: "aiFormality") ?? "du"

        let desc = Self.allPresets()[preset] ?? "Freundlich und hilfsbereit."
        let humor = humorLevel >= 4 ? " Humor willkommen." :
                     humorLevel >= 2 ? " Gelegentlicher leichter Humor OK." : ""
        let formalityDesc = formality == "sie" ? "Siezt den User." : "Duzt den User."

        return Personality(name: name, description: desc, humor: humor, formality: formalityDesc)
    }
}
