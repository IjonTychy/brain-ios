import AppIntents
import BrainCore
import GRDB
import os.log

// Phase 20: Apple Shortcuts & Siri — App Intents for Brain.
// These intents expose Brain's core features to Siri, Spotlight, and Shortcuts.
// Each intent accesses the database directly via a shared container,
// since App Intents may run outside the app's main lifecycle.

// MARK: - Shared Database Container

// Provides thread-safe database access for App Intents.
// Uses SharedContainer for App Group database path.
enum BrainIntentsContainer {
    private static let logger = Logger(subsystem: "com.example.brain-ios", category: "Intents")

    /// Errors surfaced to users when intents cannot access the database.
    enum ContainerError: Error, CustomLocalizedStringResourceConvertible {
        case databaseUnavailable(underlying: String)

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .databaseUnavailable(let detail):
                "Datenbank nicht verfügbar: \(detail)"
            }
        }
    }

    /// Returns the shared database manager, or throws a user-visible error.
    /// Intents should call this instead of silently falling back to a temp DB.
    static func database() throws -> DatabaseManager {
        do {
            return try SharedContainer.makeDatabaseManager()
        } catch {
            logger.error("BrainIntentsContainer: Datenbank nicht verfuegbar — \(error)")
            throw ContainerError.databaseUnavailable(underlying: error.localizedDescription)
        }
    }

    // Legacy static accessor — kept for background intents that catch errors themselves.
    static let db: DatabaseManager = {
        do {
            return try SharedContainer.makeDatabaseManager()
        } catch {
            // Log prominently instead of silently swallowing.
            Logger(subsystem: "com.example.brain-ios", category: "Intents")
                .critical("Hauptdatenbank fehlgeschlagen in App Intent: \(error)")
            do {
                return try DatabaseManager.temporary()
            } catch {
                fatalError("BrainIntentsContainer: Konnte weder Datenbank noch temporaere DB erstellen — \(error.localizedDescription)")
            }
        }
    }()

    static var entryService: EntryService { EntryService(pool: db.pool) }
    static var searchService: SearchService { SearchService(pool: db.pool) }
    static var tagService: TagService { TagService(pool: db.pool) }
}

// MARK: - Entry Type Enum for Intents

enum IntentEntryType: String, AppEnum {
    case thought, task, event, note

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Entry-Typ"
    }

    static var caseDisplayRepresentations: [IntentEntryType: DisplayRepresentation] {
        [
            .thought: "Gedanke",
            .task: "Aufgabe",
            .event: "Ereignis",
            .note: "Notiz",
        ]
    }
}

// MARK: - 1. Add Entry Intent

struct AddEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Neuen Brain-Entry erstellen"
    static let description: IntentDescription = "Erstellt einen neuen Eintrag in Brain."
    // Security: Write-only intent. Siri/Shortcuts require device unlock.
    // Only returns confirmation text with the title the user just provided — no stored data exposed.
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Titel")
    var title: String

    @Parameter(title: "Typ", default: .thought)
    var type: IntentEntryType

    @Parameter(title: "Inhalt", default: nil)
    var body: String?

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let entryType = EntryType(rawValue: type.rawValue) ?? .thought
        let entry = try BrainIntentsContainer.entryService.create(
            Entry(type: entryType, title: title, body: body)
        )
        let typeName = type.rawValue == "task" ? "Aufgabe" : "Entry"
        return .result(value: "\(typeName) '\(title)' erstellt (ID: \(entry.id ?? 0))")
    }
}

// MARK: - 2. Quick Capture Intent

struct QuickCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Schnellerfassung"
    static let description: IntentDescription = "Erfasst schnell einen Gedanken in Brain."
    // Security: Write-only intent. Siri/Shortcuts require device unlock.
    // Only returns confirmation text — no stored data exposed.
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Text")
    var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let entry = try BrainIntentsContainer.entryService.create(
            Entry(type: .thought, title: text)
        )
        return .result(value: "Gespeichert: '\(text)' (ID: \(entry.id ?? 0))")
    }
}

// MARK: - 3. Search Brain Intent

struct SearchBrainIntent: AppIntent {
    static let title: LocalizedStringResource = "In Brain suchen"
    static let description: IntentDescription = "Durchsucht alle Brain-Einträge."
    // F-10: Force app open so biometric auth runs before returning search results.
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Suchbegriff")
    var query: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let results = try BrainIntentsContainer.searchService
            .search(query: query, limit: 5)
            .map(\.entry)

        if results.isEmpty {
            return .result(value: "Keine Ergebnisse für '\(query)'.")
        }

        let list = results.enumerated().map { i, entry in
            "\(i + 1). \(entry.title ?? "Ohne Titel") (\(entry.type.rawValue))"
        }.joined(separator: "\n")

        return .result(value: "\(results.count) Ergebnis(se):\n\(list)")
    }
}

// MARK: - 4. List Tasks Intent

struct ListTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Offene Aufgaben anzeigen"
    static let description: IntentDescription = "Zeigt alle offenen Tasks in Brain."
    // F-10: Force app open so biometric auth runs before returning task data.
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let tasks = try BrainIntentsContainer.entryService
            .list(type: .task, status: .active, limit: 10)

        if tasks.isEmpty {
            return .result(value: "Keine offenen Aufgaben — alles erledigt!")
        }

        let list = tasks.enumerated().map { i, task in
            "\(i + 1). \(task.title ?? "Ohne Titel")"
        }.joined(separator: "\n")

        return .result(value: "\(tasks.count) offene Aufgabe(n):\n\(list)")
    }
}

// MARK: - 5. Complete Task Intent

struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Aufgabe abschliessen"
    static let description: IntentDescription = "Markiert eine Brain-Aufgabe als erledigt."
    // F-10: Opens app for biometric auth — intent reads and mutates entry data.
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Aufgaben-Titel")
    var taskTitle: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Search for the task by title
        let results = try BrainIntentsContainer.searchService
            .search(query: taskTitle, limit: 5)
            .map(\.entry)
            .filter { $0.type == .task && $0.status == .active }

        guard let task = results.first, let taskId = task.id else {
            return .result(value: "Keine offene Aufgabe mit '\(taskTitle)' gefunden.")
        }

        let _ = try BrainIntentsContainer.entryService.markDone(id: taskId)
        return .result(value: "Erledigt: '\(task.title ?? taskTitle)'")
    }
}

// MARK: - 6. Daily Briefing Intent

struct DailyBriefingIntent: AppIntent {
    static let title: LocalizedStringResource = "Brain Tagesbriefing"
    static let description: IntentDescription = "Gibt eine Zusammenfassung deines Tages."
    // F-10: Force app open so biometric auth runs before returning briefing data.
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let service = BrainIntentsContainer.entryService

        let openTasks = try service.count(type: .task, status: .active)
        let totalEntries = try service.count()

        // Today's entries
        let todayEntries = try await BrainIntentsContainer.db.pool.read { db -> Int in
            let row = try Row.fetchOne(db, sql: """
                SELECT COUNT(*) as cnt FROM entries
                WHERE deletedAt IS NULL AND DATE(createdAt) = DATE('now')
                """)
            return row?["cnt"] ?? 0
        }

        let greeting: String
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: greeting = "Guten Morgen"
        case 12..<17: greeting = "Guten Tag"
        case 17..<22: greeting = "Guten Abend"
        default: greeting = "Gute Nacht"
        }

        var briefing = "\(greeting)! Hier ist dein Brain-Briefing:\n"
        briefing += "• \(totalEntries) Entries insgesamt\n"
        briefing += "• \(openTasks) offene Aufgaben\n"
        briefing += "• \(todayEntries) Entries heute erstellt"

        // Pattern insights
        let engine = PatternEngine(pool: BrainIntentsContainer.db.pool)
        let patterns = try engine.analyze()
        if let topPattern = patterns.first {
            briefing += "\n• Erkenntnis: \(topPattern.description)"
        }

        return .result(value: briefing)
    }
}

// EntryCountIntent removed — not actionable, stats already in DailyBriefingIntent.

// MARK: - 8. Ask Brain Intent (opens app for LLM chat)

struct AskBrainIntent: AppIntent {
    static let title: LocalizedStringResource = "Brain fragen"
    static let description: IntentDescription = "Oeffnet Brain und stellt eine Frage an die KI."
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Frage")
    var question: String

    func perform() async throws -> some IntentResult {
        // Store the question in the App Group so the main app can pick it up.
        // F-20: Use shared container instead of UserDefaults.standard, which
        // is not accessible across the intent extension / app boundary.
        UserDefaults(suiteName: SharedContainer.appGroupID)?.set(question, forKey: "pendingSiriQuestion")
        return .result()
    }
}

// SetBrainReminderIntent removed — only created tasks, did not schedule actual notifications.

// SetBrainFocusIntent removed — feature was not connected to anything functional.

// MARK: - Background Analysis (Shortcuts Automation Backup)

// Backup for unreliable BGAppRefreshTask: Users can set up a Shortcuts
// Automation (e.g. "When I arrive home", "Every day at 8am") that triggers
// this intent to run Brain's periodic analysis.
struct RunAnalysisIntent: AppIntent {
    static let title: LocalizedStringResource = "Brain Analyse ausführen"
    static let description: IntentDescription = "Führt Brain's periodische Analyse aus (Muster-Erkennung, Backfill, Verhaltens-Tracking). Ideal als Shortcuts-Automation Backup für Background Fetch."
    // Security: Background-only intent. No user data returned — only status text.
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let pool = BrainIntentsContainer.db.pool
        let tracker = BehaviorTracker(pool: pool)
        let service = await MainActor.run {
            PeriodicAnalysisService(pool: pool, behaviorTracker: tracker)
        }
        // Await the analysis — don't fire-and-forget.
        await service.runSingleCycle()

        // Also reschedule notifications while we're at it
        let notifBridge = NotificationBridge()
        await notifBridge.rescheduleFromDatabase(pool: pool)

        return .result(value: "Analyse abgeschlossen. Erinnerungen aktualisiert.")
    }
}

// Mail sync intent — syncs all email folders for all configured accounts.
struct RunMailSyncIntent: AppIntent {
    static let title: LocalizedStringResource = "Brain Mail-Sync"
    static let description: IntentDescription = "Synchronisiert alle konfigurierten E-Mail-Konten. Ideal als Shortcuts-Automation (z.B. alle 30 Minuten)."
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let pool = BrainIntentsContainer.db.pool
        let bridge = EmailBridge(pool: pool)
        let accounts = (try? bridge.listAccounts()) ?? []

        guard !accounts.isEmpty else {
            return .result(value: "Kein E-Mail-Konto konfiguriert.")
        }

        var totalSynced = 0
        var errors: [String] = []
        for account in accounts {
            do {
                let count = try await bridge.syncAllFolders(accountId: account.id, limit: 30)
                totalSynced += count
            } catch {
                errors.append(account.name)
            }
        }

        var result = "\(totalSynced) neue Mail\(totalSynced == 1 ? "" : "s")"
        result += " (\(accounts.count) Konto\(accounts.count == 1 ? "" : "n"))"
        if !errors.isEmpty {
            result += ". Fehler bei: \(errors.joined(separator: ", "))"
        }
        return .result(value: result)
    }
}

// MARK: - Good Morning Intent (combined routine)

struct GoodMorningIntent: AppIntent {
    static let title: LocalizedStringResource = "Brain Guten Morgen"
    static let description: IntentDescription = "Morgenroutine: Synchronisiert E-Mails, führt Analyse aus und gibt das Tagesbriefing mit offenen Tasks, Terminen und Erkenntnissen."
    // F-10: Opens app for biometric auth — intent returns sensitive aggregated data
    // (mail counts, tasks, patterns, calendar events).
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let pool = BrainIntentsContainer.db.pool

        // 1. Mail sync
        let bridge = EmailBridge(pool: pool)
        let accounts = (try? bridge.listAccounts()) ?? []
        var mailCount = 0
        for account in accounts {
            do {
                let count = try await bridge.syncAllFolders(accountId: account.id, limit: 50)
                mailCount += count
            } catch { }
        }

        // 2. Analysis cycle
        let tracker = BehaviorTracker(pool: pool)
        let service = await MainActor.run {
            PeriodicAnalysisService(pool: pool, behaviorTracker: tracker)
        }
        await service.runSingleCycle()

        // 3. Reschedule notifications
        let notifBridge = NotificationBridge()
        await notifBridge.rescheduleFromDatabase(pool: pool)

        // 4. Build briefing
        let entryService = BrainIntentsContainer.entryService
        let openTasks = try entryService.count(type: .task, status: .active)

        let todayEntries = (try? await pool.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM entries
                WHERE deletedAt IS NULL AND DATE(createdAt) = DATE('now')
            """)
        }) ?? 0

        let unreadMails = (try? await pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM emailCache WHERE isRead = 0")
        }) ?? 0

        let engine = PatternEngine(pool: pool)
        let patterns = (try? engine.analyze()) ?? []
        let insights = patterns.prefix(2).map { "• \($0.description)" }

        let overdueCount = (try? await pool.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM entries
                WHERE type = 'task' AND status = 'active' AND deletedAt IS NULL
                AND createdAt < datetime('now', '-7 days')
            """)
        }) ?? 0

        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String = switch hour {
            case 5..<12: "Guten Morgen"
            case 12..<17: "Guten Tag"
            case 17..<22: "Guten Abend"
            default: "Gute Nacht"
        }

        var lines: [String] = ["\(greeting)!"]
        if mailCount > 0 {
            lines.append("• \(mailCount) neue Mail\(mailCount == 1 ? "" : "s") synchronisiert")
        }
        if unreadMails > 0 {
            lines.append("• \(unreadMails) ungelesene Mail\(unreadMails == 1 ? "" : "s")")
        }
        lines.append("• \(openTasks) offene Aufgabe\(openTasks == 1 ? "" : "n")")
        if overdueCount > 0 {
            lines.append("• \(overdueCount) davon überfällig (>7 Tage)")
        }
        if todayEntries > 0 {
            lines.append("• \(todayEntries) Entry\(todayEntries == 1 ? "" : "s") heute erstellt")
        }
        for insight in insights {
            lines.append(insight)
        }

        return .result(value: lines.joined(separator: "\n"))
    }
}

// Deep analysis variant — runs longer, for "When charging" automations.
struct RunDeepAnalysisIntent: AppIntent {
    static let title: LocalizedStringResource = "Brain Tiefenanalyse"
    static let description: IntentDescription = "Führt eine ausführliche Analyse durch (grössere Batches, mehrere Runden). Ideal als Shortcuts-Automation wenn das Gerät lädt."
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let pool = BrainIntentsContainer.db.pool
        let tracker = BehaviorTracker(pool: pool)
        let service = await MainActor.run {
            PeriodicAnalysisService(pool: pool, behaviorTracker: tracker)
        }
        // Await the deep analysis — don't fire-and-forget.
        await service.runDeepCycle(batchSize: 50)

        // Also reschedule notifications
        let notifBridge = NotificationBridge()
        await notifBridge.rescheduleFromDatabase(pool: pool)

        return .result(value: "Tiefenanalyse abgeschlossen. Erinnerungen aktualisiert.")
    }
}
