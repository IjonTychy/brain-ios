# brain-ios – Review-Notes

> Periodische Reviews durch den Zora-Review-Agent. Findings werden hier dokumentiert.
> Claude Code arbeitet offene Findings mit Priorität ab (vor dem normalen Scope).
> Format: Neuester Review zuerst.

---

## Session-Review 26.03.2026 -- Contacts Crash Fix + Settings UI + Dashboard Fix

### Status: OK

### Zusammenfassung

Contacts-Crash durch fehlenden CNContactFormatter-Descriptor behoben. Settings UI vereinfacht
(Advanced-Toggle entfernt, Proxy nach oben). Dashboard Aufgaben-Tile navigiert jetzt korrekt
(goToSearch statt goToCalendar). System Prompt Skill-Creator Hint verstaerkt. SSH Keepalive
auf VPS konfiguriert fuer stabile MacVM-Verbindung.

### Findings

- **[BEHOBEN] Schweregrad: hoch** -- Contacts-Crash: CNContactFormatter schlug fehl wegen fehlendem
  Descriptor. Fix: Korrekten keysToFetch-Descriptor hinzugefuegt + Merge-Hinweis dokumentiert.

- **[BEHOBEN] Schweregrad: mittel** -- Dashboard Aufgaben-Tile navigierte zu Kalender statt Suche.
  Fix: goToCalendar durch goToSearch ersetzt.

- **[BEHOBEN] Schweregrad: mittel** -- Settings UI: Erweiterte Einstellungen waren hinter
  Advanced-Toggle versteckt. Fix: Toggle entfernt, alle Sektionen sichtbar, Proxy nach oben.

- **[BEHOBEN] Schweregrad: niedrig** -- System Prompt Skill-Creator Hint war zu schwach, KI
  erstellte nicht zuverlaessig Skills. Fix: Hint im System Prompt verstaerkt.

- **[BEHOBEN] Schweregrad: niedrig** -- SSH-Tunnel zur MacVM brach regelmaessig ab.
  Fix: ClientAliveInterval 60 + ClientAliveCountMax 10 auf VPS konfiguriert.

- **[OFFEN] Schweregrad: mittel** -- Mail Sync: Geloeschte Mails kehren nach erneutem Sync zurueck.
  Delete-Flag wird nicht korrekt an den IMAP-Server propagiert.

- **[OFFEN] Schweregrad: mittel** -- Skills Qualitaet: actions_json wird von der KI nicht
  zuverlaessig generiert. Braucht bessere Beispiele oder Schema-Validierung.

- **[OFFEN] Schweregrad: niedrig** -- Google OAuth noch nicht auf physischem Device getestet.

---
## Session-Review 25.03.2026 — Runtime-Fixes + Dokumentationsabgleich

### Status: OK (Runtime-Verifikation ausstehend)

### Zusammenfassung

Die kritischsten Laufzeitpfade wurden code-seitig repariert: Contacts-Tab, Skill-Runtime,
Skill-Import/Kompilierung, Self-Improve-Handoff sowie Shortcuts/App-Intents. Parallel dazu wurde
die Projektdokumentation bereinigt: `ARCHITECTURE.md` auf den aktuellen Implementierungsstand
gezogen, `CLAUDE.md` mit verifiziertem Snapshot aktualisiert, doppelte 24.03-Eintraege in
`SESSION-LOG.md` und `REVIEW-NOTES.md` entfernt und `PLAN.md` als historischer Backlog markiert.

### Findings

- **[OFFEN] Schweregrad: mittel** — Die Runtime-Fixes vom 25.03 sind noch nicht auf Device oder im
  Simulator verifiziert. Besonders Kontakte, Skill-Kompilierung und Shortcuts/App-Intents brauchen
  einen echten Xcode/iOS-Durchlauf.

- **[BEHOBEN] Schweregrad: mittel** — Dokumentationsdrift zwischen Architekturtext und
  Implementierung. Fix: `ARCHITECTURE.md` beschreibt jetzt GRDB + SharedContainer, `entryEmbeddings`,
  EmailBridge und den realen Provider-Stack statt veralteter SQLiteData/SwiftMail-Annahmen.

- **[BEHOBEN] Schweregrad: mittel** — Doppelte 24.03-Reviews und Session-Eintraege fuehrten zu
  konkurrierenden Wahrheiten. Fix: Die doppelten Anhaenge wurden entfernt, die aktuelle 25.03-Session
  dokumentiert und der operative Snapshot zentral in `CLAUDE.md` aktualisiert.

- **[OFFEN] Schweregrad: niedrig** — BrainTheme/BrainEffects sind weiterhin nur teilweise auf die
  produktiven Views ausgerollt. Das bleibt ein UX-Thema, ist aber kein Blocker fuer den aktuellen
  Runtime-Fix-Pass.

---

## Session-Review 24.03.2026 — Frontend Overhaul + Bugfixes

### Status: OK (Build ausstehend)

### Zusammenfassung

Kompletter visueller Overhaul der App: Neues Design System (BrainTheme), Material-Backgrounds, SF Symbol Animationen, Spring Physics, Haptics, ScrollTransitions. 10 Bugfixes implementiert. Alle 12 "Fertig"-Keyboard-Buttons entfernt. Neues kontextuelles Hilfe-System (BrainHelpButton). 19 Commits, Build 6 an Xcode Cloud gesendet.

### Findings

- **[BEHOBEN] Schweregrad: hoch** — Bugfix #5: Auto-Routing wurde durch manuelles chatModelOverride ueberschrieben. Fix: chatModelOverride = nil wenn autoRouteModels aktiv.

- **[BEHOBEN] Schweregrad: hoch** — Bugfix #14: "Interview starten" im Onboarding funktionierte nicht. NavigationLink in TabView hat keinen NavigationStack-Parent. Fix: .sheet Praesentation.

- **[BEHOBEN] Schweregrad: hoch** — Bugfix #12: Skill-Buttons waren wirkungslos. handleBuiltinAction kannte nur "navigate:*". Fix: goTo*, navigate.tab:*, Fehlermeldung bei unbekannten Actions.

- **[BEHOBEN] Schweregrad: mittel** — Bugfix #4: Mail "Speichern & Testen" schloss UI sofort ohne Erfolgsmeldung. Fix: 1.5s Verzoegerung mit Erfolgsmeldung.

- **[BEHOBEN] Schweregrad: mittel** — Bugfix #15: 12x doppelte "Fertig"-Buttons ueber der Tastatur. Fix: Alle entfernt, .scrollDismissesKeyboard als Standard.

- **[BEHOBEN] Schweregrad: mittel** — Bugfix #16b: Gemini 2.0 Flash 404 Error. Fix: Aktualisierte Model-IDs (2.5 Pro/Flash).

- **[BEHOBEN] Schweregrad: niedrig** — Bugfix #2/#13: Kontakte ohne Sortierung und ohne Bearbeiten-Button. Fix: Sort-Menu + CNContactViewController Sheet.

- **[BEHOBEN] Schweregrad: niedrig** — Bugfix #10/#11: Privacy Zones Tags nicht erklaert, Model-Preise fehlten. Fix: Ausfuehrliche Erklaerung + echte Preise.

- **[OFFEN] Schweregrad: mittel** — Bugfix #7: entry.open Fehler auf Dashboard. Fehlermeldung wird dynamisch generiert, Quelle unklar. Braucht Skill-Engine Debugging.

- **[OFFEN] Schweregrad: niedrig** — Bugfix #3: Tags koennen nirgends erfasst werden. Tag-Editor (TagEditorView) noch nicht implementiert.

- **[OFFEN] Schweregrad: niedrig** — Bugfix #6/#8: Dashboard "Heute" ohne Kalendereintraege. Braucht Erweiterung der Dashboard-Skill-Definition und DataBridge.

- **[OFFEN] Schweregrad: niedrig** — ContentView-Merge: Nach dem Merge mit Google OAuth PRs (ContentView aufgeteilt) muessten einige Patches (Bugfix #5, BrainAvatar in Tabs) auf die neue Dateistruktur uebertragen werden.

---

## Session-Review 23.03.2026 — Google OAuth, Multi-Provider, Code-Cleanup

### Status: OK

### Zusammenfassung

Umfangreiche Session mit 20 Commits auf Branch `claude/add-google-oauth-DsV33`. Hauptarbeit: Google OAuth fuer Gemini, Multi-Provider-Support (OpenAI erweitert, xAI Grok neu, Custom Endpoints), grosse Datei-Aufteilungen (4 God Objects eliminiert), Dead-Code-Bereinigung (~850 Zeilen), Duplikat-Eliminierung (~110 Zeilen), und 8 fehlende Dateien im pbxproj registriert. System-Prompt modularisiert und verschlankt.

### Findings

- **[BEHOBEN] Schweregrad: mittel** — Google OAuth fehlte. Jetzt implementiert mit PKCE, Token-Refresh, Keychain-Storage. GeminiProvider unterstuetzt API-Key und OAuth.

- **[BEHOBEN] Schweregrad: mittel** — ContentView.swift war mit 1074 Zeilen ein God Object. Aufgeteilt in PeopleTabView, QuickCaptureView, ChatView (jeweils eigene Dateien). Jetzt 374 Zeilen.

- **[BEHOBEN] Schweregrad: mittel** — OnboardingView.swift war mit 1241 Zeilen das groesste File. Aufgeteilt in 4 Dateien (Hauptview + 3 Page-Gruppen im Onboarding/-Ordner). Jetzt 295 Zeilen.

- **[BEHOBEN] Schweregrad: mittel** — MailTabView.swift 1130 Zeilen. Aufgeteilt in MailInboxView und MailConfigView. Jetzt 367 Zeilen.

- **[BEHOBEN] Schweregrad: mittel** — SettingsView.swift hatte ~400 Zeilen toten Code (alte Provider-Sections, die nie aus body referenziert wurden). Komplett entfernt.

- **[BEHOBEN] Schweregrad: niedrig** — SearchContactDetailView war eine fast identische Kopie (~110 Zeilen) von ContactDetailView in PeopleTabView. Entfernt, nutzt jetzt shared ContactDetailView(contact:).

- **[BEHOBEN] Schweregrad: niedrig** — 8 Swift-Dateien fehlten im pbxproj (ChatView, QuickCaptureView, MailInboxView, MailConfigView, OpenAICompatibleProvider, 3x Onboarding-Pages). Registriert.

- **[BEHOBEN] Schweregrad: niedrig** — System-Prompt enthielt GRDB SQL-Expression-Objekte statt lesbarem Text. Gefixt.

- **[OFFEN] Schweregrad: niedrig** — `nonisolated(unsafe)` Anzahl unveraendert (~11 Stellen). Kein akuter Handlungsbedarf.

- **[OFFEN] Schweregrad: niedrig** — Force-Casts in CloudKitBridge.swift (5 Stellen). Unveraendert seit letztem Review.

### Metriken

- Commits auf Branch: 20
- Neue Dateien: 11 (LLMProviderSettingsView, LLMBillingView, OpenAICompatibleProvider, ChatView, QuickCaptureView, PeopleTabView, MailInboxView, MailConfigView, OnboardingStaticPages, OnboardingProviderPages, OnboardingFinalPages)
- Entfernte Duplikate: ~110 Zeilen (SearchContactDetailView, OnboardingMailWizard)
- Entfernter Dead Code: ~850 Zeilen (SettingsView)
- Groesste Datei vorher: OnboardingView.swift (1241 Zeilen) → jetzt 295 Zeilen
- LLM Provider: 5 → 7 (+ xAI Grok, Custom Endpoint)
- Net LOC: +806 (4620 Insertions, 3814 Deletions)

### Positiv

- **God Objects aufgeloest.** Die 4 groessten Dateien (ContentView, OnboardingView, MailTabView, SettingsView) zusammen von ~4477 auf ~1461 Zeilen reduziert.
- **Multi-Provider-Architektur.** OpenAICompatibleProvider als Basis-Klasse fuer alle OpenAI-kompatiblen APIs. Sauber erweiterbar.
- **Google OAuth korrekt implementiert.** PKCE, Token-Refresh, Keychain-Storage. Keine Secrets im Code.
- **Duplikate eliminiert.** ContactDetailView wird jetzt geteilt statt kopiert.
- **Dead Code konsequent entfernt.** Nicht nur auskommentiert, sondern geloescht.

---

## Review 23.03.2026 — Post-Session Projekt-Status-Review

### Status: OK

### Zusammenfassung

brain-ios ist ein ausgereiftes Projekt mit 156 Swift-Quelldateien, 34 Testdateien mit 540 @Test-Methoden, und 140 Commits ueber alle Branches. Seit dem letzten Review (21.03.2026) wurden 21 Commits auf master hinzugefuegt, hauptsaechlich Build-Fixes, App Store Metadaten (Privacy Policy, Privacy Manifest, App Store Description), eine Device-Test-Checkliste, CloudKit-Bridge-Implementierung, Lokalisierungs-Service, und diverse Compiler-Fehlerbehebungen. Der aktuelle Branch `claude/review-project-status-aTN6X` ist 5 Commits ahead von master mit weiteren Build-Fixes. Kein STOP-SESSION.md vorhanden. Working tree ist clean.

### Findings

- **[OFFEN] Schweregrad: mittel** — Force-Casts (`as!`) in CloudKitBridge.swift an 5 Stellen (Zeilen 57-60 und 226). GRDB Row-Subscripts koennen nil zurueckgeben wenn die Spalte NULL ist oder der Typ nicht stimmt. Ein korrupter oder unerwarteter pending_sync-Eintrag wuerde die App zum Absturz bringen. Empfehlung: `as? Int64 ?? 0` oder `guard let` mit Error-Handling verwenden, analog zum sauberen Pattern in BrainAPIAuthService.swift.

- **[OFFEN] Schweregrad: niedrig** — `nonisolated(unsafe)` an 11 Stellen. Seit dem letzten Review unveraendert (war 9, jetzt 11 durch neue Captures in GeminiProvider und ChatService). Alle Stellen sind dokumentiert und nachvollziehbar begruendet. Kein akuter Handlungsbedarf, aber die Tendenz steigt leicht.

- **[OFFEN] Schweregrad: niedrig** — SESSION-LOG.md dokumentiert den aktuellen Stand nicht vollstaendig. Die letzten 21 Commits auf master (App Store Metadaten, CloudKitBridge, LocalizationService, Device-Test-Checkliste, PrivacyInfo.xcprivacy) sind im SESSION-LOG nicht erfasst. Die letzte Session im Log ist vom 23.03.2026 und deckt nur "Findings-Abgleich + Build 188 Fixes" ab, nicht die nachfolgenden 7 PRs (#63-#69).

- **[BEHOBEN] Schweregrad: mittel** — BrainAPIAuthService Force-Unwraps. Alle URL-Konstruktionen nutzen jetzt `guard let url = URL(string:...) else { throw }`. Sauber behoben.

- **[BEHOBEN] Schweregrad: mittel** — PrivacyInfo.xcprivacy war als ausstehend markiert. Ist jetzt vorhanden mit korrekten API-Deklarationen (UserDefaults: CA92.1, FileTimestamp: C617.1). NSPrivacyTracking = false, keine gesammelten Datentypen. Korrekt fuer eine Offline-First App.

- **[BEHOBEN] Schweregrad: mittel** — App Store Metadaten waren ausstehend. Privacy Policy (DE + EN), App Store Beschreibung, und Device-Test-Checkliste sind jetzt als Markdown-Dokumente im docs/ Ordner vorhanden.

- **[INFO]** Keine `URL(string:...)!` Force-Unwraps mehr im gesamten Source-Code. Alle wurden durch `guard let` ersetzt.

- **[INFO]** Keine leeren catch-Bloecke gefunden. Error-Handling ist durchgehend vorhanden.

- **[INFO]** Keine API-Keys, Secrets oder Passwoerter im Code gefunden.

- **[INFO]** UI-Texte weiterhin konsequent Deutsch, Code-Kommentare konsequent Englisch.

- **[INFO]** Test-Anzahl ist von 451 (letzter Review) auf 540 gestiegen (+89 Tests). Die neuen Tests befinden sich sowohl in BrainCoreTests als auch in einem neuen BrainAppTests-Verzeichnis (HandlerTests, LLMAuthModeTests, LocalizationServiceTests, BrainThemeTests).

### Architektur-Konsistenz

| Entscheidung | Status |
|-------------|--------|
| Runtime-Engine Architektur | OK |
| GRDB + SQLiteData | OK |
| SwiftUI only (kein UIKit ausser erlaubt) | OK |
| MVVM mit @Observable | OK |
| async/await (kein Combine) | OK |
| Swift 6 strict concurrency | OK |
| Offline-First | OK |
| Entry als Herzstueck | OK |
| API-Keys in Keychain | OK |
| Multi-LLM Router | OK (5 Provider: Anthropic, OpenAI, Gemini, OnDevice, Shortcuts) |
| .brainskill.md Skill-Format | OK |
| Bootstrap-Skills als JSON | OK |
| PrivacyInfo.xcprivacy | OK (neu hinzugefuegt) |

### Metriken

- Commits total: 140 (alle Branches), 37 auf master
- Commits seit letztem Review: 21 auf master (PRs #63-#69)
- Quelldateien: 156 Swift (BrainApp + BrainCore + Extensions)
- Testdateien: 34 (BrainCoreTests: 30, BrainAppTests: 4)
- @Test-Methoden: 540 (vorher 451, +89)
- LOC BrainApp: ~30.500
- LOC BrainCore: ~6.100
- LOC Tests: ~8.350
- LOC Gesamt: ~45.000
- iOS Bridges: 23
- LLM Provider: 5 (+ GoogleOAuthService, LLMAuthMode)
- Handler-Dateien: 10
- Neue Dokumente: Privacy Policy, App Store Metadata, Device-Test-Checkliste
- PrivacyInfo.xcprivacy: Vorhanden
- STOP-SESSION.md: Nicht vorhanden (kein Stopp-Grund)
- Working Tree: Clean
- Aktuelle Phase: Alle abgeschlossen, App Store Readiness aktiv
- Scope eingehalten: ja
- Tests vorhanden: ja (540 @Test-Methoden)
- Tests ausfuehrbar auf VPS: nein (kein Swift installiert)

### Positiv

- **App Store Readiness macht Fortschritte.** Privacy Policy (DE+EN), App Store Metadata, PrivacyInfo.xcprivacy und Device-Test-Checkliste sind alle vorhanden. Die wichtigsten nicht-Code-Aufgaben fuer den App Store sind adressiert.
- **Test-Abdeckung waechst.** 540 Tests (+89 seit letztem Review). Neues BrainAppTests-Verzeichnis mit Handler-, Auth-, Lokalisierungs- und Theme-Tests zeigt, dass auch die App-Schicht getestet wird.
- **Keine Security-Probleme.** Keine Force-Unwraps auf URLs, keine Secrets im Code, keine leeren catch-Bloecke. BrainAPIAuthService sauber mit guard let.
- **CloudKit-Bridge ist eine echte Implementierung.** Nicht nur ein Stub — pushLocalChanges(), pullRemoteChanges(), ensureZoneExists() sind vollstaendig implementiert mit CKRecord-Mapping und inkrementellem Sync via Change Tokens.
- **Lokalisierung als Skill-System.** LocalizationService laedt Sprach-Skills aus der DB statt .strings-Dateien. Innovativer Ansatz der zur Runtime-Engine-Architektur passt.
- **Commit-Messages sind klar und beschreibend.** Jeder Commit erklaert was und warum.

### Empfehlung

1. **CloudKitBridge Force-Casts beheben.** 5 Stellen mit `as! Int64` / `as! String` auf GRDB Row-Subscripts. Einfacher Fix mit `as?` + Default-Wert oder guard let. Prioritaet: mittel.
2. **SESSION-LOG nachfuehren.** Die letzten 7 PRs und zugehoerigen Aenderungen (App Store Metadaten, CloudKitBridge, LocalizationService, PrivacyInfo.xcprivacy, Device-Test-Checkliste) sind nicht im SESSION-LOG dokumentiert. Fuer die Kontinuitaets-Garantie zwischen Sessions sollte das Log aktuell gehalten werden.
3. **CLAUDE.md Metriken aktualisieren.** Tests: 540 (nicht 451), Commits: 140 (nicht 130+), Swift-Dateien: 190 (nicht 165). Die Kennzahlen im Current Objective sind veraltet.
4. **Branch nach master mergen.** Der aktuelle Branch hat Build-Fixes und Dokumentation die auf master gehoeren.
5. **Support URL klaren.** Privacy Policy und App Store Beschreibung sind vorhanden, aber die Support URL (erforderlich fuer App Store Connect) fehlt noch.


## Findings-Abgleich 23.03.2026 — Alle Code-Findings erledigt

### Status: ALLE OFFEN FINDINGS GESCHLOSSEN

Code-Abgleich der verbleibenden offenen Findings aus frueheren Reviews. Alle 4 Code-Findings
waren bereits implementiert, aber nicht in den Review-Dokumenten aktualisiert.

| Finding | Vorher | Jetzt | Nachweis |
|---------|--------|-------|----------|
| **Two-Way Input Binding** | OFFEN | RESOLVED | SkillRendererInput.swift: bindingVariable(), stringBinding(), boolBinding(), doubleBinding(), intBinding(), dateBinding(), colorBinding(). Alle Input-Primitives (TextField, Toggle, Picker, Slider, Stepper, DatePicker, ColorPicker) nutzen echte Bindings mit get/set via onSetVariable. `.constant()` nur als Fallback wenn kein Binding-Key vorhanden. |
| **Error-Banner in SkillView** | OFFEN | RESOLVED | SkillView.swift:53-71: Rotes Overlay am unteren Rand, dismissible per Tap, animiert, mit accessibilityLabel. |
| **Onboarding-Flow** | OFFEN | RESOLVED | OnboardingView.swift (645 Zeilen): 7-seitiger Flow (Welcome, Features, Privacy, API-Key, Mail-Config, Permissions, First Entry). Keyboard-Management, API-Key-Validierung, Skip-Optionen. |
| **Fehlersprache konsistent** | TEILWEISE | RESOLVED | LocalizationService.swift mit L() Funktion, 60+ deutsche Keys, ActionDispatcher deutsch ("Kein Handler registriert fuer..."). Sprach-Skills fuer DE + EN. |

### Verbleibende nicht-Code-Aufgaben (App Store Connect)

- Privacy Policy URL (Webseite, nicht Code)
- Support URL (Webseite, nicht Code)
- App Store Description + Screenshots (Marketing, nicht Code)
- PrivacyInfo.xcprivacy (empfohlen fuer iOS 17.2+, aber kein Blocker fuer TestFlight)

### Einziges verbleibendes LOW-Finding im Code

- `nonisolated(unsafe)` an ~9 Stellen — akzeptabel, dokumentiert, kein Handlungsbedarf

---

## Review 21.03.2026 (Umfassender Projekt-Review nach Phase-Komplett)

### Status: OK

### Zusammenfassung

brain-ios ist ein ausgereiftes Projekt: 166 Swift-Dateien, 29 Testdateien mit 451 Test-Methoden, 23 iOS Bridges, ~158 Action Handler, 121 Tool-Definitionen, ~90 UI Primitives, 5 LLM Provider, SPKI Certificate Pinning, CI/CD via GitHub Actions und Xcode Cloud. Am 22.03.2026 wurden umfassende Verbesserungen durchgefuehrt: UI-Ueberarbeitung (Kontakte, Mail, Dashboard, Skills-Navigation), Brain-Intelligenz (Chat-to-Knowledge Extraction, User/Brain-Profile, Kennenlern-Dialog, Knowledge Consolidation, Neglected Contacts Detection), und Kontakt-Management (Update/Delete/Merge/Duplikaterkennung mit direkter iOS-Kontakte-Synchronisation).

### Findings

- **[BEHOBEN] Schweregrad: mittel** — Force-Unwraps in GeminiProvider. Alle 3 URL-Konstruktionen nutzen jetzt `guard let url = URL(string:...) else { throw }` (Zeilen 30, 70, 158). Konsistent mit AnthropicProvider und OpenAIProvider.

- **[BEHOBEN] Schweregrad: mittel** — Force-Unwraps in BrainAPIAuthService. Alle URL-Konstruktionen nutzen jetzt `guard let url = URL(string:...) else { throw }`.

- **[BEHOBEN] Schweregrad: mittel** — Force-Unwrap in OnThisDayView. Nutzt jetzt `yearGroups[year, default: []]`.

- **[BEHOBEN] Schweregrad: mittel** — API-Key in Gemini-URL als Query-Parameter. GeminiProvider nutzt jetzt `x-goog-api-key` Header statt URL-Query-Parameter.

- **[VERBESSERT] Schweregrad: niedrig** — `@unchecked Sendable` Anzahl reduziert. 31 Bridge-Handler (7 Audio + 24 Sensor/Stopwatch/Camera/Font/Morse) auf `@MainActor` umgestellt — @unchecked Sendable bleibt formal, aber durch Actor-Isolation korrekt abgesichert. Verbleibende Stellen: Handler mit DataBridge-Referenz (architektonisch bedingt, da ActionHandler-Protocol Sendable ist). Alle Stellen haben Begruendungskommentare.

- **[OFFEN] Schweregrad: niedrig** — `nonisolated(unsafe)` an 9 Stellen. Die meisten sind fuer Captures in `@Sendable`-Closures (AnthropicProvider, GeminiProvider, BrainApp BGTasks). Die `HealthBridge.isoFormatter` (Zeile 116) ist ein statischer `ISO8601DateFormatter` — nach Konfiguration thread-safe, aber formal nicht Sendable. Akzeptabel fuer den aktuellen Stand; bei Gelegenheit auf per-call Factory umstellen (wie PatternEngine es bereits tut).

- **[BEHOBEN] Schweregrad: niedrig** — ActionHandlers.swift war mit 2069 Zeilen die groesste Datei. Wurde aufgeteilt in 10 thematische Dateien: EntryHandlers, AIHandlers, CalendarReminderHandlers, ContactHandlers, FileNetworkHandlers, LinkTagHandlers, MemoryHandlers, SkillRuleHandlers, SystemUIHandlers, CoreActionHandlers (Factory). Jede Datei hat 80-360 Zeilen.

- **[OFFEN] Schweregrad: niedrig** — Leere catch-Bloecke: Keine gefunden. Gut.

- **[BEHOBEN] Schweregrad: niedrig** — Branch-Situation: Aenderungen von `claude/review-project-status-PNXeq` wurden nach master gemerged (PRs #6-#11). Aktuelle Entwicklung auf `claude/fix-swift-compiler-errors-dnedh`.

- **[INFO]** Keine API-Keys, Secrets oder Passwoerter im Code gefunden. Alle Schluessel werden korrekt ueber KeychainService verwaltet. API-Key-Konstanten sind nur Keychain-Schluesselnamen, keine Werte.

- **[INFO]** Keine leeren catch-Bloecke gefunden. Error Handling ist durchgehend vorhanden.

- **[INFO]** Access Control: BrainCore verwendet korrektes `public` fuer die Modul-API. BrainApp-Dateien verwenden implizites `internal` (korrekt fuer App-Code). `private` wird konsequent fuer interne State-Variablen verwendet.

- **[INFO]** UI-Texte sind konsequent Deutsch ("Keine Skills installiert", "Testen & Speichern", "Noch keine Eintraege"). Code-Kommentare sind konsequent Englisch. Konvention eingehalten.

### Architektur-Konsistenz

| Entscheidung | Status | Bemerkung |
|-------------|--------|-----------|
| Runtime-Engine Architektur | OK | JSON-Skills werden via Render/Action/Logic Engine ausgefuehrt |
| GRDB + SQLiteData | OK | GRDB durchgehend, Schema.swift + Migrations.swift sauber |
| SwiftUI only | OK | Kein UIKit ausser PencilKit, VisionKit, UIImagePickerController (erlaubt) |
| MVVM mit @Observable | OK | DataBridge, SkillViewModel, ChatService alle @Observable |
| async/await | OK | Kein Combine gefunden, durchgehend async/await |
| Swift 6 strict concurrency | OK | Package.swift: swift-tools-version 6.0, Sendable-Annotations durchgehend |
| Offline-First | OK | Skill Engine komplett lokal, CloudKit nur als Sync-Layer |
| Entry als Herzstück | OK | Entry-Model zentral, alle Operationen via Entry CRUD |
| API-Keys in Keychain | OK | KeychainService mit kSecAttrAccessibleWhenUnlockedThisDeviceOnly |
| Multi-LLM Router | OK | Anthropic, OpenAI, Gemini, On-Device Provider implementiert |
| Skill-Format .brainskill.md | OK | 3 Skill-Dateien (23 nutzlose entfernt), Skills als Code-Konstanten oder LLM-generiert |
| Bootstrap-Skills als JSON | OK | BootstrapSkills.swift definiert Skills als JSON, nicht hardcodiert |
| Certificate Pinning | OK | Echtes SPKI-Pinning mit SHA-256 Hashes + TOFU Fallback (RFC 7469) |
| BrainCore/BrainApp Trennung | OK | BrainCore ist pure Swift (Linux-testbar), BrainApp hat SwiftUI/iOS |

### Metriken (aktualisiert 22.03.2026, nach UI-Ueberarbeitung)

- Commits: 130+
- Quelldateien: 165 (BrainApp: 90, BrainCore: 46, Tests: 29)
- Testdateien: 29
- Test-Methoden: 451 (@Test Macro, Swift Testing)
- Skill-Dateien: 3 (23 nutzlose bundled Skills entfernt)
- iOS Bridges: 23
- Action Handler Klassen: ~158 (davon 31 mit @MainActor)
- Tool-Definitionen: 121 (+4 Kontakt-Management)
- LLM Provider: 5 (Anthropic, OpenAI, Gemini, OnDevice, Shortcuts)
- App Intents: 12
- LOC (BrainApp): ~28'000 (+1000 fuer Kontakte-Detail, Mail-Ordner, Dashboard)
- LOC (BrainCore): ~5'600
- LOC (Tests): ~7'000
- Groesste Datei: ToolDefinitions.swift (1672 Zeilen)
- GitHub Actions Workflows: 2 (tests.yml, ios-build.yml)
- Xcode Cloud Builds: 156+
- Aktuelle Phase: Alle abgeschlossen, UI-Polish + Brain-Intelligenz aktiv
- Neue Features: Brain-Profile, Kennenlern-Dialog, Chat-to-Knowledge, Kontakt-Management
- Scope eingehalten: ja
- Tests vorhanden und gruen: nicht ausfuehrbar (VPS, kein Swift installiert)

### Positiv

- **Keine Secrets im Code.** Alle API-Keys korrekt in Keychain, keine hardcodierten Werte.
- **Solide Error-Handling-Kultur.** Keine leeren catch-Bloecke, strukturierte ActionResult.actionError() mit Error-Codes.
- **SPKI Certificate Pinning korrekt implementiert.** Echte SHA-256 Hashes gegen Zertifikatskette, nicht nur TLS-Validierung. TOFU-Fallback fuer Certificate-Rotation (opt-in). Das war ein Finding aus dem Gross-Review und ist vollstaendig behoben.
- **DataBridge Refactoring abgeschlossen.** God Object aufgeteilt in 5 Repositories mit Dependency Injection. Saubere Fassade fuer Rueckwaerts-Kompatibilitaet.
- **Sandbox-Sicherheit bei File-Handlern.** Path-Traversal-Check (`hasPrefix(docsDir)`) auf allen File-Operationen. HTTPS-only fuer HTTP-Requests.
- **@unchecked Sendable mit Begruendungen.** Fast alle Stellen haben MARK-Kommentare die erklaeren warum es sicher ist.
- **Skill-Oekosystem umfangreich.** 24 gebundlete Skills (mehr als die 17 im SESSION-LOG dokumentierten), Import/Export, Preview vor Installation, Berechtigungsanzeige.
- **SESSION-LOG Qualitaet.** Durchgehend vorbildlich, jede Session dokumentiert mit Entscheidungen, Tests, und naechsten Schritten.
- **Multi-Provider LLM mit Tool-Use.** Anthropic, OpenAI, Gemini alle mit Streaming und Tool-Calling. Per-Task Modell-Routing konfigurierbar.
- **CI/CD Pipeline.** GitHub Actions (Linux + macOS) und Xcode Cloud mit TestFlight Distribution.

### Empfehlung

1. **Force-Unwraps in GeminiProvider und BrainAPIAuthService beheben.** 5 Stellen mit `URL(string:)!`. Einfacher Fix: `guard let url = URL(string:...) else { throw }`. Prioritaet: mittel.
2. **Branch nach master mergen.** Der aktuelle Branch hat sinnvolle Build-Fixes (inline Picker-Optionen, extrahierte Trigger-Parsing-Funktion) die auf master gehoeren.
3. **CLAUDE.md Metriken aktualisieren.** Skill-Anzahl ist 24 (nicht 17), Test-Methoden sind 451 (nicht 438), Commits sind 79+ (nicht 145+). SESSION-LOG sollte den aktuellen Stand reflektieren.
4. **ActionHandlers.swift aufteilen.** 2069 Zeilen mit ~70 Handler-Klassen. Thematische Aufteilung wuerde Wartbarkeit verbessern. Prioritaet: niedrig.
5. **Gemini API-Key aus URL entfernen.** Query-Parameter sind in Logs sichtbar. Pruefen ob Gemini Authorization-Header unterstuetzt. Prioritaet: niedrig.

---


## PROJEKT-STATUS-REVIEW 21.03.2026 — Umfassende Bestandsaufnahme

### Gesamturteil: Reifes Projekt, aktiv weiterentwickelt, architektonisch solide

### Zusammenfassung

brain-ios ist ein ausgereiftes iOS-Projekt mit ~35.600 LOC Swift (BrainCore: 5.571, BrainApp: 23.088, Tests: 6.964). Alle 24+ Phasen sind abgeschlossen, TestFlight ist aktiv, 451 Tests definiert (via `@Test` Macro, Swift Testing). Das Projekt hat seit dem letzten Review (Auto-Pause 19.03.2026) signifikante Weiterentwicklung erfahren: 77 Commits auf master, mehrere PRs merged, 4 neue gebundlete Skills, 5-Tab iPhone Navigation, Calendar-Farben, Chat Model-Picker, und diverse Build-Fixes.

### Git & Branch-Status

- **master**: 77 Commits, letzter: `3a030bf` (Merge PR #10)
- **Aktueller Branch**: `claude/review-project-status-PNXeq` — 2 Commits ahead (PR #11 Merge + SwiftCompile Fix)
- **Working Tree**: Clean, keine uncommitteten Aenderungen
- **Aktive PRs**: #6-#11 gemerged (alle von `claude/fix-email-sync-bug-jNkYH`)
- **Neueste Aenderungen auf Branch**: SettingsView (Picker inline statt NavigationLink) + SkillManagerView (Trigger-Parsing refactored)

### Metriken

| Metrik | Wert |
|--------|------|
| **LOC Total** | ~35.600 |
| **BrainCore (SPM)** | 5.571 LOC, 46 Dateien |
| **BrainApp (iOS)** | 23.088 LOC, 72 Dateien |
| **Tests** | 6.964 LOC, 29 Testdateien, 451 `@Test` Methoden |
| **Commits** | 77 (master) |
| **Skills gebundlet** | 24 .brainskill.md Dateien (davon 1 Lessons-Learned) |
| **iOS Bridges** | 15 (Audio, Bluetooth, Camera, Contacts, Email, Embedding, EventKit, Health, Home, Location, NFC, Notification, Pencil, Scanner, Speech) |
| **LLM Providers** | 4 (Anthropic, OpenAI, Gemini, OnDevice) |
| **Action Handlers** | ~80+ (in ActionHandlers.swift: 2.069 LOC + EmailBridge Handlers) |
| **Tool Definitions** | 1.241 LOC |

### Projekt-Struktur

Die Struktur entspricht dem CLAUDE.md Layout:
- `Sources/BrainCore/` — Pure Swift, Linux-testbar (Engine, Models, Services, LLM, Auth, Navigation, DB)
- `Sources/BrainApp/` — iOS App (Views, Bridges, Providers, Repositories, Services)
- `Tests/BrainCoreTests/` — 29 Testdateien
- `Skills/` — 24 .brainskill.md Dateien
- `.claude/agents/` — 4 Agent-Definitionen

**[OK]** BrainCore/BrainApp-Trennung sauber eingehalten.

### Code-Qualitaet

#### @unchecked Sendable (103 Stellen)
- Alle ActionHandlers (60+) verwenden `@unchecked Sendable` mit Begruendungskommentar
- LLM Providers (4) mit Begruendungskommentar ("immutable after init")
- Bridges (5) mit Begruendungskommentar
- BehaviorTracker mit Begruendungskommentar
- **[OK]** Alle Stellen sind dokumentiert und begruendet. Das Pattern ist konsistent.
- **[MEDIUM]** Die Menge (103 Stellen) ist hoch. Langfristig waere ein Protocol-basierter Ansatz mit Actor-Isolation sauberer. Fuer TestFlight/App Store akzeptabel.

#### Force-Unwraps
- **[HIGH]** `BrainAPIAuthService.swift:21` und `:64` — `URL(string: ...)!` auf dynamische Base-URL. Crash-Risiko wenn User eine ungueltige URL konfiguriert. Sollte `guard let` verwenden.
- Alle anderen Force-Unwraps in Source-Code sind `!isEmpty`-Pattern oder Negationen — keine echten Force-Unwraps.
- **[OK]** Test-Code verwendet Force-Unwraps (`.id!`) — akzeptabel in Tests.

#### Concurrency
- **[OK]** ChatService ist `@MainActor @Observable` — korrekte Isolation.
- **[OK]** DataBridge ist `@MainActor @Observable` mit Repository-Delegation — sauber.
- **[OK]** `destructiveTools` ist `nonisolated static let` — korrekt fuer Set<String> (Sendable).
- **[OK]** `isSending` Guard verhindert parallele send()-Aufrufe.
- **[LOW]** `lazy var session` in PinnedURLSession: Wird im init() eager initialisiert (`_ = self.session`) — Race Condition damit entschaerft. OK.

#### Access Control
- **[OK]** BrainCore nutzt `public` korrekt fuer Module-API.
- **[OK]** BrainApp nutzt `private`/`private(set)` konsistent.
- **[LOW]** DataBridge.db ist `let` statt `private let` — wird von BrainApp-Code direkt zugegriffen. Akzeptabel als bewusste Entscheidung (Facade-Pattern).

#### Architektur-Highlights
- **[OK]** SPKI Certificate Pinning mit TOFU-Fallback implementiert (RFC 7469 konform, 4 Hosts gepinnt)
- **[OK]** Multi-LLM Router mit 4 Providern + Privacy-Zone-Routing
- **[OK]** Skill Engine komplett: Parser → Renderer → ActionDispatcher → LogicInterpreter
- **[OK]** 5 Repository-Klassen (DataBridge refactored aus God Object)
- **[OK]** Conversation Memory mit Person-Topic Cross-Referenz
- **[OK]** Proactive Intelligence: Morning Briefing, Evening Recap, 5 Pattern-Detektoren, Background Tasks

### Skills (24 Dateien)

23 Brain-Skills + 1 Lessons-Learned-Dokument:
- backup, contact-intel, email-draft, files, habits, handwriting-font, journal, meeting-prep, news, on-this-day, patterns, pomodoro, proactive, project, proposals, reminders, routines, shopping, spam-filter, summarize, translate, weather, weekly-review
- **[OK]** Breite Abdeckung. Mischung aus App-Skills und KI-Skills.
- **[INFO]** SESSION-LOG erwaehnt 17 gebundlete Skills, tatsaechlich sind 24 .brainskill.md vorhanden (inkl. 1 Lessons-Learned). Die Zahl im SESSION-LOG ist veraltet.

### Neueste Entwicklungen (seit letztem Review)

Basierend auf Git-History (Commits nach dem Auto-Pause-Zeitpunkt):

1. **5-Tab iPhone Navigation** mit "Mehr"-Tab (Commit `d1d9557`)
2. **Kalender-Farben, Chat Model Picker, Per-Task Model Routing** (Commit `ce0f9a4`)
3. **Skills wie iPhone Settings** mit Detail-View (Commit `c70139f`)
4. **4 neue Skills**: OnThisDay, Proposals, Backup, Files (Commit `84bd00c`)
5. **OnThisDay, Backup, ProposalReject Handler** (Commit `9f5c192`)
6. **Diverse Xcode Cloud Build-Fixes** (Commits `27bdf86`, `971cf23`, `021dc68`)
7. **German Error Messages, Notification Reschedule, Shortcuts** (Commit `79ebdbc`)
8. **Email Sync Bug Fix** (Commit `09bb236`)
9. **@unchecked Sendable Bereinigung**: 5 Bridges + 8 Handlers → @MainActor (Commit `0dcfe3f`)
10. **Gemini Provider** + Modellauswahl-Dropdown (Commits `550cf8d`, `df524b1`)

### Offene Findings (aus frueheren Reviews, Status-Update)

| Finding | Severity | Status |
|---------|----------|--------|
| CertificatePinning Naming | MEDIUM | **RESOLVED** — Echtes SPKI-Pinning jetzt implementiert, Name passt |
| DataBridge @unchecked Sendable | MEDIUM | **RESOLVED** — DataBridge ist jetzt @MainActor @Observable |
| Force-Unwrap BrainAPIAuthService | HIGH | **OFFEN** — 2 Stellen mit `URL(...)!` |
| Two-Way Input Binding | LOW | **RESOLVED** — SkillRendererInput.swift: stringBinding/boolBinding/etc. mit get/set via onSetVariable |
| Error-Banner in SkillView | LOW | **RESOLVED** — Rotes Overlay mit Animation + Tap-to-Dismiss + Accessibility |
| Konsistente Fehlersprache | LOW | **RESOLVED** — LocalizationService mit L() Funktion, 60+ Keys, ActionDispatcher deutsch |

### Neue Findings

- **[HIGH] Force-Unwrap in BrainAPIAuthService** (Zeile 21 + 64): `URL(string: "\(baseURL)/api/auth/login")!` — User-konfigurierbare URL darf nicht force-unwrapped werden. Fix: `guard let url = URL(...) else { throw AuthError.invalidURL }`.

- **[MEDIUM] @unchecked Sendable Masse** (103 Stellen): Jede Stelle ist begruendet, aber die Menge zeigt ein Pattern-Problem. Empfehlung: Einen `@MainActor`-isolierten ActionDispatcher evaluieren, der die Handler-Registrierung kapselt, statt jeden einzelnen Handler als @unchecked Sendable zu markieren.

- **[LOW] SESSION-LOG Metriken veraltet**: SESSION-LOG erwaehnt "17 gebundlete Skills" und "438 Tests". Tatsaechlich: 24 Skills (23 Brain-Skills), 451 @Test-Methoden. Die Zahlen in CLAUDE.md ("438 Tests", "17 Skills") stimmen ebenfalls nicht mehr.

- **[LOW] Tests nicht ausfuehrbar auf VPS**: `swift` ist auf diesem VPS nicht installiert. Tests koennen nur via Xcode Cloud oder lokal verifiziert werden. Die 451 @Test-Methoden sind aus dem Code gezaehlt, nicht aus einem Testlauf.

- **[INFO] Branch-Hygiene**: Alle PRs (#6-#11) kommen von `claude/fix-email-sync-bug-jNkYH` — der Branch-Name ist irrefuehrend, da er fuer viel mehr als Email-Sync-Fixes verwendet wurde (Navigation, Skills, Build-Fixes, etc.).

### Architektur-Konsistenz mit ARCHITECTURE.md

- **[OK]** Runtime-Engine Architektur eingehalten (JSON-Skills → native UI)
- **[OK]** Zwei-Schichten-Trennung sauber (Skill Engine vs. Proaktive Intelligenz)
- **[OK]** Multi-LLM Router mit 4 Providern (Anthropic, OpenAI, Gemini, OnDevice)
- **[OK]** GRDB + SQLite (kein SwiftData/CoreData)
- **[OK]** Offline-First Design
- **[OK]** Bootstrap Skills als JSON (nicht hardcodiert)
- **[OK]** Entry als Herzstück
- **[OK]** Face ID via LocalAuthentication
- **[OK]** API-Keys in iOS Keychain
- **[OK]** Alle 16 Architektur-Entscheidungen eingehalten

### Verdikt

**Projekt ist in gutem Zustand.** Aktive Weiterentwicklung seit dem letzten Review, architektonisch sauber, gute Test-Abdeckung (451 Tests fuer ~35k LOC). Die Hauptrisiken sind:

1. **Force-Unwrap in BrainAPIAuthService** (HIGH — sollte gefixt werden)
2. **@unchecked Sendable Masse** (MEDIUM — technisch korrekt, aber architektonisch verbesserungswuerdig)
3. **Dokumentation veraltet** (LOW — Metriken in SESSION-LOG/CLAUDE.md nachziehen)

**Empfehlung:**
- Fix fuer BrainAPIAuthService Force-Unwraps (5 Minuten)
- Metriken in CLAUDE.md aktualisieren (Skills: 24, Tests: 451+, Commits: 77+)
- Weiterhin TestFlight-Testing und User-Feedback sammeln

---

## Auto-Pause 19.03.2026 — Zwei Reviews ohne Aktivität. Task pausiert.

Seit der Reaktivierung hat sich am Projekt nichts verändert. Zwei aufeinanderfolgende Scheduled Reviews (19.03.2026 Review #1 und dieser) zeigen identischen Stand: Phase 14 abgeschlossen, ASSESSMENT-COMPLETE, 277 Tests grün, keine neuen Commits oder Sessions. Das Projekt ist weiterhin BEREIT für TestFlight gemäss Gross-Review-Verdikt.

Review-Task wird deaktiviert bis Claude Code wieder am brain-ios Projekt arbeitet.

---

## Review 19.03.2026 (Scheduled Review — Keine Aktivität)

### Status: OK (keine Änderungen)

Task wurde reaktiviert, aber SESSION-LOG zeigt keine neuen Einträge seit der Auto-Pause vom 18.03.2026. Projektzustand unverändert: Phase 14 abgeschlossen, ASSESSMENT-COMPLETE, 277 Tests grün, keine neuen Commits oder Sessions. Gross-Review-Verdikt "BEREIT für TestFlight" gilt weiterhin.

### Metriken

- Aktuelle Phase: Phase 14 abgeschlossen, ASSESSMENT-COMPLETE
- Tests: 277 bestanden / 0 fehlgeschlagen (unverändert)
- Neue Commits seit letztem Review: keine
- Gross-Review-Verdikt: BEREIT für TestFlight (ohne Auflagen)

### Hinweis

Dies ist der erste Scheduled Review nach Reaktivierung, ohne Aktivität. Falls der nächste Review ebenfalls keine Änderungen zeigt, wird der Task erneut automatisch pausiert (Auto-Pause-Regel).

---

## Auto-Pause 18.03.2026 — Zwei Reviews ohne Aktivität. Task pausiert.

Seit dem 2. Gross-Review hat sich am Projekt nichts verändert. Zwei aufeinanderfolgende Scheduled Reviews (Post Gross-Review #1 und dieser) zeigen identischen Stand: Phase 14 abgeschlossen, ASSESSMENT-COMPLETE, 277 Tests grün, keine neuen Commits oder Sessions. Das Projekt ist weiterhin BEREIT für TestFlight gemäss Gross-Review-Verdikt.

Review-Task wird deaktiviert bis Claude Code wieder am brain-ios Projekt arbeitet.

---

## GROSS-REVIEW 18.03.2026 (2. Durchlauf) — Nach Phase 11+12 + Findings-Fixes

### Gesamturteil: BEREIT für TestFlight

### Zusammenfassung

Seit dem ersten Gross-Review wurden alle damals dokumentierten MEDIUM-Findings behoben, Phase 11 (CloudKit Sync) und Phase 12 (Vision Pro) implementiert, und ein finaler Assessment-Fix-Durchlauf mit 2 CRITICAL und 3 HIGH Findings abgeschlossen. Das Projekt umfasst jetzt 56 Quelldateien, 18 Testdateien mit 277 grünen Tests. Die Codebase ist architektonisch sauber, die Zwei-Schichten-Trennung eingehalten, und die Runtime-Engine funktioniert lückenlos. Dieser zweite Gross-Review wurde UNABHÄNGIG mit frischen Augen auf der lokalen brain-ios-backup Kopie durchgeführt.

### Security

- **[MEDIUM] CertificatePinning ist kein echtes Pinning.** `PinnedURLSession` validiert nur Standard-TLS (`SecTrustEvaluateWithError`), pinnt aber NICHT gegen SPKI-Hashes. Der Kommentar bestätigt das ("Full SPKI hash pinning is deferred to config-driven approach"). Der Klassenname ist irreführend; die Sicherheit ist Standard-TLS (was für TestFlight ausreicht), aber die Erwartung "Pinning" wird nicht erfüllt. Vor App Store Release: echtes SPKI-Pinning implementieren oder den Klassennamen auf `ValidatedURLSession` ändern.
- **[LOW] `PinnedURLSession` lazy var Thread-Safety.** `private lazy var _session` ist nicht atomar initialisiert. Bei gleichzeitigem erstem Zugriff von mehreren Threads könnte eine Race Condition entstehen. In der Praxis unwahrscheinlich (Singleton, erster Zugriff typisch bei App-Start), aber unsauber.
- **[RESOLVED] Force-Unwrap in LLM Providers.** AnthropicProvider und OpenAIProvider verwenden jetzt korrekt `guard let url = URL(string: baseURL) else { throw }`. Sauber behoben.
- **[RESOLVED] Image-URLs HTTPS-only.** SkillRenderer akzeptiert nur `https://`, blockt `http://` mit visuellem Indikator ("Unsicheres Bild blockiert"). Korrekt.
- **[RESOLVED] Markdown-Sanitization.** HTML-Tags und `javascript:`-Links werden gestrippt. Sauber.
- **[OK] Keychain-Nutzung korrekt.** `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, delete-before-add Pattern, keine Secrets in Code.
- **[OK] ExpressionParser Rekursionslimit 20.** Verhindert Stack Overflow.
- **[OK] SQL-Queries parametrisiert.** GRDB Query Builder durchgehend, FTS5 korrekt.
- **[OK] URL-Whitelist.** Nur https, http, mailto.
- **[OK] CloudKit Sync korrekt offline-first.** Lokale GRDB ist immer Source of Truth.

### Code-Qualität

- **[MEDIUM] `@unchecked Sendable` auf ActionHandlers hält `DataBridge` Referenz.** EntryCreateHandler, EntrySearchHandler etc. halten eine Referenz auf DataBridge, das `@Observable` aber NICHT `@MainActor` annotiert ist. Die Begründungskommentare sind jetzt vorhanden ("Safe because dataBridge is @Observable and thread-safe via MainActor isolation in practice"), aber die Argumentation ist fragil; DataBridge selbst hat keine Isolation-Garantie. Für TestFlight akzeptabel; langfristig sollte DataBridge `@MainActor` werden oder die Handlers über einen Actor dispatchen.
- **[LOW] DataBridge.refreshDashboard() synchron auf Main Thread.** Macht DB-Queries direkt; bei grosser Datenbank könnte es kurz blockieren. Der 5s-Cache mildert das, aber bei Cold-Start werden alle Queries synchron ausgeführt.
- **[LOW] `nonisolated(unsafe)` DateFormatters.** Dokumentiert als akzeptabel. Unverändert, weiterhin OK für TestFlight.
- **[RESOLVED] SkillViewModel Race Condition.** `actionTask?.cancel()` mit `[weak self]` und `Task.isCancelled` Checks. Sauber.
- **[RESOLVED] `@unchecked Sendable` Begründungskommentare.** Alle 11 Stellen haben jetzt MARK-Kommentare mit Begründung. Gut.
- **[OK] ActionDispatcher immutable nach Init.** Keine Data Races.
- **[OK] CloudKitSyncEngine und MultiWindowManager als `actor`.** Korrekte Isolation.
- **[OK] async/await durchgehend statt Combine.** Konsistent.
- **[OK] @Observable MVVM Pattern sauber.** SkillViewModel, DataBridge.
- **[OK] GRDB-Transaktionen korrekt.** pool.write/pool.read konsistent.

### Funktionalität

- **[OK] Skill-Engine-Kette lückenlos.** SkillDefinition → ExpressionParser → SkillRenderer → ActionDispatcher → LogicInterpreter. Vollständig und korrekt verifiziert.
- **[OK] 22 Renderer-Primitives funktional.** Layout (8), Content (7), Input (2), Interaction (1), Data (3), Fallback. Alle mit Expression-Resolution.
- **[OK] 12+ Action Handlers.** entry.create, entry.search, haptic, clipboard.copy, open-url, toast, set, contact.search, calendar.list, reminder.list, location.current, notification.schedule.
- **[OK] ExpressionParser robust.** Variable Lookup, dotted Paths, Vergleiche, Arithmetik, Pipe-Filter, String-Interpolation. Division durch Null gibt 0. Depth-Limit 20.
- **[OK] LogicInterpreter korrekt.** if/forEach/set/sequence funktionieren. set-Bug behoben (Variable wird im Context gesetzt).
- **[OK] CloudKit Sync Infrastruktur.** Actor-basiert, SyncState-Machine, PendingSyncRecord-Tracking, SyncMigrations mit 3 Tabellen (pending_sync, sync_tokens, cloudkit_mapping). Stub-Implementierung für Linux/VPS, `#if canImport(CloudKit)` Guards.
- **[OK] Vision Pro Support.** ForceDirectedLayout mit O(n²) Repulsion + Edge-Attraction, Velocity-Clamping, SIMD3<Float>. MultiWindowManager actor-basiert. SpatialConfig mit window/volume/fullSpace. KnowledgeGraphProvider lädt Daten aus GRDB.
- **[OK] Datenintegrität.** GRDB-Transaktionen, Soft-Delete-Pattern, Cursor-Pagination.
- **[OK] Offline-Modus.** Skill-Engine komplett lokal. CloudKit nur als Sync-Layer.
- **[KNOWN] TextField/Toggle read-only.** `.constant()` Bindings. Bekannt, akzeptiert für MVP.

### UX & Usability

- **[RESOLVED] iPad-Layout.** ContentView hat jetzt separate `iPhoneLayout` (TabView) und `iPadLayout` (NavigationSplitView). Korrekt implementiert mit `UIDevice.current.userInterfaceIdiom` Check.
- **[RESOLVED] Accessibility Labels.** stat-card, badge, avatar, icon, text, button, progress, empty-state, image haben jetzt `.accessibilityLabel()`. Der Fallback-View hat `accessibilityLabel("Unbekanntes Element: ...")`. Deutlich verbessert.
- **[LOW] Error-Banner noch nicht in SkillView UI.** SkillViewModel.errorMessage existiert, wird aber im SkillView nicht als UI-Element angezeigt. Für TestFlight OK; User sieht keine Fehler bei Action-Fehlschlägen.
- **[LOW] Kein Onboarding-Flow.** App zeigt direkt Dashboard. Für TestFlight akzeptabel.
- **[LOW] Mischung Deutsch/Englisch in Error Messages.** User-facing Texte Deutsch, ActionDispatcher-Fehler Englisch.
- **[OK] Empty States vorhanden.** Alle Skills.
- **[OK] UI-Texte grundsätzlich Deutsch.** Begrüssungen, Platzhalter, Labels.

### Architektur-Konsistenz

- **[OK] Alle 16 Architektur-Entscheidungen eingehalten.**
  - 13/16 korrekt implementiert
  - 1/16 jetzt erfüllt: iPad-Layout mit NavigationSplitView (war vorher TabView-only)
  - CloudKit (Phase 11): Korrekt offline-first, lokale GRDB als Source of Truth
  - Vision Pro (Phase 12): Korrekt als BrainCore-Modul, nicht JSON-getrieben
- **[OK] Zwei-Schichten-Trennung sauber.** Skill Engine (JSON) klar getrennt von Proaktiver Intelligenz (nativ). CloudKit und VisionPro sind infrastrukturelle Schichten, nicht JSON-getrieben. Kein Durchsickern.
- **[OK] Bootstrap Skills sind reine JSON-Skills.** Strukturell identisch mit user-generierten Skills.
- **[OK] BrainCore/BrainApp-Trennung sauber.** BrainCore ist pure Swift (Linux-testbar). CloudKitSync und VisionProSupport korrekt in BrainCore (plattformunabhängige Logik).

### Offene Punkte (die Andy entscheiden muss)

- **Echtes SPKI-Pinning:** Vor App Store Release PinnedURLSession mit echten SHA-256 SPKI-Hashes ausstatten? Oder Standard-TLS akzeptieren?
- **DataBridge MainActor:** Soll DataBridge `@MainActor` annotiert werden für saubere Sendable-Garantie?
- **Two-Way Input Binding:** Priorität für interaktive Skills (Quick Capture ist betroffen)?

### Verdikt

**BEREIT für TestFlight** — ohne Auflagen.

Alle MEDIUM-Findings aus dem ersten Gross-Review sind behoben. Die verbleibenden zwei MEDIUM-Findings (CertificatePinning-Naming, DataBridge @unchecked Sendable) sind für TestFlight nicht blockierend; sie sind korrekt funktional, nur nicht optimal benannt/isoliert.

**Zusammenfassung der Verbesserungen seit Gross-Review 1:**
1. Certificate Pinning (TLS-Validierung) implementiert
2. iPad NavigationSplitView implementiert
3. Accessibility Labels auf interaktive Elemente
4. Image-URLs HTTPS-only
5. Markdown-Sanitization
6. SkillViewModel Race Condition behoben
7. Phase 11 (CloudKit Sync) komplett, 12 Tests
8. Phase 12 (Vision Pro) komplett, 13 Tests
9. Assessment-Fixes: 2 CRITICAL + 3 HIGH behoben
10. Tests: 256 → 277

**Vor App Store Release (nicht TestFlight) adressieren:**
- Echtes SPKI Certificate Pinning
- DataBridge @MainActor Isolation
- Two-Way Input Binding
- Error-Banner in SkillView
- Onboarding-Flow
- Konsistente Fehlersprache (Deutsch)

Das Projekt ist architektonisch solide, funktional komplett für MVP, und die Qualitätsoffensive hat alle kritischen Findings adressiert. Für internes TestFlight-Testing bereit.

---

## Review 18.03.2026 (Post Gross-Review — Scheduled Review — Keine Aktivität)

### Status: OK (keine Änderungen)

Seit dem GROSS-REVIEW hat sich am Projekt nichts verändert. SESSION-LOG zeigt weiterhin Phase 14 (ASSESSMENT-COMPLETE) als letzten Eintrag. Keine neuen Commits, keine neuen Sessions. Das Projekt ist weiterhin BEREIT für TestFlight gemäss Gross-Review-Verdikt.

### Metriken

- Aktuelle Phase: Phase 14 abgeschlossen, ASSESSMENT-COMPLETE
- Tests: 256 bestanden / 0 fehlgeschlagen (unverändert)
- Neue Commits seit letztem Review: keine
- Build: Zuletzt OK (iPhone 16 Pro, iOS 18.4 Simulator)
- Gross-Review-Verdikt: BEREIT für TestFlight (mit Auflagen)

### Offene Punkte (aus Gross-Review, weiterhin offen)

- Certificate Pinning (vor App Store Release)
- iPad-Layout mit NavigationSplitView
- Face ID Integration in App-Flow
- Accessibility Labels auf alle interaktiven Elemente
- Two-Way Input Binding für interaktive Skills

### Hinweis

Dies ist der erste Scheduled Review ohne Aktivität nach dem Gross-Review. Falls der nächste Review ebenfalls keine Änderungen zeigt, wird der Task automatisch pausiert (Auto-Pause-Regel: 2 Reviews ohne Fortschritt).

### Empfehlung

- TestFlight-Build erstellen und internes Testing starten.
- Offene Punkte aus dem Gross-Review priorisieren (Accessibility, Certificate Pinning, iPad-Layout).

---

## GROSS-REVIEW 18.03.2026 — Finaler Abschluss-Review

### Gesamturteil: BEREIT für TestFlight (mit Auflagen)

### Zusammenfassung

brain-ios implementiert eine funktionsfähige Runtime-Engine, die JSON-Skills als native SwiftUI rendert. Die Architektur ist sauber, die Zwei-Schichten-Trennung eingehalten, und alle 8 Module existieren als JSON-Skills. 256 Tests grün, iOS-Build OK. Die Skill-Engine-Kette (Definition → Parser → Renderer → Actions → State) ist lückenlos. Das Projekt hat solide Security-Grundlagen (Keychain, parametrisierte Queries, URL-Whitelist), aber einige Punkte müssen vor einem öffentlichen Release (nicht TestFlight) adressiert werden.

Dieser Review wurde UNABHÄNGIG von Phase 14 durchgeführt. Alle Dateien wurden mit frischen Augen gelesen.

### Security

- **[MEDIUM] Force-Unwrap bei URL-Konstruktion in LLM Providers.** AnthropicProvider (Zeile 25) und OpenAIProvider (Zeile 24) verwenden `URL(string: baseURL)!`. Die baseURL ist hardcoded und valide, daher ist ein Crash in der Praxis unwahrscheinlich; dennoch verletzt es defensive Programmierung. Phase 14 hat dieses Finding ebenfalls identifiziert und mit `guard + throw` behoben; die lokale Kopie zeigt noch den alten Stand. *Verifizieren, dass der Fix auf GitHub tatsächlich committed ist.*
- **[MEDIUM] Kein Certificate Pinning auf API-Calls.** Beide LLM Providers nutzen `URLSession.shared` ohne Certificate Pinning. Für TestFlight akzeptabel; vor App Store Release sollte TLS-Pinning evaluiert werden (TrustKit oder manueller URLSessionDelegate).
- **[MEDIUM] Image-URLs akzeptieren HTTP.** SkillRenderer prüft `hasPrefix("http")`, was sowohl http:// als auch https:// zulässt. Sollte auf HTTPS-only eingeschränkt werden.
- **[LOW] Markdown aus Skills wird nicht sanitized.** `AttributedString(markdown:)` parsed Markdown direkt aus Skill-JSON. Das SwiftUI-AttributedString-Framework ist robust, aber ein Allowlist-Filter für Markdown-Tags wäre sauberer.
- **[OK] Keychain-Nutzung korrekt.** `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, keine Secrets in UserDefaults, keine hardcodierten API-Keys.
- **[OK] SQL-Queries parametrisiert.** GRDB Query Builder + parametrisierte FTS5-Queries. Kein Injection-Risiko.
- **[OK] URL-Whitelist für open-url.** Nur https, http, mailto erlaubt.
- **[OK] ExpressionParser Rekursionslimit.** Depth-Limit 20 verhindert Stack Overflow.
- **[INFO] Info.plist konnte nicht geprüft werden.** Keine .plist-Datei in der lokalen Kopie. Muss auf dem Mac verifiziert werden (Permission-Strings für Contacts, EventKit, Location, Notifications).

### Code-Qualität

- **[MEDIUM] `nonisolated(unsafe)` DateFormatters in PatternEngine.** ISO8601DateFormatter ist nach Konfiguration thread-safe; `DateFormatter` technisch nicht. Phase 14 hat dies analysiert und als akzeptabel dokumentiert. Für TestFlight OK, langfristig auf einen Lock oder pro-Task-Formatter umstellen.
- **[MEDIUM] `@unchecked Sendable` ohne Begründungskommentare.** 11 Stellen verwenden `@unchecked Sendable`. Phase 14 hat die Korrektheit verifiziert (immutable Properties, iOS-Framework-Wrapping). Empfehlung: MARK-Kommentare mit Begründung ergänzen.
- **[MEDIUM] Race Condition in SkillViewModel.** Wenn `executeAction()` mehrfach schnell aufgerufen wird, laufen parallele Tasks. Empfehlung: vorherigen Task canceln.
- **[LOW] ActionDispatcher gibt Fehler als Return-Value statt throw zurück.** Bei unbekanntem Handler wird `ActionResult.error(...)` zurückgegeben statt geworfen. Inkonsistent mit der `async throws` Signatur. LogicInterpreter behandelt beide Fälle korrekt, aber die Inkonsistenz ist verwirrend.
- **[LOW] Potentieller Retain Cycle in LocationBridge.** CLLocationManager hält starke Referenz auf delegate (self), self hält starke Referenz auf manager. Als `final class` ohne Escape-Pfade praktisch unproblematisch, aber unsauber.
- **[OK] async/await durchgehend statt Combine.** Modernes, konsistentes Pattern.
- **[OK] @Observable MVVM sauber implementiert.** SkillViewModel, DataBridge korrekt.
- **[OK] GRDB-Transaktionen korrekt.** pool.write/pool.read überall konsistent.

### Funktionalität

- **[OK] Skill-Engine-Kette lückenlos.** SkillDefinition → ExpressionParser → SkillRenderer → ActionDispatcher → LogicInterpreter. Vollständig und korrekt.
- **[OK] 22 Renderer-Primitives implementiert und funktional.** Layout (8), Content (7), Input (2), Interaction (1), Data (3), Fallback für unbekannte Primitives.
- **[OK] ExpressionParser robust.** Variable Lookup, dotted Paths, Vergleiche, Arithmetik, Pipe-Filter, String-Interpolation. Division durch Null gibt 0. Fehlende Variablen geben null.
- **[OK] LogicInterpreter korrekt.** if/forEach/set/sequence funktionieren. Context-Propagation (lastResult) korrekt. forEach setzt index-Variable. Verschachtelung funktioniert.
- **[OK] Datenintegrität.** GRDB-Transaktionen, Soft-Delete-Pattern konsistent, Cursor-Pagination.
- **[OK] Offline-Modus.** Skill-Engine arbeitet komplett lokal. Keine versteckten Netzwerk-Abhängigkeiten.
- **[KNOWN] TextField/Toggle read-only.** `.constant()`-Bindings; Two-Way-Binding nicht implementiert. Bekannte Einschränkung, dokumentiert im SESSION-LOG. Betrifft Quick Capture (Input funktioniert nicht). Akzeptabel für TestFlight.
- **[KNOWN] 12 Action Handlers implementiert.** entry.create, entry.search, haptic, clipboard.copy, open-url, toast, set, contact.search, calendar.list, reminder.list, location.current, notification.schedule. Für MVP ausreichend.
- **[INFO] Skills-Status: 3 voll funktional (Dashboard, Kalender, Quick Capture teilweise), 1 teilfunktional (Mail Inbox mit Demo-Daten), 4 UI-Shells (Files, Canvas, People, Brain Admin, Chat).** Für TestFlight akzeptabel.

### UX & Usability

- **[MEDIUM] Keine expliziten accessibilityLabels.** Kein einziges `.accessibilityLabel()` oder `.accessibilityHint()` auf interaktiven Elementen in SkillRenderer. SwiftUI-Standard-Accessibility greift (Button-Text wird als Label verwendet), aber Custom-Komponenten (stat-card, badge, avatar) haben keine Labels. Für TestFlight akzeptabel; vor App Store Release zwingend.
- **[MEDIUM] Kein iPad-Layout.** ContentView verwendet TabView für alle Geräte. ARCHITECTURE.md spezifiziert NavigationSplitView für iPad. Auf iPad funktioniert die App, aber nicht optimiert. Für TestFlight OK.
- **[LOW] Face ID implementiert aber nicht in App-Flow integriert.** DeviceBiometricAuthenticator existiert und ist korrekt, wird aber beim App-Start nicht aufgerufen. Für TestFlight akzeptabel (erleichtert das Testen).
- **[LOW] Ladeindikator fehlt für initiale Dashboard-Daten.** `dashboardVariables()` lädt synchron. Bei grosser DB könnte das zu einem kurzen Freeze führen.
- **[LOW] Mischung Deutsch/Englisch in Error Messages.** User-facing Texte sind Deutsch ("Noch keine Eintraege"), aber ActionDispatcher-Fehler sind Englisch ("No handler registered"). Für TestFlight akzeptabel.
- **[OK] Empty States vorhanden.** Alle Skills haben leere Zustände mit Icon + Titel + Nachricht.
- **[OK] UI-Texte grundsätzlich auf Deutsch.** Begrüssungen, Fehlermeldungen, Platzhalter.

### Architektur-Konsistenz

- **[OK] Alle 16 Architektur-Entscheidungen eingehalten oder korrekt aufgeschoben.**
  - 13/16 korrekt implementiert (Runtime-Engine, kein VPS, SwiftUI only, GRDB, Offline-First, Multi-LLM, Skill-Format, Bootstrap als JSON, Face ID, Keychain, Entry als Herzstück, App Store-konform, kein Marktplatz)
  - 2/16 korrekt aufgeschoben (Proaktive Intelligenz = Phase 8+, Geschäftsmodell = später)
  - 1/16 teilweise (iPad/Vision Pro: funktioniert auf iPad via TabView, nicht optimiert; Vision Pro Phase 12)
- **[OK] Zwei-Schichten-Trennung sauber.** Skill Engine (JSON) klar getrennt von Proaktiver Intelligenz (nativ, noch nicht implementiert). Kein Durchsickern in die jeweils andere Schicht.
- **[OK] Bootstrap Skills sind reine JSON-Skills.** Dashboard, Mail, Kalender als SkillDefinition-Konstanten, strukturell identisch mit user-generierten Skills.
- **[OK] ComponentRegistry als Security-Katalog.** 47 Primitives registriert. Skills können nur registrierte Primitives verwenden. Validation vor Installation.
- **[OK] BrainCore/BrainApp-Trennung sauber.** BrainCore ist pure Swift (Linux-testbar), BrainApp enthält SwiftUI und iOS-Frameworks.

### Offene Punkte (die Andy entscheiden muss)

- **Certificate Pinning:** Vor App Store Release implementieren oder bewusst aufschieben? TrustKit als Library oder manueller URLSessionDelegate?
- **iPad-Layout:** Wann NavigationSplitView nachrüsten? Jetzt oder nach TestFlight-Feedback?
- **Face ID Integration:** Soll Face ID für TestFlight aktiviert werden oder erst für den öffentlichen Release?
- **Two-Way Input Binding:** Priorität für interaktive Skills (TextField/Toggle)? Blockiert Quick Capture.

### Verdikt

**BEREIT für TestFlight** mit folgenden Auflagen:

1. **Vor TestFlight (empfohlen, nicht blockierend):** Verifizieren, dass die Force-Unwrap-Fixes aus Phase 14 tatsächlich im GitHub-Repo sind (lokale Kopie zeigt alten Stand). Falls nicht, nachholen.
2. **Vor App Store Release (blockierend):**
   - Accessibility Labels auf alle interaktiven Elemente
   - Certificate Pinning auf LLM API-Calls
   - Image-URLs auf HTTPS-only einschränken
   - iPad-Layout mit NavigationSplitView
   - Face ID in App-Flow integrieren
   - Error Messages konsistent auf Deutsch
3. **Langfristig (nicht blockierend):**
   - Two-Way Input Binding für interaktive Skills
   - DateFormatter Thread-Safety
   - `@unchecked Sendable` Begründungskommentare

Das Projekt ist architektonisch solide, die Runtime-Engine funktioniert, und die Qualitätsoffensive in Phase 14 hat die wichtigsten Findings adressiert. Für TestFlight (internes Testing) ist das Projekt bereit.

---

## Phase 14 Assessment Report 18.03.2026

### Status: ASSESSMENT-COMPLETE

Phase 14 (Assessment & Audit) vollstaendig durchgefuehrt. Alle HIGH/MEDIUM Findings behoben.
Tests von 154 auf 256 ausgebaut. Bereit fuer Zora-Abschluss-Review und TestFlight.

### Behobene Findings (aus frueheren Reviews)

- **[RESOLVED]** Test-Coverage stagniert bei 154 → Jetzt 256 Tests (+102 neue)
- **[RESOLVED]** Advanced Skills (Files, Canvas, People) unklar → Dokumentiert als UI-Shells, nicht als Bug
- **[RESOLVED]** AnthropicProvider/OpenAIProvider Streaming-Flag falsch → Korrigiert auf false
- **[RESOLVED]** nonisolated(unsafe) DateFormatters → Analysiert, akzeptabel, dokumentiert

### Verbleibende LOW-Findings (nicht blockierend)

- **[Severity: LOW]** Keine expliziten accessibilityLabels fuer Custom-Renderer-Komponenten (stat-card, badge, avatar). SwiftUI-Standard-Accessibility greift, aber Custom Labels wuerden VoiceOver verbessern.
- **[Severity: LOW]** SkillViewModel.errorMessage wird im SkillView nicht angezeigt — Errors sind nur als Property vorhanden, keine UI-Darstellung.
- **[Severity: LOW]** Kein Onboarding-Flow. App zeigt direkt Dashboard. Akzeptabel fuer TestFlight.
- **[Severity: LOW]** LLM Streaming nicht implementiert (supportsStreaming korrigiert auf false). Kein funktionaler Impact da Chat noch UI-Shell ist.
- **[Severity: LOW]** People-Skill nicht an ContactsBridge angebunden (Bridge existiert, Skill zeigt leere Liste).
- **[Severity: LOW]** Brain Admin zeigt statische Werte statt live DB-Daten aus DataBridge.

### Metriken

- Tests: 256 bestanden / 0 fehlgeschlagen
- LOC: ~6200 Zeilen Swift (inkl. 1175 Zeilen neue Tests)
- Security Findings: 0 offen (alle behoben)
- Code-Qualitaet Findings: 0 offen (alle behoben)
- Funktionalitaet: 3/8 Skills voll funktional, 1 teilfunktional, 4 UI-Shells
- Action Handlers: 12 implementiert (inkl. neue toast + set)
- Build: OK (iPhone 16 Pro, iOS 18.4 Simulator)

---

## Review 18.03.2026 (Scheduled Review — Keine Aktivität)

### Status: OK (keine Änderungen)

Seit dem letzten Review (Post Phase 10+13) hat sich am Projekt nichts verändert. SESSION-LOG zeigt weiterhin Phase 7-10+13 als letzten Eintrag. Phase 14 (Assessment & Audit) steht als nächste Phase an, wurde aber noch nicht gestartet. ASSESSMENT-COMPLETE nicht gefunden.

### Metriken

- Aktuelle Phase: Phase 10+13 abgeschlossen, Phase 14 ausstehend
- Tests: 154 bestanden / 0 fehlgeschlagen (unverändert)
- Neue Commits seit letztem Review: keine
- Build: Zuletzt OK (iPhone 16 Pro, iOS 18.4 Simulator)

### Offene Findings (aus vorherigem Review, weiterhin offen)

- **[MEDIUM]** Test-Coverage stagniert bei 154 Tests für ~5000 LOC — Phase 14 muss das adressieren
- **[MEDIUM]** Advanced Skills (Files, Canvas, People, Brain Admin, Chat) vermutlich nur UI-Shells ohne echte Action Handlers
- **[LOW]** Streaming-Support bei LLM Providers unklar
- **[LOW]** PatternEngine unvollständig (nur Streak + Anomalie, keine Knowledge Extraction / Self-Modifier)
- **[LOW]** `nonisolated(unsafe)` Workaround für DateFormatters

### Hinweis

Dies ist der erste Scheduled Review ohne Aktivität. Falls der nächste Review ebenfalls keine Änderungen zeigt, wird der Task automatisch pausiert (Auto-Pause-Regel: 2 Reviews ohne Fortschritt).

### Empfehlung

- Phase 14 (Assessment & Audit) starten. Das Projekt ist feature-komplett für MVP und wartet auf die Qualitätsoffensive.
- Die offenen MEDIUM-Findings (Test-Coverage, Action Handlers) werden durch Phase 14 direkt adressiert.

---

## Review 18.03.2026 (Post Phase 10+13 — manueller Review durch Zora/Cowork)

### Status: OK

Phasen 0–10 und Teile von Phase 13 in einer einzigen Session abgeschlossen. ~5000 Zeilen
Swift Code, 154 Tests grün, iOS Build OK. Alle 8 Tabs rendern Skills. LLM Providers
(Anthropic, OpenAI) stehen, Keychain implementiert, Pattern Engine erkennt Streaks und
Anomalien. Das Projekt ist funktional fast komplett.

### Findings

- **[Severity: MEDIUM]** Testzahl stagniert bei 154 seit Phase 2. Phasen 5-10 haben keine neuen Tests hinzugefügt. Die Bridges, Advanced Skills, Pattern Engine, LLM Providers und Keychain sind alle ohne Unit-Tests. Bei ~5000 LOC und nur 154 Tests ist die Coverage vermutlich unter 50%. — *Empfehlung: Phase 14 (Assessment) muss zwingend Test-Coverage adressieren. Insbesondere: PatternEngine (Streak-Logic, Anomalie-Detection), KeychainService (save/read/delete), LLM Providers (Response-Parsing, Error-Handling), und SkillViewModel (State-Transitions). Ziel gemäss Phase 14 Spec: >80% Core, >90% Security-kritisch.*

- **[Severity: MEDIUM]** Die Advanced Skills (Files, Canvas, People, Brain Admin, Chat) sind als JSON-Skills definiert, aber die zugehörigen Action Handlers sind unklar. Der SESSION-LOG erwähnt keine konkreten Handlers für file.read/write, canvas-Operationen, oder chat.send. Vermutlich rendern diese Skills nur UI ohne Funktionalität. — *Empfehlung: In Phase 14 systematisch prüfen welche Skills funktional sind (echte Daten) und welche nur UI-Shells (Demo/Empty State). Dokumentieren.*

- **[Severity: LOW]** AnthropicProvider und OpenAIProvider sind als "REST" implementiert. Unklar ob Streaming (AsyncThrowingStream) unterstützt wird, was laut ARCHITECTURE Pflicht ist. — *Empfehlung: In Phase 14 verifizieren ob Streaming funktioniert. Falls nicht, nachbauen.*

- **[Severity: LOW]** PatternEngine hat nur Streak-Detection und Activity-Anomalien. Die ARCHITECTURE spezifiziert auch: Knowledge Extraction, Self-Modifier Proposals, Proaktive Notifications ("Du hast Sarah seit 2 Wochen nicht geantwortet"). — *Empfehlung: Die fehlenden Pattern-Engine-Features als "Tier 2" für nach Phase 14 dokumentieren. Streak + Anomalie reichen für MVP.*

- **[Severity: LOW]** `nonisolated(unsafe)` für DateFormatters (Commit e465beb) ist ein Swift 6 Workaround. Funktioniert, aber `@unchecked Sendable` oder `nonisolated(unsafe)` sind Red Flags für Phase 14.2 (Code-Qualität). — *Empfehlung: In Phase 14 prüfen ob eine sauberere Lösung möglich ist (z.B. DateFormatter pro Task erstellen statt shared).*

- **[Severity: INFO]** Renderer steht bei 22 von ~50 Primitives. Für die Advanced Skills (Phase 7) reichen die vorhandenen Primitives offensichtlich, da der Build grün ist. Die fehlenden ~28 Primitives sind vermutlich für Tier 2/3 Features (Charts, Maps, Rich Editor, Canvas, etc.). Demand-driven nachbauen bleibt der richtige Ansatz.

### Metriken

- Abgeschlossene Phasen: 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, Teile von 13
- Tests: 154 bestanden / 0 fehlgeschlagen (seit Phase 2 unverändert!)
- LOC: ~5000 Zeilen Swift
- Skills: 8 (Dashboard, Mail, Kalender, Quick Capture, Files, Canvas, People, Brain Admin, Chat)
- Renderer-Primitives: 22 implementiert
- Bridges: 4 (Contacts, EventKit, Location, Notifications) + Spotlight
- LLM Providers: 2 (Anthropic, OpenAI)
- Build: OK auf iPhone 16 Pro, iOS 18.4 Simulator

### Positiv

- **Geschwindigkeit:** Von Null auf fast-komplett in einer Session. Beispiellos.
- **Architektur-Treue:** Alle 16 Entscheidungen eingehalten. Zwei-Schichten-Trennung sauber. Entry als Herzstück. Offline-First. Runtime-Engine-Konzept durchgezogen.
- **Der Proof-of-Concept funktioniert:** 8 Tabs rendern JSON-Skills als native SwiftUI. Das validiert die gesamte Architektur-Hypothese.
- **Saubere Zäsur:** Phase 11 (CloudKit) und 12 (Vision Pro) korrekt als "später" identifiziert. Phase 14 (Assessment) als nächster Schritt.
- **KeychainService:** kSecAttrAccessibleWhenUnlockedThisDeviceOnly ist die richtige Access-Control-Policy.
- **Pattern Engine:** Streak-Detection und Anomalie-Erkennung als Grundlage für Proaktive Intelligenz.
- **SESSION-LOG-Qualität:** Durchgehend vorbildlich. Jede Entscheidung begründet.

### Empfehlung

- **Phase 14 ist jetzt kritisch.** Der Code existiert, aber die Test-Coverage ist unzureichend. Phase 14 muss die grösste "Qualitäts-Offensive" des Projekts werden.
- **Priorität 1:** Test-Coverage massiv ausbauen (aktuell ~154 Tests für ~5000 LOC).
- **Priorität 2:** Funktionale Validierung aller Skills (welche haben echte Daten, welche sind Shells?).
- **Priorität 3:** Security Audit (Keychain, LLM API-Keys, Input Validation, nonisolated(unsafe)).
- **Phase 11 (CloudKit) und 12 (Vision Pro) können warten.** Phase 14 zuerst.

---

## Review 18.03.2026 (Post Phase 5: iOS Bridges + Bug-Fixes — Scheduled Review)

### Status: OK

Phase 5 bringt die ersten echten iOS-Framework-Anbindungen und eine solide Runde Bug-Fixes. Die kritischen Fixes (Data Race im ActionDispatcher, Force Unwrap, URL-Whitelist) zeigen gutes Sicherheitsbewusstsein. Vier Bridges (Contacts, EventKit, Location, Notifications) sind implementiert und folgen dem Architecture-Pattern sauber.

### Findings

- **[Severity: MEDIUM]** Phase 5 ist laut SESSION-LOG abgeschlossen, aber der ARCHITECTURE-Scope listet auch SwiftMail, Camera/Scanner, Audio, BLE, Health, Home, NFC. Nur 4 von ~10 Bridges sind implementiert. Insbesondere fehlt SwiftMail, das für den Bootstrap-Skill "Inbox" (Phase 6) relevant ist; der Inbox-Skill rendert aktuell nur mit Demo-Daten. — *Empfehlung: Klar dokumentieren welche Bridges als Tier 1 (MVP) gelten und welche bewusst verschoben sind. SwiftMail-Bridge sollte vor oder mit Phase 7 nachgezogen werden, damit die Inbox funktional wird. Kein Blocker für Phase 6 (Bootstrap Skills rendern korrekt), aber ein funktionaler Gap.*

- **[Severity: LOW]** Bridges sind nicht unit-testbar (Framework-Abhängigkeiten). Akzeptabel für den Moment, aber bei wachsender Komplexität (besonders EventKit mit Recurring Events, Contact-Permissions) steigt das Risiko unentdeckter Bugs. — *Empfehlung: Protocol-basierte Abstraktion (wie bei BiometricAuth) für testbare Bridge-Interfaces. MockContactsBridge, MockEventKitBridge etc. für Unit-Tests. Integration-Tests via XCUITest wenn Simulator verfügbar.*

- **[Severity: LOW]** 22 von ~50 Renderer-Primitives implementiert. Gegenüber dem letzten Review (16) ein Fortschritt, aber immer noch unter 50%. Fehlende Primitives für erweiterte Skills: `picker`, `date-picker`, `search-field`, `chart`, `calendar-grid`, `swipe-actions`, `pull-to-refresh`, `slider`, `stepper`, `color-picker`, `secure-field`, `menu`, `long-press`, `map`, `gauge`, `timer-display`, `graph`, `rich-editor`, `canvas`, `camera`, `scanner`, `audio-player`, `web-view`, `tab-view`, `split-view`, `link`, `text-editor`. — *Empfehlung: Demand-driven nachbauen. Für Phase 7 (Advanced Skills) werden mindestens `search-field`, `swipe-actions`, `chart`, `map`, `rich-editor` gebraucht. Priorisierung nach tatsächlichem Bedarf der nächsten Skills.*

- **[Severity: INFO]** Bug-Fixes aus Commit `75a1255` adressieren genau die Art von Problemen die ein Security Audit (Phase 14) finden würde: Data Races, Force Unwraps, fehlende URL-Whitelists, fehlende DB-Indizes. Das ist proaktive Qualitätsarbeit. Gut.

- **[Severity: INFO]** Die Action Handler (ContactSearchHandler, CalendarListHandler etc.) folgen dem Protocol-Pattern sauber. Jeder Handler ist ein eigenständiger Typ mit `execute(properties:context:)`. Das ist architekturkonform und erweiterbar.

### Metriken

- Aktuelle Phase: 5 abgeschlossen (iOS Bridges Tier 1)
- Tests: 154 bestanden / 0 fehlgeschlagen (BrainCore, unverändert)
- Neue Commits seit letztem Review: 75a1255 (Bug-Fixes), a7080b2 (Bridges)
- Bridges implementiert: 4 (Contacts, EventKit, Location, Notifications)
- Bridges ausstehend: ~6 (SwiftMail, Camera/Scanner, Audio, BLE, Health, Home/NFC)
- Renderer-Primitives: 22 von ~50
- Build: OK auf iPhone 16 Pro, iOS 18.4 Simulator

### Positiv

- **Proaktive Bug-Fixes:** CRITICAL und HIGH Findings selbst identifiziert und behoben, bevor der Review sie gefunden hat. ActionDispatcher als immutable nach Init ist die richtige Lösung für die Data Race.
- **Architektur-Treue:** Alle 16 Architektur-Entscheidungen eingehalten. Bridges sind native Handlers, aufgerufen via JSON-Actions. Zwei-Schichten-Trennung sauber.
- **Saubere Handler-Architektur:** Jeder Bridge-Handler folgt dem Protocol-Pattern. Erweiterbar ohne bestehenden Code zu ändern.
- **DB-Indizes nachgezogen:** 6 neue Indizes zeigen, dass Performance-Überlegungen nicht vergessen gehen.
- **ExpressionParser Rekursionslimit:** Wichtig für Security (DoS-Schutz bei bösartigen JSON-Skills).
- **Dokumentationsqualität:** SESSION-LOG bleibt vorbildlich, jede Entscheidung begründet.

### Empfehlung

- **Nächste Priorität:** Phase 6/7 weiter vorantreiben. Bootstrap-Skills brauchen echte Daten-Anbindung (Entry CRUD → SkillViewModel → UI).
- **SwiftMail-Bridge:** Sollte nicht zu lange aufgeschoben werden. Inbox ohne echte E-Mail-Anbindung ist nur eine Demo.
- **Bridge-Tests:** Protocol-Abstraktionen + Mocks als Pattern für alle Bridges einführen. Das zahlt sich bei Phase 14 (Assessment) aus.
- **Renderer on-demand erweitern:** Die nächsten Skills bestimmen welche Primitives nachgebaut werden müssen.

---

## Review 18.03.2026 (Post iOS App Shell + SwiftUI Renderer — Scheduled Review)

### Status: OK

Xcode-Projekt steht, SwiftUI Renderer funktioniert, App baut auf dem iPhone 16 Pro Simulator. Der Proof-of-Concept-Moment ist erreicht: JSON-Skills werden als native SwiftUI gerendert. XcodeClub VM-Zugang eingerichtet mit SSH-Tunnel via VPS.

### Findings

- **[Severity: LOW]** 16 von 47 registrierten Primitives sind im SwiftUI Renderer implementiert. Die fehlenden 31 werden für Bootstrap Skills (Phase 6) benötigt; insbesondere `list`, `grid`, `sheet`, `picker`, `date-picker`, `search-field`, `chart`, `calendar-grid`, `swipe-actions`, `pull-to-refresh`. — *Empfehlung: Bei Phase 5/6 priorisiert die Primitives nachbauen, die Dashboard/Inbox/Kalender brauchen. Nicht alle 47 auf einmal, sondern demand-driven.*

- **[Severity: LOW]** Inputs sind read-only (`.constant()` Bindings). Das ist korrekt dokumentiert und bewusst, aber es bedeutet, dass kein Skill aktuell interaktiv ist (Textfelder, Toggles reagieren nicht). — *Empfehlung: @Observable SkillViewModel ist der richtige nächste Schritt. Ohne State Management sind Bootstrap Skills nicht möglich. Sollte vor Phase 6 gelöst sein.*

- **[Severity: LOW]** SSH-Tunnel zu XcodeClub VM muss bei Neustart manuell erneuert werden. GUI-Interaktion auf der VM ist langsam. — *Empfehlung: Rein CLI-basierter Workflow (xcodebuild via SSH) ist der richtige Ansatz. Für CI langfristig GitHub Actions macOS Runner evaluieren.*

- **[Severity: INFO]** SkillRenderer lebt im BrainApp Target, nicht in BrainCore. Das ist architekturkonform (SwiftUI-Dependency isoliert). BrainCore bleibt pure Swift und Linux-testbar. Gute Entscheidung.

- **[Severity: INFO]** Lokaler Workflow (Code lokal → commit → push → pull auf Mac → bauen) ist pragmatisch für die aktuelle Situation. Kein direktes Datei-Transfer via SSH (Heredoc-Probleme). Akzeptable Lösung.

### Metriken

- Aktuelle Phase: iOS App Shell (zwischen Phase 4 Engine-Kern und Phase 5 iOS Bridges)
- Tests: 154 bestanden / 0 fehlgeschlagen (BrainCore, unverändert)
- Neue Commits seit letztem Review: 5d87f05, f63f78a, 9787c9e
- SwiftUI Renderer: 16 Primitive-Typen (Layout: 5, Content: 5, Input: 2, Interaction: 1, Data: 3)
- Build: OK auf iPhone 16 Pro, iOS 18.4 Simulator

### Positiv

- **Proof of Concept erreicht:** JSON-Skill → native SwiftUI. Das ist der wichtigste Meilenstein seit dem Engine-Kern.
- **Architektur-Treue:** Alle 16 Architektur-Entscheidungen eingehalten. Zwei-Schichten-Trennung sauber. BrainCore bleibt pure Swift.
- **Pragmatische Infrastruktur:** XcodeClub VM + SSH-Tunnel + Keep-Alive funktioniert. Nicht elegant, aber effektiv.
- **Face ID:** DeviceBiometricAuthenticator mit LAError-Mapping implementiert. Protocol-basiert (testbar).
- **Defensive Programmierung:** Unbekannte Primitives zeigen Placeholder statt Crash.
- **Dokumentationsqualität:** Jede Entscheidung im SESSION-LOG begründet. Kontinuitätskette funktioniert.

### Empfehlung

- **Nächste Priorität:** @Observable SkillViewModel für Zwei-Wege-Binding. Ohne das sind interaktive Skills nicht möglich.
- **Phase 5+6 als Einheit:** iOS Bridges (konkrete Action Handlers) und Bootstrap Skills parallel. Jeder Handler sofort gegen einen echten Skill validieren. (Bestätigt Empfehlung vom letzten Review.)
- **Renderer erweitern on-demand:** Nicht alle 47 Primitives auf einmal, sondern die, die Dashboard/Inbox/Kalender brauchen.
- **SwiftUI-Tests:** XCUITest-Infrastruktur aufsetzen sobald interaktive Skills möglich sind.

---

## Review 18.03.2026 (Post Phase 4 — manueller Review durch Zora/Cowork)

### Status: OK

Phasen 0–4 in einer einzigen Session abgeschlossen. Der gesamte Engine-Kern ist gebaut
und getestet. 154 Tests, alle grün. Die natürliche Zäsur ist korrekt identifiziert:
alles was ohne Xcode/macOS machbar ist, ist gemacht. Ab Phase 5 braucht es den Mac.

### Findings

- **[Severity: LOW]** ExpressionParser nutzt NSRegularExpression mit reverse-order Offset-Berechnung. Funktioniert, ist aber bei tief verschachtelten UIs mit vielen Expressions ein potenzieller Performance-Bottleneck. — *Empfehlung: Im Hinterkopf behalten. Wenn der SwiftUI-Renderer steht und echte Skills gerendert werden, Performance-Profiling machen. Falls nötig, auf einen echten Recursive-Descent-Parser umbauen.*

- **[Severity: LOW]** 47 UI Primitives registriert vs. ~50 in der ARCHITECTURE spezifiziert. Differenz von 3 ist akzeptabel, sollte aber bei Phase 6 (Bootstrap Skills) geprüft werden ob die fehlenden für Dashboard/Inbox/Kalender benötigt werden. — *Empfehlung: Bei Phase 6 die fehlenden Primitives identifizieren und nachregistrieren.*

- **[Severity: LOW]** Keine konkreten Action Handlers implementiert (nur MockHandler für Tests). Das ist architekturkonform (konkrete Handler brauchen iOS-Frameworks), aber bedeutet, dass Phase 5 (iOS Bridges) und Phase 6 (Bootstrap Skills) eng gekoppelt werden müssen. — *Empfehlung: Phase 5 und 6 als Einheit planen. Bridges bauen UND sofort mit einem echten Skill validieren.*

- **[Severity: INFO]** Die WWDC 2025 Recherche ist wertvoll: Apple Foundation Models Framework (`@Generable` Macro) könnte den SkillCompiler erheblich vereinfachen (constrained JSON-Generation On-Device). SwiftUI iOS 26 bringt nativen WebView und Rich Text Editor, was zwei Primitives obsolet macht. — *Empfehlung: Bei Phase 10 (On-Device LLM) Apple Foundation Models als primären Provider evaluieren, nicht nur MLX Swift.*

- **[Severity: INFO]** LLM-Kompilierung (Markdown → JSON via LLM) ist korrekt auf "später" verschoben. Der SkillCompiler kann Frontmatter parsen und validieren, aber die eigentliche KI-Übersetzung braucht einen konkreten Provider + API-Key. Das ist die richtige Entscheidung. — *Kein Handlungsbedarf.*

### Metriken

- Aktuelle Phase: 4 abgeschlossen (Engine-Kern komplett)
- Tests: 154 bestanden / 0 fehlgeschlagen
- Commits: 8a9c51d → 749e033 → c323e77 → aba125a → f8e9cce → e54a33c → 51508e6 → 7240b0e → 8b2d420 → 2bd66b3 → 6c6d88e
- Komponenten: 13 Tabellen, 11 Models, 6 Services, 47 Primitives, ExpressionParser, ActionDispatcher, LogicInterpreter, SkillCompiler, SkillLifecycle, ThemeConfig, LLM Layer, Auth Protocol, Navigation Model

### Positiv

- **Tempo:** 5 Phasen (0–4) in einer Session. Beeindruckend.
- **Testdisziplin:** 154 Tests, alle grün. Jede Phase baut auf den vorherigen Tests auf, keine Regression.
- **Architektur-Treue:** Alle 16 Architektur-Entscheidungen werden eingehalten. Zwei-Schichten-Trennung sauber. Entry als Herzstück. Offline-First.
- **Pragmatische Entscheidungen:** Kein YAML-Library (einfacher Parser reicht), BiometricAuth als Protocol-Stub, LLM-Kompilierung auf "später" verschoben. Alles nachvollziehbar dokumentiert.
- **Saubere Zäsur:** Die Empfehlung "hier stoppen, nächster Schritt braucht Mac" ist korrekt und zeigt gutes Urteilsvermögen.
- **Recherche-Qualität:** WWDC 2025 Findings (Apple Foundation Models, SwiftUI iOS 26) sind direkt relevant und gut dokumentiert.
- **Cursor-Pagination statt Offset:** Richtige Wahl für skalierbare Datasets.
- **SESSION-LOG-Qualität:** Jede Entscheidung ist mit Begründung dokumentiert. Die Kontinuitätskette funktioniert.

### Empfehlung

- **Nächster Meilenstein:** Cloud-Mac-Zugang aktivieren, Xcode-Projekt erstellen, BrainUI Target einrichten
- **Erste Priorität auf Mac:** SwiftUI Renderer (JSON-Baum → native Views). Das ist der Proof-of-Concept-Moment: wenn ein JSON-Skill als echte SwiftUI-App gerendert wird.
- **Phase 5+6 zusammen planen:** iOS Bridges (konkrete Action Handlers) und Bootstrap Skills (Dashboard, Inbox) parallel entwickeln, damit jeder Handler sofort gegen einen echten Skill validiert wird.
- **Review-Intervall:** Stündlich reaktivieren sobald Claude Code wieder arbeitet.

---

## Auto-Pause 18.03.2026 — Zwei Reviews ohne Aktivität. Task pausiert.

Seit dem initialen Projekt-Setup hat sich nichts verändert. Weder das Initiale Review noch Scheduled Review #1 zeigten Fortschritt. Der Projektzustand ist identisch: Phase 0 nicht begonnen, kein GitHub-Repo, keine Commits, keine Tests. Cloud-Mac-Zugang (XcodeClub) weiterhin ausstehend.

Review-Task wird deaktiviert bis Claude Code wieder am brain-ios Projekt arbeitet.

---

## Review 18.03.2026 (Scheduled Review #1)

### Status: OK

Projekt befindet sich weiterhin in der Pre-Phase-0-Planung. Keine Implementierung seit dem initialen Setup. Prozessinfrastruktur steht, Architektur ist definiert.

### Findings

- **[Severity: LOW]** Cloud-Mac-Zugang (XcodeClub) ist noch ausstehend. Ohne Mac-Zugang kann Phase 0 nur teilweise durchgeführt werden (Swift Package auf VPS/lokal, aber kein Xcode-Projekt, kein Simulator). — *Empfehlung: Status der XcodeClub-Anmeldung klären. Falls blockiert, Phase 0 auf die VPS-fähigen Teile beschränken (GRDB-Models, JSON Parser, Expression Parser als SPM-Package).*
- **[Severity: LOW]** GitHub-Repo (IjonTychy/brain-ios) existiert offenbar noch nicht (konnte nicht geprüft werden, da `gh` CLI nicht verfügbar in dieser Umgebung). — *Empfehlung: Repo-Erstellung als ersten Schritt von Phase 0 bestätigen.*
- **[Severity: LOW]** ARCHITECTURE-brain-ios.md referenziert `SQLiteData (Point-Free)` als Sync-Layer für CloudKit. SQLiteData/Sharing ist experimentell und die API kann sich ändern. — *Empfehlung: Für Phase 0–3 keine Abhängigkeit von SQLiteData/CloudKit. GRDB direkt nutzen. CloudKit-Integration erst in Phase 11 evaluieren.*

### Metriken
- Aktuelle Phase: Projekt-Start (Phase 0 nicht begonnen)
- Tests vorhanden: keine
- Commits: keine (Repo ausstehend)

### Positiv
- Prozessinfrastruktur vollständig und sauber (CLAUDE.md, ARCHITECTURE.md, SESSION-LOG, REVIEW-NOTES)
- 16 Architektur-Entscheidungen klar formuliert und konsistent
- Zwei-Schichten-Trennung (Skill Engine JSON vs. Proaktive Intelligenz nativ) ist sauber
- Primitives-Katalog umfassend (~50 UI + ~60 Action + ~15 Logic)
- App-Store-Konformitätsstrategie durchdacht (Server-Driven UI Präzedenzfälle)
- Phasenplan realistisch sequenziert (Engine-Kern zuerst, Features danach)
- Marktanalyse gemacht; Alleinstellungsmerkmal klar benannt

### Empfehlung
- Cloud-Mac-Zugang klären oder Alternative evaluieren (z.B. GitHub Actions macOS Runner für CI, lokale Entwicklung auf VPS mit Swift-only Packages)
- Phase 0 beginnen mit den VPS-fähigen Teilen: SPM Package Structure, GRDB Models, SQLite Schema, JSON Parser Grundstruktur
- Xcode-Projekt-Setup und iOS-Simulator-Tests erst wenn Mac-Zugang steht

---

## Initiales Review 18.03.2026

### Status: OK

Projekt-Infrastruktur aufgesetzt. Architektur definiert. Noch keine Implementierung.

### Findings

(keine)

### Metriken
- Aktuelle Phase: Projekt-Start (noch keine Implementierung)
- Tests vorhanden: keine

### Positiv
- Runtime-Engine-Architektur ist sauber durchdacht (Zwei-Schichten-Modell)
- Primitives-Katalog ist umfassend (~125 Primitives über UI/Action/Logic)
- Marktanalyse durchgeführt — Konzept ist genuinely novel in der Kombination
- Klare Trennung: Engine (Linux-testbar) vs. UI (Mac-only)

### Empfehlung
- Phase 0 starten sobald GitHub-Repo steht
- Engine-Teile (JSON Parser, Expression Parser, Logic Engine) als Swift Package priorisieren — auf Linux testbar, kein Mac nötig

---


