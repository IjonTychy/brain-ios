# Audit-Findings Fix-Plan

Basierend auf dem Assessment vom 23.03.2026. Sortiert nach Severity.
Enthaelt ALLE Findings aus dem Assessment + User-Requests.

> Status 25.03.2026: Dieses Dokument ist jetzt ein **historischer Audit-Backlog** und kein
> autoritativer Live-Plan mehr. Fuer den aktuellen Stand gelten `ARCHITECTURE.md`,
> `CLAUDE.md`, `SESSION-LOG.md` und `REVIEW-NOTES.md`.

## Bereits erledigt / ueberholt (Stand 25.03.2026)

- **A2 erledigt:** Anthropic-Max/Session-Token-Modus entfernt.
- **E5 erledigt:** Skill-Inputs haben produktive Bindings; der aktuelle Fix-Pass hat zusaetzlich
  den Action-Kontext in Listen/Repeaters repariert.
- **E6 erledigt:** SkillView zeigt Fehler wieder an.
- **F1 weitgehend erledigt:** Gemini OAuth und die aktuelle Provider-Auswahl sind implementiert;
  die Build-/Runtime-Pfade fuer Skill-Kompilierung wurden am 25.03 auf den realen Provider-Stack
  nachgezogen.
- **Shortcuts/App-Intents Runtime-Fix erledigt:** App und Intents teilen sich jetzt dieselbe DB
  ueber `SharedContainer`.

---

## Phase A: Security Fixes (MEDIUM)

### A1: TOFU-Pins von UserDefaults nach Keychain migrieren
- **Datei:** `Sources/BrainApp/LLMProviders/CertificatePinning.swift` (Zeilen 50-95)
- **Problem:** TOFU-Pins (Trust-On-First-Use SHA-256 Hashes) werden in UserDefaults gespeichert. Ein Angreifer mit App-Sandbox-Zugriff koennte Pins manipulieren und MITM ermoeglichen.
- **Fix:** `loadTOFUPins()` und `saveTOFUPin()` auf KeychainService umstellen. Keychain-Key: `certificatePinning.tofuPins`. Migration: beim ersten Aufruf UserDefaults lesen, in Keychain schreiben, UserDefaults loeschen.
- **Tests:** Bestehende CertificatePinning-Tests anpassen.

### A2: Anthropic Max Session-Token-Modus entfernen
- **Datei:** `Sources/BrainApp/LLMProviders/AnthropicProvider.swift`, `Sources/BrainApp/SettingsView.swift`
- **Problem:** Der "Max"-Modus nutzt Session-Tokens aus Browser-Cookies. Anthropic hat im Feb 2026 explizit verboten, OAuth/Session-Tokens fuer Drittanbieter-Apps zu verwenden (Verstoss gegen Consumer ToS). Accounts koennen gesperrt werden.
- **Fix:** Max-Modus komplett entfernen. Settings auf 2 Modi reduzieren: "API-Key" und "Proxy". Klare Hinweise dass ein API-Key benoetigt wird.
- **Quellen:** https://winbuzzer.com/2026/02/19/anthropic-bans-claude-subscription-oauth-in-third-party-apps-xcxwbn/

## Phase B: Code-Robustheit (LOW)

### B1: try! in ExpressionParser durch statische Initialisierung ersetzen
- **Datei:** `Sources/BrainCore/Engine/ExpressionParser.swift:83`
- **Problem:** `try! NSRegularExpression(...)` — sicher weil Pattern hardcoded, aber verletzt Konvention.
- **Fix:** `guard let regex = try? NSRegularExpression(...) else { fatalError("Invalid hardcoded regex") }` — gleicher Effekt, aber expliziter Intent.

### B2: try! in BrainApp Fallback-DB ersetzen
- **Datei:** `Sources/BrainApp/BrainApp.swift:50`
- **Problem:** `try! DatabaseManager.temporary()` als Fallback wenn Haupt-DB fehlschlaegt.
- **Fix:** `do { db = try DatabaseManager.temporary() } catch { fatalError("Cannot create temporary DB: \(error)") }` — bessere Diagnostik im Crash-Log.

### B3: Force-Unwraps in BrainApp.swift absichern
- **Datei:** `Sources/BrainApp/BrainApp.swift:39, 209, 236`
- **Problem:** 3x `FileManager...urls(...).first!` — sicher auf iOS, aber verletzt Konvention.
- **Fix:** `guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { fatalError("No Documents directory") }` — eine Hilfsfunktion, 3x aufrufen.

## Phase C: Performance (LOW)

### C1: Fehlende DB-Indizes ergaenzen
- **Datei:** `Sources/BrainCore/Database/Migrations.swift`
- **Problem:** Bei 100k+ Entries werden gefilterte Queries langsam ohne Indizes auf haeufigen Filter-Spalten.
- **Fix:** Neue Migration `v12_performance_indices`:
  ```sql
  CREATE INDEX IF NOT EXISTS idx_entries_type_status ON entries(type, status);
  CREATE INDEX IF NOT EXISTS idx_entries_created ON entries(createdAt);
  CREATE INDEX IF NOT EXISTS idx_emailCache_account_read ON emailCache(accountId, isRead);
  CREATE INDEX IF NOT EXISTS idx_knowledgeFacts_subject ON knowledgeFacts(subject);
  ```
- **Hinweis:** Pruefen ob v3-Migration diese bereits enthaelt. Falls ja, nur die fehlenden ergaenzen.

## Phase D: Code-Hygiene (LOW)

### D1: ToolDefinitions.swift aufteilen
- **Datei:** `Sources/BrainApp/ToolDefinitions.swift` (1702 Zeilen)
- **Problem:** Groesste Datei im Projekt, schwer zu navigieren.
- **Fix:** Aufteilen in thematische Dateien:
  - `ToolDefinitions+Entry.swift` (Entry CRUD Tools)
  - `ToolDefinitions+Communication.swift` (Email, Contact Tools)
  - `ToolDefinitions+System.swift` (Calendar, Reminder, File, Storage Tools)
  - `ToolDefinitions+AI.swift` (LLM, Knowledge, Skill Tools)
  - `ToolDefinitions+Mapping.swift` (toolNameToHandlerType Dictionary)
- **Risiko:** Niedrig — rein strukturelle Aenderung, keine Logik-Aenderung.

## Phase E: UX-Verbesserungen

### E1: Offline-Indikator
- **Quelle:** Assessment Finding "Kein Offline-Indikator"
- **Problem:** App ist offline-first, signalisiert dies aber nirgends. User weiss nicht ob Cloud-LLM verfuegbar ist oder nur On-Device.
- **Fix:** `NetworkMonitor` Service (NWPathMonitor) der den Verbindungsstatus trackt. Kleines Icon in der Toolbar/StatusBar (z.B. Cloud-Symbol mit Slash wenn offline). ChatView zeigt "Offline — On-Device LLM aktiv" Banner wenn kein Internet.
- **Dateien:** Neuer `NetworkMonitor.swift`, Aenderungen in `ContentView.swift`, `ChatView.swift`
- **Aufwand:** ~2h

### E2: Visuelle Konsistenz (Native SwiftUI vs. JSON-Skills)
- **Quelle:** Assessment Finding "Visuelle Inkonsistenz"
- **Problem:** Native Views (Kontakte, Mail, Settings) und JSON-gerenderte Skills (Dashboard, Custom Skills) haben unterschiedliches Look & Feel.
- **Fix:** Gemeinsames Design-System: `BrainTheme` Struct mit konsistenten Farben, Spacing, Corner-Radii, Schatten. Anwenden auf SkillRenderer UND native Views. Section-Header-Stil vereinheitlichen. Card-Stil fuer beide Welten gleich.
- **Dateien:** Neuer `BrainTheme.swift`, Aenderungen in `SkillRenderer*.swift`, diverse Views
- **Aufwand:** ~4-6h

### E3: Inline-Feldvalidierung
- **Quelle:** Assessment Finding "Fehler-Zustaende"
- **Problem:** Toasts vorhanden fuer Fehler, aber keine Inline-Validierung bei Formularen (z.B. API-Key-Eingabe, Mail-Konfiguration, Entry-Erstellung).
- **Fix:** `ValidationModifier` ViewModifier der unter TextFields eine rote Fehlermeldung anzeigt. Anwenden auf: SettingsView (API-Key), MailConfigView (IMAP/SMTP), EntryDetailView (Titel-Pflichtfeld), OnboardingView.
- **Dateien:** Neuer `ValidationModifier.swift`, Aenderungen in betroffenen Views
- **Aufwand:** ~2-3h

### E4: Visual Knowledge Graph
- **Quelle:** Assessment Finding "Knowledge-Graph-Visualisierung unvollstaendig"
- **Problem:** MapView ist ein Platzhalter fuer geo-getaggte Entries. Ein visueller Knowledge Graph wuerde mehr Mehrwert bieten.
- **Fix:** `KnowledgeGraphView` mit Grape Force-Directed-Layout. Nodes = Entries + Tags + Personen. Edges = Links + Tags + Knowledge Facts. Tap auf Node oeffnet Entry/Tag-Detail. Pinch-to-Zoom, Drag. Suchfilter. Kann den Map-Tab ersetzen oder als zusaetzlicher Tab.
- **Dateien:** Neuer `KnowledgeGraphView.swift`, Aenderungen in `ContentView.swift` (Tab)
- **Aufwand:** ~6-8h
- **Abhaengigkeit:** Grape ist in ARCHITECTURE.md referenziert. Pruefen ob im Package.swift enthalten, sonst hinzufuegen.

### E5: Two-Way Input Binding fuer Skills
- **Quelle:** Assessment Finding "Input-Binding unvollstaendig"
- **Problem:** TextField und Toggle in JSON-gerenderten Skills verwenden `.constant()` Bindings — sie sind read-only. Quick Capture und interaktive Skills funktionieren nicht richtig.
- **Fix:** `SkillViewModel` um State-Dictionary erweitern. Jedes Input-Primitive bekommt einen `bindingKey`. SkillRenderer erstellt echte `@Binding`s die in SkillViewModel.state schreiben/lesen. Actions koennen via `{{state.fieldName}}` auf die Werte zugreifen.
- **Dateien:** `SkillViewModel.swift`, `SkillRenderer.swift`, `SkillRendererInput.swift`
- **Aufwand:** ~4-6h

### E6: Error-Banner in SkillView
- **Quelle:** Assessment Finding (seit Gross-Review offen)
- **Problem:** `SkillViewModel.errorMessage` existiert als Property, wird aber nirgends in der UI angezeigt. User sieht keine Fehlermeldungen bei Action-Fehlschlaegen in Skills.
- **Fix:** Rotes Banner (oder `.alert()`) in `SkillView` das `errorMessage` anzeigt. Auto-Dismiss nach 5 Sekunden oder via Tap.
- **Dateien:** `SkillView.swift` (oder wo SkillViewModel genutzt wird)
- **Aufwand:** ~30min

## Phase F: LLM-Provider Auth-Architektur

### F1: Auth-Mode-Abstraktion und Gemini OAuth2
- **Quelle:** User-Request "Abo-Einbindung" + Recherche-Ergebnis
- **Recherche-Ergebnis (23.03.2026):**
  - **Anthropic:** Hat im Feb 2026 Third-Party-OAuth/Session-Tokens VERBOTEN. Nur API-Keys erlaubt. Max-Modus muss entfernt werden (→ A2).
  - **OpenAI:** Kein OAuth fuer Dritte. Plus-Abo ≠ API-Zugang. Apps SDK (MCP) nur innerhalb ChatGPT UI. Nur API-Keys.
  - **Google Gemini:** OAuth2 offiziell unterstuetzt! Standard Google `InstalledAppFlow`. Scope: `generative-language.retriever`. Einziger Provider mit sauberem Pfad.
- **Fix:**
  1. `LLMAuthMode` Protocol/Enum: `.apiKey(String)`, `.oauth(OAuthCredential)`, `.proxy(URL)`
  2. `LLMProvider` Protocol um `supportedAuthModes: [LLMAuthMode]` erweitern
  3. `GeminiProvider`: Google OAuth2 implementieren via ASWebAuthenticationSession (iOS-nativer OAuth-Browser). Scope `generative-language.retriever`. Refresh-Token in Keychain. Access-Token automatisch erneuern.
  4. `AnthropicProvider` + `OpenAIProvider`: Nur `.apiKey` und `.proxy` — klar dokumentiert warum kein OAuth (ToS/nicht verfuegbar).
  5. SettingsView: Pro Provider zeigt nur die unterstuetzten Auth-Modi an. Gemini bekommt "Mit Google anmelden"-Button.
  6. Zukunftssicher: Wenn Anthropic/OpenAI OAuth einfuehren, muss nur der Provider + SettingsView erweitert werden.
- **Dateien:** `LLMProvider.swift`, `GeminiProvider.swift`, `AnthropicProvider.swift`, `SettingsView.swift`, neuer `GoogleOAuthService.swift`
- **Aufwand:** ~6-8h
- **Quellen:**
  - Anthropic Verbot: https://www.theregister.com/2026/02/20/anthropic_clarifies_ban_third_party_claude_access/
  - OpenAI kein OAuth: https://community.openai.com/t/why-cant-users-leverage-their-own-openai-plus-subscriptions-for-api-access/1023241
  - Gemini OAuth: https://ai.google.dev/gemini-api/docs/oauth

## Phase G: Test-Coverage (Assessment Finding)

### G1: BrainApp-Tests ausbauen
- **Quelle:** Assessment Finding "BrainApp Test Coverage minimal"
- **Problem:** BrainCore hat 467 Tests, BrainApp nur 1 Datei (HandlerTests.swift). Renderer, Bridges und Views sind nicht getestet.
- **Fix:** Mindestens folgende Test-Dateien erstellen:
  - `RendererTests.swift` — Testet ob JSON-Nodes korrekt in ViewBuilder-Aufrufe uebersetzt werden
  - `ExpressionParserIntegrationTests.swift` — End-to-End Expression-Resolution mit echten Skill-JSONs
  - `NetworkMonitorTests.swift` — Falls E1 implementiert
  - `BrainThemeTests.swift` — Falls E2 implementiert
- **Aufwand:** ~8-12h fuer gute Abdeckung
- **Hinweis:** Viele BrainApp-Tests brauchen iOS Simulator (Xcode). Auf VPS nur testbar was keine UIKit/SwiftUI-Imports hat.

## Phase H: Skill-basierte Lokalisierung (i18n)

### H1: LocalizationService + Language-Skill-Format
- **Quelle:** User-Request "Labels in Skills definieren, pro Sprache ein Skill"
- **Konzept:** Statt Apple `.strings`/`.xcstrings` werden alle UI-Labels als Key-Value-Paare in einem Language-Skill definiert. User koennen eigene Uebersetzungen als `.brainskill.md` erstellen und teilen.
- **Format:**
  ```markdown
  ---
  id: brain-language-de
  name: Deutsch
  capability: app
  category: language
  locale: de
  ---
  ## Labels
  tab.home: Home
  tab.search: Suche
  tab.chat: Chat
  tab.mail: Posteingang
  button.save: Speichern
  button.cancel: Abbrechen
  ...
  ```
- **Fix:**
  1. `LocalizationService`: Laedt aktiven Language-Skill, stellt `L("key")` Funktion bereit
  2. Fallback-Kette: aktiver Skill → eingebautes Deutsch → Key selbst
  3. Sprachauswahl: Systemsprache als Default, manuell ueberschreibbar in Settings
  4. 2 eingebaute Language-Skills: `brain-language-de` (Deutsch) + `brain-language-en` (Englisch)
  5. Alle hardcodierten Strings in Views durch `L("key")` ersetzen
  6. Skill-Kategorie `language` in SkillManager speziell behandeln (nur einer aktiv)
- **Dateien:** Neuer `LocalizationService.swift`, 2 `.brainskill.md` Dateien, Aenderungen in allen Views
- **Aufwand:** ~8-12h (Service + 2 Skills + Refactoring aller Views)

## Phase I: Commit & Push

### I1: Code-Review
- code-reviewer Agent ueber alle Aenderungen laufen lassen

### I2: Tests
- `swift test` ausfuehren (BrainCore-Tests)
- Sicherstellen dass keine Regression entsteht

### I3: Commit & Push
- Einen Commit pro Phase oder thematische Commits
- Push auf `claude/fix-swift-compiler-errors-dnedh`

---

## Zusammenfassung: Was kommt woher?

| # | Finding | Quelle |
|---|---------|--------|
| A1 | TOFU-Pins Keychain | Assessment: Security |
| A2 | Max-Modus entfernen | Recherche: Anthropic ToS-Verstoss |
| B1 | try! ExpressionParser | Assessment: Code-Hygiene |
| B2 | try! BrainApp | Assessment: Code-Hygiene |
| B3 | Force-Unwraps | Assessment: Code-Hygiene |
| C1 | DB-Indizes | Assessment: Performance |
| D1 | ToolDefinitions Split | Assessment: Code-Hygiene |
| E1 | Offline-Indikator | Assessment: UX + User-Request |
| E2 | Visuelle Konsistenz | Assessment: UX + User-Request |
| E3 | Inline-Validierung | Assessment: UX + User-Request |
| E4 | Knowledge Graph | Assessment: Funktionsumfang + User-Request |
| E5 | Two-Way Binding | Assessment: Funktionsumfang (seit Gross-Review offen) |
| E6 | Error-Banner Skills | Assessment: UX (seit Gross-Review offen) |
| F1 | Auth-Abstraktion + Gemini OAuth | User-Request + Recherche |
| G1 | BrainApp-Tests | Assessment: Test-Coverage |
| H1 | Skill-basierte Lokalisierung | User-Request |
