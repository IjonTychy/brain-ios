import Foundation
import BrainCore
import GRDB
import os.log

// H1: Skill-based localization service.
// Instead of Apple's .strings/.xcstrings, all UI labels are defined in Language Skills.
// Users can create their own translations as .brainskill.md and share them.
//
// Fallback chain: active Language Skill → built-in German → key itself.
// System language is used as default; user can override in Settings.
@MainActor
@Observable
final class LocalizationService {

    static let shared = LocalizationService()

    /// Currently active locale (e.g. "de", "en").
    /// Observed by views to trigger re-render on language change.
    var activeLocale: String = "de"

    /// Incremented on every language change to force SwiftUI re-renders.
    var revision: Int = 0

    /// All available language skill IDs
    var availableLocales: [(id: String, name: String, locale: String)] = []

    private var labels: [String: String] = [:]
    private let fallbackLabels: [String: String]
    private let logger = Logger(subsystem: "com.example.brain-ios", category: "Localization")

    private init() {
        // Built-in German as ultimate fallback
        self.fallbackLabels = Self.builtInGerman
        self.labels = Self.builtInGerman

        // Detect system language and try to match
        let systemLang = Locale.current.language.languageCode?.identifier ?? "de"
        self.activeLocale = systemLang
    }

    // MARK: - Public API

    /// Resolve a localization key. Returns the localized string or the key itself.
    func resolve(_ key: String) -> String {
        labels[key] ?? fallbackLabels[key] ?? key
    }

    /// Load a language skill from the database.
    /// Called when the user switches language or on app start.
    func loadLanguageSkill(from pool: DatabasePool) {
        // Check user override first
        let overrideLocale = UserDefaults.standard.string(forKey: "brainLanguage")

        do {
            // List all installed language skills
            let skills: [Skill] = try pool.read { db in
                try Skill.filter(Column("capability") == "app")
                    .filter(Column("id").like("brain-language-%"))
                    .fetchAll(db)
            }

            availableLocales = skills.map { (id: $0.id, name: $0.name, locale: String($0.id.dropFirst("brain-language-".count))) }

            // Determine which locale to use
            let targetLocale = overrideLocale ?? activeLocale

            // Try exact match, then fallback to "de"
            let matchingSkill = skills.first(where: { $0.id == "brain-language-\(targetLocale)" })
                ?? skills.first(where: { $0.id == "brain-language-de" })

            if let skill = matchingSkill {
                loadLabels(from: skill)
                activeLocale = String(skill.id.dropFirst("brain-language-".count))
                logger.info("Loaded language skill: \(skill.id)")
            } else {
                // No language skills installed — use built-in German
                labels = fallbackLabels
                activeLocale = "de"
            }
        } catch {
            logger.error("Failed to load language skills: \(error)")
            labels = fallbackLabels
        }
    }

    /// Set language override (nil = follow system).
    /// Ensures only ONE language skill is active at a time —
    /// activating "en" deactivates "de" and vice versa.
    func setLanguage(_ locale: String?, pool: DatabasePool) {
        if let locale {
            UserDefaults.standard.set(locale, forKey: "brainLanguage")
        } else {
            UserDefaults.standard.removeObject(forKey: "brainLanguage")
        }

        // Exclusive activation: enable the chosen language skill, disable all others
        do {
            let lifecycle = SkillLifecycle(pool: pool)
            let allLangSkills: [Skill] = try pool.read { db in
                try Skill.filter(Column("id").like("brain-language-%")).fetchAll(db)
            }
            let targetId = locale.map { "brain-language-\($0)" }
            for skill in allLangSkills {
                let shouldBeActive = (skill.id == targetId) || (targetId == nil && skill.id == "brain-language-\(activeLocale)")
                if skill.enabled && !shouldBeActive {
                    try lifecycle.disable(id: skill.id)
                } else if !skill.enabled && shouldBeActive {
                    try lifecycle.enable(id: skill.id)
                }
            }
        } catch {
            logger.error("Failed to toggle language skills: \(error)")
        }

        // Reload labels with new language
        loadLanguageSkill(from: pool)
        revision += 1
    }

    // MARK: - Private

    private func loadLabels(from skill: Skill) {
        guard let markdown = skill.sourceMarkdown else {
            labels = fallbackLabels
            return
        }
        var parsed: [String: String] = [:]
        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Parse "key: value" lines (skip YAML frontmatter, headers, empty lines)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("---"),
                  !trimmed.hasPrefix("#"),
                  !trimmed.hasPrefix("-"),
                  trimmed.contains(": ")
            else { continue }

            let parts = trimmed.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            // Only accept dotted keys (e.g. "tab.home", "button.save")
            if key.contains(".") {
                parsed[key] = value
            }
        }

        // Merge with fallback: parsed labels take precedence
        labels = fallbackLabels.merging(parsed) { _, new in new }
    }

    // MARK: - Built-in German (Fallback)

    static let builtInGerman: [String: String] = [
        // Tabs
        "tab.home": "Home",
        "tab.search": "Suche",
        "tab.chat": "Chat",
        "tab.mail": "Posteingang",
        "tab.calendar": "Kalender",
        "tab.files": "Dateien",
        "tab.capture": "Erfassen",
        "tab.contacts": "Kontakte",
        "tab.graph": "Wissensnetz",
        "tab.skills": "Skills",
        "tab.more": "Mehr",

        // Buttons
        "button.save": "Speichern",
        "button.cancel": "Abbrechen",
        "button.delete": "Löschen",
        "button.edit": "Bearbeiten",
        "button.done": "Fertig",
        "button.add": "Hinzufügen",
        "button.send": "Senden",
        "button.retry": "Nochmal versuchen",
        "button.confirm": "Bestätigen",
        "button.back": "Zurück",
        "button.next": "Weiter",
        "button.skip": "Überspringen",
        "button.install": "Installieren",
        "button.test": "Testen & Speichern",
        "button.logout": "Abmelden",
        "button.copy": "Kopieren",
        "button.share": "Teilen",
        "button.archive": "Archivieren",
        "button.restore": "Wiederherstellen",

        // Settings
        "settings.title": "Einstellungen",
        "settings.apiKey": "API-Key",
        "settings.model": "Standard-Modell",
        "settings.security": "Sicherheit",
        "settings.advanced": "Erweiterte Einstellungen",
        "settings.proxy": "Proxy / VPS",
        "settings.language": "Sprache",
        "settings.faceId": "Face ID",
        "settings.reset": "Zurücksetzen",

        // Chat
        "chat.placeholder": "Nachricht an Brain...",
        "chat.thinking": "Brain denkt...",
        "chat.empty": "Starte eine Konversation mit Brain",
        "chat.offline": "Offline — nur On-Device LLM verfügbar",
        "chat.error": "Fehler bei der Kommunikation",

        // Search
        "search.placeholder": "Suchen...",
        "search.empty": "Keine Ergebnisse",
        "search.all": "Alle",

        // Entry types
        "type.thought": "Gedanke",
        "type.task": "Aufgabe",
        "type.note": "Notiz",
        "type.event": "Termin",
        "type.email": "E-Mail",
        "type.contact": "Kontakt",
        "type.bookmark": "Lesezeichen",
        "type.habit": "Gewohnheit",

        // Common
        "common.noTitle": "Ohne Titel",
        "common.loading": "Laden...",
        "common.error": "Fehler",
        "common.success": "Erfolgreich",
        "common.today": "Heute",
        "common.yesterday": "Gestern",
        "common.entries": "Einträge",
        "common.tags": "Tags",
        "common.skills": "Skills",
        "common.openTasks": "Offene Aufgaben",
        "common.unreadMails": "Ungelesene Mails",

        // Onboarding
        "onboarding.welcome": "Willkommen bei Brain",
        "onboarding.subtitle": "Dein persönliches Gehirn auf dem iPhone",
        "onboarding.privacy": "Deine Daten bleiben auf deinem Gerät",
        "onboarding.start": "Los geht's",

        // Mail
        "mail.inbox": "Posteingang",
        "mail.sent": "Gesendet",
        "mail.drafts": "Entwürfe",
        "mail.archive": "Archiv",
        "mail.trash": "Papierkorb",
        "mail.spam": "Spam",
        "mail.compose": "Neue Nachricht",
        "mail.reply": "Antworten",
        "mail.forward": "Weiterleiten",
        "mail.markRead": "Als gelesen markieren",

        // Skills
        "skills.installed": "Installierte Skills",
        "skills.noSkills": "Keine Skills installiert",
        "skills.import": "Skill importieren",
        "skills.export": "Skill exportieren",
        "skills.permissions": "Berechtigungen",

        // Knowledge Graph
        "graph.title": "Wissensnetz",
        "graph.empty": "Noch kein Wissensnetz",
        "graph.emptyHint": "Erstelle Einträge und verlinke sie, um dein Wissensnetz zu sehen.",
        "graph.connections": "Verbindungen",
        "graph.noConnections": "Keine Verbindungen",

        // Errors
        "error.network": "Keine Internetverbindung",
        "error.apiKey": "API-Key ungültig",
        "error.permission": "Berechtigung verweigert",
        "error.notFound": "Nicht gefunden",
    ]
}

// MARK: - Global Localization Function

/// Shorthand for localization lookup. Use throughout all views.
/// Example: `Text(L("tab.home"))` instead of `Text("Home")`
@MainActor
func L(_ key: String) -> String {
    LocalizationService.shared.resolve(key)
}
