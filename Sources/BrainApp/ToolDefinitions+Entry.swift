import Foundation

// Entry CRUD, Tags, Links, Search tool definitions.
extension BrainTools {

    static let entryTools: [ToolDefinition] = [
        // MARK: - Entry CRUD
        ToolDefinition(
            name: "entry_create",
            description: "Erstellt einen neuen Entry (Gedanke, Aufgabe, Notiz, Event, E-Mail oder Dokument) in Brain.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "Titel des Entries"],
                    "type": ["type": "string", "enum": ["thought", "task", "note", "event", "email", "document"], "description": "Art des Entries"],
                    "body": ["type": "string", "description": "Optionaler ausführlicher Inhalt"]
                ],
                "required": ["title"]
            ]
        ),
        ToolDefinition(
            name: "entry_search",
            description: "Durchsucht alle Entries per Volltextsuche (FTS5). Findet Titel und Inhalt.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Suchbegriff"],
                    "limit": ["type": "integer", "description": "Max. Anzahl Ergebnisse (Standard: 20)"]
                ],
                "required": ["query"]
            ]
        ),
        ToolDefinition(
            name: "entry_update",
            description: "Aktualisiert Titel und/oder Inhalt eines bestehenden Entries.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "integer", "description": "ID des Entries"],
                    "title": ["type": "string", "description": "Neuer Titel"],
                    "body": ["type": "string", "description": "Neuer Inhalt"]
                ],
                "required": ["id"]
            ]
        ),
        ToolDefinition(
            name: "entry_delete",
            description: "Löscht einen Entry (Soft-Delete, kann wiederhergestellt werden).",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "integer", "description": "ID des Entries"]
                ],
                "required": ["id"]
            ]
        ),
        ToolDefinition(
            name: "entry_fetch",
            description: "Holt einen einzelnen Entry mit allen Details anhand seiner ID.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "integer", "description": "ID des Entries"]
                ],
                "required": ["id"]
            ]
        ),
        ToolDefinition(
            name: "entry_list",
            description: "Listet die neuesten Entries auf (nach Erstellungsdatum absteigend).",
            inputSchema: [
                "type": "object",
                "properties": [
                    "limit": ["type": "integer", "description": "Max. Anzahl (Standard: 20)"]
                ]
            ]
        ),
        ToolDefinition(
            name: "entry_markDone",
            description: "Markiert einen Task-Entry als erledigt.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "integer", "description": "ID des Task-Entries"]
                ],
                "required": ["id"]
            ]
        ),
        ToolDefinition(
            name: "entry_archive",
            description: "Archiviert einen Entry (verschiebt ihn ins Archiv).",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "integer", "description": "ID des Entries"]
                ],
                "required": ["id"]
            ]
        ),
        ToolDefinition(
            name: "entry_restore",
            description: "Stellt einen gelöschten oder archivierten Entry wieder her.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "integer", "description": "ID des Entries"]
                ],
                "required": ["id"]
            ]
        ),
        ToolDefinition(
            name: "entry_crossref",
            description: "Findet verwandte Entries zu einem bestimmten Entry (Cross-Referenz).",
            inputSchema: [
                "type": "object",
                "properties": [
                    "entryId": ["type": "integer", "description": "ID des Entries für den Verwandte gesucht werden"]
                ],
                "required": ["entryId"]
            ]
        ),

        // MARK: - Tags
        ToolDefinition(
            name: "tag_add",
            description: "Haengt einen Tag an einen Entry. Erstellt den Tag falls er noch nicht existiert.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "entryId": ["type": "integer", "description": "ID des Entries"],
                    "tag": ["type": "string", "description": "Tag-Name (z.B. 'projekt/brain' für hierarchische Tags)"]
                ],
                "required": ["entryId", "tag"]
            ]
        ),
        ToolDefinition(
            name: "tag_remove",
            description: "Entfernt einen Tag von einem Entry.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "entryId": ["type": "integer", "description": "ID des Entries"],
                    "tag": ["type": "string", "description": "Tag-Name"]
                ],
                "required": ["entryId", "tag"]
            ]
        ),
        ToolDefinition(
            name: "tag_list",
            description: "Listet alle vorhandenen Tags auf.",
            inputSchema: [
                "type": "object",
                "properties": [:]
            ]
        ),
        ToolDefinition(
            name: "tag_counts",
            description: "Listet alle Tags mit der Anzahl zugeordneter Entries.",
            inputSchema: [
                "type": "object",
                "properties": [:]
            ]
        ),

        // MARK: - Links
        ToolDefinition(
            name: "link_create",
            description: "Verknüpft zwei Entries miteinander (bi-direktional).",
            inputSchema: [
                "type": "object",
                "properties": [
                    "sourceId": ["type": "integer", "description": "ID des ersten Entries"],
                    "targetId": ["type": "integer", "description": "ID des zweiten Entries"],
                    "relation": ["type": "string", "enum": ["related", "parent", "blocks", "references"], "description": "Art der Verknüpfung"]
                ],
                "required": ["sourceId", "targetId"]
            ]
        ),
        ToolDefinition(
            name: "link_delete",
            description: "Entfernt die Verknüpfung zwischen zwei Entries.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "sourceId": ["type": "integer", "description": "ID des ersten Entries"],
                    "targetId": ["type": "integer", "description": "ID des zweiten Entries"]
                ],
                "required": ["sourceId", "targetId"]
            ]
        ),
        ToolDefinition(
            name: "link_list",
            description: "Listet alle mit einem Entry verknuepften Entries auf.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "entryId": ["type": "integer", "description": "ID des Entries"]
                ],
                "required": ["entryId"]
            ]
        ),

        // MARK: - Search
        ToolDefinition(
            name: "search_autocomplete",
            description: "Gibt Autocomplete-Vorschläge für einen Suchbegriff (Prefix-Suche).",
            inputSchema: [
                "type": "object",
                "properties": [
                    "prefix": ["type": "string", "description": "Anfang des Suchbegriffs"],
                    "limit": ["type": "integer", "description": "Max. Vorschläge (Standard: 10)"]
                ],
                "required": ["prefix"]
            ]
        ),

        // MARK: - Semantic Search
        ToolDefinition(
            name: "search_semantic",
            description: "Semantische Suche: findet Einträge die inhaltlich ähnlich zum Suchbegriff sind, auch wenn die exakten Wörter nicht vorkommen.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Suchbegriff oder Satz für semantische Ähnlichkeit"],
                    "limit": ["type": "integer", "description": "Maximale Anzahl Ergebnisse (Standard: 10)"]
                ],
                "required": ["query"]
            ]
        ),
        ToolDefinition(
            name: "entry_similar",
            description: "Findet Einträge die einem bestimmten Eintrag inhaltlich ähnlich sind (Deja-Vu-Funktion).",
            inputSchema: [
                "type": "object",
                "properties": [
                    "entry_id": ["type": "integer", "description": "ID des Eintrags für den ähnliche gesucht werden"],
                    "limit": ["type": "integer", "description": "Maximale Anzahl Ergebnisse (Standard: 5)"]
                ],
                "required": ["entry_id"]
            ]
        ),

        // MARK: - Entry erweitert
        ToolDefinition(
            name: "entry_read",
            description: "Liest einen Entry vollständig (alle Felder inkl. Body, Status, Priorität).",
            inputSchema: ["type": "object", "properties": [
                "id": ["type": "integer", "description": "Entry-ID"],
            ], "required": ["id"]]
        ),
        ToolDefinition(
            name: "entry_toggle",
            description: "Wechselt den Status eines Entries zwischen aktiv und erledigt.",
            inputSchema: ["type": "object", "properties": [
                "id": ["type": "integer", "description": "Entry-ID"],
            ], "required": ["id"]]
        ),
    ]
}
