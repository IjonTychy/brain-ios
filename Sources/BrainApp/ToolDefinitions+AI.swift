import Foundation

// AI analysis, Knowledge, Skills, Rules, LLM, Memory, OnThisDay, Backup, Proposals tool definitions.
extension BrainTools {

    static let aiTools: [ToolDefinition] = [
        // MARK: - Knowledge
        ToolDefinition(
            name: "knowledge_save",
            description: "Speichert ein Wissensfakt (Subjekt-Praedikat-Objekt Tripel). Beispiel: 'Sarah' 'arbeitet bei' 'Google'.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "subject": ["type": "string", "description": "Subjekt des Fakts"],
                    "predicate": ["type": "string", "description": "Praedikat/Beziehung"],
                    "object": ["type": "string", "description": "Objekt des Fakts"],
                    "confidence": ["type": "number", "description": "Konfidenz 0.0–1.0 (Standard: 1.0)"],
                    "sourceEntryId": ["type": "integer", "description": "Optionale Quell-Entry ID"]
                ],
                "required": ["subject", "predicate", "object"]
            ]
        ),

        // MARK: - AI Analysis
        ToolDefinition(
            name: "ai_summarize",
            description: "Erstellt eine KI-Zusammenfassung eines Textes oder Entries.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "Text zum Zusammenfassen"],
                    "entryId": ["type": "integer", "description": "Alternativ: Entry-ID"]
                ]
            ]
        ),
        ToolDefinition(
            name: "ai_extractTasks",
            description: "Extrahiert Aufgaben/Action Items aus einem Text.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "Text aus dem Tasks extrahiert werden"],
                    "entryId": ["type": "integer", "description": "Alternativ: Entry-ID"]
                ]
            ]
        ),
        ToolDefinition(
            name: "ai_briefing",
            description: "Erstellt ein Tages-Briefing: offene Tasks, heutige Termine, aktuelle Entries.",
            inputSchema: [
                "type": "object",
                "properties": [:]
            ]
        ),
        ToolDefinition(
            name: "ai_draftReply",
            description: "Erstellt einen Antwort-Entwurf für eine E-Mail. Gibt den Entwurfstext zurück.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "emailId": ["type": "integer", "description": "ID der E-Mail auf die geantwortet werden soll"],
                    "style": ["type": "string", "description": "Stil der Antwort: formal, casual, brief", "enum": ["formal", "casual", "brief"]],
                    "instructions": ["type": "string", "description": "Zusätzliche Anweisungen für den Entwurf"]
                ],
                "required": ["emailId"]
            ]
        ),

        // MARK: - Skills
        ToolDefinition(
            name: "skill_create",
            description: """
            Erstellt oder AKTUALISIERT einen Skill mit nativer UI. BEIDE Parameter sind PFLICHT. \
            Der Skill wird installiert und ist sofort unter Skills sichtbar und oeffenbar. \
            Nutze dieses Tool wenn der User einen neuen Skill, eine UI oder ein Feature will. \
            WICHTIG: Ohne screens_json hat der Skill KEINE UI und ist nutzlos!
            """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "markdown": [
                        "type": "string",
                        "description": """
                        .brainskill.md Inhalt. Format: \
                        ---\\nid: mein-skill\\nname: Mein Skill\\ndescription: Beschreibung\\nversion: 1.0\\n\
                        capability: app\\nicon: star\\ncolor: \"#3B82F6\"\\n---\\n# Beschreibung
                        """,
                    ],
                    "screens_json": [
                        "type": "string",
                        "description": """
                        PFLICHT! JSON-String mit UI-Baum. Ohne screens_json ist der Skill nutzlos (keine UI). \
                        Format: {\"main\":{\"type\":\"stack\",\"properties\":{\"direction\":\"vertical\",\"spacing\":16},\
                        \"children\":[{\"type\":\"text\",\"properties\":{\"value\":\"Titel\",\"style\":\"largeTitle\"}},\
                        {\"type\":\"button\",\"properties\":{\"title\":\"Aktion\",\"action\":\"doSomething\"}}]}}. \
                        Verfuegbare Primitives: stack (direction:vertical/horizontal, spacing), text (value, style: \
                        largeTitle/title/headline/subheadline/body/caption/footnote), button (title, action, style: \
                        primary/secondary/destructive/plain), icon (name: SF-Symbol, color), image (url, systemName), \
                        list (data, as), spacer, divider, badge (text, color), stat-card (title, value, subtitle), \
                        progress (value, total, label), toggle (label, binding), text-field (placeholder, binding), \
                        picker (label, selection, options), empty-state (icon, title, message), \
                        avatar (initials, size), conditional (condition), repeater, markdown (content), \
                        chart (chartType, data), map, calendar-grid. \
                        Variablen: {{varName}} in Properties. Button-Action: Name der Action in actions_json. \
                        Daten-Anbindung: Wenn der Skill Daten aus der DB braucht, definiere einen \
                        "data"-Block im Top-Level JSON (NEBEN screens, nicht darin). Format: \
                        "data":{"varName":{"source":"entries","filter":{"type":"habit"},"sort":"createdAt DESC","limit":20}}. \
                        Erlaubte sources: entries, tags, knowledgeFacts, emailCache. \
                        Die Ergebnisse sind dann als {{varName}} in screens verfuegbar (Array von Objekten).
                        """,
                    ],
                    "actions_json": [
                        "type": "string",
                        "description": """
                        PFLICHT wenn Buttons vorhanden! JSON-String mit Action-Definitionen. \
                        Jeder Button braucht eine zugehoerige Action. \
                        Format: {\"doSomething\":{\"steps\":[{\"type\":\"haptic\",\"properties\":{\"style\":\"success\"}},\
                        {\"type\":\"toast\",\"properties\":{\"message\":\"Erledigt!\"}}]}}. \
                        Verfuegbare Action-Typen: entry.create (title, type, body), entry.update (id, title, body), \
                        entry.delete (id), entry.markDone (id), entry.search (query), entry.open (id), \
                        navigate.tab (tab: chat/mail/search), haptic (style: success/warning/error), \
                        toast (message), clipboard.copy (text), open-url (url), set (key: value), \
                        llm.complete (prompt), llm.summarize (text), camera.capture, audio.record, audio.transcribe. \
                        Variablen: {{varName}} in Properties.
                        """,
                    ],
                ],
                "required": ["markdown", "screens_json", "actions_json"],
            ]
        ),
        ToolDefinition(
            name: "skill_list",
            description: "Listet alle installierten Skills auf.",
            inputSchema: [
                "type": "object",
                "properties": [:]
            ]
        ),

        // MARK: - Rules / Self-Modifier
        ToolDefinition(
            name: "rules_evaluate",
            description: "Evaluiert die Rules Engine für einen bestimmten Trigger.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "trigger": ["type": "string", "description": "Trigger-Name (z.B. 'app_open', 'entry_created')"],
                    "entryType": ["type": "string", "description": "Optionaler Entry-Typ Filter"]
                ],
                "required": ["trigger"]
            ]
        ),
        ToolDefinition(
            name: "improve_list",
            description: "Listet Verbesserungsvorschlaege (Improvement Proposals) auf.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "status": ["type": "string", "enum": ["pending", "approved", "applied", "rejected"], "description": "Filter nach Status"]
                ]
            ]
        ),
        ToolDefinition(
            name: "improve_apply",
            description: "Wendet einen Verbesserungsvorschlag an (setzt Status auf applied).",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "integer", "description": "ID des Verbesserungsvorschlags"]
                ],
                "required": ["id"]
            ]
        ),

        // MARK: - LLM
        ToolDefinition(
            name: "llm_complete",
            description: "Sendet eine Anfrage an das LLM und gibt die vollständige Antwort zurück. Nutze dieses Tool für KI-Aufgaben innerhalb von Skills.",
            inputSchema: ["type": "object", "properties": [
                "prompt": ["type": "string", "description": "Die Anfrage an das LLM"],
                "system": ["type": "string", "description": "Optionaler System-Prompt"],
            ], "required": ["prompt"]]
        ),
        ToolDefinition(
            name: "llm_classify",
            description: "Klassifiziert einen Text in eine der angegebenen Kategorien.",
            inputSchema: ["type": "object", "properties": [
                "text": ["type": "string", "description": "Zu klassifizierender Text"],
                "categories": ["type": "string", "description": "Komma-getrennte Kategorien"],
            ], "required": ["text", "categories"]]
        ),
        ToolDefinition(
            name: "llm_extract",
            description: "Extrahiert strukturierte Daten aus einem Text gemaess einem Schema.",
            inputSchema: ["type": "object", "properties": [
                "text": ["type": "string", "description": "Quelltext"],
                "schema": ["type": "string", "description": "JSON-Schema-Beschreibung der zu extrahierenden Felder"],
            ], "required": ["text", "schema"]]
        ),

        // MARK: - Conversation Memory
        ToolDefinition(
            name: "memory_search_person",
            description: "Durchsucht Brains Gedächtnis nach allen Einträgen, die eine bestimmte Person erwähnen. Findet Notizen, Tasks, E-Mails und andere Entries über diese Person.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Name der Person (z.B. 'Sarah', 'Herr Mueller')"],
                    "limit": ["type": "integer", "description": "Maximale Anzahl Ergebnisse (Standard: 10)"]
                ],
                "required": ["name"]
            ]
        ),
        ToolDefinition(
            name: "memory_search_topic",
            description: "Durchsucht Brains Gedächtnis nach Einträgen zu einem bestimmten Thema. Nutzt Volltextsuche (FTS5) für präzise Ergebnisse.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "topic": ["type": "string", "description": "Thema oder Suchbegriff (z.B. 'Projektplan', 'Urlaub', 'Deployment')"],
                    "limit": ["type": "integer", "description": "Maximale Anzahl Ergebnisse (Standard: 10)"]
                ],
                "required": ["topic"]
            ]
        ),
        ToolDefinition(
            name: "memory_facts",
            description: "Ruft gespeicherte Wissensfakten über ein Thema oder eine Person ab. Fakten sind strukturierte Informationen die Brain über die Zeit gelernt hat (z.B. 'Sarah arbeitet bei Firma X').",
            inputSchema: [
                "type": "object",
                "properties": [
                    "subject": ["type": "string", "description": "Subjekt der Fakten (z.B. 'Sarah', 'Projekt Brain', 'Meeting')"]
                ],
                "required": ["subject"]
            ]
        ),

        // MARK: - User Profile
        ToolDefinition(
            name: "user_profile",
            description: "Ruft das vollstaendige Profil des Users ab — persoenliche Informationen, Vorlieben, Hintergrund. Nutze dieses Tool wenn du mehr Kontext ueber den User brauchst als im System-Prompt steht.",
            inputSchema: [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ),

        // MARK: - On This Day
        ToolDefinition(
            name: "onthisday_list",
            description: "Zeigt Einträge die am gleichen Kalendertag in vergangenen Jahren erstellt wurden ('An diesem Tag').",
            inputSchema: [
                "type": "object",
                "properties": [
                    "limit": ["type": "integer", "description": "Maximale Anzahl Einträge (Standard: 20)"]
                ],
                "required": [] as [String]
            ]
        ),

        // MARK: - Backup
        ToolDefinition(
            name: "backup_export",
            description: "Erstellt eine JSON-Zusammenfassung aller Brain-Daten (Entries, Tags). Für Datensicherung.",
            inputSchema: [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ),

        // MARK: - Proposal reject
        ToolDefinition(
            name: "proposal_reject",
            description: "Lehnt einen Verbesserungsvorschlag ab.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "integer", "description": "ID des Proposals"]
                ],
                "required": ["id"]
            ]
        ),
    ]
}
