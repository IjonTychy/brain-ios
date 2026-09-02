# brain-ios – Projektsteuerung für Claude Code

> Auftrag: @ARCHITECTURE.md (Single Source of Truth)
> Log: @SESSION-LOG.md | Reviews: @REVIEW-NOTES.md

**Ein Dokument, eine Wahrheit.**
ARCHITECTURE.md definiert Vision, Runtime-Engine, Primitives, Phasen und alle
Architektur-Entscheidungen. Bei Widersprüchen gilt ARCHITECTURE.md.

## Kern-Konzept

brain-ios ist eine **Runtime-Engine**, keine App mit fest codierten Modulen.

```
.brainskill.md  →  KI (Ribosom)  →  skill.json  →  Runtime Engine  →  Native UI + Aktionen
   (DNA)                              (Protein)       (Zelle)
```

- **UI Primitives:** Vorkompilierte SwiftUI-Komponenten (~90 Stück), via JSON zusammengesetzt
- **Action Primitives:** Vorkompilierte Swift-Handler (~60 Stück), via JSON aufgerufen
- **Logic Primitives:** Bedingungen, Schleifen, Variablen, Templates (~15 Stück)
- **Skill Engine:** KI übersetzt .brainskill.md → skill.json
- **Proaktive Intelligenz:** Mustererkennung als nativer Code (nicht JSON-getrieben)

Die App shipped mit **Bootstrap-Skills** (Dashboard, Inbox, Kalender), die genauso
via JSON definiert sind wie user-generierte Skills. Kein Unterschied zwischen
"eingebaut" und "generiert".

## Dokumentations-Pflicht bei Commits

Bei **jedem Commit** muessen folgende Dokumentationen aktualisiert werden:
1. **SESSION-LOG.md**: Was wurde geaendert, warum, welche Entscheidungen
2. **REVIEW-NOTES.md**: Neue Findings oder Status-Updates bestehender Findings
3. **ARCHITECTURE.md**: NUR wenn architektonische Aenderungen gemacht wurden

Bei **jedem Push** zusaetzlich:
4. Pruefen ob Build-Nummer in project.pbxproj erhoeht werden muss (Xcode Cloud triggered bei push auf main)

## Build & Test

```bash
# Xcode Build + Test (auf macOS mit Xcode)
xcodebuild test -scheme brain-ios -destination 'platform=iOS Simulator,name=iPhone 16'

# SPM-only Packages (auch auf Linux/VPS möglich)
swift test
```

**WICHTIG:** brain-ios Entwicklung erfordert macOS mit Xcode. Auf dem VPS kann man Swift
Packages entwickeln und testen, aber UI-Code und iOS-Simulator-Tests brauchen einen Mac.
Wenn Tests nicht ausführbar sind: im SESSION-LOG dokumentieren, weitermachen.

**Package-Struktur für VPS-Entwicklung:**
Die Runtime-Engine (Render Engine, Action Engine, Logic Engine, Expression Parser) wird
als eigenständiges Swift Package entwickelt, das auch auf Linux testbar ist.
Nur die SwiftUI-Views und iOS-Bridge-Schicht brauchen Xcode.

## Deployment (Xcode Cloud → TestFlight)

Deployment läuft über **Xcode Cloud** → **TestFlight**. Kein manuelles Signing nötig.

```bash
# Build-Nummer erhöhen (im Xcode-Projekt oder via Script)
# Push zu main → Xcode Cloud baut automatisch → TestFlight
git push origin main
```

**Bei Deployment-Fragen, Build-Fehlern oder TestFlight-Builds:** Der installierte
Desktop-Skill `/xcode-cloud-deploy` kennt alle bekannten Fehler (Exit Code 65/70,
Signing, Package Resolution) und den korrekten Workflow. Wird automatisch
ausgelöst bei Erwähnung von brain-ios, TestFlight, Xcode Cloud oder Build-Fehlern.

**Lessons Learned:** `Skills/xcode-cloud-lessons-learned.brainskill.md` dokumentiert
den gesamten Xcode Cloud Setup-Prozess und alle gelösten Build-Probleme (51+ Builds).

**Wichtig:**
- Automatisches Signing (Xcode Cloud verwaltet Zertifikate)
- `ci_scripts/ci_post_clone.sh` für Package-Resolution
- `Package.resolved` muss im Repo sein
- objectVersion 56 in `.pbxproj` (Kompatibilität)

## Git Remote

- **Repo:** IjonTychy/brain-ios (Public seit 28.03.2026, Unlicense)
- **Branch:** main (seit Public Release; vorher master)
- **Push:** `git push origin main`

Sicherheitsregel: Der PAT wird ausschliesslich via `$GITHUB_TOKEN` oder
`~/.git-credentials` konfiguriert. Nie in Dokumenten, Commits oder Agent-Outputs.

## Lokale Kopien

Das Projekt existiert an mehreren Orten:

| Ort | Pfad | Zweck |
|-----|------|-------|
| **GitHub** | IjonTychy/brain-ios | Source of Truth |
| **VPS** | /home/andy/brain-ios | Entwicklung (SPM Tests) |
| **Lokal (Repo)** | `André/Claude/brain-ios/` | Git Clone |
| **Lokal (Backup)** | `2nd Brain/brain-ios-backup/` | Disaster Recovery |

Nach Commits: `git push origin main`, dann auf VPS und Backup jeweils `git pull`.

## Code-Konventionen

- **Swift 6** mit strict concurrency (`-strict-concurrency=complete`)
- **SwiftUI** für alle Views — kein UIKit ausser wo nötig (PencilKit, Scanner)
- **MVVM** mit `@Observable` (Observation framework)
- **async/await** überall — kein Combine (ausser wo SwiftUI es erfordert)
- **Tests:** XCTest + Swift Testing (`@Test` macro)
- **Formatting:** swift-format (Apple)
- **UI-Texte:** Deutsch
- **Code-Kommentare:** Englisch
- **Kein Force-Unwrapping** (`!`) ausserhalb von Tests
- **Naming:** Swift API Design Guidelines (camelCase, clear at point of use)
- **Error Handling:** Typed errors wo sinnvoll, `Result` oder `throws`
- **Access Control:** Explizit — `internal` ist OK, `public` nur für Module-API

## Architektur-Entscheidungen (unveränderlich ohne explizite Freigabe)

1. **Runtime-Engine Architektur:** App ist eine Engine, keine Sammlung von Modulen. Alles wird via JSON-Skills gerendert und ausgeführt.
2. **Kein VPS** — alles lokal auf dem Gerät
3. **SwiftUI only** — kein UIKit ausser wo nötig (PencilKit, Scanner)
4. **GRDB + SQLiteData** statt SwiftData/CoreData
5. **Offline-First:** Alles funktioniert ohne Internet
6. **Multi-LLM Router:** Nie an einen Anbieter gebunden
7. **Skill-Format:** `.brainskill.md` (Markdown + YAML Frontmatter), KI kompiliert zu JSON
8. **Bootstrap-Skills:** Dashboard, Inbox, Kalender sind Skills (nicht hardcodiert)
9. **Proaktive Intelligenz:** Nativer Code, nicht JSON-getrieben (Performance-kritisch)
10. **Geschäftsmodell:** Einmalkauf, kein Abo
11. **iPhone + iPad + Vision Pro** (ein Codebase)
12. **Face ID** statt Passwort/JWT
13. **API-Keys in iOS Keychain** — nie im Binary
14. **Entry als Herzstück** — alles ist ein Entry
15. **App-Store-Konformität:** JSON ist Konfiguration, nicht Code. Alle Komponenten vorkompiliert. Kein Hot-Code-Loading.
16. **Kein eigener Skill-Marktplatz:** Offene Import/Export-Schnittstelle

## Agent-Architektur (Middle-Manager-Muster)

Du bist der "Middle Manager". Du implementierst nicht alles selbst, sondern
delegierst an spezialisierte Worker-Agents.

### Verfügbare Agents

| Agent | Modell | Aufgabe | Wann nutzen |
|-------|--------|---------|-------------|
| `arch-consultant` | Sonnet | Liest ARCHITECTURE.md und beantwortet Fragen | Jede Frage zur Architektur |
| `test-architect` | Sonnet | Tests schreiben & ausführen | Nach jedem Feature |
| `code-reviewer` | Sonnet | Pre-Commit Qualitätsprüfung | VOR jedem Commit |
| `zora-review` | Opus | Architektur-Review (extern) | Wird von Cowork getriggert |

### Pflicht-Workflow pro Implementierungsschritt

```
1. Architektur-Frage?  → Agent: arch-consultant
2. Implementieren (du selbst)
3. Tests              → Agent: test-architect
4. Pre-Commit         → Agent: code-reviewer
5. Commit (nur wenn code-reviewer OK meldet)
```

### Kontextfenster-Hygiene

- Delegiere IMMER an Agents statt selbst grosse Dateien zu lesen
- Wenn Kontext voll → Session sauber beenden, SESSION-LOG sichert Kontinuität

## Phase-Gate-Modell

### Innerhalb einer Phase (autonom):
1. Implementiere Schritt für Schritt gemäss Phasen-Scope
2. Nach jedem Schritt: Tests ausführen
3. Tests rot → Fix, wiederholen bis grün
4. Tests grün → Committen, nächsten Schritt beginnen
5. Bei Unklarheiten: SESSION-LOG dokumentieren, weitermachen wenn möglich

### Am Phasenende (manuelles Gate):
1. Alle Tests grün (oder dokumentiert warum nicht)
2. SESSION-LOG aktualisieren
3. Dokumentieren: "Phase X abgeschlossen. Bereit für Review."
4. Committen und Session beenden
5. NICHT eigenständig die nächste Phase beginnen

### Bei Session-Start:
1. STOP-SESSION.md prüfen
2. REVIEW-NOTES.md lesen → Offene Findings haben Priorität
3. SESSION-LOG.md lesen → Aktueller Stand
4. Dieses Dokument lesen → Current Objective
5. Findings abarbeiten, DANN Phasen-Scope fortsetzen

### Stop-Bedingungen:
- STOP-SESSION.md existiert
- Nativer Build-Fehler der nicht ohne Xcode lösbar ist
- Externe Dependency nicht via SPM verfügbar
- 3+ aufeinanderfolgende Testfailures ohne Fortschritt
- Scope-Erweiterung über den Auftrag hinaus

### SESSION-LOG Format:
```
## Session [Datum]
### Abgeschlossen
- **Phase X, Step Y: [Name]** (Commit `hash`) – Stichpunkte
### Entscheidungen
- [Entscheidung]: Begründung
### Tests
- [Testname]: OK/FAIL
### Offene Probleme
- [Problem]: Beschreibung
### Nächster Schritt
- Phase/Step oder "Phase X abgeschlossen. Bereit für Review."
### Systemzustand
- OK/Ausstehend
```

### Kontinuitäts-Garantie

```
Master Agent (liest nur Signale)
  └── Middle Manager Session N (startet frisch)
        ← SessionStart: CLAUDE.md + SESSION-LOG + REVIEW-NOTES
        ├── @arch-consultant   (stateless)
        ├── @test-architect    (stateless)
        ├── @code-reviewer     (stateless)
        → Stop-Hook: SESSION-LOG aktualisieren
  └── Middle Manager Session N+1 (startet frisch)
        ← Liest aktualisiertes SESSION-LOG
```

## Verfügbare Claude Code Skills (Desktop-App)

Diese Skills sind in Andys Claude Desktop-App installiert und stehen in jeder Session zur Verfügung:

| Skill | Auslöser | Zweck |
|-------|----------|-------|
| `/xcode-cloud-deploy` | Build-Fehler, TestFlight, Deployment, `brain-ios`, `com.example.brain-ios` | Xcode Cloud Workflow, bekannte Fehler, Build-Nummer erhöhen, Signing-Probleme |

## Current Objective

**Update 02.09.2026:** LLMRouter im Chat verdrahtet -- Privacy Zones und
Offline-Routing werden jetzt bei jedem Send durchgesetzt (fail-loud statt
stillem Cloud-Fallback); Auto-Route-Sticky-Bug und "on-device"-als-OpenAI-
Fehlrouting behoben. brain-api-Auth-Schicht restlos entfernt (Service, UI,
Keychain-Keys, /claude-proxy-Suffix) -- Proxy-Modus ist jetzt generisch
OpenAI-kompatibel. Zudem Provider-Auswahl in LLMProviderFactory konsolidiert:
Auch der AI-Handler-Pfad (DataBridge.buildLLMProvider) laeuft jetzt ueber den
Router; Entry-basierte Handler setzen Privacy Zones durch.
Details: SESSION-LOG 02.09.2026.

**Update 04.07.2026 (Wiederaufnahme nach Public Release):** CI repariert
(Trigger main + claude/**, pipefail, libsqlite3-dev), 2 rote Test-Assertions
gefixt, Expression-Sprache auf das dokumentierte Vokabular ausgebaut
(and/or/not, contains, matches, Array-Indexing, Datums-Mathematik,
Filter mit Argumenten), executeSet-Template-Bug behoben, actions_json wird
jetzt semantisch gegen den Handler-Katalog validiert, StoreKit-Trial in
Keychain gehaertet, Gemma-4-On-Device-Backend (Katalog + Download + Provider)
integriert, GRDB auf 7.11.1 (Linux-Fixes). Details: SESSION-LOG 04.07.2026.

### Aktueller Snapshot (04.07.2026)

Bei Konflikten gilt dieser Snapshot vor aelteren Zahlen in diesem Dokument.

- **Repo-Status:** Public Release 28.03.2026 (Unlicense): Historie gesquasht
  (2 Commits + neue Arbeit), Default-Branch `main`, alle Identifier anonymisiert
  (`com.example.brain-ios`) — fuer TestFlight/Device-Deploy muessen echte
  Bundle-IDs/App-Group/iCloud-Container wiederhergestellt werden.
- **CI:** GitHub Actions laufen wieder (main + claude/** Branches). Linux-Job
  baut BrainCore erstmals nachweisbar; iOS-Job nutzt neuestes Xcode +
  dynamische Simulator-Wahl. pipefail aktiv — keine maskierten Fehler mehr.
- **Engine:** ExpressionParser implementiert das in ARCHITECTURE.md
  dokumentierte Vokabular vollstaendig. skill.create validiert actions_json
  semantisch (wahrscheinliche Root Cause des Skill-Qualitaetsproblems behoben).
- **On-Device:** Apple Foundation Models + Gemma 4 E2B/E4B (GGUF-Katalog,
  Download nach Bedarf). Gemma-Inferenz benoetigt einmalig das
  llama.cpp-Package in Xcode (docs/ON-DEVICE-MODELS.md).
- **Datenhaltung:** App, Widgets, Share Extension und App Intents greifen ueber
  `SharedContainer` auf dieselbe SQLite-Datei im App-Group-Container zu.
- **LLM-Stack:** Anthropic, OpenAI, Gemini, On-Device (Apple + Gemma) sowie
  xAI/custom ueber `OpenAICompatibleProvider`.
- **Verifizierte Repo-Metriken (03.07.):** 216 getrackte Swift-Dateien,
  ~53'400 LOC, 590 `@Test`-Funktionen, 6 gebuendelte `.brainskill.md`.
- **Erledigt (Doku war veraltet):** Mail-Delete-Sync (Tombstones + IMAP-Expunge)
  und StoreKit (StoreKit 2, Trial + Einmalkauf) sind implementiert.
- **Offene Baustellen:** Echte Bundle-IDs wiederherstellen, llama.cpp-Package
  aktivieren, Device-Verifikation (OAuth, Runtime-Fixes, Gemma), God Objects
  wieder splitten (OnboardingView, MailTabView). LLM-Routing ist seit 02.09.2026
  konsolidiert (LLMProviderFactory): Chat- und AI-Handler-Pfad laufen ueber den
  LLMRouter mit Privacy-/Offline-Gate.

**Historischer Snapshot 23.03.2026:** App ist funktional, TestFlight aktiv, 540+ Tests grün.
Google OAuth, Multi-Provider (7 LLM Provider), modularer System-Prompt.
Grosse Dateien aufgeteilt (4 God Objects eliminiert), ~960 Zeilen Dead Code/Duplikate entfernt.
23 Bridges, 158+ Handler, 121+ Tools, 7 LLM Provider, 160+ Commits.

### App Store Readiness

| Bereich | Status |
|---------|--------|
| **Code & Features** | Weitgehend komplett; Runtime-Fixes vom 25.03 muessen noch auf Device/Xcode verifiziert werden |
| **TestFlight** | Aktiv, Builds laufen |
| **Onboarding** | 9-seitiger Flow (Multi-Provider, API-Key/OAuth, Mail, Permissions, Kennenlernen) |
| **Voice Input** | Mikrofon-Button im Chat mit Live-Transkription |
| **Ethiksystem** | Gebundelte Dokumente (Axiome + Alignment), System-Prompt-Referenz |
| **System-Prompt-Editor** | Editierbar in Einstellungen → Erweitert, Reset auf Standard |
| **Two-Way Binding** | Implementiert (SkillRendererInput.swift) |
| **Error-Handling UI** | Error-Banner in SkillView |
| **Lokalisierung** | LocalizationService mit L(), 60+ Keys, DE + EN |
| **Privacy Policy URL** | Live: your-domain.example.com/privacy (Google OAuth, Proxy/VPS dokumentiert) |
| **Support URL** | Live: your-domain.example.com/support (Butler-Konzept, Skills-FAQ, Proxy-FAQ) |
| **Landing Page** | Live: your-domain.example.com (Features, DNA-Flow, Privacy-Grid) |
| **App Store Description** | Vorhanden in docs/APP-STORE-METADATA.md |
| **PrivacyInfo.xcprivacy** | Vorhanden |
| **Screenshots** | Ausstehend (Marketing) |
| **StoreKit** | Implementiert (StoreKit 2: 30-Tage-Trial in Keychain + Einmalkauf, PaywallView); Produkt-Konfiguration in App Store Connect ausstehend |

### Aktuelle Prioritaeten (04.07.2026)

| Priorität | Thema | Beschreibung |
|-----------|-------|-------------|
| **Hoch** | Deploy-Faehigkeit | Echte Bundle-IDs/App-Group/iCloud-Container wiederherstellen (Public-Release-Anonymisierung rueckgaengig fuer den privaten Build), Xcode Cloud reaktivieren |
| **Hoch** | CI vollstaendig gruen | BrainCore-Linux + iOS-Build auf main stabil halten (Feedback-Loop etabliert 04.07.) |
| **Mittel** | Gemma aktivieren | llama.cpp-Package in Xcode hinzufuegen (docs/ON-DEVICE-MODELS.md), auf Device verifizieren |
| **Mittel** | Device-Verifikation | OAuth, Runtime-Fixes vom Maerz, Skill-Erstellung mit neuem Expression-Vokabular |
| **Mittel** | God Objects splitten | OnboardingView (1255 Z.), MailTabView (1193 Z.), EmailBridge (1045 Z.), SkillManagerView (876 Z.) |
| **Niedrig** | Screenshots | App Store Screenshots erstellen |
| **Niedrig** | CloudKit Sync / Vision Pro | Bei Bedarf aktivieren bzw. fertigstellen |

Siehe SESSION-LOG für letzten Stand und offene Punkte.

## Phasen-Übersicht (alle abgeschlossen)

| Phase | Name | Status |
|-------|------|--------|
| **0** | Projekt-Setup | ✅ |
| **1** | Core Foundation | ✅ |
| **2** | Render Engine | ✅ |
| **3** | Action & Logic Engine | ✅ |
| **4** | LLM Router & Skill Compiler | ✅ |
| **5** | iOS Bridges | ✅ |
| **6** | Bootstrap Skills | ✅ |
| **7** | Advanced Skills | ✅ |
| **8** | Proaktive Intelligenz | ✅ |
| **9** | System-Integration | ✅ |
| **10** | On-Device LLM | ✅ |
| **11** | Family & Sync (CloudKit) | ✅ |
| **12** | Vision Pro | ✅ |
| **13** | Migration & Polish | ✅ |
| **14** | Assessment & Audit | ✅ |
| **17** | TestFlight-Ready | ✅ |
| **18** | Tool-Use | ✅ |
| **19** | Proaktive Intelligenz (v2) | ✅ |
| **20** | Apple Shortcuts & Siri | ✅ |
| **21** | Share Extension & Widgets | ✅ |
| **22** | Search UI & Chat UX | ✅ |
| **23** | On-Device LLM & NLP | ✅ |
| **24** | Skills-Ökosystem | ✅ |
| **30** | LLM Kosten-Kontrolle | ✅ |
| **31** | Privacy Zones | ✅ |
| **B1–B4** | Bundling, Chat-Skills, Semantic Search, Rules UI | ✅ |
| — | Mail-App (Multi-Account, Detail, Compose) | ✅ |
| — | Conversation Memory | ✅ |
| — | Security Audit + Fixes | ✅ |

## Bekannte Probleme

- **Runtime-Fixes noch nicht auf Device verifiziert:** Kontakte-Tab, Skills, Skill-Import/Kompilierung,
  Self-Improve-Handoff und Shortcuts/App-Intents wurden code-seitig repariert, aber in dieser
  Umgebung nicht via Xcode/iOS-Geraet getestet.
- **BrainTheme nur teilweise ausgerollt:** Design-System existiert, wird aber noch nicht
  durchgaengig in allen produktiven Views genutzt.
- **Primitive-Luecke:** Wenn ein Skill ein Action Primitive braucht das nicht existiert, braucht es
  ein App-Update.
- **64 Notification Limit:** Reschedule-on-Launch Pattern.
- **Anonymisierte Identifier:** Seit dem Public Release stehen ueberall
  `com.example.brain-ios`-Platzhalter (Bundle-IDs, App Group, iCloud, BGTasks) —
  ohne Wiederherstellung echter IDs kein TestFlight/Device-Deploy.
- **Gemma-Inferenz noch nicht aktiv:** Provider/Katalog/Downloads sind eingebaut;
  das llama.cpp-Package muss einmalig in Xcode hinzugefuegt und auf einem Geraet
  verifiziert werden (docs/ON-DEVICE-MODELS.md).
- **Rohtext ohne Privacy-Provenance:** ai.draftReply und llm.*-Handler erhalten
  reinen Text und koennen kein Entry-basiertes Privacy-Level ableiten (laufen
  unrestricted); Chat- und Entry-basierte Handler-Pfade sind seit 02.09.2026
  ueber den LLMRouter abgesichert.
- **Google OAuth braucht User-Setup:** PKCE Flow, Token-Refresh und Keychain-Storage sind
  implementiert; die Client-ID muss weiterhin vom User in Google Cloud Console erstellt werden.
- **brain-api abgeschaltet:** VPS-Backend nicht mehr aktiv. Backup unter
  `/home/andy/brain-api-backup/`.
- **User-Profil-Import ausstehend:** `brain-profil.md` + `user-profil.md` unter
  `/home/andy/brain-api-backup/` bereit.
- **Background Fetch unzuverlaessig:** Shortcuts Automations bleiben der Backup-Pfad.

## Projekt-Inventar

### Repo-Struktur

```
brain-ios/
├── ARCHITECTURE.md              # Architektur & Vision (Single Source of Truth)
├── CLAUDE.md                    # Projektsteuerung (dieses Dokument)
├── SESSION-LOG.md               # Session-Journal (Phase 17+)
├── REVIEW-NOTES.md              # Review-Protokoll (2 Gross-Reviews, 40+ Findings)
├── Package.swift                # SPM Package Definition (BrainCore)
├── BrainApp.xcodeproj/          # Xcode Projekt
├── Sources/
│   ├── BrainCore/               # SPM Package (auch auf Linux testbar)
│   └── BrainApp/                # iOS App (SwiftUI Views, Bridges, Services, Onboarding/, LLMProviders/)
├── Tests/                       # BrainCoreTests + BrainAppTests
├── Skills/                      # 6 .brainskill.md Dateien plus Prompt-Assets
├── ci_scripts/                  # Xcode Cloud Build-Scripts
├── .github/workflows/           # GitHub Actions CI (tests.yml + ios-build.yml)
├── docs/archive/                # Archivierte Plandokumente
└── .claude/
    ├── settings.json            # Hooks (SessionStart, PreToolUse, Stop)
    └── agents/                  # arch-consultant, test-architect, code-reviewer, zora-review
```

### Inventar-Update (25.03.2026)

- **Swift-Dateien:** 215 getrackte `.swift`-Dateien im Repo
- **Tests:** 579 `@Test(...)`-Marker in `Sources/` und `Tests/`
- **Commits:** 502 Commits in `HEAD`
- **Skills:** 6 gebuendelte `.brainskill.md`-Dateien in `Skills/`
- **LLM-Provider-Dateien:** `AnthropicProvider`, `GeminiProvider`, `OpenAIProvider`,
  `OpenAICompatibleProvider`, `OnDeviceProvider`
- **Provider-Stack fachlich:** Anthropic, OpenAI, Gemini, On-Device sowie xAI/custom ueber
  `OpenAICompatibleProvider`

### Historische Kennzahlen (Stand 23.03.2026)

- **Commits:** 160+
- **Tests:** 540+ (BrainCore + BrainApp, alle grün)
- **Gebundelte Dokumente:** Ethiksystem + Alignment-Ableitung (als Entries importiert)
- **Skills:** 3 .brainskill.md Dateien
- **Swift-Dateien:** 190+ (BrainApp: 100+, BrainCore: 46, Tests: 34)
- **UI Primitives:** ~90
- **Action Handler Klassen:** ~158 (in 10 Handler-Dateien + Bridge-Dateien)
- **iOS Bridges:** 23
- **Tool-Definitionen:** 121
- **LLM Provider:** 7 (Anthropic, OpenAI, Gemini, xAI Grok, Custom, OnDevice, Shortcuts)
- **Logic Primitives:** ~15
- **App Intents (Siri/Shortcuts):** 12
- **Xcode Cloud Builds:** 234+ (Frontend Overhaul Session)
- **TestFlight:** Aktiv
