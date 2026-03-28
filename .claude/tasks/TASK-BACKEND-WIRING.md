# Auftrag: Advanced Skills Backend-Wiring

## Ziel
Die bestehenden UI-Shells mit echten Daten und Funktionalitaet verbinden.
Bridges existieren bereits, muessen nur an die Tabs/Skills angebunden werden.

## Voraussetzung
- Input-Bindings bereits gefixt (Two-Way Bindings mit onSetVariable)
- Bridges: ContactsBridge, EventKitBridge, LocationBridge, NotificationBridge, SpotlightBridge
- Services: EntryService, TagService, LinkService, SearchService
- Providers: AnthropicProvider, OpenAIProvider
- KeychainService: save/read/delete/exists

## Auftraege

### 1.2 Kalender-Tab wiren (Klein)
**Datei:** `Sources/BrainApp/DataBridge.swift`
- `calendarVariables()` muss `EventKitBridge.todayEvents()` aufrufen
- Events als ExpressionValue Array zurueckgeben
- Berechtigungsabfrage (EKEventStore.requestAccess) beim ersten Aufruf
- Fehlerfall: Leeres Array + Banner "Kalender-Zugriff nicht erlaubt"

### 1.3 People-Tab wiren (Klein)
**Datei:** `Sources/BrainApp/DataBridge.swift`
- People-Tab muss `ContactsBridge.search("")` aufrufen (alle Kontakte)
- Kontakte als ExpressionValue Array zurueckgeben
- Berechtigungsabfrage (CNContactStore.requestAccess) beim ersten Aufruf
- Suchfeld im People-Tab muss `ContactsBridge.search(query)` aufrufen

### 1.4 Quick Capture → DB (Mittel)
**Dateien:** `Sources/BrainApp/SkillViewModel.swift`, `Sources/BrainApp/DataBridge.swift`
- "Speichern" Button im Quick Capture Skill muss Action "save_entry" ausloesen
- ActionHandler fuer "save_entry": liest text aus SkillViewModel State
- Ruft `EntryService.create(title:body:type:)` auf
- Nach Erfolg: Toast "Gespeichert!", TextField leeren
- Entry-Typ basierend auf Inhalt erkennen (task, thought, note)

### 1.5 Chat → AnthropicProvider (Mittel)
**Dateien:** `Sources/BrainApp/DataBridge.swift`, neuer `ChatService.swift`
- Neuer ChatService der AnthropicProvider nutzt
- API-Key aus KeychainService lesen
- User-Nachricht → AnthropicProvider.complete() → Antwort
- Nachrichten in chat_history Tabelle persistieren (ChatMessage Model existiert)
- Chat-Tab Skill muss messages Array aus DB laden
- Neuer ActionHandler "send_message": Text → ChatService → Response → UI Update
- Markdown-Rendering fuer AI-Antworten (markdown Primitive existiert)

### 1.6 API-Key Settings UI (Klein)
**Datei:** Neuer `SettingsSkill.swift` oder als BootstrapSkill
- Settings-Screen als Skill definieren (JSON)
- Sections: "LLM Anbieter", "Sicherheit", "Ueber Brain"
- Anthropic API-Key: secure-field + save Button → KeychainService.save()
- OpenAI API-Key: secure-field + save Button → KeychainService.save()
- Key-Status anzeigen: "Konfiguriert" / "Nicht konfiguriert" (KeychainService.exists())
- Zugang: Brain Admin Tab oder eigener Settings-Button in der Toolbar

### 1.7 Search UI wiren (Klein)
**Dateien:** `Sources/BrainApp/DataBridge.swift`, `Sources/BrainApp/SkillViewModel.swift`
- Search-TextField in Files-Tab und Dashboard muss funktionieren
- Bei Eingabe: `SearchService.searchWithFilters(query:)` aufrufen
- Ergebnisse als Entry-Liste darstellen
- Debounce: 300ms nach letztem Tastendruck (kein Suchen bei jedem Buchstaben)
- Leere Suche: Alle Entries anzeigen (oder Recent Entries)

### 1.8 Entry Detail/Edit View (Mittel)
**Datei:** Neuer `EntryDetailSkill.swift` oder als dynamischer Skill
- Tap auf Entry in Liste → Navigation zu Detail-View
- Detail zeigt: Titel, Body, Typ, Tags, Links, Created/Updated Datum
- Edit-Mode: Titel und Body editierbar (text-field, text-editor)
- Tags anzeigen und hinzufuegen/entfernen
- Save Button → EntryService.update()
- Delete Button → Confirmation Dialog → EntryService.softDelete()
- Zurueck-Navigation nach Save/Delete

## Reihenfolge
```
1.6 (API-Key Settings) → 1.5 (Chat) → 1.4 (Quick Capture) → 1.2 (Kalender) → 1.3 (People) → 1.7 (Search) → 1.8 (Entry Detail)
```
API-Key zuerst, weil Chat davon abhaengt.

## Qualitaetskriterien
- Jeder Tab zeigt echte Daten (keine leeren Arrays mehr)
- Berechtigungsabfragen erscheinen beim ersten Zugriff
- Fehler werden dem User angezeigt (Toast/Banner)
- Kein Crash bei fehlenden Berechtigungen oder Netzwerk-Fehlern
- Chat funktioniert mit Anthropic API-Key
- Quick Capture erstellt echte Entries in der Datenbank
- Search liefert Ergebnisse aus FTS5
