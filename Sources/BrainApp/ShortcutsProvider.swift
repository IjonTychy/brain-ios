import AppIntents

// Phase 20: AppShortcutsProvider — Pre-built shortcuts for Siri & Spotlight.
// These 10 slots appear automatically in the Shortcuts app under "Brain".
// Additional AppIntents (AddEntryIntent etc.) are available manually.

struct BrainShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {

        // 1. Guten Morgen — Kombinierte Morgenroutine (Sync + Analyse + Briefing)
        AppShortcut(
            intent: GoodMorningIntent(),
            phrases: [
                "\(.applicationName) Guten Morgen",
                "Guten Morgen \(.applicationName)",
                "\(.applicationName) Morgenroutine",
            ],
            shortTitle: "Guten Morgen",
            systemImageName: "sun.max"
        )

        // 2. Schnellerfassung — Gedanke per Sprache speichern
        AppShortcut(
            intent: QuickCaptureIntent(),
            phrases: [
                "\(.applicationName) Schnellerfassung",
                "In \(.applicationName) speichern",
                "Merke dir in \(.applicationName)",
            ],
            shortTitle: "Schnellerfassung",
            systemImageName: "brain.head.profile"
        )

        // 3. Brain fragen — Öffnet Chat mit Frage
        AppShortcut(
            intent: AskBrainIntent(),
            phrases: [
                "Frag \(.applicationName)",
                "\(.applicationName) fragen",
            ],
            shortTitle: "Brain fragen",
            systemImageName: "bubble.left"
        )

        // 4. Offene Aufgaben — Schneller Task-Check
        AppShortcut(
            intent: ListTasksIntent(),
            phrases: [
                "Was steht an in \(.applicationName)",
                "\(.applicationName) offene Aufgaben",
                "Zeige meine \(.applicationName) Aufgaben",
            ],
            shortTitle: "Offene Aufgaben",
            systemImageName: "checklist"
        )

        // 5. Aufgabe erledigen — Task per Sprache abhaken
        AppShortcut(
            intent: CompleteTaskIntent(),
            phrases: [
                "\(.applicationName) Aufgabe erledigt",
                "In \(.applicationName) abschliessen",
            ],
            shortTitle: "Aufgabe erledigen",
            systemImageName: "checkmark.circle"
        )

        // 6. Suchen — Volltext-Suche über alle Entries
        AppShortcut(
            intent: SearchBrainIntent(),
            phrases: [
                "In \(.applicationName) suchen",
                "\(.applicationName) durchsuchen",
                "Suche in \(.applicationName)",
            ],
            shortTitle: "Brain durchsuchen",
            systemImageName: "magnifyingglass"
        )

        // 7. Tagesbriefing — Zusammenfassung ohne Sync
        AppShortcut(
            intent: DailyBriefingIntent(),
            phrases: [
                "\(.applicationName) Briefing",
                "\(.applicationName) Zusammenfassung",
                "Was gibt es Neues in \(.applicationName)",
            ],
            shortTitle: "Tagesbriefing",
            systemImageName: "list.bullet.clipboard"
        )

        // 8. Analyse — Muster-Erkennung, Verknüpfungen, Backfill
        // Ideal als Automation: "Jeden Tag um 8:00" oder "Alle 2 Stunden"
        AppShortcut(
            intent: RunAnalysisIntent(),
            phrases: [
                "\(.applicationName) Analyse",
                "\(.applicationName) analysieren",
            ],
            shortTitle: "Analyse",
            systemImageName: "waveform.path.ecg"
        )

        // 9. Tiefenanalyse — Grosser Batch, Knowledge-Konsolidierung
        // Ideal als Automation: "Beim Laden" oder "Täglich um 3:00"
        AppShortcut(
            intent: RunDeepAnalysisIntent(),
            phrases: [
                "\(.applicationName) Tiefenanalyse",
                "\(.applicationName) gründlich analysieren",
            ],
            shortTitle: "Tiefenanalyse",
            systemImageName: "brain"
        )

        // 10. Mail-Sync — E-Mails aller Konten synchronisieren
        // Ideal als Automation: "Alle 30 Minuten"
        AppShortcut(
            intent: RunMailSyncIntent(),
            phrases: [
                "\(.applicationName) Mail-Sync",
                "\(.applicationName) Mails abrufen",
            ],
            shortTitle: "Mail-Sync",
            systemImageName: "envelope.arrow.triangle.branch"
        )
    }
}
