# brain-ios — Umfassendes Assessment & Audit

**Datum:** 23. Maerz 2026 | **Codebase:** ~34'000 LOC | **Tests:** 467 | **Builds:** 182+

---

## 1. User-Sicht

### Was der User sieht
- **5 Haupt-Tabs** (Dashboard, Suche, Mail, Chat, Kalender) + Mehr-Tab (Kontakte, Dateien, Karte, On This Day, Brain Admin)
- **iPad:** NavigationSplitView mit Sidebar
- **Onboarding:** 7-seitiger Flow (Willkommen → Features → Privacy → API-Key → Mail → Berechtigungen → Erste Erfassung)
- **Chat:** Multi-LLM mit Model-Picker, Tool-Use-Visualisierung, Streaming
- **Skill-Manager:** 24 installierte Skills, Import/Export, Self-Modifier-Vorschlaege

### Staerken
- Offline-First: Alles funktioniert ohne Internet
- Einheitliches Suchfeld ueber alle Inhalte (FTS5 + Typ-Filter)
- Schnellerfassung direkt auf dem Dashboard
- Swipe-Gesten in Mail und Suche (iOS-nativ)
- Dark Mode automatisch via SwiftUI

### Schwaechen
- **Kein Rich-Text-Editor** (nur Basic-Markdown)
- **Input-Binding unvollstaendig** — TextField in JSON-Skills sind read-only (`.constant()`)
- **Kein Offline-Indikator** — User weiss nicht ob er online/offline ist
- **Skill-Oekosystem klein** — 24 Skills, davon ~3-5 voll funktional
- **Visuelle Inkonsistenz** — Native SwiftUI-Views vs. JSON-gerenderte Skills

---

## 2. Ingenieur-Sicht

### Architektur: 9/10
- **Zwei-Schichten-Trennung** sauber eingehalten (JSON-Skills vs. native Proaktive Intelligenz)
- **BrainCore/BrainApp-Grenze** strikt — BrainCore importiert kein SwiftUI, laeuft auf Linux
- **Alle 16 Architektur-Entscheidungen** aus ARCHITECTURE.md eingehalten
- **Erweiterbarkeit:** Neues UI-Primitive = 3-4 Dateien, ~1h. Neuer Handler = 2 Dateien, ~30min. Neuer LLM-Provider = 3-4 Dateien, ~2-3h.

### Kennzahlen

| Metrik | Wert |
|--------|------|
| Swift-Dateien | 165 (BrainCore: 46, BrainApp: 90, Tests: 31) |
| UI Primitives | 90 registriert, ~85 renderbar |
| Action Handlers | 153 implementiert |
| iOS Bridges | 23 |
| LLM Provider | 5 (Anthropic, OpenAI, Gemini, OnDevice, Shortcuts) |
| Tool-Definitionen | 121 |
| App Intents (Siri) | 12 |
| DB-Tabellen | 18 (14 Core + 4 Migrations) |
| Tests | 467 @Test-Methoden |
| Dependencies | 3 (GRDB, swift-crypto, swift-asn1) — minimal |

### Test-Coverage
- **BrainCore:** Exzellent (467 Tests, alle Module abgedeckt)
- **BrainApp:** Minimal (15 Handler-Tests, kein Renderer-Test, keine Bridge-Tests)
- **Gap:** ~20-30h Arbeit fuer umfassende BrainApp-Tests

---

## 3. Sicherheit: Note A-

| Bereich | Status | Details |
|---------|--------|---------|
| **API-Keys** | SICHER | Keychain mit Biometrie, keine Hardcoded Secrets |
| **Netzwerk** | STARK | Echtes SPKI-Pinning (RFC 7469), HTTPS-only, 4 Hosts gepinnt |
| **SQL-Injection** | GESCHUETZT | 100% parametrisierte Queries via GRDB |
| **Path-Traversal** | GESCHUETZT | Sandbox-Check auf allen File-Operationen |
| **Input-Validierung** | GUT | Titel max 500, Body max 10'000, API-Key-Prefix-Check |
| **Privacy Zones** | IMPLEMENTIERT | Tag-basiertes LLM-Routing (onDevice/approvedCloud/unrestricted) |
| **Logs** | SICHER | os.log (kein print), keine Secrets in Fehlermeldungen |
| **Dependencies** | MINIMAL | Nur GRDB + swift-crypto (Apple-Pakete) |

### Offene Findings

| Severity | Finding | Empfehlung |
|----------|---------|-----------|
| MEDIUM | TOFU-Pins in UserDefaults statt Keychain | Vor App Store Release nach Keychain migrieren |
| LOW | Secure Enclave Proof nach Biometrie-Auth (TODO) | Nice-to-have fuer v2 |
| LOW | 2 `try!` (ExpressionParser Regex, BrainApp Fallback-DB) | guard let verwenden |

### OWASP/CWE Compliance
Kein SQL-Injection, kein XSS, keine Hardcoded Secrets, kein schwaches Crypto

---

## 4. Vergleich mit aehnlichen Applikationen

```
                AI-First                    Knowledge-First
         +====================+         +===================+
Privacy  |  * brain-ios *     |         |  Obsidian         |
First    |                    |         |                   |
         +====================+         +===================+
         +====================+         +===================+
Cloud    |  ChatGPT App       |         |  Notion           |
Centric  |  Reflect, Mem      |         |  Capacities       |
         +====================+         +===================+
```

| Dimension | brain-ios | Obsidian | Notion | Reflect | ChatGPT |
|-----------|----------|----------|--------|---------|---------|
| Offline | Voll | Voll | Cloud | Hybrid | Cloud |
| AI-Chat | Multi-LLM | Nein | Basic | Basic | Voll |
| Erweiterbar | Skills | Plugins | Templates | Nein | Plugins |
| Privacy | Lokal | Lokal | Cloud | SaaS | Cloud |
| Rich Text | Basic | Voll | Voll | Voll | Nein |
| Collaboration | Nein | Nein | Voll | Nein | Nein |
| Web-App | Nein | Publish | Ja | Ja | Ja |
| Preis | TBD | $50 | Free/$12/mo | Free/$10/mo | Free/$20/mo |

### Alleinstellungsmerkmale von brain-ios
1. **Runtime-Engine** — KI generiert neue Features ohne App-Update
2. **Multi-LLM + Offline** — 5 Provider, funktioniert ohne Internet
3. **Privacy Zones** — Tag-basiertes LLM-Routing (einzigartig am Markt)
4. **Sensor-Bridges** — 23 iOS-Framework-Anbindungen (Phyphox-artig)
5. **Self-Modifier** — App schlaegt eigene Verbesserungen vor

### Was fehlt vs. Konkurrenz
- Kein Rich-Text-Editor (vs. Notion/Obsidian)
- Kein Web-Interface (vs. Notion/Reflect)
- Keine Collaboration (vs. Notion)
- Kleines Skill-Oekosystem (vs. Obsidian Community Plugins)

---

## 5. Funktionsumfang & Loesungsansatz

### Loesungsansatz: Bewertung 9/10
Die "Runtime-Engine"-Idee ist **genuinely novel**. JSON als Konfiguration (nicht Code) ist App-Store-konform (Airbnb, Uber machen dasselbe). Die Zwei-Schichten-Architektur trennt sauber zwischen "was der User sieht" (JSON) und "was das Brain denkt" (nativ).

### Funktionsumfang: 8/10
- **Vollstaendig:** Entry CRUD, Suche, Mail (Multi-Account), Kalender, Kontakte, Chat mit Tool-Use, Proaktive Analyse, Widgets, Siri Shortcuts, Share Extension
- **Grundlage steht:** Skills, Knowledge Facts, Rules Engine, Improvement Proposals
- **Unvollstaendig:** Rich-Text-Editor, Knowledge-Graph-Visualisierung, Two-Way-Binding in Skills

---

## 6. Code-Hygiene: Note B+

| Kriterium | Status | Details |
|-----------|--------|---------|
| Force-Unwraps | 2 Stellen | `try!` in ExpressionParser + BrainApp |
| @unchecked Sendable | 25 Stellen, alle dokumentiert | Konsistente Kommentare |
| nonisolated(unsafe) | 9 Stellen, alle sicher | SpeechBridge marginal |
| Leere catch-Bloecke | 0 | Exzellent |
| print() Statements | 0 | Alles os.log |
| TODO/FIXME | 4 Stueck | Alle dokumentiert mit Sprint-Referenz |
| Groesste Datei | ToolDefinitions.swift: 1702 Zeilen | Kandidat fuer Split |
| Duplicate Code | Minimal | 1-2 kleine Patterns |
| Dead Code | 0 gefunden | Alles aktiv genutzt |

---

## 7. Code-Qualitaet: Note A-

| Kriterium | Score |
|-----------|-------|
| Modul-Grenzen | 9/10 |
| Erweiterbarkeit | 8/10 |
| Testbarkeit | 7/10 (BrainCore exzellent, BrainApp minimal) |
| Error Handling | 8/10 (Typed ActionError, strukturierte Fehler) |
| Concurrency | 8/10 (Swift 6 strict, @MainActor konsistent) |
| Dokumentation | 8/10 (ARCHITECTURE.md vorbildlich) |

---

## 8. Zukunftsfaehigkeit: Note A

| Aspekt | Bewertung |
|--------|-----------|
| **Swift 6 Strict Concurrency** | Vollstaendig (async/await, Sendable) |
| **Vision Pro** | Infrastruktur steht (VisionProSupport.swift, conditional compilation) |
| **On-Device LLM** | Apple Foundation Models (iOS 26+) mit Fallback |
| **CloudKit Sync** | Abstraktionsschicht bereit (CloudKitSync.swift) |
| **100k Entries** | Machbar (FTS5, WAL-Modus, Batch-Analyse) — 2-3 fehlende Indizes ergaenzen |
| **Neue LLM-Provider** | Protocol-basiert, ~2-3h Integration |
| **Skill-Oekosystem** | Format definiert (.brainskill.md), Import/Export funktioniert |

---

## 9. Konkurrenzfaehigkeit

### Zielgruppe
**Privacy-bewusste Power-User** die ihre Daten lokal behalten wollen und bereit sind, eigene API-Keys zu konfigurieren. Nicht fuer: Teams, Casual-User, Collaboration-Szenarien.

### Marktposition
- **Staerke:** Einzige App die Offline-First + Multi-LLM + Runtime-Engine + Privacy Zones kombiniert
- **Schwaeche:** Kleines Oekosystem, kein Web, kein Team-Feature
- **Geschaetzter TAM:** 50'000-200'000 User global (Obsidian-aehnliche Nische)

### Risiken
1. **"API-Key selber mitbringen"** — Hohe Einstiegshuerde fuer Nicht-Techniker
2. **App Store Review** — "Runtime Engine" koennte Fragen aufwerfen (Argumentation steht aber)
3. **Skill-Qualitaet** — LLM-generierte Skills koennen inkonsistent sein

---

## 10. Akzeptabler Preis

### Empfehlung: **CHF 49 Einmalkauf** (Obsidian-Paritaet)

**Begruendung:**
- Keine Server-Kosten fuer den Entwickler (Offline-First)
- User traegt eigene LLM-Kosten (~CHF 2-5/Monat bei normalem Gebrauch)
- Vergleichbar mit Obsidian ($50 one-time)
- Deutlich guenstiger als Reflect/Capacities ($10-12/Monat = CHF 120-144/Jahr)

**Langfristige Option:** CHF 49 Basis + optional CHF 10/Monat "Brain Plus" fuer:
- Skill-Generierung via Cloud-LLM
- Proaktive Analyse mit groesseren Modellen
- CloudKit Family Sync (wenn implementiert)

---

## Gesamturteil

| Perspektive | Note | Kommentar |
|-------------|------|-----------|
| **User** | B+ | Solide Kernfunktionen, UX-Polish noetig |
| **Ingenieur** | A | Saubere Architektur, exzellente Erweiterbarkeit |
| **Sicherheit** | A- | Professionell, 1 MEDIUM Finding |
| **Wettbewerb** | B+ | Einzigartiger Ansatz, Feature-Luecken vs. Platzhirsche |
| **Funktionsumfang** | A- | Breit und tief, wenige Luecken |
| **Code-Hygiene** | B+ | Sauber, 2 Force-Unwraps, 2 grosse Dateien |
| **Code-Qualitaet** | A- | Swift 6, typed errors, gute Patterns |
| **Zukunftsfaehigkeit** | A | Vision Pro, CloudKit, On-Device LLM vorbereitet |
| **Konkurrenzfaehigkeit** | B+ | Nische gut besetzt, Oekosystem klein |
| **Preis** | ok | CHF 49 Einmalkauf empfohlen |

**Gesamtnote: A-** — Produktionsreif fuer TestFlight, App-Store-Ready mit kleinen Fixes (TOFU-Pins, Force-Unwraps, DB-Indizes).
