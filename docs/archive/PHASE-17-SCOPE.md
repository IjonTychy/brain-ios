# Phase 17: TestFlight-Ready

> Ziel: brain-ios von einer UI-Shell mit Placeholder-Daten zu einer funktionsfaehigen
> App machen, die ueber TestFlight verteilt und taeglich genutzt werden kann.

---

## Uebersicht

| Sprint | Name | Prioritaet | Abhaengigkeit |
|--------|------|------------|---------------|
| S1 | Onboarding-Flow | HOCH | — |
| S2 | Backend-Wiring | HOCH | S1 (API-Key) |
| S3 | LLM Streaming | MITTEL | S2 (Chat-Backend) |
| S4 | Xcode Cloud Tests | MITTEL | S2 |
| S5 | On-Device LLM | NIEDRIG | S3 |

---

## S1: Onboarding-Flow

**Warum:** Ohne Onboarding ist die App fuer TestFlight-Tester nicht verstaendlich.

### Schritte

**S1.1: OnboardingView erstellen**
- Neue Datei: `Sources/BrainApp/OnboardingView.swift`
- SwiftUI TabView mit PageTabViewStyle (4 Swipe-Pages)
- Screen 1: Willkommen (Logo, Titel, Untertitel)
- Screen 2: Features (4 Icons mit Beschreibung)
- Screen 3: Datenschutz (Privacy-Erklaerung)
- Screen 4: Los geht's (Start-Button)

**S1.2: API-Key Setup**
- Zwischen Screen 3 und 4 einfuegen
- secure-field fuer Anthropic API-Key
- "Testen" Button → kurzer API-Call zur Validierung
- "Ueberspringen" Option
- Key → KeychainService.save("anthropic_api_key", key)

**S1.3: Berechtigungen anfragen**
- Kontakte: CNContactStore.requestAccess()
- Kalender: EKEventStore.requestAccess()
- Benachrichtigungen: UNUserNotificationCenter.requestAuthorization()
- Jede einzeln mit Erklaerung und "Nicht jetzt" Option

**S1.4: Face ID Setup**
- "Schuetze Brain mit Face ID" Screen
- "Aktivieren" → Test-Authentifizierung
- "Ohne Face ID fortfahren" Option
- Einstellung in UserDefaults speichern

**S1.5: Erster Entry erstellen**
- "Schreib deinen ersten Gedanken" TextField
- "Speichern" → EntryService.create()
- Optional, kann uebersprungen werden

**S1.6: Onboarding-Flag**
- @AppStorage("hasCompletedOnboarding") in BrainApp.swift
- Onboarding VOR Face ID Lock Screen
- Reset-Option in Settings fuer Entwicklung

### Tests
- Onboarding erscheint nur beim ersten Start
- Alle "Ueberspringen" Pfade funktionieren ohne Crash
- API-Key wird im Keychain gespeichert
- Berechtigungen werden korrekt angefragt

---

## S2: Backend-Wiring

**Warum:** Alle Tabs zeigen leere Arrays. Bridges existieren, sind aber nicht verbunden.

### Schritte

**S2.1: API-Key Settings UI**
- Settings-Screen als Skill oder eigene View
- Anthropic + OpenAI Key Eingabe (secure-field)
- Key-Status: "Konfiguriert" / "Nicht konfiguriert"
- Zugang via Brain Admin Tab oder Toolbar-Button

**S2.2: Kalender-Tab wiren**
- DataBridge.calendarVariables() → EventKitBridge.todayEvents()
- Events als ExpressionValue Array zurueckgeben
- Fehlerfall: Leeres Array + Banner

**S2.3: People-Tab wiren**
- DataBridge → ContactsBridge.search("")
- Suchfeld → ContactsBridge.search(query)
- Kontakte als ExpressionValue Array

**S2.4: Quick Capture → DB**
- "Speichern" Button → ActionHandler "save_entry"
- Liest Text aus SkillViewModel State
- EntryService.create(title:body:type:)
- Toast "Gespeichert!", TextField leeren

**S2.5: Chat → AnthropicProvider**
- Neuer ChatService: API-Key aus Keychain → AnthropicProvider.complete()
- Nachrichten in chat_history persistieren
- Chat-Tab messages Array aus DB laden
- ActionHandler "send_message"
- Markdown-Rendering fuer AI-Antworten

**S2.6: Search UI wiren**
- Search-TextField → SearchService.searchWithFilters()
- Debounce 300ms
- Ergebnisse als Entry-Liste

**S2.7: Entry Detail/Edit View**
- Tap auf Entry → Detail-View (Titel, Body, Tags, Dates)
- Edit-Mode mit Save/Delete
- Zurueck-Navigation nach Aktion

### Reihenfolge
S2.1 → S2.5 → S2.4 → S2.2 → S2.3 → S2.6 → S2.7

### Tests
- Kein Tab zeigt mehr leere Arrays (bei vorhandenen Berechtigungen)
- Chat funktioniert mit API-Key
- Quick Capture erstellt echte Entries
- Search liefert FTS5-Ergebnisse

---

## S3: LLM Streaming

**Warum:** Chat ohne Streaming fuehlt sich langsam und tot an.

### Schritte

**S3.1: AnthropicProvider Streaming**
- supportsStreaming = true
- POST /v1/messages mit "stream": true
- SSE-Parsing: message_start, content_block_delta, message_stop
- URLSession bytes(for:) fuer async byte stream
- AsyncThrowingStream<Delta, Error>

**S3.2: Chat-UI Streaming-Anzeige**
- Typing-Indicator waehrend Streaming
- Token-by-Token Text-Aufbau
- Auto-Scroll
- Cancel-Button
- Error-State mit Retry

**S3.3: OpenAIProvider Streaming**
- Analog zu Anthropic
- SSE Format: data: {"choices":[{"delta":{"content":"..."}}]}

**S3.4: Markdown-Rendering**
- AI-Antworten als markdown Primitive rendern
- Code-Bloecke, Links, Listen

### Tests
- Erste Tokens erscheinen innerhalb 1-2 Sekunden
- UI bleibt responsive
- Cancel bricht Stream sofort ab
- Chat-History wird nach Completion gespeichert

---

## S4: Xcode Cloud Tests

**Warum:** 90 Primitives ohne Tests = Risiko. Xcode Cloud hat iOS Simulator.

### Schritte

**S4.1: Test-Target anlegen**
- BrainAppTests Target in BrainApp.xcodeproj
- @testable import BrainApp

**S4.2: SkillRenderer Smoke Tests**
- 1 Test pro Primitive (90 Tests): Rendert ohne Crash
- 9 Test-Dateien (pro Kategorie)
- Edge Cases: fehlende Properties, leere Children

**S4.3: Xcode Cloud Workflow erweitern**
- Test-Action hinzufuegen (vor Archive)
- Destination: Any iOS Simulator

### Tests
- 90+ neue Tests, alle gruen auf Xcode Cloud
- Kein Test > 5 Sekunden

---

## S5: On-Device LLM

**Warum:** Offline-Nutzung und Privacy. Kann nach v1.0 TestFlight gemacht werden.

### Schritte

**S5.1: MLX Swift Integration**
- SPM Dependency mlx-swift
- MLXProvider implementiert LLMProvider Protocol
- Modell laden aus Documents/Models/

**S5.2: Modell-Download UI**
- Settings → verfuegbare Modelle (Llama 3.2 3B, Phi-3 Mini)
- Speicherplatz-Check, Download mit Progress

**S5.3: Offline-Routing**
- NWPathMonitor → wenn offline + MLXProvider → automatisch routen

**S5.4: Modell-Auswahl**
- Picker fuer installierte Modelle
- Benchmark: "X Tokens/Sek auf diesem Geraet"

### Tests
- Modell laeuft auf iPhone 15 Pro (~10-30 tokens/sec)
- Offline-Chat funktioniert
- App crasht nicht bei Speichermangel

---

## Phase-Gate

Jeder Sprint ist ein eigenes Gate:
- S1 abgeschlossen → Review, dann S2 starten
- S2 abgeschlossen → Review, dann S3 starten
- S3 + S4 koennen parallel laufen
- S5 ist optional fuer v1.0

**Definition of Done (Phase 17):**
- App startet mit Onboarding
- Alle Tabs zeigen echte Daten
- Chat mit Claude funktioniert (mit Streaming)
- Quick Capture erstellt Entries
- Suche funktioniert
- 90 Renderer-Primitives getestet
- Xcode Cloud Build + Tests gruen
- TestFlight-Build verfuegbar
