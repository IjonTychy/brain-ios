import SwiftUI
import BrainCore
import GRDB

// MARK: - Brain Avatar Button

// Floating Brain avatar button that opens the contextual assistant.
// The user can set a custom profile image for Brain (stored in Documents).
// Falls back to a styled SF Symbol if no custom image is set.
struct BrainAvatarButton: View {
    let context: BrainAssistantContext
    @State private var showAssistant = false
    @AppStorage("aiPersonalityName") private var personalityName = "Brain"

    @State private var avatarTapped = false

    var body: some View {
        Button {
            avatarTapped.toggle()
            showAssistant = true
        } label: {
            brainAvatarImage
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .shadow(color: BrainTheme.Colors.brandBlue.opacity(0.3), radius: 3, y: 1)
                .symbolEffect(.bounce, value: avatarTapped)
        }
        .accessibilityLabel("\(personalityName) fragen")
        .sheet(isPresented: $showAssistant) {
            NavigationStack {
                BrainAssistantSheet(context: context)
            }
        }
    }

    @ViewBuilder
    private var brainAvatarImage: some View {
        if let imageData = loadCustomAvatar(), let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Circle()
                    .fill(BrainTheme.Gradients.brand)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }

    private func loadCustomAvatar() -> Data? {
        let url = BrainAvatarStorage.avatarURL
        return try? Data(contentsOf: url)
    }
}

// MARK: - Avatar Storage

enum BrainAvatarStorage {
    static var avatarURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("brain-avatar.png")
    }

    static func save(_ image: UIImage) {
        guard let data = image.pngData() else { return }
        try? data.write(to: avatarURL)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: avatarURL)
    }

    static var hasCustomAvatar: Bool {
        FileManager.default.fileExists(atPath: avatarURL.path)
    }
}

// MARK: - Context Definition

// Describes where the assistant is opened from and what data is available.
struct BrainAssistantContext {
    let location: String          // e.g., "contacts", "mail", "entries", "skills", "dashboard"
    let title: String             // Display title for the sheet
    let systemPromptExtra: String // Additional context injected into the system prompt
    let prefilledMessage: String? // Optional pre-filled message

    // Factory methods for common contexts
    static var contacts: BrainAssistantContext {
        BrainAssistantContext(
            location: "contacts",
            title: "Kontakte-Assistent",
            systemPromptExtra: """
            Du bist im Kontakte-Bereich geoeffnet worden. Der User moechte Hilfe mit seinen iOS-Kontakten.
            Du kannst: Kontakte suchen (contact_search), lesen (contact_read), bearbeiten (contact_update),
            loeschen (contact_delete), zusammenfuehren (contact_merge), Duplikate finden (contact_duplicates).
            Alle Aenderungen erscheinen sofort in der iOS Kontakte-App.
            Typische Auftraege: Dienstgrade aus Namen entfernen, Duplikate bereinigen, fehlende Infos ergaenzen,
            Kontakte nach Firma gruppieren, alte Kontakte aufraeumen.
            """,
            prefilledMessage: nil
        )
    }

    static var mail: BrainAssistantContext {
        BrainAssistantContext(
            location: "mail",
            title: "Mail-Assistent",
            systemPromptExtra: """
            Du bist im Mail-Bereich geoeffnet worden. Der User moechte Hilfe mit seinen E-Mails.
            Du kannst: Mails lesen (email_fetch), suchen (email_search), senden (email_send),
            verschieben (email_move), Spam pruefen (email_spamCheck), synchronisieren (email_sync).
            Typische Auftraege: Mails zusammenfassen, Antworten entwerfen, Spam bereinigen, wichtige Mails finden.
            """,
            prefilledMessage: nil
        )
    }

    static var entries: BrainAssistantContext {
        BrainAssistantContext(
            location: "entries",
            title: "Einträge-Assistent",
            systemPromptExtra: """
            Du bist im Einträge/Notizen-Bereich geöffnet worden. Der User möchte Hilfe mit seinen Entries.
            Du kannst: Entries suchen (entry_search), erstellen (entry_create), bearbeiten (entry_update),
            verlinken (link_create), taggen (tag_add), ähnliche finden (entry_similar).
            Typische Aufträge: Entries verlinken, Tags vorschlagen, Zusammenfassungen erstellen, Notizen organisieren.
            """,
            prefilledMessage: nil
        )
    }

    static var skills: BrainAssistantContext {
        BrainAssistantContext(
            location: "skills",
            title: "Skill-Assistent",
            systemPromptExtra: """
            Du bist im Skill-Manager geoeffnet worden. Der User moechte Hilfe mit Skills.
            Du kannst: Skills auflisten (skill_list).
            Fuer neue Skills: Verweise den User auf den Skill-Creator-Button.
            """,
            prefilledMessage: nil
        )
    }

    /// Dedicated Skill Creator mode with full Primitives catalog.
    /// Skills can ONLY be created in this mode — not in normal chat.
    static var skillCreator: BrainAssistantContext {
        BrainAssistantContext(
            location: "skill_creator",
            title: "Skill-Creator",
            systemPromptExtra: """
            Du bist der Skill-Creator. Der User moechte einen neuen BrainSkill erstellen.
            Frage den User was der Skill tun soll, dann erstelle ihn mit skill_create.

            ALLE drei Parameter muessen sinnvoll befuellt sein:

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
            Beschreibung fuer spaetere Referenz.
            ```

            ### Parameter 2: screens_json (PFLICHT — ohne das hat der Skill keine UI!)
            JSON-String mit UI-Baum. Muss einen "main" Screen enthalten.
            ```json
            {"main":{"type":"stack","properties":{"direction":"vertical","spacing":16},"children":[...]}}
            ```

            Verfuegbare UI-Primitives:
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

            Variablen: {{varName}} in Properties. Automatisch verfuegbar: \
            {{greeting}}, {{today}}, {{currentHour}}, {{stats.entries}}, {{stats.openTasks}}, \
            {{stats.unreadMails}}, {{stats.todayEntries}}, {{stats.facts}}.

            ### Parameter 3: actions_json (PFLICHT wenn Buttons vorhanden!)
            JSON-String mit Action-Workflows. Jeder Button braucht eine Action.
            ```json
            {"doSomething":{"steps":[{"type":"entry.create","properties":{"title":"...","type":"thought"}}]}}
            ```

            Verfuegbare Action-Typen:
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
            """,
            prefilledMessage: "Ich moechte einen neuen Skill erstellen."
        )
    }

    static var dashboard: BrainAssistantContext {
        BrainAssistantContext(
            location: "dashboard",
            title: "Dashboard-Assistent",
            systemPromptExtra: """
            Du bist auf dem Dashboard geoeffnet worden. Der User moechte einen Ueberblick oder Hilfe mit Tagesplanung.
            Du kannst: Tasks erstellen/erledigen, Briefing generieren (ai_briefing), Entries durchsuchen,
            Kalender abfragen (calendar_list), Erinnerungen setzen (reminder_set).
            Typische Auftraege: Tagesplan erstellen, offene Tasks priorisieren, Wochenrueckblick.
            """,
            prefilledMessage: nil
        )
    }


    // Dedicated Skill Creator context — full Primitives catalog for LLM skill generation.
    static func forEntry(_ entry: Entry) -> BrainAssistantContext {
        BrainAssistantContext(
            location: "entry_detail",
            title: "Entry-Assistent",
            systemPromptExtra: """
            Du bist bei einem spezifischen Entry geoeffnet worden:
            - Titel: \(entry.title ?? "Ohne Titel")
            - Typ: \(entry.type.rawValue)
            - Status: \(entry.status.rawValue)
            - Inhalt: \(entry.body?.prefix(500) ?? "")
            Du kannst diesen Entry bearbeiten (entry_update), verlinken (link_create), taggen (tag_add),
            zusammenfassen (ai_summarize), Tasks extrahieren (ai_extractTasks).
            """,
            prefilledMessage: nil
        )
    }

    static func forEmail(subject: String, from: String, body: String) -> BrainAssistantContext {
        BrainAssistantContext(
            location: "mail_detail",
            title: "Mail-Assistent",
            systemPromptExtra: """
            Du bist bei einer spezifischen E-Mail geoeffnet worden:
            - Betreff: \(subject)
            - Von: \(from)
            - Inhalt: \(body.prefix(500))
            Du kannst: Antworten (email_reply), weiterleiten (email_forward), zusammenfassen (ai_summarize),
            Tasks extrahieren (ai_extractTasks), als Entry speichern (entry_create).
            """,
            prefilledMessage: nil
        )
    }
}

// MARK: - Brain Assistant Sheet

// Compact contextual chat interface that can be opened from any view.
struct BrainAssistantSheet: View {
    let context: BrainAssistantContext
    @Environment(DataBridge.self) private var dataBridge
    @Environment(\.dismiss) private var dismiss
    @State private var chatService: ChatService?
    @State private var inputText = ""
    @State private var isInitialized = false
    @State private var showSettings = false
    @AppStorage("aiPersonalityName") private var personalityName = "Brain"

    var body: some View {
        Group {
            if let service = chatService, isInitialized {
                ChatView(chatService: service, showSettings: $showSettings)
            } else {
                ProgressView("Lade \(personalityName)...")
            }
        }
        .navigationTitle(context.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fertig") { dismiss() }
            }
        }
        .task {
            guard !isInitialized else { return }
            let service = ChatService(pool: dataBridge.db.pool)
            service.setHandlers(CoreActionHandlers.all(data: dataBridge))
            service.contextPromptExtra = context.systemPromptExtra
            service.isSkillCreatorMode = (context.location == "skill_creator")
            chatService = service
            isInitialized = true

            // If there's a prefilled message, send it
            if let prefilled = context.prefilledMessage {
                try? await Task.sleep(for: .milliseconds(300))
                await MainActor.run {
                    service.pendingInput = prefilled
                }
            }
        }
    }
}
