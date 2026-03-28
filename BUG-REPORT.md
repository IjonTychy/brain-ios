# brain-ios — Umfassender Bug-Report

**Datum:** 2026-03-25  
**Branch:** `claude/fix-skillviewmodel-context-LkYEV`  
**Methode:** Automatisierte Code-Analyse aller Subsysteme + Simulator-Tests  
**Geprüfte Bereiche:** Skill-System, Chat/LLM, Email/Kalender, Daten/Einträge, Navigation/UI, Einstellungen, Skill Engine/Bridges

---

## Übersicht

| Schwere | Anzahl | Status |
|---------|--------|--------|
| CRITICAL | 12 | Offen |
| HIGH | 18 | Offen |
| MEDIUM | 22 | Offen |
| LOW | 21 | Offen |
| **Gesamt** | **73** | |

### Bereits gefixt (Skill-System Diagnose)

| # | Bug | Commit |
|---|-----|--------|
| ✅ | Dashboard badge `text` statt `value` | 7ddbddf |
| ✅ | Stille Fehlerunterdrückung in Bootstrap | 7ddbddf |
| ✅ | Validator/Renderer badge Inkonsistenz | 7ddbddf |
| ✅ | Sprach-Skills in Skill-Liste sichtbar | 7ddbddf |
| ✅ | renderCard() ignorierte Properties | 7ddbddf |

---

## CRITICAL Bugs (12)

### C1: Dashboard Skill fehlt in DB ✅ GEFIXT
**Datei:** BootstrapSkills.swift:101  
**Fix:** Commit 7ddbddf

### C2: Race Condition in ChatService Streaming-Timer
**Datei:** ChatService.swift:119-131  
**Problem:** `streamingTimer` wird cancelled und neu erstellt ohne Synchronisation. Bei schnellem Senden mehrerer Nachrichten laufen mehrere Timer-Tasks parallel, `elapsedSeconds` wird von mehreren Quellen gleichzeitig inkrementiert.  
**Impact:** Falsche Timer-Anzeige, potentielle Memory-Leaks.

### C3: Template Expression Extraction Bug in LogicInterpreter
**Datei:** LogicInterpreter.swift:202-206  
**Problem:** `executeSet()` verwendet naives String-Replacement (`replacingOccurrences` von `{{` und `}}`). Bei mehrfachen Expressions wie `"{{a}} und {{b}}"` wird das zu `"a und b"` zusammengemischt statt einzeln evaluiert.  
**Impact:** Variablen erhalten falsche Werte bei komplexen Expressions.

### C4: Parentheses-Matching Bug in ExpressionParser
**Datei:** ExpressionParser.swift:144-160  
**Problem:** Off-by-one bei Klammervalidierung. Unbalancierte Klammern wie `"((a)"` werden nicht erkannt und als Literal behandelt.  
**Impact:** Malformierte Expressions produzieren falsche Ergebnisse.

### C5: Missing accountId bei Email Reply/Forward
**Datei:** MailComposeView.swift:24-25  
**Problem:** `accountId` ist optional in EmailCache. Bei Legacy-Mails ohne accountId wird nil an die Reply-Funktion übergeben → falsches Konto oder Crash bei Multi-Account.  
**Impact:** Email-Antworten gehen an falsches Konto.

### C6: Race Condition in Email-Account-Migration
**Datei:** EmailBridge.swift:44-93  
**Problem:** `migrateFromSingleAccountIfNeeded()` ist nicht thread-safe. Bei gleichzeitigem Aufruf entstehen Duplikat-Accounts.  
**Impact:** Doppelte Email-Konten, Daten-Korruption.

### C7: Race Condition bei Kontakt-Laden (PeopleTabView)
**Datei:** PeopleTabView.swift:155-177  
**Problem:** `loadContacts()` wird von `.task` und `.refreshable` ohne Synchronisation aufgerufen. Concurrent writes auf `contacts` State.  
**Impact:** UI-Crashes, korrupte Kontaktliste.

### C8: Entry.id Nil nach Insert
**Datei:** EntryRepository.swift:17-18  
**Problem:** `create()` gibt Entry zurück ohne zu prüfen ob `id` von GRDB zugewiesen wurde. Downstream-Code erwartet non-nil `id`.  
**Impact:** Crashes bei allen Operationen mit neu erstellten Entries.

### C9: Tag-ID nicht garantiert nach Insert
**Datei:** TagRepository.swift:17-37  
**Problem:** Nach `newTag.insert(db)` wird angenommen dass `tag.id` gesetzt ist. GRDB's `didInsert` könnte nicht synchron laufen. Guard auf Zeile 27 returned still bei nil.  
**Impact:** Tags werden nicht an Entries angehängt.

### C10: Keychain Fehlerbehandlung fehlt
**Datei:** KeychainService.swift  
**Problem:** Keychain-Operationen (delete, save) ohne Error-Handling. Fehlgeschlagene Löschungen lassen User mit unerreichbaren API-Keys.  
**Impact:** User kann API-Keys nicht korrekt verwalten.

### C11: StoreKit Transaction-Handling unvollständig
**Datei:** StoreKitManager.swift  
**Problem:** Fehlende Transaction-Completion-Handler. Unvollständige Käufe bleiben ewig im Pending-Status.  
**Impact:** User bezahlt aber erhält kein Pro-Abo.

### C12: Biometrie-Fallback speichert ohne Schutz
**Datei:** LLMProviderSettingsView.swift:426-428  
**Problem:** `saveWithBiometry()` fällt bei Fehler auf normalen Keychain-Save zurück, ohne den User zu informieren. User denkt Biometrie-Schutz ist aktiv.  
**Impact:** API-Keys sind ohne biometrischen Schutz gespeichert.

---

## HIGH Bugs (18)

### H1: Memory Leak — Uncancelled Background Task
**Datei:** ChatService.swift:297-303  
**Problem:** `Task.detached` für Knowledge-Extraction ohne Handle/Cancellation.

### H2: Memory Context bei On-Device Provider ignoriert
**Datei:** ChatService.swift:150-154  
**Problem:** Memory-Context wird berechnet aber nicht verwendet wenn On-Device Provider nicht verfügbar.

### H3: Unsafe Provider Casting
**Datei:** ChatService.swift:369, 381  
**Problem:** Cast auf `ToolUseProvider` ohne Guard, schlägt still fehl.

### H4: IMAP Connection Cleanup fehlt
**Datei:** EmailBridge.swift:138-146  
**Problem:** Bei fehlgeschlagenem `connect()` hängt `disconnect()` im defer-Block.

### H5: Email-Body ohne Grössenlimit
**Datei:** MailComposeView.swift:96-112  
**Problem:** Quoted Body bei Reply/Forward ohne Truncation → SMTP-Rejection möglich.

### H6: Unread-Count Cache nie invalidiert
**Datei:** MailTabView.swift:294-300  
**Problem:** Unread-Zähler wird einmal geladen und nie aktualisiert.

### H7: KnowledgeGraphView verschluckt Fehler
**Datei:** KnowledgeGraphView.swift:148-193  
**Problem:** Alle Errors silent gecatched, leerer Graph ohne Feedback.

### H8: ContactDetailView State-Mutation in init
**Datei:** PeopleTabView.swift:244-262  
**Problem:** `@State`-Properties im init mutiert → unreliable in SwiftUI.

### H9: EntryTags nie geladen in EntryDetailView
**Datei:** EntryDetailView.swift:16, 100+  
**Problem:** `entryTags` bleibt immer `[]`. Tags werden nie aus DB geladen.  
**Impact:** User sieht keine Tags an Einträgen.

### H10: Entry delete() scheitert still
**Datei:** EntryService.swift:65-71  
**Problem:** Wenn Entry nicht existiert, returned `delete()` ohne Fehler.

### H11: Kontakt-Suche ohne Error-Handling
**Datei:** SearchView.swift:345-356  
**Problem:** `ContactsBridge.search` Fehler werden mit `try?` geschluckt.

### H12: createdAt Format-Mismatch im Dashboard
**Datei:** DashboardRepository.swift:56-60  
**Problem:** String-Vergleich mit `>=` setzt identisches Datumsformat voraus. ISO8601 vs. yyyy-MM-dd Mismatch möglich.

### H13: Parallel-Execution verliert Context
**Datei:** LogicInterpreter.swift:318-341  
**Problem:** Variablen die in parallelen Tasks gesetzt werden, gehen verloren (lokale Kopien).

### H14: Unresolved Variables werden zu Leerstrings
**Datei:** ExpressionParser.swift:195-201  
**Problem:** `{{user.name}}` wird zu `""` wenn `user` nicht existiert. Kein Error/Placeholder.

### H15: Race Condition in ActionDispatcher Context
**Datei:** ActionDispatcher.swift:89-104  
**Problem:** `currentContext.variables` wird in async for-loop ohne Synchronisation mutiert.

### H16: Proxy-URL ohne Validierung gespeichert
**Datei:** SettingsView.swift:499  
**Problem:** Ungültige URLs werden in Keychain gespeichert, scheitern erst bei Verwendung.

### H17: JWT-Token wird bei Ablauf nicht gelöscht
**Datei:** BrainAPIAuthService.swift  
**Problem:** Expired Token bleibt gespeichert, wird wiederholt verwendet.

### H18: Monthly Budget ohne numerische Validierung
**Datei:** LLMBillingView.swift:157-162  
**Problem:** TextField akzeptiert Buchstaben. "abc" als Budget → Crash bei Vergleich.

---

## MEDIUM Bugs (22)

| # | Datei | Problem |
|---|-------|---------|
| M1 | ChatService.swift:102-103 | `isSending` Flag nicht atomic — Messages werden gedroppt |
| M2 | ChatService.swift:489 | Privacy Zone Detection: `try?` umgeht Restrictions bei DB-Fehler |
| M3 | ChatService.swift:226-230 | Tool Confirmation Handler Deadlock-Risiko |
| M4 | ChatService.swift:311-317 | Cost Tracking Failures still ignoriert |
| M5 | ChatService.swift:159 | systemPrompt Injection bei DB-Änderung während Streaming |
| M6 | ChatService.swift:237-239 | Tool Input nicht gegen Schema validiert |
| M7 | EventKitBridge.swift:68 | `defaultCalendarForNewEvents` kann nil sein |
| M8 | EmailBridge.swift:101-121 | Port-Validierung fehlt (1-65535) |
| M9 | CalendarReminderHandlers.swift:87-120 | Reminder-Access nicht geprüft vor Operationen |
| M10 | BackupView.swift:159-174 | Import-Dialog Race Condition mit pendingImportURL |
| M11 | ContentView.swift:155-157 | SettingsView Sheet fehlt StoreKitManager Environment |
| M12 | QuickCaptureView.swift:35-43 | onChange überschreibt User's Entry-Type-Auswahl |
| M13 | DashboardRepository.swift:53 | Unread Mail Count versteckt DB-Fehler |
| M14 | PrivacyZoneSettingsView.swift:161 | allTags nicht refreshed nach Zone-Änderung |
| M15 | RulesView.swift:99 | Rules unsortiert → unvorhersehbare UI |
| M16 | ProfileView.swift:64 | parseProfileToKnowledgeFacts löscht Facts ohne Rollback |
| M17 | ValidationModifier.swift | Validierung nur bei Blur, nicht bei Submit |
| M18 | LogicInterpreter.swift:56-58 | Fehlender Handler-Type wird still weitergereicht |
| M19 | ExpressionParser.swift:225-246 | Integer Overflow bei grossen Zahlen |
| M20 | RulesEngine.swift:63-72 | Unparseable Conditions matchen alles statt nichts |
| M21 | ExpressionParser.swift:287-296 | Negative Klammer-Tiefe nicht abgefangen |
| M22 | SearchService.swift:86-94 | Tag-Filter FTS5 Injection-Risiko |

---

## LOW Bugs (21)

| # | Datei | Problem |
|---|-------|---------|
| L1 | CalendarReminderHandlers.swift:7 | ISO8601DateFormatter bei jedem Aufruf neu erstellt |
| L2 | EventKitBridge.swift:19 | iOS-Version-Guard fehlt für `.fullAccess` |
| L3 | PeopleTabView.swift:482 | monthName() Array bei jedem Aufruf neu erstellt |
| L4 | BriefingView.swift:213 | Missing Accessibility Labels für StatPill/SectionCard |
| L5 | PeopleTabView.swift:503 | Potentieller Memory Leak in ContactEditor Coordinator |
| L6 | BriefingView.swift:31 | Unlocalized CHF-Beträge (Punkt vs. Komma) |
| L7 | FilesTabView.swift:118 | Search Query nicht getrimmt |
| L8 | DashboardRepository.swift:27 | 7+ separate DB-Queries statt aggregiert |
| L9 | TagRepository.swift:17 | Tag-Namen nicht getrimmt/validiert |
| L10 | EntryDetailView.swift:15 | Privacy Level nie geladen |
| L11 | EntryService.swift:157 | restore() erlaubt Wiederherstellen aller soft-deleted Entries |
| L12 | ExpressionParser.swift:84 | fatalError bei Regex-Fehler statt graceful handling |
| L13 | ExpressionParser.swift:186 | Unclosed String Literals werden zu null |
| L14 | LogicInterpreter.swift:118 | forEach ohne Begrenzung der Step-Komplexität |
| L15 | SkillDefinition.swift:32 | DataQuery.limit nicht validiert (negativ möglich) |
| L16 | LLMBillingView.swift:218 | Currency Formatter verliert Präzision bei kleinen Beträgen |
| L17 | LocalizationService.swift | Fehlende Keys zeigen internen Key-Namen statt Fallback |
| L18 | PrivacyZoneSettingsView.swift:149 | Force-Unwrap auf optionales tag.id |
| L19 | RulesView.swift:225 | parseTrigger() nil → leerer String statt Fehlermeldung |
| L20 | CostTracker.swift | DB-Fehler propagiert und crasht LLMBillingView |
| L21 | ChatService.swift:366-450 | Provider-Instanzen bei jedem Aufruf neu erstellt |

---

## Empfohlene Fix-Reihenfolge

### Sprint 1: Show-Stopper (CRITICAL)
1. **C3** — LogicInterpreter Expression Extraction
2. **C5/C6** — Email accountId + Migration Race
3. **C8/C9** — Entry/Tag ID nach Insert
4. **C10/C11** — Keychain + StoreKit
5. **C12** — Biometrie Fallback

### Sprint 2: Funktionale Bugs (HIGH)
1. **H9** — EntryTags nie geladen (sofort sichtbar für User)
2. **H6** — Unread Count Cache
3. **H12** — Dashboard createdAt Format
4. **H14** — Unresolved Variables zu Leerstrings
5. **H18** — Budget Validierung

### Sprint 3: Robustness (MEDIUM + LOW)
- Alle MEDIUM Bugs nach Priorität
- LOW Bugs als Teil von Quality Passes

---

*Erstellt am 2026-03-25 durch automatisierte Code-Analyse von 6 parallelen Review-Agents.*
*Skill-System-Bugs basierend auf Simulator-Tests, Rest auf statischer Code-Analyse.*

---

## Nachtrag: Deep-Dive Reviews (Kontakte, Wissensnetz, Dateien, Handler, Bridges, Renderer)

### Zusätzliche CRITICAL Bugs

#### C13: LinkService Query-Bug — gibt alle Links statt gefilterte zurück
**Datei:** LinkService.swift:40  
**Problem:** `ids.contains(Column("sourceId"))` ist falsche GRDB-Syntax. `ids.contains()` ist eine Swift-Array-Methode, nicht SQL. Query gibt wahrscheinlich **alle Links** zurück statt gefilterte.  
**Impact:** Wissensnetz zeigt falsche Verbindungen.

#### C14: ContactsBridge read()/listAll() ohne Permission-Check
**Datei:** ContactsBridge.swift:56-89  
**Problem:** `store.unifiedContacts()` wird aufgerufen ohne vorherigen `requestAccess()`. Crash wenn Permission nicht gewährt.  
**Impact:** App crasht beim Kontakt-Laden.

#### C15: ColorPicker Binding setzt immer leeren String
**Datei:** SkillRendererInput.swift:295-300  
**Problem:** `colorBinding` setter ignoriert den ausgewählten Farbwert und ruft `onSetVariable(key, .string(""))` auf. Farb-Änderungen werden nie gespeichert.  
**Impact:** ColorPicker in Skills funktioniert nicht.

### Zusätzliche HIGH Bugs

#### H19: AudioAnalysisBridge Memory Leak — inputNode.installTap()
**Datei:** AudioAnalysisBridge.swift:32-50  
**Problem:** Tap-Closure hält starke Referenz auf `self`. removeTap() nach engine.stop() → falsche Reihenfolge.

#### H20: AudioBridge Recording-Cancellation setzt Continuation nicht zurück
**Datei:** AudioBridge.swift:38-44  
**Problem:** Bei CancellationError wird `playerContinuation` nicht resettet → Race bei sofortigem play().

#### H21: EventKitBridge updateEvent() nicht async-safe
**Datei:** EventKitBridge.swift:74-82  
**Problem:** EKEvent-Mutation und `store.save()` blockieren. Nicht @MainActor-markiert.

#### H22: LocationBridge Race — isRequestInFlight nicht atomic
**Datei:** LocationBridge.swift:22-50  
**Problem:** Concurrent `currentLocation()`-Aufrufe können deadlocken. Flag ist nicht synchronized.

#### H23: Phone-Suche nicht case-insensitive
**Datei:** PeopleTabView.swift:26-35  
**Problem:** `phones.contains(where:)` wendet kein `lowercased()` an. Inkonsistente Suche.

#### H24: ContactHandlers Race nach Permission-Request
**Datei:** ContactHandlers.swift:16  
**Problem:** Nach `requestAccess()` kein Re-Check ob Permission tatsächlich gewährt wurde.

#### H25: Force Unwrap dataBridge in SettingsView
**Datei:** SettingsView.swift:316  
**Problem:** `dataBridge!.db.pool` — Crash wenn dataBridge nil.

#### H26: Force Unwrap sourceMarkdown in SkillManagerView
**Datei:** SkillManagerView.swift:464  
**Problem:** `skill.sourceMarkdown!.isEmpty` nach nil-Check, aber Force Unwrap unnötig.

### Zusätzliche MEDIUM Bugs

| # | Datei | Problem |
|---|-------|---------|
| M23 | BluetoothBridge.swift:19 | `isAvailable` prüft nicht ob Bluetooth eingeschaltet |
| M24 | ContactsBridge.swift:248 | Telefon-Duplikat-Erkennung zu aggressiv (Country Codes ignoriert) |
| M25 | AudioAnalysisBridge.swift:72 | FFT-Size nicht als Power-of-2 validiert |
| M26 | SpeechBridge.swift:71 | Timer nicht cancelled bei deinit → Use-after-free |
| M27 | NotificationBridge.swift | Keine Permission-Prüfung vor Reminder-Scheduling |
| M28 | CameraBridge.swift:64 | dismiss() auf deallocated ViewController → Crash |
| M29 | CoreActionHandlers.swift:10 | EmailBridge einmal erstellt, nie refreshed |
| M30 | PeopleTabView.swift:177 | Alle Fehler als "permission denied" angezeigt |
| M31 | PeopleTabView.swift:395 | Monat > 12 gibt leeren String statt Fehlermeldung |
| M32 | ContactsBridge.swift:305 | Force-Cast auf emailAddresses value |
| M33 | ContactsBridge.swift:313 | Leere Adressen-Einträge im Array |
| M34 | KnowledgeGraphView.swift:78 | Labels verschwinden bei Zoom-Out |
| M35 | KnowledgeGraphView.swift:180 | Division-by-Zero bei (0,0)-Nodes |
| M36 | KnowledgeFact.swift:6 | Alle Felder optional → leere Facts möglich |
| M37 | LinkRepository.swift:16 | Ungültige Relation defaulted still zu "related" |
| M38 | FilesTabView.swift:98 | Delete/Archive Feedback fehlt |
| M39 | ScannerBridge.swift:18 | Leerer String bei korrupten Bilddaten statt Error |
| M40 | CameraBridge.swift:19 | withCheckedContinuation ohne Timeout |
| M41 | SkillRendererLayout.swift:96 | TabView ForEach mit instabiler offset-ID |
| M42 | SkillRenderer.swift:336 | Non-String Properties (Int, Bool) returned nil statt Konvertierung |
| M43 | SkillRenderer.swift:377 | Chart-Daten Fehler still — leere Charts ohne Grund |
| M44 | SkillRendererInput.swift:186 | Multi-Picker selection Key undokumentiert |

### Zusätzliche LOW Bugs

| # | Datei | Problem |
|---|-------|---------|
| L22 | KnowledgeGraphView.swift:190 | Leerer catch-Block bei Graph-Laden |
| L23 | ScannerBridge.swift:76 | Telefonnummer-Validierung zu schwach (7+ Digits) |
| L24 | SkillRendererData.swift:160 | Kalender-Grid hardcoded 31 Tage (auch für Februar) |
| L25 | SkillRendererInput.swift:38 | Picker ohne bindingKey wird read-only ohne Feedback |
| L26 | SkillRendererInput.swift:145 | SearchField ohne bindingKey wird read-only |
| L27 | Diverse Renderer | Fehlende Accessibility Labels (Chart, Map, Gauge, HeatMap) |

---

## Aktualisierte Gesamtübersicht

| Schwere | Erstbericht | Deep-Dive | **Gesamt** |
|---------|-------------|-----------|------------|
| CRITICAL | 12 | +3 | **15** |
| HIGH | 18 | +8 | **26** |
| MEDIUM | 22 | +22 | **44** |
| LOW | 21 | +6 | **27** |
| **Total** | **73** | **+39** | **112** |

