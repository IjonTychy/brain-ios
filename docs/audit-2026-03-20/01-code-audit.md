# Brain-iOS Code Audit Report

**Datum:** 20. Maerz 2026
**Scope:** Vollstaendige Codebase-Analyse (`Sources/BrainCore`, `Sources/BrainApp`, Tests)
**Methodik:** Statische Analyse, Architektur-Review, Security-Audit

---

## Zusammenfassung

| Schweregrad | Anzahl |
|-------------|--------|
| KRITISCH    | 4      |
| HOCH        | 7      |
| MITTEL      | 6      |
| NIEDRIG     | 23     |
| **Gesamt**  | **40** |

---

## KRITISCH (4)

### K1: Secure Enclave nicht implementiert in BiometricAuth

**Datei:** `Sources/BrainApp/BiometricAuth.swift`
**Problem:** `saveWithBiometry()` in `KeychainService` deklariert Secure-Enclave-Nutzung via `kSecAttrAccessControl` mit `.biometryCurrentSet`, speichert den Key aber im Standard-Keychain — nicht im Secure Enclave (`kSecAttrTokenIDSecureEnclave` fehlt).
**Risiko:** API-Keys sind extrahierbar bei Jailbreak oder physischem Zugriff mit Backup-Extraction.
**Empfehlung:** `kSecAttrTokenID: kSecAttrTokenIDSecureEnclave` zum Query-Dictionary hinzufuegen. Fallback auf Standard-Keychain nur wenn Secure Enclave nicht verfuegbar (Simulator).

### K2: Race Condition in ChatService.send()

**Datei:** `Sources/BrainApp/ChatService.swift`
**Problem:** `send()` ist `async` aber nicht `actor`-isoliert. Mehrere gleichzeitige Aufrufe (z.B. durch schnelles Doppeltippen) koennen das `messages`-Array korrumpieren, da `append()` und Tool-Call-Verarbeitung nicht atomar sind.
**Risiko:** Crash, Datenverlust, oder inkonsistenter Chat-Zustand.
**Empfehlung:** Entweder `ChatService` zum `actor` machen, oder einen `AsyncStream`-basierten Message-Queue implementieren. Alternativ: UI-seitig den Send-Button waehrend der Verarbeitung deaktivieren UND einen Guard (`isSending`) einbauen.

### K3: Unvalidierte API-Key-Speicherung

**Datei:** `Sources/BrainApp/SettingsView.swift`, `Sources/BrainCore/Services/KeychainService.swift`
**Problem:** API-Keys werden ohne jede Validierung gespeichert. Ein leerer String oder Whitespace wird als "konfiguriert" behandelt (`keychain.exists()` prueft nur Existenz, nicht Inhalt).
**Risiko:** User denkt API ist konfiguriert, bekommt aber kryptische Fehler bei LLM-Aufrufen.
**Empfehlung:** Minimale Validierung (nicht leer, Prefix-Check `sk-ant-` fuer Anthropic, `sk-` fuer OpenAI). Optional: Test-Request bei Speicherung.

### K4: Anthropic Max Session Key ohne TTL/Rotation

**Datei:** `Sources/BrainCore/LLM/AnthropicProvider.swift`
**Problem:** Wenn ein Anthropic Max Session-Key verwendet wird, liegt dieser im selben Keychain-Slot wie der permanente API-Key. Es gibt keinen TTL-Mechanismus und keine automatische Rotation.
**Risiko:** Session-Keys haben normalerweise eine begrenzte Gueltigkeit. Abgelaufene Keys fuehren zu schwer debugbaren Fehlern.
**Empfehlung:** Separater Keychain-Eintrag fuer Session-Keys mit gespeichertem Expiry-Timestamp. Automatische Loesch-Logik bei Ablauf.

---

## HOCH (7)

### H1: Silent Exception Swallowing in ProactiveService

**Datei:** `Sources/BrainCore/Services/ProactiveService.swift`
**Problem:** Durchgehend `try?` statt `try` — alle Fehler werden still ignoriert.
**Risiko:** Proaktive Features (Erinnerungen, Vorschlaege) versagen ohne jede Rueckmeldung.
**Empfehlung:** `do/catch` mit Logging. Mindestens `os_log` fuer Debug-Builds.

### H2: Email-Passwort ohne biometrische Absicherung

**Datei:** `Sources/BrainCore/Bridges/EmailBridge.swift`
**Problem:** IMAP/SMTP-Passwort wird im Keychain gespeichert, aber ohne `SecAccessControl` mit Biometrie-Gate. Andere Keychain-Eintraege (API-Keys) haben Biometrie-Schutz.
**Risiko:** Inkonsistente Sicherheitsebene. Email-Passwort ist bei Jailbreak leichter extrahierbar als API-Keys.
**Empfehlung:** Gleiche `SecAccessControl`-Policy wie fuer API-Keys anwenden.

### H3: Fehlende Input-Validierung in EntryDetailView

**Datei:** `Sources/BrainApp/EntryDetailView.swift`
**Problem:** Titel und Body haben keine Laengenbegrenzung. Extrem lange Eingaben koennten die SQLite-DB aufblaaehen oder das UI blockieren.
**Empfehlung:** Soft-Limit mit Warnung (z.B. 10'000 Zeichen fuer Body, 500 fuer Titel).

### H4: Fehlende Error-Propagation in ActionHandlers

**Datei:** `Sources/BrainCore/Engine/ActionHandlers/`
**Problem:** Mehrere ActionHandler fangen Fehler und geben generische "Fehler aufgetreten"-Meldungen zurueck, ohne den eigentlichen Fehler zu propagieren.
**Risiko:** Debugging ist fuer Entwickler und User unmoeglich.
**Empfehlung:** Strukturierte Error-Responses mit Error-Code und Beschreibung.

### H5: SkillService JSON-Validierung unvollstaendig

**Datei:** `Sources/BrainCore/Services/SkillService.swift`
**Problem:** `install()` validiert die JSON-Struktur der Skill-Definition, aber nicht die semantische Korrektheit (z.B. ob referenzierte Screens existieren, ob Action-Handler registriert sind).
**Risiko:** Skill installiert sich erfolgreich, crasht aber beim ersten Aufruf.
**Empfehlung:** Semantische Validierung in `SkillCompiler.validate()` erweitern.

### H6: Statische Certificate Pins ohne Rotations-Mechanismus

**Datei:** `Sources/BrainCore/Network/CertificatePinning.swift`
**Problem:** SPKI-Hashes sind hardcoded. Bei Zertifikats-Rotation durch Anthropic/OpenAI muss ein App-Update released werden.
**Risiko:** App verliert API-Zugang bis zum naechsten Update.
**Empfehlung:** Backup-Pins sind vorhanden (gut!). Zusaetzlich: Remote-Config fuer Pin-Updates oder Trust-on-First-Use als Fallback.

### H7: Kein Memory-Limit fuer Variable-Bindings in LogicInterpreter

**Datei:** `Sources/BrainCore/Engine/LogicInterpreter.swift`
**Problem:** `maxRecursionDepth=20` und `maxForEachIterations=1000` sind gesetzt, aber es gibt kein Limit fuer die Anzahl oder Groesse der Variable-Bindings im Scope.
**Risiko:** Ein boeswilliger Skill koennte den Speicher durch massenhaftes Erstellen von Variablen erschoepfen.
**Empfehlung:** Limit fuer Scope-Groesse (z.B. 1000 Variablen, 1 MB Gesamtgroesse).

---

## MITTEL (6)

### M1: Tool-Call Confirmation Handler kann nil sein

**Datei:** `Sources/BrainApp/ChatService.swift`
**Problem:** `confirmationHandler` ist optional. Wenn nicht gesetzt, werden destruktive Tool-Calls ohne Bestaetigung ausgefuehrt.
**Empfehlung:** Default-Handler der immer `false` zurueckgibt (deny by default).

### M2: Unvollstaendige Markdown-Sanitisierung

**Datei:** `Sources/BrainCore/Utilities/DataSanitizer.swift`
**Problem:** `sanitizeForLLM()` trunciert nach Laenge, aber sanitisiert keine Markdown-Injection-Patterns (z.B. `![](http://evil.com/tracking.gif)` in Entry-Titeln die an den LLM geschickt werden).
**Empfehlung:** Image-URLs und Link-URLs in LLM-Kontext strippen oder escapen.

### M3: Kein Retry-Logic fuer Netzwerk-Fehler

**Datei:** `Sources/BrainCore/LLM/AnthropicProvider.swift`, `OpenAIProvider.swift`
**Problem:** Bei transientem Netzwerk-Fehler (Timeout, 503) gibt es keinen automatischen Retry.
**Empfehlung:** Exponential Backoff mit max. 3 Retries fuer 429/503/Timeout.

### M4: FTS5-Tokenizer-Konfiguration nicht optimal

**Datei:** `Sources/BrainCore/Database/DatabaseManager.swift`
**Problem:** FTS5 nutzt den Default-Tokenizer (`unicode61`). Fuer deutsche Texte waere `porter` oder ein Custom-Tokenizer mit Stemming besser.
**Empfehlung:** `tokenize='porter unicode61'` fuer bessere Suchergebnisse bei deutschen Woertern (Konjugation, Deklination).

### M5: Fehlende Pagination bei Entry-Listen

**Datei:** `Sources/BrainCore/Services/EntryService.swift`
**Problem:** `list(limit:)` hat einen Limit-Parameter, aber keinen Offset. Bei vielen Entries muss der gesamte Datensatz bis zum gewuenschten Offset geladen werden.
**Empfehlung:** `list(limit:offset:)` Parameter hinzufuegen.

### M6: EventKit-Zugriff ohne Graceful Degradation

**Datei:** `Sources/BrainCore/Bridges/EventKitBridge.swift`
**Problem:** Wenn der User Kalender-Zugriff verweigert, zeigt der Kalender-Skill eine leere Liste ohne Erklaerung.
**Empfehlung:** Unterscheidung zwischen "keine Events" und "kein Zugriff" mit entsprechender UI-Meldung.

---

## NIEDRIG (23)

| # | Bereich | Problem |
|---|---------|---------|
| L1 | i18n | Alle UI-Strings auf Deutsch hardcoded, kein `Localizable.strings` |
| L2 | Tests | Fehlende Unit-Tests fuer `SkillCompiler`, `LogicInterpreter`, `RulesEngine` |
| L3 | Tests | Keine UI-Tests vorhanden |
| L4 | Debug | `print()`-Statements in Produktionscode (`DataBridge`, `ChatService`) |
| L5 | Errors | Inkonsistente Error-Messages (mal Deutsch, mal Englisch) |
| L6 | Linting | Keine SwiftLint-Konfiguration |
| L7 | Logging | Kein strukturiertes Logging-Framework (nur `print()` und `#if DEBUG`) |
| L8 | Accessibility | VoiceOver-Labels nicht durchgaengig gesetzt |
| L9 | Accessibility | Dynamic Type wird nicht ueberall unterstuetzt |
| L10 | Performance | `refreshDashboard()` macht 5 separate DB-Queries statt einer kombinierten |
| L11 | Performance | `SkillRenderer` erstellt bei jedem Render-Zyklus neue View-Instanzen |
| L12 | Memory | Keine expliziten Cache-Eviction-Policies |
| L13 | UX | Kein Onboarding fuer neue User |
| L14 | UX | Kein Undo bei Swipe-to-Delete |
| L15 | UX | Kein Pull-to-Refresh in Listen-Views |
| L16 | UX | Skill-Berechtigungen werden angezeigt aber nicht erklaert |
| L17 | UX | Leere Zustaende ohne hilfreiche Call-to-Action |
| L18 | Code | `DateFormatter` wird in Schleifen neu erstellt statt gecached |
| L19 | Code | Inkonsistente Naming-Conventions (`camelCase` vs `snake_case` in JSON-Keys) |
| L20 | Code | Mehrere `nonisolated` Annotationen in `DataBridge` koennten durch Actor-Refactor eliminiert werden |
| L21 | Build | Zwei `Package.resolved`-Dateien muessen synchron gehalten werden |
| L22 | Build | Keine Build-Warnings in CI als Fehler konfiguriert |
| L23 | Docs | Kein inline API-Dokumentation (DocC-Comments) fuer Public APIs in BrainCore |

---

## Architektur-Bewertung

### Staerken
- **Clean Architecture**: Klare Trennung BrainCore (Framework) / BrainApp (UI)
- **GRDB-Nutzung**: Typsichere Queries, Migrations, Connection-Pool
- **Skill Engine**: Durchdachtes Design mit Compiler, Validator, Renderer, Lifecycle
- **Swift 6 Concurrency**: Strict-Concurrency aktiviert, `Sendable`-Conformance durchgehend
- **Security**: Certificate Pinning, Keychain, FTS5/LIKE-Sanitisierung, Skill-Integrity-Hashing

### Schwaechen
- **DataBridge als God Object**: 400 Zeilen, 30+ Methoden — sollte in spezialisierte Repositories aufgeteilt werden
- **Fehlende Dependency Injection**: Services werden in `DataBridge.init()` hardcoded erstellt
- **Kein Protokoll-basiertes Design**: Services sind konkrete Klassen, nicht Protokolle — erschwert Testing
- **Tight Coupling**: `ChatService` kennt `DataBridge`, `SkillRenderer`, `LLMRouter` direkt
