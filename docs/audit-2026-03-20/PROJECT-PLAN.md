# Brain-iOS — Projekt-Prozess-Plan: Audit-Fixes

**Erstellt:** 20. Maerz 2026
**Basis:** Code-Audit (40 Findings), Funktionsanalyse, Wettbewerbsanalyse vom 20.03.2026
**Ziel:** Alle Sicherheitsluecken und UX-Schwaechen systematisch beheben
**Constraint:** Swift 6.1, `strict-concurrency=complete`, kein Over-Engineering

---

## Wichtige Hinweise

### Deployment via Xcode Cloud
Alle Aenderungen werden via `xcode-cloud-deploy` Skill deployed. Nach jedem abgeschlossenen Arbeitspaket:
1. `git push origin master` → Xcode Cloud Build wird automatisch getriggert
2. Build-Logs pruefen (Artifacts → Logs herunterladen bei Fehler)
3. Bei Erfolg: TestFlight-Build automatisch an Gruppe "Intern"

### Lessons Learned beachten
Die Datei `Skills/xcode-cloud-lessons-learned.brainskill.md` auf dem VPS dokumentiert 51+ Build-Iterationen. **Vor jedem Push zwingend lesen**, insbesondere:
- **objectVersion 56**: Jede neue `.swift`-Datei braucht `PBXFileReference` + `PBXBuildFile` in `project.pbxproj`
- **Package.resolved**: Muss committed sein, NIEMALS in `.gitignore`
- **Swift 6 Strict Concurrency**: VPS `swift test` prueft KEINE Sendable-Compliance — Xcode Cloud findet mehr Fehler
- **`static var` → `static let`** in AppIntents
- **`#if canImport`** muss Import UND Methode einwickeln

### Testbarkeit
- BrainCore Tests via `swift test` auf VPS (294 Tests)
- BrainApp Tests nur via Xcode Cloud (iOS Simulator)
- Jeder Fix hat ein "Done-Kriterium" das entweder via Unit-Test oder manuell pruefbar ist

---

## Arbeitspaket 1: Keychain & Secure Storage Hardening

**Scope:** K1, K3, K4, H2 — Alles rund um Keychain, Secure Enclave, API-Key-Validierung
**Geschaetzter Aufwand:** M
**Abhaengigkeiten:** Keine (Grundlage fuer alles Weitere)

### 1.1 — K1: Secure Enclave fuer API-Keys

**Datei:** `Sources/BrainApp/KeychainService.swift`

**Problem:** `saveWithBiometry()` nutzt `kSecAttrAccessControl` mit `.biometryCurrentSet`, speichert aber im Standard-Keychain statt im Secure Enclave.

**Loesung:**
```swift
func saveWithBiometry(key: String, value: String) throws {
    let access = SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        [.biometryCurrentSet, .privateKeyUsage],
        nil
    )
    var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: serviceName,
        kSecAttrAccount as String: key,
        kSecValueData as String: value.data(using: .utf8)!,
        kSecAttrAccessControl as String: access as Any,
    ]
    // Secure Enclave wenn verfuegbar (nicht auf Simulator)
    #if !targetEnvironment(simulator)
    query[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
    #endif
    // ... delete existing + add
}
```

**Done-Kriterium:** Keychain-Query enthaelt `kSecAttrTokenIDSecureEnclave` auf Device. Simulator-Fallback funktioniert weiterhin. Bestehende API-Keys werden beim naechsten Speichern migriert.

### 1.2 — K3: API-Key-Validierung bei Speicherung

**Dateien:** `Sources/BrainApp/SettingsView.swift`, `Sources/BrainApp/KeychainService.swift`

**Problem:** Leere Strings und Whitespace werden als gueltige API-Keys akzeptiert.

**Loesung:**
```swift
// KeychainService.swift — neue Methode
static func validateAPIKey(_ key: String, provider: LLMProviderType) -> Bool {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    switch provider {
    case .anthropic: return trimmed.hasPrefix("sk-ant-")
    case .openai: return trimmed.hasPrefix("sk-")
    case .anthropicMax: return trimmed.count >= 20
    default: return true
    }
}
```

In `SettingsView.swift`: Validierung vor `testAnthropicKey()` aufrufen, invalide Keys mit Inline-Fehlermeldung abweisen.

**Done-Kriterium:** Leerer String, Whitespace-only und falsche Prefixe werden abgelehnt mit klarer Fehlermeldung. `keychain.exists()` allein reicht nicht mehr fuer "konfiguriert"-Status.

### 1.3 — K4: Anthropic Max Session-Key TTL

**Datei:** `Sources/BrainApp/LLMProviders/AnthropicProvider.swift`, `Sources/BrainApp/KeychainService.swift`

**Problem:** Session-Keys liegen im selben Keychain-Slot wie permanente API-Keys, ohne TTL oder Rotation.

**Loesung:**
- Separater Keychain-Key: `KeychainKeys.anthropicMaxSessionKey` (existiert bereits)
- Neuer Keychain-Key: `KeychainKeys.anthropicMaxSessionExpiry` → speichert ISO-8601-Timestamp
- Default-TTL: 24h ab Speicherung (konfigurierbar in Settings)
- Bei `AnthropicProvider.init(maxSessionKey:)`: Expiry pruefen, bei Ablauf `.sessionExpired` Error werfen
- `SettingsView`: Ablauf-Datum anzeigen, "Erneuern"-Button

```swift
// AnthropicProvider — am Anfang von complete()/stream()
if isMaxMode {
    if let expiryStr = keychain.read(key: .anthropicMaxSessionExpiry),
       let expiry = ISO8601DateFormatter().date(from: expiryStr),
       expiry < Date() {
        throw LLMError.sessionExpired
    }
}
```

**Done-Kriterium:** Abgelaufene Session-Keys produzieren eine klare Fehlermeldung statt kryptischer API-Fehler. Expiry-Datum wird in Settings angezeigt.

### 1.4 — H2: Email-Passwort mit biometrischer Absicherung

**Datei:** `Sources/BrainApp/Bridges/EmailBridge.swift`

**Problem:** IMAP/SMTP-Passwort im Keychain ohne `SecAccessControl` Biometrie-Gate (inkonsistent mit API-Keys).

**Loesung:** `keychain.save(key:value:)` → `keychain.saveWithBiometry(key:value:)` fuer den Password-Slot (`KeychainKeys.emailPassword`). Die restlichen Email-Config-Keys (Host, Port, Username) brauchen keine Biometrie.

**Done-Kriterium:** Email-Passwort erfordert Face ID beim ersten Zugriff pro App-Session. Andere Email-Config-Keys sind ohne Biometrie lesbar.

---

## Arbeitspaket 2: ChatService Absicherung & Error Handling

**Scope:** K2, M1, H4, H1 — Race Conditions, Error Propagation, Silent Failures
**Geschaetzter Aufwand:** M
**Abhaengigkeiten:** Keine (parallel zu AP 1 moeglich)

### 2.1 — K2: Race Condition in ChatService.send()

**Datei:** `Sources/BrainApp/ChatService.swift`

**Problem:** `send()` ist `async` aber mehrere gleichzeitige Aufrufe koennen `messages`-Array korrumpieren.

**Loesung:** Minimaler Guard-Ansatz (kein Actor-Refactor noetig, da `@MainActor` bereits isoliert):
```swift
@MainActor @Observable final class ChatService {
    private var isSending = false

    func send(_ text: String) async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        // ... bestehende Logik
    }
}
```

Plus UI-seitig: Send-Button `.disabled(chatService.isSending || chatService.isStreaming)` in ChatView.

**Done-Kriterium:** Schnelles Doppeltippen auf Send erzeugt nur eine Nachricht. `isSending` Guard verhindert parallele Ausfuehrung.

### 2.2 — M1: Tool-Call Confirmation Default-Handler

**Datei:** `Sources/BrainApp/ChatService.swift`

**Problem:** `confirmationHandler` ist optional. Wenn nicht gesetzt, werden destruktive Tool-Calls ohne Bestaetigung ausgefuehrt.

**Loesung:**
```swift
// Default: deny if no handler set
private func shouldConfirm(tool: String) async -> Bool {
    guard destructiveTools.contains(tool) else { return true }
    guard let handler = confirmationHandler else { return false } // deny by default
    return await handler(tool)
}
```

**Done-Kriterium:** Destruktive Tools (`email_send`, `entry_delete`, etc.) werden abgelehnt wenn kein Confirmation-Handler registriert ist. Unit-Test moeglich.

### 2.3 — H4: Strukturierte Error-Responses in ActionHandlers

**Datei:** `Sources/BrainApp/ActionHandlers.swift`

**Problem:** Generische "Fehler aufgetreten"-Meldungen ohne Error-Code oder Details.

**Loesung:** Neues Error-Response-Format fuer alle Handler:
```swift
struct ActionError: Error {
    let code: String      // z.B. "entry.not_found"
    let message: String   // Lesbarer Text
    let details: String?  // Debug-Details (nur in #if DEBUG)
}
```

Schrittweise in allen 61 Handlers die `catch`-Bloecke ersetzen. Prioritaet: AI-Handlers und Entry-Handlers zuerst (am haeufigsten aufgerufen).

**Done-Kriterium:** Jeder ActionHandler gibt bei Fehler einen strukturierten Error mit Code und Beschreibung zurueck. Chat zeigt lesbare Fehlermeldung. Debug-Builds zeigen zusaetzliche Details.

### 2.4 — H1: ProactiveService Error Logging statt Silent Swallowing

**Datei:** `Sources/BrainApp/ProactiveService.swift`

**Problem:** Durchgehend `try?` — alle Fehler werden still ignoriert.

**Loesung:** `try?` ersetzen durch `do/catch` mit `os_log`:
```swift
import os.log

private let logger = Logger(subsystem: "com.example.brain-ios", category: "ProactiveService")

// Statt:
let tasks = try? dataBridge.listEntries(...)
// Neu:
let tasks: [Entry]
do {
    tasks = try dataBridge.listEntries(...)
} catch {
    logger.error("Failed to load tasks for briefing: \(error.localizedDescription)")
    tasks = []
}
```

**Done-Kriterium:** Alle `try?` in ProactiveService ersetzt durch `do/catch` mit Logger. Fehler in Console sichtbar. Feature funktioniert weiterhin (graceful degradation mit leeren Defaults).

---

## Arbeitspaket 3: Input-Validierung & Netzwerk-Resilienz

**Scope:** H3, H5, H7, M2, M3, M6 — Validierung, Sanitisierung, Retry, Graceful Degradation
**Geschaetzter Aufwand:** M
**Abhaengigkeiten:** Keine (parallel zu AP 1+2 moeglich)

### 3.1 — H3: Input-Laengenbegrenzung in EntryDetailView

**Datei:** `Sources/BrainApp/EntryDetailView.swift`

**Problem:** Titel und Body ohne Laengenbegrenzung.

**Loesung:**
```swift
private let maxTitleLength = 500
private let maxBodyLength = 10_000

TextField("Titel", text: $title)
    .onChange(of: title) { _, new in
        if new.count > maxTitleLength { title = String(new.prefix(maxTitleLength)) }
    }

// Body: Zeichenzaehler anzeigen
Text("\(bodyText.count)/\(maxBodyLength)")
    .font(.caption2)
    .foregroundStyle(bodyText.count > maxBodyLength * 9 / 10 ? .red : .secondary)
```

Soft-Limit: Warnung ab 90%, Hard-Limit beim Speichern.

**Done-Kriterium:** Titel >500 Zeichen wird abgeschnitten. Body zeigt Zaehler, warnt ab 9000 Zeichen, verhindert Speicherung >10000.

### 3.2 — H5: Semantische Skill-Validierung

**Datei:** `Sources/BrainCore/Services/SkillService.swift`

**Problem:** JSON-Struktur wird validiert, aber nicht ob referenzierte Action-Handler existieren.

**Loesung:** In `SkillCompiler.validate()` erweitern:
```swift
func validateSemantics(_ definition: SkillDefinition, registry: ComponentRegistry) -> [ValidationWarning] {
    var warnings: [ValidationWarning] = []
    // Pruefen ob referenzierte Actions registrierte Handler haben
    for action in definition.actions {
        for step in action.steps {
            if !registry.hasHandler(for: step.type) {
                warnings.append(.unknownHandler(step.type))
            }
        }
    }
    return warnings
}
```

Warnings werden bei `install()` angezeigt (nicht blockierend, da Custom-Skills externe Handler haben koennten).

**Done-Kriterium:** `SkillLifecycle.install()` gibt Warnings aus wenn referenzierte Handler nicht registriert sind. Installation wird nicht blockiert, aber User sieht Hinweis.

### 3.3 — H7: Memory-Limit fuer Variable-Bindings

**Datei:** `Sources/BrainCore/Engine/LogicInterpreter.swift`

**Problem:** Kein Limit fuer Anzahl/Groesse der Variablen im Scope.

**Loesung:**
```swift
private let maxVariableCount = 1000
private let maxTotalScopeSize = 1_048_576 // 1 MB

func executeSet(name:value:context:) throws {
    guard context.variables.count < maxVariableCount else {
        throw LogicError.scopeLimitExceeded("Max \(maxVariableCount) variables")
    }
    // ... bestehende Logik
}
```

**Done-Kriterium:** Unit-Test: Skill der 1001 Variablen erstellt, wirft `scopeLimitExceeded`. Bestehende Tests gruen.

### 3.4 — M2: Markdown-Sanitisierung fuer LLM-Kontext

**Datei:** `Sources/BrainCore/Utilities/DataSanitizer.swift` (aktuell: `Sources/BrainCore/Services/DataSanitizer.swift`)

**Problem:** Keine Sanitisierung von Markdown-Injection-Patterns (Image-URLs, Links).

**Loesung:**
```swift
public static func sanitizeForLLM(_ text: String, max: Int = maxToolResultLength) -> String {
    var sanitized = text
    // Strip image references (tracking pixels)
    sanitized = sanitized.replacingOccurrences(
        of: #"!\[([^\]]*)\]\([^\)]+\)"#,
        with: "[Bild: $1]",
        options: .regularExpression
    )
    // Strip raw URLs in angle brackets
    sanitized = sanitized.replacingOccurrences(
        of: #"<https?://[^>]+>"#,
        with: "[URL entfernt]",
        options: .regularExpression
    )
    return truncate(sanitized, max: max)
}
```

**Done-Kriterium:** Unit-Test: `![](http://evil.com/t.gif)` wird zu `[Bild: ]`. Bestehende Truncation funktioniert weiterhin.

### 3.5 — M3: Retry-Logic fuer Netzwerk-Fehler

**Dateien:** `Sources/BrainApp/LLMProviders/AnthropicProvider.swift`, `Sources/BrainApp/LLMProviders/OpenAIProvider.swift`

**Problem:** Kein automatischer Retry bei transienten Fehlern (429, 503, Timeout).

**Loesung:** Shared Retry-Helper:
```swift
func withRetry<T>(maxAttempts: Int = 3, operation: () async throws -> T) async throws -> T {
    var lastError: Error?
    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch let error as URLError where error.code == .timedOut {
            lastError = error
        } catch let error as HTTPError where [429, 503].contains(error.statusCode) {
            lastError = error
        }
        if attempt < maxAttempts {
            try await Task.sleep(for: .seconds(pow(2.0, Double(attempt - 1))))
        }
    }
    throw lastError!
}
```

Einsetzen in `complete()` und `stream()` beider Provider.

**Done-Kriterium:** 429/503/Timeout werden bis zu 3x mit Exponential Backoff wiederholt. 401/400-Fehler werden sofort durchgereicht.

### 3.6 — M6: EventKit Graceful Degradation

**Datei:** `Sources/BrainApp/Bridges/EventKitBridge.swift`

**Problem:** Leere Liste wenn Zugriff verweigert, ohne Erklaerung.

**Loesung:**
```swift
enum CalendarAccessState {
    case authorized, denied, notDetermined
}

func accessState() -> CalendarAccessState {
    switch EKEventStore.authorizationStatus(for: .event) {
    case .fullAccess, .authorized: return .authorized
    case .denied, .restricted: return .denied
    default: return .notDetermined
    }
}
```

In den Skill-Views: Bei `.denied` eine `ContentUnavailableView` mit "Kalender-Zugriff erlauben" Button der zu `UIApplication.openNotificationSettingsURLString` fuehrt.

**Done-Kriterium:** User mit verweigertem Kalender-Zugriff sieht "Kalender-Zugriff nicht erlaubt" mit Button zu Einstellungen statt einer leeren Liste.

---

## Arbeitspaket 4: UX Quick Wins

**Scope:** Quick Wins aus Funktionsanalyse + L14, L15, L16, L17
**Geschaetzter Aufwand:** S
**Abhaengigkeiten:** Keine

### 4.1 — Confirmation-Dialog bei Skill-Loeschen

**Datei:** `Sources/BrainApp/SkillManagerView.swift` (oder entsprechende View)

**Loesung:** `.confirmationDialog("Skill loeschen?", isPresented: $showDeleteConfirmation)` Modifier auf die Swipe-Action.

**Done-Kriterium:** Swipe-to-Delete zeigt Bestaetigung. Abbrechen behalt den Skill.

### 4.2 — Pull-to-Refresh

**Dateien:** Alle Listen-Views (Skills, Entries, Chat)

**Loesung:** `.refreshable { await loadSkills() }` auf jede `List`.

**Done-Kriterium:** Alle Listen reagieren auf Pull-to-Refresh Geste.

### 4.3 — Haptic Feedback

**Dateien:** Relevante Views (Import, Export, Toggle, Delete)

**Loesung:**
```swift
private let haptic = UIImpactFeedbackGenerator(style: .medium)
// Bei Erfolg:
haptic.impactOccurred()
```

**Done-Kriterium:** Import, Export, Toggle, Task-Completion geben haptisches Feedback.

### 4.4 — Leere-Zustand-Verbesserung

**Dateien:** Alle Views mit `ContentUnavailableView`

**Loesung:** Call-to-Action-Button im leeren Zustand:
```swift
ContentUnavailableView {
    Label("Keine Skills", systemImage: "puzzlepiece")
} description: {
    Text("Installiere deinen ersten Skill")
} actions: {
    Button("Skill importieren") { showImporter = true }
}
```

**Done-Kriterium:** Jeder leere Zustand hat einen hilfreichen Action-Button.

### 4.5 — Undo bei Swipe-to-Delete (L14)

**Dateien:** Entry-Listen, Skill-Listen

**Loesung:** Soft-Delete + Toast mit "Rueckgaengig"-Button (3 Sekunden sichtbar):
```swift
.swipeActions(edge: .trailing) {
    Button(role: .destructive) {
        deletedItem = item
        dataBridge.softDelete(item)
        showUndoToast = true
    } label: { Label("Loeschen", systemImage: "trash") }
}
```

**Done-Kriterium:** Geloeschte Items koennen 3 Sekunden lang via Toast wiederhergestellt werden.

### 4.6 — Skill-Berechtigungen erklaeren (L16)

**Datei:** Skill-Detail-View

**Loesung:** Statt "3 Berechtigungen" eine expandierbare Liste mit Icons und Erklaerungen:
```swift
DisclosureGroup("3 Berechtigungen") {
    ForEach(skill.permissions, id: \.self) { perm in
        Label(permissionDescription(perm), systemImage: permissionIcon(perm))
    }
}
```

**Done-Kriterium:** Skill-Berechtigungen werden einzeln mit Erklaerung aufgelistet.

---

## Arbeitspaket 5: Datenbank & Suche Optimierung

**Scope:** M4, M5, L10, L18
**Geschaetzter Aufwand:** S
**Abhaengigkeiten:** Keine

### 5.1 — M4: FTS5-Tokenizer fuer Deutsch

**Datei:** `Sources/BrainCore/Database/Schema.swift`

**Problem:** Default-Tokenizer `unicode61` ohne Stemming fuer deutsche Woerter.

**Loesung:** Migration v3 die FTS5-Tabelle neu erstellt:
```sql
DROP TABLE IF EXISTS entries_fts;
CREATE VIRTUAL TABLE entries_fts USING fts5(
    title, body, content=entries, content_rowid=id,
    tokenize='porter unicode61 remove_diacritics 2'
);
-- Re-populate
INSERT INTO entries_fts(rowid, title, body) SELECT id, title, body FROM entries;
```

**Done-Kriterium:** Suche nach "Besprechungen" findet auch "Besprechung". Bestehende Search-Tests anpassen.

### 5.2 — M5: Pagination mit Offset

**Datei:** `Sources/BrainCore/Services/EntryService.swift`

**Problem:** `list(limit:)` hat keinen Offset-Parameter.

**Loesung:**
```swift
public func list(limit: Int = 50, offset: Int = 0, type: String? = nil, status: String? = nil) throws -> [Entry] {
    try pool.read { db in
        var sql = "SELECT * FROM entries WHERE deletedAt IS NULL"
        var args: [DatabaseValueConvertible] = []
        if let type { sql += " AND type = ?"; args.append(type) }
        if let status { sql += " AND status = ?"; args.append(status) }
        sql += " ORDER BY createdAt DESC LIMIT ? OFFSET ?"
        args.append(limit); args.append(offset)
        return try Entry.fetchAll(db, sql: sql, arguments: StatementArguments(args))
    }
}
```

**Done-Kriterium:** Unit-Test: 10 Entries erstellen, `list(limit:5, offset:5)` gibt die letzten 5 zurueck.

### 5.3 — L10: Dashboard DB-Queries kombinieren

**Datei:** `Sources/BrainApp/DataBridge.swift`

**Problem:** `refreshDashboard()` macht 5 separate DB-Queries.

**Loesung:** Eine kombinierte Query:
```swift
func dashboardStats() throws -> DashboardStats {
    try pool.read { db in
        let row = try Row.fetchOne(db, sql: """
            SELECT
                COUNT(*) as total,
                SUM(CASE WHEN status = 'active' AND type = 'task' THEN 1 ELSE 0 END) as openTasks,
                SUM(CASE WHEN date(createdAt) = date('now') THEN 1 ELSE 0 END) as todayCount,
                SUM(CASE WHEN status = 'done' THEN 1 ELSE 0 END) as doneCount,
                SUM(CASE WHEN deletedAt IS NOT NULL THEN 1 ELSE 0 END) as archivedCount
            FROM entries
            """)
        return DashboardStats(row: row!)
    }
}
```

**Done-Kriterium:** `refreshDashboard()` macht 1 statt 5 DB-Queries. Dashboard-Daten bleiben korrekt.

### 5.4 — L18: DateFormatter cachen

**Dateien:** Alle Dateien mit `DateFormatter()` in Schleifen

**Loesung:** Statische Formatter:
```swift
enum Formatters {
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()
    nonisolated(unsafe) static let relative: DateFormatter = {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        return f
    }()
}
```

**Done-Kriterium:** Keine `DateFormatter()`-Instanziierung innerhalb von Schleifen oder haeufig aufgerufenen Methoden.

---

## Arbeitspaket 6: Certificate Pinning & Netzwerk-Sicherheit

**Scope:** H6, M2 (Netzwerk-spezifisch)
**Geschaetzter Aufwand:** S
**Abhaengigkeiten:** Keine

### 6.1 — H6: Remote-Config fuer Certificate Pins

**Datei:** `Sources/BrainApp/LLMProviders/CertificatePinning.swift`

**Problem:** SPKI-Hashes sind hardcoded. Zertifikats-Rotation erzwingt App-Update.

**Loesung:** Trust-on-First-Use (TOFU) als Fallback:
```swift
// 1. Hardcoded Pins pruefen (primaer + backup)
// 2. Wenn KEIN Pin passt UND User-Setting "Trust-on-First-Use" aktiv:
//    → Neuen Pin speichern (UserDefaults), Warnung loggen
//    → Beim naechsten Start: neuer Pin gilt als trusted
// 3. Wenn TOFU deaktiviert: Verbindung ablehnen (bestehendes Verhalten)
```

Zusaetzlich: Pin-Hashes in einer Property-List statt inline, damit ein App-Update die Pins einfacher aktualisieren kann.

**Done-Kriterium:** Bei Zertifikats-Rotation durch API-Provider: App warnt, verliert aber nicht den Zugang. TOFU standardmaessig deaktiviert (Opt-in in Einstellungen).

---

## Arbeitspaket 7: UX-Verbesserungen (Onboarding, i18n, Accessibility)

**Scope:** L1, L8, L9, L13, L5
**Geschaetzter Aufwand:** L
**Abhaengigkeiten:** AP 4 (Quick Wins) sollte vorher abgeschlossen sein

### 7.1 — L13: Onboarding fuer neue User

**Neue Datei:** `Sources/BrainApp/OnboardingFlow.swift`

**Loesung:** 3-Schritte Onboarding (nur beim ersten Start):
1. **Willkommen**: Was ist Brain? (1 Satz + Illustration)
2. **API-Key**: Anthropic Key eingeben (mit "Ueberspringen" Option)
3. **Berechtigungen**: Kalender, Kontakte, Benachrichtigungen anfordern

```swift
struct OnboardingFlow: View {
    @AppStorage("hasCompletedOnboarding") var completed = false
    // ... 3 TabView-Pages mit PageTabViewStyle
}
```

**Done-Kriterium:** Neue User sehen Onboarding. Bestehende User (hasCompletedOnboarding=true) nicht. API-Key-Eingabe funktional.

### 7.2 — L1: i18n-Framework vorbereiten

**Problem:** Alle UI-Strings auf Deutsch hardcoded.

**Loesung:** Phase 1 — String-Catalog erstellen, Strings migrieren:
1. `Localizable.xcstrings` im Xcode-Projekt anlegen
2. Alle hardcoded Strings via `String(localized:)` ersetzen
3. Deutsche Uebersetzungen als Default

```swift
// Statt:
Text("Keine Eintraege")
// Neu:
Text("empty_state_entries", tableName: "Localizable")
```

Phase 2 (spaeter): Englische Uebersetzungen hinzufuegen.

**Done-Kriterium:** Alle UI-Strings in Localizable.xcstrings. App funktioniert weiterhin auf Deutsch. Grundlage fuer Englisch-Support gelegt.

### 7.3 — L8 + L9: Accessibility-Verbesserungen

**Dateien:** Alle SwiftUI Views

**Loesung:**
```swift
// VoiceOver Labels ueberall
.accessibilityLabel("Offene Aufgaben: \(openTasks)")
.accessibilityHint("Doppeltippen um die Liste zu oeffnen")

// Dynamic Type
.dynamicTypeSize(...DynamicTypeSize.accessibility3)

// Accessibility Identifier fuer UI-Tests
.accessibilityIdentifier("dashboard.openTasks")
```

Prioritaet: Dashboard, Chat, Entry-Liste, Settings.

**Done-Kriterium:** VoiceOver navigiert alle Hauptscreens sinnvoll. Dynamic Type bis Accessibility3 unterstuetzt. Mindestens 20 Accessibility-Identifier fuer spaetere UI-Tests.

### 7.4 — Skill-Capability-Feld (AppSkill vs BrainSkill)

**Problem:** Kein Unterschied zwischen deterministischen UI-Skills (Dashboard, Kalender) und KI-gestuetzten Skills (Zusammenfassungen, Analyse). User sieht nicht ob ein Skill Daten an ein LLM schickt, und Offline-Routing weiss nicht welche Skills ohne Internet funktionieren.

**Loesung:** Neues `capability`-Feld im `.brainskill.md` Frontmatter:
```yaml
---
id: weekly-summary
name: Wochen-Zusammenfassung
capability: brain  # app | brain | hybrid
permissions: [entries, calendar]
---
```

- **app**: Hat UI-Screens, nutzt ActionHandlers, deterministisch, funktioniert offline
- **brain**: Hat Prompt-Templates, braucht LLM, generiert dynamische Antworten
- **hybrid**: Beides (z.B. UI mit einem "Brain analysieren"-Button)

Aenderungen:
1. `BrainSkillParser`: `capability` aus Frontmatter parsen (Default: `app`)
2. `Skill`-Model: Neues Feld `capability: SkillCapability` (.app/.brain/.hybrid)
3. `SkillRenderer`: Bei `brain`-Skills Hinweis "Braucht KI" anzeigen
4. Skill-Detail-View (7.6): Capability-Badge neben Berechtigungen
5. Offline-Routing: `brain`-Skills bei fehlendem LLM deaktivieren/warnen

**Done-Kriterium:** Skill-Frontmatter akzeptiert `capability`-Feld. Skill-Detail-View zeigt Capability-Badge. brain/hybrid-Skills werden bei fehlendem LLM als eingeschraenkt markiert.

### 7.5 — L5: Konsistente Error-Messages

**Problem:** Mal Deutsch, mal Englisch.

**Loesung:** Alle User-facing Error-Messages auf Deutsch. Interne Logs auf Englisch. Pattern:
```swift
// User sieht:
throw BrainError.userFacing("Verbindung fehlgeschlagen. Pruefe deine Internetverbindung.")
// Log zeigt:
logger.error("Network request failed: \(error)")
```

**Done-Kriterium:** Alle Fehlermeldungen die der User sieht sind auf Deutsch. Logs bleiben Englisch.

---

## Arbeitspaket 8: Architektur-Refactoring

**Scope:** DataBridge aufteilen, Dependency Injection, Protokoll-basiertes Design, L20
**Geschaetzter Aufwand:** L
**Abhaengigkeiten:** AP 1-4 sollten vorher abgeschlossen sein (Refactoring aendert viele Dateien)

### 8.1 — DataBridge aufteilen

**Datei:** `Sources/BrainApp/DataBridge.swift` (395 Zeilen, 30+ Methoden)

**Problem:** God Object mit zu vielen Verantwortlichkeiten.

**Loesung:** Aufteilen in spezialisierte Repositories:
```
DataBridge (orchestriert, ~50 Zeilen)
├── EntryRepository    (Entry CRUD, ~80 Zeilen)
├── TagRepository      (Tag-Operationen, ~40 Zeilen)
├── LinkRepository     (Link-Operationen, ~30 Zeilen)
├── DashboardRepository (Stats, Greeting, ~60 Zeilen)
└── SearchRepository   (FTS5, Autocomplete, ~50 Zeilen)
```

DataBridge bleibt als Fassade bestehen (backward-compatible), delegiert intern an Repositories.

**Done-Kriterium:** DataBridge ist <100 Zeilen. Jedes Repository hat eine klar definierte Aufgabe. Alle bestehenden Aufrufe funktionieren via DataBridge-Fassade. Tests gruen.

### 8.2 — Dependency Injection

**Problem:** Services in `DataBridge.init()` hardcoded erstellt.

**Loesung:** Protokoll-basierte Injection:
```swift
@MainActor @Observable final class DataBridge {
    let entries: EntryRepository
    let tags: TagRepository
    // ...

    init(pool: DatabasePool,
         entries: EntryRepository? = nil,
         tags: TagRepository? = nil) {
        self.entries = entries ?? EntryRepository(pool: pool)
        self.tags = tags ?? TagRepository(pool: pool)
    }
}
```

Default-Implementierungen fuer Produktion, Mock-Injections fuer Tests.

**Done-Kriterium:** Alle Services sind injizierbar. Mindestens 1 Test nutzt Mock-Injection. Produktion nutzt Default-Implementierungen.

### 8.3 — Protokoll-basiertes Design

**Problem:** Services sind konkrete Klassen — erschwert Testing und Austauschbarkeit.

**Loesung:** Protokolle fuer die wichtigsten Services:
```swift
protocol EntryProviding: Sendable {
    func create(_ entry: Entry) throws -> Entry
    func fetch(id: Int) throws -> Entry?
    func list(limit: Int, offset: Int) throws -> [Entry]
    // ...
}

struct EntryService: EntryProviding { /* bestehende Implementierung */ }
struct MockEntryService: EntryProviding { /* fuer Tests */ }
```

Prioritaet: `EntryService`, `SearchService`, `SkillService` (meistgenutzt).

**Done-Kriterium:** 3 Kern-Services haben Protokolle. Tests nutzen Mock-Implementierungen. Keine Breaking Changes fuer bestehenden Code.

### 8.4 — L20: `nonisolated` Annotationen eliminieren

**Problem:** Viele `nonisolated` Annotationen in DataBridge, die durch Actor-Refactor ueberfluessig werden.

**Loesung:** Wird automatisch durch 8.1 (DataBridge-Aufteilung) geloest. Repositories sind `Sendable` Structs, nicht `@MainActor` — kein `nonisolated` noetig.

**Done-Kriterium:** Keine `nonisolated` Annotationen in den neuen Repository-Klassen.

---

## Arbeitspaket 9: Code-Qualitaet & Build-Hygiene

**Scope:** L2, L3, L4, L6, L7, L19, L21, L22, L23
**Geschaetzter Aufwand:** M
**Abhaengigkeiten:** Keine (kann parallel laufen)

### 9.1 — L7: Strukturiertes Logging

**Problem:** Nur `print()` und `#if DEBUG`.

**Loesung:** `os.log` Logger fuer alle Module:
```swift
import os.log
extension Logger {
    static let chat = Logger(subsystem: "com.example.brain-ios", category: "Chat")
    static let skills = Logger(subsystem: "com.example.brain-ios", category: "Skills")
    static let proactive = Logger(subsystem: "com.example.brain-ios", category: "Proactive")
    static let network = Logger(subsystem: "com.example.brain-ios", category: "Network")
    static let db = Logger(subsystem: "com.example.brain-ios", category: "Database")
}
```

**Done-Kriterium:** Alle `print()` in Produktionscode ersetzt durch `Logger`. Logs filterbar nach Subsystem/Category in Console.app.

### 9.2 — L4: print()-Statements entfernen

**Dateien:** `DataBridge.swift`, `ChatService.swift`, weitere

**Loesung:** Alle `print()` ersetzen:
- Debug-Output → `Logger.debug()`
- Error-Output → `Logger.error()`
- Unnoetige Prints → loeschen

**Done-Kriterium:** `grep -r "print(" Sources/` findet 0 Treffer (ausser in Utility-Code der explizit stdout braucht).

### 9.3 — L6: SwiftLint-Konfiguration

**Neue Datei:** `.swiftlint.yml`

**Loesung:** Minimale Konfiguration:
```yaml
included:
  - Sources
excluded:
  - Sources/BrainCore/Engine/SkillDefinition.swift  # Generated-like code
opt_in_rules:
  - empty_count
  - closure_spacing
disabled_rules:
  - line_length  # SwiftUI Views sind oft lang
  - type_body_length
```

**Done-Kriterium:** `swiftlint` laeuft ohne kritische Violations. Warnungen sind dokumentiert.

### 9.4 — L19: Konsistente Naming-Conventions

**Problem:** `camelCase` vs `snake_case` in JSON-Keys.

**Loesung:** Standard: `camelCase` fuer alle internen JSON-Keys (konsistent mit Swift). Mapping-Layer fuer externe APIs (Anthropic nutzt `snake_case`). CodingKeys wo noetig.

**Done-Kriterium:** Alle internen JSON-Keys camelCase. Keine gemischten Conventions innerhalb einer Datei.

### 9.5 — L21: Package.resolved Synchronisierung

**Problem:** Zwei `Package.resolved`-Dateien (SPM + Xcode).

**Loesung:** Symlink oder Post-Resolve-Hook:
```bash
# In ci_post_clone.sh:
cp "$CI_PRIMARY_REPOSITORY_PATH/BrainApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" \
   "$CI_PRIMARY_REPOSITORY_PATH/Package.resolved" 2>/dev/null || true
```

**Done-Kriterium:** Nur eine autoritative Package.resolved (Xcode). SPM-Version wird davon abgeleitet.

### 9.6 — L22: Build-Warnings als Fehler in CI

**Loesung:** In `project.pbxproj`:
```
SWIFT_TREAT_WARNINGS_AS_ERRORS = YES;
```

Alternativ: Nur in Release-Config, damit Development-Builds flexibler bleiben.

**Done-Kriterium:** Xcode Cloud Build scheitert bei neuen Warnings. Bestehende Warnings vorher behoben.

### 9.7 — L2 + L3: Test-Abdeckung erhoehen

**Scope:** Unit-Tests fuer SkillCompiler, LogicInterpreter, RulesEngine (L2). UI-Test-Grundgeruest (L3).

**Loesung:**
- SkillCompiler: Edge-Cases testen (ungueltige YAML, fehlende Felder, zu grosse Skills)
- LogicInterpreter: Scope-Limit-Tests (H7 Fix), verschachtelte if/forEach
- RulesEngine: Zeitbasierte Regeln, komplexe Conditions
- UI-Tests: Basic Navigation Flow (Dashboard → Chat → Settings → zurueck)

**Done-Kriterium:** Mindestens 20 neue Tests. UI-Test-Target in Xcode-Projekt angelegt. Test-Coverage fuer kritische Engine-Komponenten >80%.

### 9.8 — L23: DocC-Comments fuer Public APIs

**Dateien:** Alle `public` APIs in `Sources/BrainCore/`

**Loesung:** `///` Kommentare fuer alle public Types, Methoden und Properties:
```swift
/// Manages entry CRUD operations with SQLite persistence.
///
/// Thread-safe via GRDB's DatabasePool. All methods can be called
/// from any thread without MainActor isolation.
public struct EntryService: Sendable {
    /// Creates a new entry and returns it with the assigned ID.
    /// - Parameter entry: The entry to persist. `id` is ignored and auto-generated.
    /// - Returns: The persisted entry with its assigned `id`.
    /// - Throws: `DatabaseError` if the insert fails.
    public func create(_ entry: Entry) throws -> Entry { ... }
}
```

**Done-Kriterium:** Alle public Types und Methoden in BrainCore haben `///` Dokumentation. `swift package generate-documentation` laeuft ohne Fehler.

---

## Arbeitspaket 10: Niedrige Issues (Performance, UI, Misc)

**Scope:** L11, L12, L15 (verbleibend), L17 (verbleibend)
**Geschaetzter Aufwand:** S
**Abhaengigkeiten:** AP 4 und AP 5 sollten vorher abgeschlossen sein

### 10.1 — L11: SkillRenderer View-Instanz-Caching

**Datei:** `Sources/BrainApp/SkillRenderer.swift`

**Problem:** Bei jedem Render-Zyklus neue View-Instanzen.

**Loesung:** `EquatableView` Wrapper oder `@ViewBuilder` Caching fuer stabile Identitaeten. SwiftUI's Diffing-Algorithmus braucht stabile Identitaeten:
```swift
ForEach(children.indices, id: \.self) { index in
    renderNode(children[index])
        .id(children[index].stableId)
}
```

**Done-Kriterium:** Profiler zeigt keine redundanten View-Allokationen bei Skill-Rendering. Kein sichtbarer UI-Flicker.

### 10.2 — L12: Cache-Eviction-Policies

**Problem:** Kein explizites Cache-Management.

**Loesung:** `NSCache`-basierte Eviction fuer Dashboard-Daten und Skill-Rendering:
```swift
let cache = NSCache<NSString, CachedResult>()
cache.countLimit = 100
cache.totalCostLimit = 5 * 1024 * 1024 // 5 MB
```

**Done-Kriterium:** Cache raeumt automatisch auf bei Memory-Pressure. Kein manuelles `removeAll()` noetig.

---

## Abhaengigkeits-Graph

```
AP 1 (Keychain) ─────────────────────┐
AP 2 (ChatService) ──────────────────┤
AP 3 (Validierung) ──────────────────┤─→ AP 8 (Architektur-Refactoring)
AP 4 (UX Quick Wins) ────────────────┤         │
AP 5 (DB/Suche) ─────────────────────┘         ↓
AP 6 (Certificate Pinning) ──────────────→ AP 10 (Niedrige Issues)
AP 7 (Onboarding/i18n/a11y) ─────────────→ (nach AP 4)
AP 9 (Code-Qualitaet) ───────────────────→ (parallel moeglich)
```

**Empfohlene Reihenfolge:**
1. **AP 1 + AP 2 + AP 3** parallel (Sicherheit + Stabilisierung)
2. **AP 4 + AP 5 + AP 6** parallel (Quick Wins + DB + Netzwerk)
3. **AP 7 + AP 9** parallel (UX + Code-Qualitaet)
4. **AP 8** (Architektur — nach Stabilisierung, groesstes Risiko)
5. **AP 10** (Cleanup)

---

## Zusammenfassung

| AP | Scope | Aufwand | Issues | Prioritaet |
|----|-------|---------|--------|------------|
| 1 | Keychain & Secure Storage | M | K1, K3, K4, H2 | KRITISCH |
| 2 | ChatService & Error Handling | M | K2, M1, H4, H1 | KRITISCH |
| 3 | Validierung & Netzwerk | M | H3, H5, H7, M2, M3, M6 | HOCH |
| 4 | UX Quick Wins | S | Quick Wins + L14-L17 | MITTEL |
| 5 | DB & Suche | S | M4, M5, L10, L18 | MITTEL |
| 6 | Certificate Pinning | S | H6 | HOCH |
| 7 | Onboarding/i18n/a11y | L | L1, L5, L8, L9, L13 | MITTEL |
| 8 | Architektur-Refactoring | L | DataBridge, DI, Protocols, L20 | NIEDRIG |
| 9 | Code-Qualitaet & Build | M | L2-L4, L6, L7, L19, L21-L23 | NIEDRIG |
| 10 | Performance & Misc | S | L11, L12 | NIEDRIG |

**Total: 40 Issues abgedeckt in 10 Arbeitspaketen**

---

## Phase 9: Brain-generierte Skills (nach Audit-Fixes)

**Scope:** Brain (die KI) kann neue Skills entwerfen, dem User vorschlagen und installieren.
**Prioritaet:** FEATURE (nicht Audit-Fix)
**Abhaengigkeit:** AP 1-10 abgeschlossen, Skill Engine funktional

### Aktueller Stand

Brain kann aktuell:
- Installierte Skills auflisten (`skill_list` Tool)
- Vorgefertigte Skills installieren (`skill_install` Handler)
- 3 vorinstallierte Skills nutzen (reminders, patterns, proactive)

Brain kann NICHT:
- Neue Skills waehrend einer Konversation entwerfen
- Dem User Skill-Vorschlaege machen
- Aus erkannten Mustern automatisch Skills ableiten

### Implementierungs-Schritte

#### 9.1 — `skill_create` Tool fuer Claude

**Datei:** `Sources/BrainApp/ToolDefinitions.swift`

Neues Tool `skill_create` mit Parametern:
- `name`: Skill-Name
- `description`: Was der Skill tut
- `capability`: `app` | `brain` | `hybrid` (siehe 7.4 Skill-Capability-Feld)
- `permissions`: Array der benoetigten Berechtigungen
- `screens`: JSON-Definition der UI-Screens
- `actions`: JSON-Definition der Action-Steps
- `triggers`: Optionale Trigger-Konfiguration

Claude generiert die Skill-Definition als strukturiertes JSON — kein .brainskill.md Parsing noetig.

#### 9.2 — Skill-Proposal-Flow

**Datei:** `Sources/BrainApp/ActionHandlers.swift` (neuer SkillCreateHandler)

Flow:
1. Claude ruft `skill_create` auf → Handler erstellt Skill-Preview
2. Handler gibt "Vorschlag" zurueck mit Zusammenfassung und benoetigten Berechtigungen
3. ChatView zeigt Skill-Vorschlag als spezielle Karte (Name, Beschreibung, Berechtigungen, "Installieren"/"Ablehnen" Buttons)
4. User tippt "Installieren" → `SkillLifecycle.install()` wird aufgerufen
5. User tippt "Ablehnen" → Vorschlag wird verworfen

#### 9.3 — Skill-Vorschlag-UI in ChatView

**Datei:** `Sources/BrainApp/ChatView.swift`

Neue ChatBubble-Variante fuer Skill-Vorschlaege:
- Skill-Icon + Name + Beschreibung
- Berechtigungs-Liste mit Icons (DisclosureGroup)
- "Installieren" Button (gruen) + "Ablehnen" Button (grau)
- Nach Installation: Status-Update in der Chat-Historie

#### 9.4 — System-Prompt Erweiterung

**Datei:** `Sources/BrainApp/ChatService.swift`

System-Prompt erhaelt zusaetzlichen Abschnitt:
```
Du kannst neue Skills erstellen wenn der User eine wiederkehrende Aufgabe hat.
Nutze das skill_create Tool um einen Skill vorzuschlagen.
Erstelle nur Skills die mit den vorhandenen ActionHandlers umsetzbar sind.
Frage den User IMMER bevor du einen Skill installierst.
```

#### 9.5 — Proaktive Skill-Vorschlaege (optional)

**Datei:** `Sources/BrainApp/ProactiveService.swift`

PatternEngine analysiert wiederkehrende Aktionsmuster:
- "User fragt jeden Montag nach offenen Tasks" → Vorschlag: Wochen-Review Skill
- "User erstellt oft Entries mit Tag 'meeting'" → Vorschlag: Meeting-Notes Skill
- Vorschlaege als lokale Notification oder im Morning Briefing

### Done-Kriterium

- User kann im Chat sagen "Erstelle einen Skill der meine offenen Tasks jeden Morgen zeigt"
- Claude generiert einen Skill-Vorschlag mit UI-Definition und Actions
- User sieht den Vorschlag als Karte im Chat und kann ihn mit einem Tap installieren
- Installierter Skill erscheint im SkillManager und ist sofort nutzbar

---

## Deployment-Checkliste (pro Arbeitspaket)

1. [ ] Alle Fixes implementiert
2. [ ] `swift test` auf VPS gruen (294+ Tests)
3. [ ] Neue Tests fuer jeden Fix geschrieben
4. [ ] Keine neuen `print()`-Statements
5. [ ] Keine Force-Unwraps (`!`) ausserhalb von Tests
6. [ ] Neue Dateien in `project.pbxproj` eingetragen (PBXFileReference + PBXBuildFile)
7. [ ] `git push origin master` → Xcode Cloud Build → `xcode-cloud-deploy`
8. [ ] Build-Logs pruefen (Artifacts herunterladen bei Fehler)
9. [ ] TestFlight-Build auf Device testen
10. [ ] SESSION-LOG.md aktualisieren
