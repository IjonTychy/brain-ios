import Foundation

// Email and Contact tool definitions.
extension BrainTools {

    static let communicationTools: [ToolDefinition] = [
        // MARK: - Contacts
        ToolDefinition(
            name: "contact_search",
            description: "Durchsucht iOS-Kontakte nach Name.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Suchbegriff (Name)"],
                    "limit": ["type": "integer", "description": "Max. Ergebnisse (Standard: 20)"]
                ],
                "required": ["query"]
            ]
        ),
        ToolDefinition(
            name: "contact_read",
            description: "Liest die Details eines iOS-Kontakts.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Name des Kontakts"]
                ],
                "required": ["query"]
            ]
        ),
        ToolDefinition(
            name: "contact_create",
            description: "Erstellt einen neuen iOS-Kontakt.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "givenName": ["type": "string", "description": "Vorname"],
                    "familyName": ["type": "string", "description": "Nachname"],
                    "email": ["type": "string", "description": "E-Mail-Adresse"],
                    "phone": ["type": "string", "description": "Telefonnummer"]
                ],
                "required": ["givenName"]
            ]
        ),
        ToolDefinition(
            name: "contact_update",
            description: "Aktualisiert einen bestehenden iOS-Kontakt. Änderungen erscheinen sofort in der iOS Kontakte-App. Nutze 'email'/'phone' zum Ersetzen, 'addEmail'/'addPhone' zum Hinzufügen.",
            inputSchema: ["type": "object", "properties": [
                "identifier": ["type": "string", "description": "Kontakt-Identifier"],
                "givenName": ["type": "string", "description": "Vorname"],
                "familyName": ["type": "string", "description": "Nachname"],
                "organization": ["type": "string", "description": "Firma/Organisation"],
                "jobTitle": ["type": "string", "description": "Berufsbezeichnung"],
                "email": ["type": "string", "description": "E-Mail (ersetzt alle bestehenden)"],
                "addEmail": ["type": "string", "description": "E-Mail hinzufügen (behält bestehende)"],
                "phone": ["type": "string", "description": "Telefon (ersetzt alle bestehenden)"],
                "addPhone": ["type": "string", "description": "Telefon hinzufügen (behält bestehende)"],
                "note": ["type": "string", "description": "Notiz zum Kontakt"],
            ], "required": ["identifier"]]
        ),
        ToolDefinition(
            name: "contact_delete",
            description: "Löscht einen Kontakt aus iOS Kontakte. ACHTUNG: Nicht rückgängig machbar! Immer vorher bestätigen lassen.",
            inputSchema: ["type": "object", "properties": [
                "identifier": ["type": "string", "description": "Kontakt-Identifier"],
            ], "required": ["identifier"]]
        ),
        ToolDefinition(
            name: "contact_merge",
            description: "Führt zwei Kontakte zusammen. Behaelt den Ziel-Kontakt und übernimmt fehlende Daten (Emails, Telefon, Adresse, Notiz) vom Quell-Kontakt. Der Quell-Kontakt wird gelöscht.",
            inputSchema: ["type": "object", "properties": [
                "sourceId": ["type": "string", "description": "Identifier des Kontakts der aufgeloest wird"],
                "targetId": ["type": "string", "description": "Identifier des Kontakts der bestehen bleibt"],
            ], "required": ["sourceId", "targetId"]]
        ),
        ToolDefinition(
            name: "contact_duplicates",
            description: "Findet doppelte Kontakte (gleicher Name, gleiche E-Mail oder gleiche Telefonnummer). Gibt Paare mit Begründung zurück.",
            inputSchema: ["type": "object", "properties": [
                "limit": ["type": "integer", "description": "Max. Duplikate (Standard: 20)"],
            ], "required": []]
        ),

        // MARK: - Email
        ToolDefinition(
            name: "email_list",
            description: "Listet E-Mails im Posteingang auf.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "limit": ["type": "integer", "description": "Max. E-Mails (Standard: 20)"]
                ]
            ]
        ),
        ToolDefinition(
            name: "email_fetch",
            description: "Holt den vollständigen Inhalt einer E-Mail.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Message-ID der E-Mail"]
                ],
                "required": ["id"]
            ]
        ),
        ToolDefinition(
            name: "email_search",
            description: "Durchsucht E-Mails nach Stichwort.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Suchbegriff"]
                ],
                "required": ["query"]
            ]
        ),
        ToolDefinition(
            name: "email_send",
            description: "Sendet eine E-Mail.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "to": ["type": "string", "description": "Empfaenger-Adresse"],
                    "subject": ["type": "string", "description": "Betreff"],
                    "body": ["type": "string", "description": "Nachrichtentext"]
                ],
                "required": ["to", "subject", "body"]
            ]
        ),

        ToolDefinition(
            name: "email_sync",
            description: "Synchronisiert E-Mails vom Server in den lokalen Cache.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "folder": ["type": "string", "description": "Ordner (Standard: INBOX)"],
                    "limit": ["type": "integer", "description": "Max. E-Mails (Standard: 50)"]
                ]
            ]
        ),
        ToolDefinition(
            name: "email_markRead",
            description: "Markiert eine E-Mail als gelesen.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "integer", "description": "ID der E-Mail"]
                ],
                "required": ["id"]
            ]
        ),
        // email_configure REMOVED (F-02): E-Mail-Credentials duerfen nie durch den LLM-Kontext fliessen.
        // Konfiguration erfolgt ausschliesslich über die Settings-UI.

        ToolDefinition(
            name: "email_move",
            description: "Verschiebt eine E-Mail in einen anderen Ordner (INBOX, Sent, Drafts, Archive, Junk, Trash).",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "integer", "description": "ID der E-Mail"],
                    "folder": ["type": "string", "description": "Zielordner (z.B. INBOX, Junk, Trash, Archive)"]
                ],
                "required": ["id", "folder"]
            ]
        ),
        ToolDefinition(
            name: "email_spamCheck",
            description: "Prüft ungelesene E-Mails im Posteingang auf Spam. Gibt verdächtige E-Mails mit Begründung zurück. Du analysierst Absender, Betreff und Inhalt.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "limit": ["type": "integer", "description": "Max. E-Mails zu prüfen (Standard: 20)"]
                ]
            ]
        ),
        ToolDefinition(
            name: "email_rescueSpam",
            description: "Prüft E-Mails im Spam-Ordner auf False Positives (fälschlich als Spam markiert). Du analysierst ob die E-Mails legitim sind.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "limit": ["type": "integer", "description": "Max. E-Mails zu prüfen (Standard: 20)"]
                ]
            ]
        ),

        // MARK: - Email erweitert
        ToolDefinition(
            name: "email_read",
            description: "Liest eine E-Mail vollständig (inkl. Body) und markiert sie als gelesen.",
            inputSchema: ["type": "object", "properties": [
                "id": ["type": "integer", "description": "E-Mail-ID"],
            ], "required": ["id"]]
        ),
        ToolDefinition(
            name: "email_delete",
            description: "Löscht eine E-Mail (verschiebt in Papierkorb).",
            inputSchema: ["type": "object", "properties": [
                "id": ["type": "integer", "description": "E-Mail-ID"],
            ], "required": ["id"]]
        ),
        ToolDefinition(
            name: "email_reply",
            description: "Antwortet auf eine E-Mail. Erstellt automatisch Re: Betreff und zitiert die Original-Nachricht.",
            inputSchema: ["type": "object", "properties": [
                "id": ["type": "integer", "description": "ID der Original-E-Mail"],
                "body": ["type": "string", "description": "Antwort-Text"],
            ], "required": ["id", "body"]]
        ),
        ToolDefinition(
            name: "email_forward",
            description: "Leitet eine E-Mail weiter an einen neuen Empfaenger.",
            inputSchema: ["type": "object", "properties": [
                "id": ["type": "integer", "description": "ID der Original-E-Mail"],
                "to": ["type": "string", "description": "Empfaenger-Adresse"],
                "body": ["type": "string", "description": "Optionaler Begleittext"],
            ], "required": ["id", "to"]]
        ),
        ToolDefinition(
            name: "email_flag",
            description: "Markiert eine E-Mail als wichtig (Flag setzen/entfernen).",
            inputSchema: ["type": "object", "properties": [
                "id": ["type": "integer", "description": "E-Mail-ID"],
            ], "required": ["id"]]
        ),
    ]
}
