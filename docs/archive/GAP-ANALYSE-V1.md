# brain-ios v1.0 — Gap-Analyse (Stand 19.03.2026)

## Gebaut & funktional (~40%)

### Engine & Core
- **SkillDefinition & ExpressionParser** — 21 Parser-Tests gruen
- **ComponentRegistry** — 47 UI-Primitives + Validation
- **ActionDispatcher & LogicInterpreter** — Error-Handling komplett
- **Render Engine** — JSON→SwiftUI, 22 Primitives
- **SkillCompiler & SkillLifecycle** — YAML Parser + Validation + Installation
- **GRDB Database** — 13 Tabellen, FTS5, Migrations, alle Services
- **Face ID** — DeviceBiometricAuthenticator, UI-Hook aktiv
- **LLM Router** — Multi-Provider (Anthropic, OpenAI)
- **Keychain** — API-Key Speicherung
- **Xcode Cloud CI** — Builds erfolgreich, TestFlight aktiv

### iOS Integration
- **DataBridge** — 20+ nonisolated Methoden
- **10 iOS Bridges** — Contacts, Calendar, Location, Notifications, Spotlight, Email(REST), Scanner, NFC, Speech, Pencil
- **4 Bootstrap-Skills** — Dashboard, Mail, Kalender, Quick Capture
- **Spotlight Integration** — CoreSpotlight indexing
- **8-Tab Navigation** — TabView (iPhone) / NavigationSplitView (iPad)
- **AppIcon** — 1024x1024 registriert

### Tests
- **294 BrainCore Tests gruen**
- **61 Action Handlers**
- **Swift 6 Concurrency Ready**

---

## Gebaut aber nicht auf echtem Device getestet (~10%)

| Feature | Status | Effort |
|---------|--------|--------|
| Speech-to-Text | Implementiert, 4 Apple-Warnings | Klein |
| PencilKit | Implementiert | Klein (iPad + Pencil) |
| VisionKit Scanner | Implementiert | Klein (echte Kamera) |
| NFC Tags | Implementiert | Klein (echte Tags) |
| Email Sync | REST-Bridge aktiv | Mittel |
| Contacts | Implementiert | Klein |
| EventKit | Implementiert | Klein |
| Notifications | Implementiert | Klein |

**Effort: ~4-6h auf echtem iPhone**

---

## Teilweise gebaut (~25%)

| Feature | Was fehlt | Effort |
|---------|----------|--------|
| **E-Mail IMAP/SMTP** | SwiftMail entfernt, nur REST-Bridge | Gross (3-5 Tage) |
| **LLM Chat UI + Streaming** | Provider da, keine Chat-View | Mittel (1-2 Tage) |
| **Self-Modifier** | Rules Engine da, keine Proposal-UI | Gross (1-2 Tage) |
| **App Intents / Siri** | Nicht definiert | Mittel (4-6h) |
| **Share Extension** | Braucht Xcode Target | Mittel (4-6h) |
| **Widgets** | Braucht Xcode Target | Mittel (1 Tag) |
| **CloudKit Sync** | Nicht gestartet | Sehr gross (1+ Woche) |
| **Knowledge Graph 3D** | Grape nicht implementiert | Sehr gross (v2.0) |

---

## Komplett fehlend (MVP-relevant, ~15%)

| Feature | Effort |
|---------|--------|
| **Search UI** (FTS5 existiert, kein UI) | Mittel (1 Tag) |
| **Skill Import/Export** (.brainskill.md) | Mittel (4-8h) |
| **On-This-Day** | Klein (2-3h) |
| **Backup/Migration** (brain-api Import) | Mittel (4-8h) |
| **Natural Language Input Parser** | Gross (2-3 Tage) |
| **Map View** | Mittel (1 Tag) |
| **On-Device LLM** | Gross (braucht neue SPM Dep) |

---

## v2.0 (kann warten)

- Knowledge Graph 3D Visualization
- Apple Intelligence Integration
- Temporal Map (Reisen-Timeline)
- Family Sharing (CloudKit Zones)
- Vision Pro Spatial Computing
- Custom Skill Marketplace
- Shortcut Composer
- Privacy Zones

---

## MVP-Kritikpfad (1 Woche bis Release)

### Essenzielle Gaps:
1. **LLM Chat UI + Streaming** (1-2 Tage) — ohne Chat nicht nutzbar
2. **System-Prompt fuer Brain-Identitaet** (erledigt 19.03.)
3. **Real Device Testing** (4-6h) — alle Bridges auf iPhone
4. **Share Extension** (4-6h) — "Teilen → Brain"
5. **Search UI** (1 Tag) — taegliches Feature
6. **E-Mail IMAP** (3-5 Tage) — oder REST-Bridge als v1.0-Kompromiss

### Realistische Schaetzung:
- **19.03.2026:** Build 36 TestFlight-ready, 294 Tests, 61 Handlers, System-Prompt
- **+3-4 Tage:** Chat UI, Email, Device Testing
- **+2-3 Tage:** Refinement, Bug-Fixes, TestFlight-Iteration
- **~1 Woche bis v1.0 Release Ready**

### Effort-Verteilung:
```
Gebaut & funktional:              ~40%
Teilweise gebaut:                 ~25%  (3-5 Tage)
Real-Device Testing:              ~10%  (4-6h)
Komplett fehlend (MVP-kritisch):  ~15%  (3-4 Tage)
Nice-to-have v2.0:               ~10%  (kann warten)
```
