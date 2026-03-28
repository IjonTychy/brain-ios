# brain-ios — Security Audit & Deep Assessment

## Datum: 2026-03-19

## Auditor: Claude Opus 4.6 (Zora), im Auftrag von Andy

## Scope: Vollständige Codebase (~12.600 LOC, 97 Swift-Dateien)

---

## Zusammenfassung

brain-ios ist ein ambitioniertes, architektonisch durchdachtes Projekt mit einer soliden Grundstruktur. Die Offline-First-Architektur, die saubere BrainCore/BrainApp-Trennung und die konsequente Verwendung von Swift 6 Concurrency sind Stärken. Die Keychain-Nutzung für Secrets und die GRDB-parametrisierte SQL-Nutzung zeigen Security-Bewusstsein.

**Jedoch gibt es kritische Lücken**, vor allem im Zusammenspiel von LLM-Agent und sensiblen Daten. Die grössten Risiken liegen nicht in klassischen Schwachstellen (SQL-Injection, XSS), sondern in der **LLM-Agent-Sicherheit**: Das System erlaubt dem LLM, E-Mails zu senden, Kontakte anzulegen, Einträge zu löschen und auf GPS/Kalender/E-Mail zuzugreifen — alles ohne Benutzerbestätigung und ohne Datensanitisierung. Ein einziger Prompt-Injection-Angriff (z.B. über eine empfangene E-Mail) könnte katastrophale Auswirkungen haben.

Certificate Pinning ist ein reiner Stub — kein einziger Pin-Hash ist implementiert. Die biometrische Authentifizierung ist auf Jailbroken Devices trivial umgehbar. Sensible Daten fliessen ungefiltert an Cloud-LLMs.

**Gesamtbewertung: Die lokale Datenhaltung ist gut geschützt, aber die LLM-Agent-Schnittstelle ist ein offenes Scheunentor.**

---

## Kritische Findings

### 🔴 F-01: Certificate Pinning ist ein Stub — kein echtes Pinning

**Datei:** `Sources/BrainApp/LLMProviders/CertificatePinning.swift:47-50`

```swift
// Full SPKI hash pinning is deferred to config-driven approach
completionHandler(.useCredential, URLCredential(trust: serverTrust))
```

Die Klasse `PinnedURLSession` mit dem Set `pinnedHosts` suggeriert Sicherheit, implementiert aber **null Pin-Hashes**. Es wird nur die Standard-TLS-Validierung durchgeführt, die iOS ohnehin macht. Ein MITM-Angriff mit einem CA-signierten Zertifikat (Corporate Proxy, kompromittierte CA, staatlicher Akteur) fängt alle API-Keys und Konversationen im Klartext ab.

**Betroffen:** Alle API-Kommunikation mit Anthropic, OpenAI, Gemini.

**Realistischer Angriffsvektor:** Corporate WiFi mit SSL-Inspection-Proxy → alle API-Keys abgegriffen.

---

### 🔴 F-02: E-Mail-Passwort fliesst durch den LLM-Kontext

**Datei:** `Sources/BrainApp/ToolDefinitions.swift:454`

```swift
"password": ["type": "string", "description": "Passwort oder App-Passwort"],
```

Das `email_configure` Tool akzeptiert IMAP/SMTP-Passwörter als Parameter. Wenn ein Nutzer sagt "Konfiguriere meine E-Mail mit Passwort X", wird dieses Passwort im Klartext an die Anthropic API gesendet, dort verarbeitet und möglicherweise in Logs gespeichert. E-Mail-Credentials dürfen **niemals** durch einen LLM-Kanal fliessen.

**Realistischer Angriffsvektor:** Normaler Nutzungsfall — User konfiguriert E-Mail über Chat.

---

### 🔴 F-03: LLM kann E-Mails senden ohne Benutzerbestätigung

**Datei:** `Sources/BrainApp/ToolDefinitions.swift:409-421`, `Sources/BrainApp/ChatService.swift:106-116`

Das `email_send` Tool erlaubt dem LLM, E-Mails an beliebige Empfänger mit beliebigem Inhalt zu senden. Der System-Prompt instruiert "Tu es SOFORT" — es gibt keinen Bestätigungsdialog. Kombiniert mit der Tool-Loop (bis zu 10 Runden pro Nachricht) kann eine einzige Prompt-Injection in einer empfangenen E-Mail eine Kaskade auslösen.

**Realistischer Angriffsvektor:** Angreifer sendet E-Mail mit versteckter Prompt-Injection → User lässt Brain die E-Mail lesen → LLM wird instruiert, vertrauliche Daten per E-Mail an den Angreifer zu senden.

---

### 🔴 F-04: Sensitive-Data-Routing ist Fake — ChatService umgeht LLMRouter

**Datei:** `Sources/BrainApp/ChatService.swift:201-209`

```swift
// ChatService.buildProvider() instanziiert direkt AnthropicProvider
```

Der sorgfältig designte `LLMRouter` mit seiner `containsSensitiveData`-Logik wird vom `ChatService` — der primären Nutzer-Interaktion — komplett umgangen. Alle Anfragen gehen direkt an Anthropic, unabhängig von Sensitivität, Konnektivität oder Nutzereinstellungen. Das `containsSensitiveData`-Flag wird zudem nie auf `true` gesetzt.

**Folge:** Kontakte, E-Mails, Kalender, GPS-Daten — alles wird ungefiltert an Anthropic gesendet, auch wenn der Nutzer "Sensible Daten nur On-Device" konfiguriert hat.

---

### 🔴 F-05: Keine Benutzerbestätigung für destruktive LLM-Aktionen

**Dateien:** `Sources/BrainApp/ToolDefinitions.swift`, `Sources/BrainApp/ChatService.swift`, `Sources/BrainApp/Bridges/*.swift`

Folgende Aktionen werden ohne jede Bestätigung ausgeführt:
- `email_send` — E-Mails senden
- `entry_delete` — Einträge permanent löschen
- `calendar_create` / `calendar_delete` — Kalendereinträge erstellen/löschen
- `contact_create` — Kontakte anlegen
- `reminder_schedule` — Erinnerungen setzen

Kombiniert mit der 10-Runden-Tool-Loop kann eine Prompt-Injection eine zerstörerische Kaskade auslösen: E-Mails lesen → Daten exfiltrieren → Einträge löschen → falsche Kalendereinträge erstellen.

**Realistischer Angriffsvektor:** Prompt-Injection via empfangener E-Mail, Kontakt-Notiz oder importiertem Skill.

---

## Hohe Findings

### 🟠 F-06: Kein Jailbreak-Schutz für Biometrie

**Datei:** `Sources/BrainApp/BiometricAuth.swift`

Auf einem Jailbroken Device kann `LAContext.evaluatePolicy` trivial mit Frida oder Liberty Lite gehookt werden, sodass immer `true` zurückgegeben wird. Die Authentifizierung basiert auf einem einfachen Boolean — kein kryptographischer Beweis, keine Secure-Enclave-Bindung.

**Mitigation:** Biometrie an Secure-Enclave-Key-Operation binden. Dann ist der Beweis nicht fälschbar.

---

### 🟠 F-07: Keine Keychain Access Control (ACL) für API-Keys

**Datei:** `Sources/BrainApp/KeychainService.swift:23-29`

Keychain-Items verwenden `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (gut), aber **kein** `kSecAttrAccessControl` mit `SecAccessControlCreateWithFlags`. Jeder Code im App-Prozess kann API-Keys lesen — auf einem Jailbroken Device auch injizierter Code.

**Empfehlung:** `SecAccessControl` mit `.biometryCurrentSet` für API-Keys.

---

### 🟠 F-08: Keine Datensanitisierung zwischen Bridges und LLM-Kontext

**Dateien:** Alle Bridge-Dateien in `Sources/BrainApp/Bridges/`

Kein einziger Bridge sanitisiert, kürzt oder redaktiert seine Ausgabe bevor sie in den LLM-Kontext injiziert wird:
- Volle E-Mail-Bodies (inklusive Passwörter, Tokens, vertrauliche Inhalte)
- Komplette Kontaktdaten (Name, Telefon, Adresse, E-Mail)
- Präzise GPS-Koordinaten
- Kalenderdetails (Meetings, Teilnehmer, Notizen)

All dies wird unmodifiziert an die Anthropic API gesendet.

---

### 🟠 F-09: FTS5 Query Injection

**Datei:** `Sources/BrainCore/Services/SearchService.swift:29, 90, 123, 143`

FTS5 hat eine eigene Query-Sprache. User-Input wird nicht für FTS5-Syntax sanitisiert. Operatoren wie `AND`, `OR`, `NOT`, `NEAR`, `*`, `"`, Spaltenfilter (`title:`) werden direkt durchgereicht. Besonders kritisch: `autocomplete()` konkateniert User-Input mit `*`.

**Risiko:** Denial-of-Service (malformierte FTS5-Queries → Crash), Column-targeted Searches, teure Scans.

---

### 🟠 F-10: App Intents exfiltrieren Daten ohne Authentifizierung

**Datei:** `Sources/BrainApp/BrainIntents.swift:100-218`

`SearchBrainIntent`, `ListTasksIntent` und `DailyBriefingIntent` geben Eintrags-Titel und Inhalte zurück — mit `openAppWhenRun = false`. Diese Intents sind für jedes Shortcut zugänglich, auch von Dritten. Kein Face ID, keine Bestätigung, kein Rate Limiting.

**Realistischer Angriffsvektor:** Bösartiger Shortcut (geteilt via iMessage) durchsucht alle Brain-Einträge nach sensiblen Begriffen.

---

### 🟠 F-11: Unbeschränkte Tool-Execution-Loop

**Datei:** `Sources/BrainApp/LLMProviders/AnthropicProvider.swift:136`

```swift
for _ in 0..<10 {
```

Pro User-Nachricht kann der LLM bis zu 10 Runden mit jeweils multiplen Tool-Calls ausführen. Ohne Per-Action-Consent und ohne Rate-Limiting innerhalb eines Turns.

---

### 🟠 F-12: LogicInterpreter hat kein Rekursionslimit

**Datei:** `Sources/BrainCore/Engine/LogicInterpreter.swift:16-29, 61-85, 146-156`

`execute(step:context:)` ruft sich selbst rekursiv auf für `if`, `forEach` und `sequence` — ohne Tiefenlimit. Im Gegensatz zum `ExpressionParser` (depth < 20) hat der `LogicInterpreter` keinen solchen Guard. Ein bösartiges Skill-File kann Stack Overflow verursachen.

---

### 🟠 F-13: forEach ohne Iterations-Limit

**Datei:** `Sources/BrainCore/Engine/LogicInterpreter.swift:89-117`

Die `forEach`-Logik iteriert über Arrays ohne Obergrenze. Kein Iterationscap, kein Timeout, kein `Task.checkCancellation()`. Ein Skill mit einer Datenbankabfrage die tausende Einträge zurückgibt friert die App ein.

---

### 🟠 F-14: web-view Primitive erlaubt beliebige URLs

**Datei:** `Sources/BrainCore/Engine/ComponentRegistry.swift:217`

Die `web-view` Primitive validiert keine URL-Schemas. `javascript:`, `file:///` oder Phishing-Domains werden nicht blockiert. Die `ComponentRegistry.validateNode()` prüft nur strukturelle Korrektheit, nicht Property-Werte.

**Hinweis:** Im `SkillRenderer` ist JavaScript deaktiviert und nur HTTPS erlaubt (positiv!). Aber die Registry-Ebene hat keinen Schutz — die Renderer-Checks könnten umgangen werden wenn ein alternativer Render-Path hinzukommt.

---

## Mittlere Findings

### 🟡 F-15: Gemini-Host fehlt im Pinning-Set

**Datei:** `Sources/BrainApp/LLMProviders/CertificatePinning.swift:13-16`

`pinnedHosts` enthält `api.anthropic.com` und `api.openai.com`, aber **nicht** `generativelanguage.googleapis.com` — obwohl `KeychainService` einen `geminiAPIKey` definiert. Auch wenn echtes Pinning implementiert wird, bleibt Gemini-Traffic ungeschützt.

---

### 🟡 F-16: LIKE-Pattern Injection in mehreren Services

**Dateien:** `Sources/BrainCore/Services/TagService.swift:84,97`, `Sources/BrainApp/Bridges/EmailBridge.swift:100-113`, `Sources/BrainApp/ConversationMemory.swift:26-27,77`

SQL LIKE-Wildcards (`%`, `_`) im User-Input werden nicht escaped. `%` als Suchbegriff matched alles.

---

### 🟡 F-17: RulesEngine — Unparsbare Conditions matchen immer

**Datei:** `Sources/BrainCore/Services/RulesEngine.swift:64-69`

Wenn `condition` JSON `nil` ist oder Parsing fehlschlägt, wird die Rule als "immer zutreffend" behandelt (`return true`). Eine korrupte oder bösartig gestaltete Condition feuert die zugehörige Action unkonditioniert.

---

### 🟡 F-18: ChatMessage.role ist ein roher String

**Datei:** `Sources/BrainCore/Models/ChatMessage.swift:6`

`role` ist `String` statt ein closed Enum. Wenn Chat-History an den LLM gesendet wird, könnte ein Eintrag mit `role: "system"` und manipuliertem Content die System-Instructions überschreiben (Stored Prompt Injection).

---

### 🟡 F-19: Widget zeigt Task-Titel auf Lock Screen

**Datei:** `Sources/BrainWidgets/BrainWidgets.swift:152-197`

`TasksWidgetView` zeigt Task-Titel, die auf dem Lock Screen sichtbar sind. Die Haupt-App hat Face ID, aber Widgets umgehen das komplett. Sensible Titel wie "Arzttermin" oder "Anwalt wegen Scheidung" sind für jeden sichtbar der das Gerät aufhebt.

---

### 🟡 F-20: Siri-Frage via UserDefaults (unverschlüsseltes IPC)

**Datei:** `Sources/BrainApp/BrainIntents.swift:259`, `Sources/BrainApp/ContentView.swift:36-46`

`AskBrainIntent` speichert die User-Frage in `UserDefaults.standard` — unverschlüsselt, auf Disk persistiert. Sensible Fragen überdauern App-Neustarts und sind bei unverschlüsselten Backups lesbar.

---

### 🟡 F-21: Race Conditions in LocationBridge und NFCBridge

**Dateien:** `Sources/BrainApp/Bridges/LocationBridge.swift:37-42`, `Sources/BrainApp/Bridges/NFCBridge.swift:25-26`

`isRequestInFlight` und `locationContinuation` bzw. `readContinuation` sind nicht synchronisiert. Concurrent Access kann zu doppeltem Continuation-Resume (Crash) oder nie-resumed Continuations (App hängt) führen. `@unchecked Sendable` unterdrückt die Compiler-Warnung.

---

### 🟡 F-22: Prompt-Injection über .brainskill.md Markdown-Body

**Datei:** `Sources/BrainCore/Engine/SkillCompiler.swift:51-101`

Der Markdown-Body eines `.brainskill.md` wird unverändert an den LLM zur JSON-Generierung geschickt. Ein bösartiger Skill-File mit "Ignore previous instructions..." im Body könnte den LLM manipulieren, ein schädliches SkillDefinition-JSON zu erzeugen.

---

### 🟡 F-23: set-Action erlaubt Variable-Name-Injection

**Datei:** `Sources/BrainCore/Engine/LogicInterpreter.swift:122-142`

Die `set`-Action nimmt den Variablennamen aus der Skill-Definition und schreibt direkt in den Expression-Kontext. Keine Validierung des Namens — ein Skill könnte Framework-interne Variablen wie `lastResult` überschreiben.

---

### 🟡 F-24: Skill-JSON wird bei Install nicht validiert

**Datei:** `Sources/BrainCore/Services/SkillService.swift:15-27`

`install(_:)` persistiert ein Skill ohne zu validieren, dass `screens`, `actions`, `triggers` oder `permissions` valides JSON enthalten. Malformed JSON wird gespeichert und crasht erst bei Ausführung.

---

### 🟡 F-25: Skill-Permissions nicht gegen Allowlist geprüft

**Datei:** `Sources/BrainCore/Models/Skill.swift:86-98`

Permissions sind frei wählbare Strings. Kein Enum, keine Allowlist. Ein Skill könnte beliebige Permissions deklarieren.

---

### 🟡 F-26: Keine Input-Validierung bei Entry-Erstellung

**Datei:** `Sources/BrainCore/Services/EntryService.swift:15-21`

Kein Längenlimit für `title`/`body`, keine JSON-Validierung für `sourceMeta`, kein Range-Check für `priority`. Unbegrenzte Strings können die Datenbank aufblähen.

---

### 🟡 F-27: Unbegrenztes Conversation History

**Datei:** `Sources/BrainApp/ChatService.swift:39-49`

Messages werden ohne Retention-Limit in der Datenbank persistiert. `loadMessages()` lädt ALLE Messages. Kein Garbage Collection, kein TTL, kein Auto-Pruning.

---

### 🟡 F-28: Anthropic Max Session-Key statt API-Key

**Datei:** `Sources/BrainApp/SettingsView.swift:62-63`

Die UI instruiert Nutzer, einen Browser-Session-Cookie als API-Credential zu extrahieren. Dieser Session-Key gewährt breiteren Account-Zugriff als ein API-Key.

---

### 🟡 F-29: KeychainService.save() versagt lautlos bei Encoding-Fehler

**Datei:** `Sources/BrainApp/KeychainService.swift:12`

```swift
guard let data = value.data(using: .utf8) else { return }
```

Wenn String-zu-Data fehlschlägt, kehrt die Funktion zurück ohne Fehler zu werfen. Der Aufrufer glaubt das Secret sei gespeichert.

---

### 🟡 F-30: OpenAI Provider ignoriert System-Prompt

**Datei:** `Sources/BrainApp/LLMProviders/OpenAIProvider.swift:35-42`

Der OpenAI Provider übergibt `request.systemPrompt` nicht an die API. Wenn OpenAI jemals via LLMRouter verwendet wird, agiert das Modell ohne System-Instructions.

---

### 🟡 F-31: Manuelle JSON-Escaping ist fragil

**Datei:** `Sources/BrainApp/ToolDefinitions.swift:636-641`

`resultToString` verwendet manuelles String-Escaping statt `JSONSerialization`. Control Characters wie `\t`, `\r`, `\0` werden nicht gehandelt.

---

### 🟡 F-32: @unchecked Sendable auf ToolDefinition mit [String: Any]

**Datei:** `Sources/BrainApp/ToolDefinitions.swift:8`

`ToolDefinition` wraps `[String: Any]` — inherent nicht Sendable. Wenn die `Any`-Werte Reference Types enthalten die concurrent mutiert werden, entsteht eine Data Race.

---

### 🟡 F-33: nonisolated(unsafe) auf geteilten DateFormattern

**Dateien:** `Sources/BrainApp/ActionHandlers.swift:9`, `Sources/BrainCore/Services/EntryService.swift:186-190`

`ISO8601DateFormatter` und `DateFormatter` sind laut Apple nicht thread-safe. Bei concurrent Handler-Execution könnte ein Crash oder Datenkorruption auftreten.

---

## Niedrige Findings / Empfehlungen

### 🟢 F-34: Force Unwraps in Produktionscode

| Datei | Zeile | Ausdruck |
|-------|-------|----------|
| `SharedContainer.swift` | 23 | `.first!` |
| `BrainIntents.swift` | 26 | `try!` |
| `SearchView.swift` | 163 | `grouped[$0]!` |

Alle drei können unter Edge Conditions crashen.

---

### 🟢 F-35: Datenbank nicht verschlüsselt

**Datei:** `Sources/BrainCore/Database/DatabaseManager.swift:18`

SQLite ohne SQLCipher. Auf iOS durch Sandbox und Data Protection geschützt, aber bei Jailbroken Devices oder unverschlüsselten Backups liegt alles offen — E-Mails, Chat-History, Knowledge Facts.

---

### 🟢 F-36: exists() liest ganzes Secret in den Speicher

**Datei:** `Sources/BrainApp/KeychainService.swift:67-69`

Könnte `kSecReturnAttributes` statt `kSecReturnData` verwenden, um Secrets nicht unnötig im Speicher zu haben.

---

### 🟢 F-37: Kein Limit-Cap auf Query-Parameter

**Dateien:** Diverse Service-Methoden (`EntryService`, `SearchService`, `TagService`)

`limit` Parameter akzeptieren jeden `Int`. Ein LLM-Tool-Call mit `limit: 999999` lädt die komplette DB in den Speicher.

---

### 🟢 F-38: Self-Links nicht verhindert

**Datei:** `Sources/BrainCore/Services/LinkService.swift:15-21`

`sourceId == targetId` wird nicht geprüft. Ein Entry kann mit sich selbst verlinkt werden.

---

### 🟢 F-39: Spotlight indexiert Body-Inhalte

**Datei:** `Sources/BrainApp/Bridges/SpotlightBridge.swift:14`

Entry-Body wird als `contentDescription` indexiert. Je nach iOS-Einstellungen auf dem Lock Screen sichtbar.

---

### 🟢 F-40: SpeechBridge: Keine Pfad-Validierung für Datei-URLs

**Datei:** `Sources/BrainApp/Bridges/SpeechBridge.swift:132-138`

Akzeptiert beliebige URL-Strings für Audio-Transkription. iOS-Sandbox schützt, aber der Code validiert nicht.

---

### 🟢 F-41: Keine Backup-Pins für zukünftiges Certificate Pinning

Wenn Pinning implementiert wird: Ohne Backup-Pins kann ein Zertifikatswechsel die App komplett lahmlegen.

---

### 🟢 F-42: Kein App Attest / DeviceCheck

Die App nutzt weder App Attest noch DeviceCheck. Für eine Offline-First-App ohne eigenen Server ist das nachvollziehbar, aber es fehlt eine Möglichkeit die Integrität der App-Instanz zu verifizieren.

---

### 🟢 F-43: Kein CryptoKit verwendet

Keine Daten werden lokal verschlüsselt, gehasht oder signiert. Es gibt kein Integrity-Checking für importierte Skills.

---

---

## Architektur-Bewertung

### Stärken

1. **Saubere Modularisierung:** BrainCore (Framework, keine iOS-Abhängigkeiten) vs BrainApp (iOS-spezifisch) ist eine gute Trennung. BrainCore ist testbar ohne Simulator.

2. **Offline-First Architektur:** GRDB + SQLite ist die richtige Wahl. FTS5 für Volltext, parameterisierte Queries überall.

3. **Swift 6 Strict Concurrency:** Die Codebase nimmt Swift 6 Concurrency ernst. Die meisten `@unchecked Sendable` Markierungen sind begründet und dokumentiert.

4. **MVVM mit @Observable:** Modernes SwiftUI-Pattern ohne Legacy-Combine.

5. **Skill Engine Design:** Die Trennung in Definition → Compiler → Lifecycle → Renderer ist architektonisch sauber.

6. **Entry als universelles Modell:** "Alles ist ein Entry" vereinfacht die Datenarchitektur erheblich.

### Schwächen

1. **LLMRouter ist Dead Code:** Der sorgfältig designte Router mit Sensitivity-Routing, Offline-Fallback und Complexity-basierter Auswahl wird vom ChatService — dem Hauptnutzungspfad — komplett umgangen.

2. **Keine Sanitisierungs-Schicht:** Zwischen Bridges (Datenquellen) und LLM-Kontext fehlt eine Schicht die Daten filtert, kürzt und redaktiert. Das ist die grösste architektonische Lücke.

3. **Keine Bestätigungs-Schicht:** Zwischen LLM-Tool-Call und Ausführung fehlt eine Schicht die gefährliche Aktionen (send, delete, create) dem User zur Bestätigung vorlegt.

4. **ComponentRegistry validiert keine Werte:** Strukturelle Validierung (required fields present) ohne semantische Validierung (URL-Schemas, Längenlimits, Typ-Checks).

5. **Schema.createTables vs Migrations:** Potential für Schema-Drift zwischen Neu-Installationen und Upgrades.

---

## Test-Coverage-Analyse

### Was getestet ist (BrainCore: 22 Testdateien, ~294 Tests)

| Bereich | Testdateien | Bewertung |
|---------|-------------|-----------|
| Entry CRUD | EntryTests | ✅ Gut |
| Tags | TagTests | ✅ Gut |
| Links | LinkTests | ✅ Gut |
| Search/FTS5 | SearchTests | ✅ Gut |
| Database/Schema | DatabaseTests | ✅ Gut |
| ExpressionParser | ExpressionParserTests, Extended | ✅ Sehr gut |
| LogicInterpreter | LogicInterpreterTests, Extended | ✅ Gut |
| ActionDispatcher | ActionDispatcherTests | ✅ Gut |
| SkillDefinition | SkillDefinitionTests | ✅ Gut |
| SkillCompiler | SkillCompilerTests | ✅ Gut |
| SkillLifecycle | SkillLifecycleExtendedTests | ✅ Gut |
| ComponentRegistry | ComponentRegistryTests | ✅ Gut |
| RulesEngine | RulesEngineTests | ✅ Gut |
| PatternEngine | PatternEngineTests | ✅ Gut |
| LLMRouter | LLMRouterTests | ✅ Gut |
| Navigation | NavigationTests | ✅ Gut |
| EmailCache | EmailCacheTests | ✅ Gut |
| VisionPro | VisionProTests | ✅ Gut |
| CloudKitSync | CloudKitSyncTests | ✅ Gut |

### Was NICHT getestet ist (BrainApp: 39 Dateien, 0 Tests)

| Bereich | Dateien | Risiko |
|---------|---------|--------|
| **KeychainService** | KeychainService.swift | 🔴 Hoch — Security-kritisch |
| **BiometricAuth** | BiometricAuth.swift | 🔴 Hoch — Auth kann umgangen werden |
| **CertificatePinning** | CertificatePinning.swift | 🔴 Hoch — Ist ohnehin ein Stub |
| **AnthropicProvider** | AnthropicProvider.swift | 🟠 Hoch — Tool-Loop, Streaming |
| **OpenAIProvider** | OpenAIProvider.swift | 🟠 Hoch — System-Prompt fehlt |
| **ChatService** | ChatService.swift | 🟠 Hoch — Zentrale LLM-Interaktion |
| **ToolDefinitions** | ToolDefinitions.swift | 🟠 Hoch — 42 Tools ungetestet |
| **Alle Bridges** | 10 Bridge-Dateien | 🟠 Hoch — Daten-Zugriff ohne Sanitisierung |
| **ActionHandlers** | ActionHandlers.swift | 🟡 Mittel — 61 Handler |
| **ShareExtension** | ShareViewController.swift | 🟡 Mittel — Externer Input |
| **Widgets** | BrainWidgets.swift | 🟢 Niedrig |
| **Views** | 7 View-Dateien | 🟢 Niedrig |

### Risikobewertung

**Die gesamte Sicherheitsinfrastruktur (Keychain, Auth, Pinning, Provider, Bridges, Tool-Handling) ist ungetestet.** Das ist das grösste strukturelle Risiko. Funktionale Tests für BrainCore sind sehr gut, aber die Angriffsfläche liegt fast ausschliesslich in BrainApp.

---

## Dependency-Analyse

### GRDB 7.8.0

| Aspekt | Bewertung |
|--------|-----------|
| Aktivität | ✅ Aktiv gepflegt, regelmässige Releases |
| Sicherheit | ✅ Parameterisierte Queries, gut auditiert |
| Pinning | ✅ Version 7.8.0 in Package.resolved |
| Risiko | 🟢 Niedrig |

### SwiftMail 1.3.2 (Cocoanetics)

| Aspekt | Bewertung |
|--------|-----------|
| Integration | ⚠️ Nur als Xcode-Projekt-Dependency, nicht SPM |
| Transitive Deps | ⚠️ 14 transitive Dependencies |
| Aktivität | ❓ Unbekannt — sollte geprüft werden |
| Risiko | 🟡 Mittel — Supply-Chain-Risiko durch 14 Dependencies |
| Update-Risiko | 🟠 Hoch — Nicht-SPM-Integration macht Updates fragil |

### Fehlende Security-Libraries

| Library | Zweck | Empfehlung |
|---------|-------|------------|
| **SQLCipher** | DB-Verschlüsselung | 🟡 Empfohlen für E-Mail-Cache und Chat-History |
| **CryptoKit** | Hashing, Signing | 🟡 Empfohlen für Skill-Integrity-Checks |
| **App Attest** | App-Integrity | 🟢 Nice-to-have für API-Schutz |

---

## Empfohlene Massnahmen (priorisiert)

### Sofort (vor nächstem TestFlight)

| # | Massnahme | Adressiert | Aufwand |
|---|-----------|-----------|---------|
| 1 | **Bestätigungs-UI für destruktive LLM-Aktionen** (email_send, entry_delete, calendar_delete, contact_create) | F-03, F-05 | 2-3 Tage |
| 2 | **email_configure Tool entfernen** — E-Mail-Konfiguration nur über Settings-UI | F-02 | 1 Stunde |
| 3 | **Tool-Loop auf 3 Runden limitieren** statt 10 | F-11 | 30 Min |
| 4 | **ChatService auf LLMRouter umstellen** statt direkter AnthropicProvider-Instantiierung | F-04 | 2-4 Stunden |

### Kurzfristig (nächste 2 Wochen)

| # | Massnahme | Adressiert | Aufwand |
|---|-----------|-----------|---------|
| 5 | **Datensanitisierungs-Layer** zwischen Bridges und LLM-Kontext (Truncation, PII-Redaktion) | F-08 | 3-5 Tage |
| 6 | **Echtes Certificate Pinning** mit SPKI-Hashes für alle 3 API-Provider + Backup-Pins | F-01, F-15, F-41 | 1-2 Tage |
| 7 | **FTS5-Query-Sanitisierung** — Tokens in Double-Quotes wrappen | F-09 | 2-3 Stunden |
| 8 | **App Intents authentifizieren** — `openAppWhenRun = true` oder Intent-Ergebnisse generalisieren | F-10 | 1 Tag |
| 9 | **ChatMessage.role zu Enum machen** | F-18 | 1-2 Stunden |
| 10 | **Force Unwraps in Prod-Code eliminieren** | F-34 | 1 Stunde |

### Mittelfristig (nächste 4-8 Wochen)

| # | Massnahme | Adressiert | Aufwand |
|---|-----------|-----------|---------|
| 11 | **Secure-Enclave-basierte Biometrie** statt Boolean-Return | F-06 | 2-3 Tage |
| 12 | **Keychain ACL mit Biometrie** für API-Keys | F-07 | 1 Tag |
| 13 | **Rekursionslimit in LogicInterpreter** | F-12 | 30 Min |
| 14 | **Iterationslimit in forEach** (max 1000) | F-13 | 30 Min |
| 15 | **LIKE-Wildcard-Escaping** in allen Services | F-16 | 2-3 Stunden |
| 16 | **Skill-Permission-Enum** statt freie Strings | F-25 | 1-2 Stunden |
| 17 | **Tests für BrainApp Security-Layer** (Keychain, Auth, Provider, Bridges) | Test-Gap | 1-2 Wochen |
| 18 | **SQLCipher Integration** für DB-Verschlüsselung | F-35 | 2-3 Tage |
| 19 | **RulesEngine: Unparseable Conditions = No Match** | F-17 | 30 Min |
| 20 | **Widget-Inhalte auf Lock Screen einschränken** | F-19 | 1-2 Stunden |

---

## Positiv-Findings (was gut gemacht ist)

- ✅ **SQL-Injection-frei:** Alle GRDB-Queries parameterisiert, kein einziger String-Interpolation-SQL-Query
- ✅ **Keine hardcoded Secrets:** API-Keys ausschliesslich in iOS Keychain
- ✅ **Keychain Accessibility:** `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` korrekt und konsistent
- ✅ **HTTPS only:** Keine Plain-HTTP-URLs im gesamten Projekt
- ✅ **Keine Force Unwraps im Engine-Layer:** ExpressionParser, LogicInterpreter, ActionDispatcher — alle clean
- ✅ **WebView JavaScript deaktiviert + HTTPS-only:** SkillRenderer ist korrekt gehärtet
- ✅ **URL-Schema-Allowlist in OpenURLHandler:** Nur `https`, `http`, `mailto` erlaubt
- ✅ **Biometrie-Policy korrekt:** `.deviceOwnerAuthenticationWithBiometrics` ohne Passcode-Fallback
- ✅ **Task Cancellation in Streaming:** `Task.isCancelled` wird korrekt geprüft
- ✅ **Debug-Prints nur in #if DEBUG:** Keine Produktions-Logging von sensiblen Daten
- ✅ **Soft Delete Pattern:** Entries werden nicht direkt gelöscht, sondern mit `deleted_at` markiert
- ✅ **20-Message Context Window:** Verhindert exzessive Token-Nutzung
- ✅ **BrainCore testbar ohne Simulator:** Saubere Framework-Trennung

---

*Dieses Audit wurde am 2026-03-19 durchgeführt auf Basis des aktuellen master-Branch. Es handelt sich um ein Code-Review — kein Penetration-Test. Dynamische Tests (Laufzeit, Netzwerk-Interception) wurden nicht durchgeführt.*
