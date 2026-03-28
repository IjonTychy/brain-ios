# brain-ios v2 — Projektplan "Next Level"

> Stand: 19.03.2026 | Build 40 (TestFlight Live)
> Grundlage: GAP-ANALYSE-V1.md, ARCHITECTURE.md, projekt-prozess.skill

---

## Vision

Brain wird vom Chatbot zum **handlungsfähigen persönlichen Assistenten**.
Es kann nicht nur antworten, sondern **agieren**: Entries erstellen, Kalender prüfen,
Erinnerungen setzen, Muster erkennen, proaktiv vorschlagen — und andere Apps
über Apple Shortcuts steuern.

---

## Ausgangslage (Build 40)

### Was funktioniert
- 294 BrainCore Tests grün, 61 Action Handlers, 10 iOS Bridges
- TestFlight Live, AppIcon, Keyboard-Bug gefixt
- System-Prompt: Brain weiß wer es ist und was es *theoretisch* kann
- Anthropic Provider mit Streaming
- GRDB mit 13 Tabellen, FTS5, alle Services
- Face ID, Keychain, Spotlight, 8-Tab Navigation
- 90 Renderer Primitives, 4 Bootstrap-Skills

### Was fehlt (kritisch)
- **Tool-Use**: Brain kann reden, aber nichts *tun* (keine Function Calls)
- **App Intents / Siri**: Keine Shortcuts-Integration
- **Share Extension**: Kein "Teilen → Brain"
- **Widgets**: Kein Homescreen-Zugriff
- **Search-UI**: FTS5 existiert, kein UI-Screen
- **Erinnerungen**: Brain erinnert nicht proaktiv
- **Mustererkennung**: PatternEngine existiert, aber nicht an Chat/UI angebunden
- **Proaktivität**: Brain analysiert nicht selbständig

---

## Phasen-Plan

### Phase 18: Tool-Use — Brain wird handlungsfähig
> **Priorität: KRITISCH** | Effort: 2-3 Tage | Blockiert alles andere

Brain hat 61 Action Handlers, aber der ChatService ruft nur `stream()` auf.
Claude bekommt keine Tools und kann nichts ausführen. Das ist der #1 Blocker.

**Steps:**

| Step | Beschreibung | Deliverable |
|------|-------------|-------------|
| 18.1 | **Tool-Definitionen generieren** | Alle 61 Handlers als Anthropic Tool-Schema (name, description, input_schema) |
| 18.2 | **AnthropicProvider erweitern** | `tools` Parameter in API-Request, `tool_use` / `tool_result` Blocks parsen |
| 18.3 | **ChatService Tool-Loop** | Wenn Claude `tool_use` zurückgibt → Handler ausführen → Ergebnis als `tool_result` zurück → Claude antwortet mit Ergebnis |
| 18.4 | **Chat-UI: Tool-Visualisierung** | Tool-Calls visuell anzeigen: "🔍 Durchsuche Entries..." → "✅ 3 gefunden" |
| 18.5 | **Chat-UI: Markdown-Rendering** | Markdown in Assistant-Nachrichten rendern (Bold, Listen, Links, Code) |
| 18.6 | **System-Prompt v2** | Dynamischer Kontext: heutige Termine, offene Tasks, letzte Entries. Brain weiß was *gerade* relevant ist |

**Gate-Kriterien:**
- User sagt "Erstelle einen Entry über XYZ" → Entry wird erstellt
- User sagt "Was steht heute im Kalender?" → Kalender wird abgefragt, Ergebnis angezeigt
- User sagt "Erinnere mich morgen an X" → Reminder wird gesetzt
- Tool-Calls sind visuell im Chat sichtbar
- Tests für Tool-Loop grün

---

### Phase 19: Erinnerungen, Mustererkennung & Proaktivität
> **Priorität: HOCH** | Effort: 3-4 Tage | Brains Intelligenz

Brain erkennt Muster, erinnert proaktiv und analysiert selbständig.
Diese Features werden als **vorinstallierte Skills** implementiert.

**Steps:**

| Step | Beschreibung | Deliverable |
|------|-------------|-------------|
| **19.1** | **Brain-Erinnerungen Skill** | Vorinstallierter Skill `brain-reminders.brainskill.md` |
| | - Intelligente Erinnerungen (nicht nur Timer, sondern kontextbezogen) | |
| | - "Du wolltest Sarah diese Woche anrufen" (aus Entry-Analyse) | |
| | - "Dein Meeting mit XY ist in 30 Minuten" (Kalender-Awareness) | |
| | - Überfällige Tasks proaktiv melden | |
| | - Background Task: `BGAppRefreshTask` für periodische Analyse | |
| | - Lokale Notifications mit Deep-Links zurück in die App | |
| **19.2** | **Mustererkennung Skill** | Vorinstallierter Skill `brain-patterns.brainskill.md` |
| | - PatternEngine an ChatService anbinden | |
| | - Streaks erkennen: "Du schreibst seit 5 Tagen täglich — weiter so!" | |
| | - Anomalien: "Du hast diese Woche ungewöhnlich wenig Entries — alles OK?" | |
| | - Themen-Cluster: "Du beschäftigst dich gerade viel mit X" | |
| | - Zeitliche Muster: "Deine produktivste Zeit ist 9-11 Uhr" | |
| | - Wiederkehrende Aufgaben erkennen → Automatisierung vorschlagen | |
| **19.3** | **Proaktivitäts-Engine** | Vorinstallierter Skill `brain-proactive.brainskill.md` |
| | - **Morgen-Briefing**: Automatisch beim App-Öffnen morgens | |
| | - Was steht heute an? (Kalender + Tasks) | |
| | - Überfällige Erinnerungen | |
| | - "On This Day": Vor 1 Woche/1 Monat/1 Jahr | |
| | - **Abend-Zusammenfassung**: Was wurde heute erledigt? | |
| | - **Déjà Vu**: Beim Erstellen eines neuen Entries verwandte alte Entries zeigen | |
| | - **Kontextuelle Vorschläge**: "Du hast gerade einen Entry über X geschrieben — soll ich Sarah informieren?" | |
| **19.4** | **Brain Pulse (Notifications)** | |
| | - Tägliche Lock-Screen-Notification mit Zusammenfassung | |
| | - Konfigurierbar: Morgens, Abends, oder beides | |
| | - Deep-Link: Tap → öffnet Briefing in der App | |
| **19.5** | **Self-Modifier UI** | |
| | - Proposal-Liste: Brain schlägt Verbesserungen vor | |
| | - Approve/Reject per Swipe | |
| | - Rules Engine visualisieren | |

**Gate-Kriterien:**
- Morgen-Briefing erscheint automatisch beim App-Start (7-10 Uhr)
- Brain erkennt mindestens 3 Pattern-Typen (Streak, Anomalie, Thema)
- Proaktive Notification funktioniert auf echtem Device
- "On This Day" zeigt alte Entries korrekt an
- Skills sind als .brainskill.md definiert und vom SkillLifecycle geladen

---

### Phase 20: Apple Shortcuts & Siri
> **Priorität: HOCH** | Effort: 2-3 Tage | System-Integration

Brain wird Teil des Apple-Ökosystems. Siri versteht Brain, Shortcuts
automatisieren Brain, andere Apps können Brain aufrufen.

**Steps:**

| Step | Beschreibung | Deliverable |
|------|-------------|-------------|
| 20.1 | **App Intents definieren** | 8-10 Core Intents als `AppIntent` Structs |
| | - `AddEntryIntent` — Neuen Entry erstellen | |
| | - `SearchBrainIntent` — In Brain suchen | |
| | - `AskBrainIntent` — Brain eine Frage stellen (LLM) | |
| | - `DailyBriefingIntent` — Morgen-Briefing abrufen | |
| | - `QuickCaptureIntent` — Schnellerfassung | |
| | - `SetReminderIntent` — Erinnerung setzen | |
| | - `ListTasksIntent` — Offene Tasks auflisten | |
| | - `ListEventsIntent` — Heutige Termine | |
| 20.2 | **AppShortcutsProvider** | Vordefinierte Shortcuts für Spotlight & Siri |
| 20.3 | **Shortcut Suggestions** | Brain schlägt Shortcuts basierend auf Nutzung vor |
| 20.4 | **Shortcuts Automations** | Vorgefertigte Templates: Morgen-Routine, Meeting-Prep, Wochen-Review |
| 20.5 | **Focus Filter** | `SetFocusFilterIntent`: Arbeit/Persönlich/Kreativ |

**Gate-Kriterien:**
- "Hey Siri, füg meinem Brain hinzu: Idee für neues Feature" → Entry erstellt
- "Hey Siri, was steht heute an?" → Briefing vorgelesen
- Brain erscheint in Spotlight-Suche
- Mindestens 3 vordefinierte Shortcut-Templates

---

### Phase 21: Share Extension & Widgets
> **Priorität: HOCH** | Effort: 1-2 Tage | Braucht neue Xcode Targets

**Steps:**

| Step | Beschreibung | Deliverable |
|------|-------------|-------------|
| 21.1 | **Share Extension Target** | Neues Xcode Target: `BrainShareExtension` |
| | - Text, URL, Bild, PDF akzeptieren | |
| | - AI-Zusammenfassung bei URLs (optional) | |
| | - Tag-Auswahl beim Teilen | |
| 21.2 | **Widget Target** | Neues Xcode Target: `BrainWidgets` |
| | - **Quick Capture Widget** (Small) — Tap → Eingabe | |
| | - **Heutige Tasks Widget** (Medium) — Offene Aufgaben | |
| | - **Brain Pulse Widget** (Medium) — Tages-Zusammenfassung | |
| | - **Nächste Termine Widget** (Small) — Kalender-Preview | |
| 21.3 | **App Group** | Shared Container für DB-Zugriff aus Extensions |
| 21.4 | **Live Activity** (optional) | Aktuelle Focus-Task auf Lock Screen |

**Gate-Kriterien:**
- "Teilen → Brain" funktioniert aus Safari, Fotos, Mail
- Mindestens 2 Widgets auf Homescreen funktional
- DB-Zugriff aus Extension via App Group

---

### Phase 22: Chat-UI & UX Verfeinerung
> **Priorität: MITTEL** | Effort: 2-3 Tage

**Steps:**

| Step | Beschreibung | Deliverable |
|------|-------------|-------------|
| 22.1 | **Search-UI** | Globale Suchleiste mit FTS5 + Autocomplete, Ergebnisse nach Typ gruppiert, Filter (Datum, Tags, Typ) |
| 22.2 | **Unified Input Bar** | NLP-Eingabe: "Treffen mit Sarah morgen 15 Uhr" → Event. Nutzt NaturalLanguage Framework |
| 22.3 | **Chat-UI Polish** | Streaming-Animation, Retry bei Fehler, Chat-History durchsuchbar, Conversation-Kontexte |
| 22.4 | **Onboarding v2** | Interaktives Tutorial: Brain stellt sich vor, zeigt Fähigkeiten, API-Key-Setup mit Erklärung |
| 22.5 | **Swipe-Gesten** | Things-3-Pattern: Swipe → Termin setzen, Swipe ← Archivieren, Long Press → alle Optionen |
| 22.6 | **Map View** | Entries mit Geo-Daten auf MapKit-Karte |

**Gate-Kriterien:**
- Suche findet Entries in < 100ms
- NLP-Input erkennt mindestens: Datum, Person, Typ (Task/Event/Note)

---

### Phase 23: On-Device LLM & Offline-Modus
> **Priorität: MITTEL** | Effort: 3-5 Tage

**Steps:**

| Step | Beschreibung | Deliverable |
|------|-------------|-------------|
| 23.1 | **Apple Foundation Models** | Integration von Apples On-Device LLM (iOS 26+, ~3B Parameter). `@Generable` Macro für constrained JSON |
| 23.2 | **LLM Router Update** | Automatisches Routing: Offline → On-Device, Sensibel → On-Device, Komplex → Cloud |
| 23.3 | **Modell-Download UI** | Einstellungen → Modell herunterladen, Speicherplatz-Anzeige |
| 23.4 | **Offline-Fähigkeiten** | Einfache Tasks (Tagging, Zusammenfassung, Klassifizierung) ohne Internet |
| 23.5 | **Privacy Zones** | Medizinisch → nur On-Device, Geschäft → nur genehmigtes Cloud-LLM |

**Gate-Kriterien:**
- Brain antwortet offline auf einfache Fragen
- LLM Router wählt automatisch das richtige Modell
- User kann Routing-Regeln konfigurieren

---

### Phase 24: Fortgeschrittene Skills & Skill-Ökosystem
> **Priorität: NIEDRIG** | Effort: 3-5 Tage

**Steps:**

| Step | Beschreibung | Deliverable |
|------|-------------|-------------|
| 24.1 | **Skill Import/Export** | `.brainskill.md` Import via Dateien-App, AirDrop, URL-Schema `brain://import-skill?url=...` |
| 24.2 | **Shortcut Composer** | Brain analysiert Workflow und schlägt Shortcuts vor: "Du öffnest jeden Morgen Mail, dann Kalender — soll ich das automatisieren?" |
| 24.3 | **NFC Brain Spots** | NFC-Sticker → Projekt/Kontext öffnen. Konfiguration im Skill |
| 24.4 | **Conversation Memory** | Cross-Referenz: Personen ↔ Themen ↔ Zeitpunkte. "Was hat Sarah letzte Woche gesagt?" |
| 24.5 | **Knowledge Graph UI** | Grape-basierte Netzwerk-Visualisierung (2D für iPhone, vorbereitet für 3D/Vision Pro) |

---

### Phase 25: Handschrift-Font Pipeline
> **Priorität: MITTEL** | Effort: 5-7 Tage | Vorinstallierter Skill `brain-handwriting-font`

Brain scannt die Handschrift des Users und erstellt daraus eine installierbare
OpenType-Schriftart (.otf) — inklusive kursiver Verbindungen via Contextual Alternates.

**Scan-Ablauf:** 7 Bögen (A-Z, a-z, Zahlen, Sonderzeichen, Bigramme, Kontexte, Pangram)

**Steps:**

| Step | Beschreibung | Deliverable |
|------|-------------|-------------|
| 25.1 | **H1: `font.segment` Handler** | Scan → Segmentierte Glyphen. Vision.framework Raster-Erkennung, Glyph-Isolation, Bigramm-Splitting, Anchor-Erkennung (Zhang-Suen Skelettierung). Modes: `.isolated`, `.bigram`, `.freeform` |
| 25.2 | **H2: `font.vectorize` Handler** | Bitmap → Bezier-Vektoren. Suzuki-Abe Konturverfolgung (keine GPL-Dependency), Douglas-Peucker + kubische Bezier-Approximation, Normalisierung (Baseline, x-Height, Ascender, Descender), Connection-Class-Clustering (5-8 Exit/Entry-Klassen) |
| 25.3 | **H3: `font.generate` Handler** | Vektoren → .otf Datei. Eigener OpenType-Writer in Swift (~2000-3000 LOC). Tabellen: head, hhea, maxp, OS/2, name, cmap, post, CFF, GPOS, GSUB, hmtx |
| 25.4 | **CFF Encoder** | CFF Type 2 Charstring Encoding (moveto, lineto, curveto). Keine Hints (optimiert ab 16pt) |
| 25.5 | **GSUB Builder** | `calt` Feature: Contextual Alternates für kursive Verbindungen. Exit-Klassen (@ExitHigh, @ExitMid) → Entry-Klassen |
| 25.6 | **GPOS Builder** | `curs` Feature: Cursive Attachment mit Entry/Exit-Anchors. `kern` Feature: Auto-Kerning via Seitenband-Analyse |
| 25.7 | **Skill-Definition** | `brain-handwriting-font.brainskill.md` mit UI-Flow für 7 Bögen, Qualitätskontrolle, Nachscan, Preview, Export |
| 25.8 | **iPad Pencil-Pfad** | Alternative zu Kamera: PencilBridge für direktes Schreiben auf Screen. Gleiche Pipeline ab H2 |

**Neue Dateien:**
```
Sources/BrainApp/Handlers/
  FontSegmentHandler.swift
  FontVectorizeHandler.swift
  FontGenerateHandler.swift

Sources/BrainApp/Font/
  OpenTypeWriter.swift
  CFFEncoder.swift
  GSUBBuilder.swift
  GPOSBuilder.swift
  GlyphContourTracer.swift
  BezierFitter.swift
  ConnectionClassifier.swift
```

**Frameworks:** Vision, CoreGraphics, CoreText, Accelerate (keine neuen SPM Dependencies)

**Offene Entscheidungen:**
- Font-Hinting: Für v1.0 weglassen (Hinweis "ab 16pt optimiert")
- iPad Pencil-Pfad: Parallel oder nachgelagert?
- Maximale Glyph-Anzahl: ~200-300 (kein Problem für OpenType)

**Gate-Kriterien:**
- Scan von 7 Bögen → Font mit ~200 Glyphen generiert
- Kursive Verbindungen funktionieren in CoreText-Rendering
- Font installierbar via UIFont/CTFont
- Preview-Text zeigt verbundene Handschrift korrekt
- Generierte .otf validiert (alle Pflicht-Tabellen vorhanden)

---

---

## Vorinstallierte Skills (Phase 19 Detail)

### brain-reminders.brainskill.md
```yaml
id: brain-reminders
name: Intelligente Erinnerungen
description: Brain erinnert proaktiv an Aufgaben, Termine und Versprechen
version: 1.0
created_by: system
permissions: [notifications, calendar, entries]
triggers:
  - type: app_open
  - type: schedule
    cron: "0 7,12,18 * * *"
  - type: entry_created
```
**Aktionen:**
- Überfällige Tasks als Notification
- "Du wolltest X diese Woche erledigen" (Entry-Analyse)
- Kontext-Erinnerungen bei App-Öffnung
- Intelligentes Timing (nicht stören während Focus)

### brain-patterns.brainskill.md
```yaml
id: brain-patterns
name: Mustererkennung
description: Brain erkennt Muster in deinem Verhalten und gibt Einblicke
version: 1.0
created_by: system
permissions: [entries, knowledge_facts]
triggers:
  - type: schedule
    cron: "0 21 * * 0"  # Sonntag Abend
  - type: entry_count_milestone
```
**Aktionen:**
- Wöchentliche Pattern-Analyse
- Streak-Detection + Motivation
- Anomalie-Erkennung
- Themen-Trend-Analyse
- Erkenntnisse als Knowledge Facts speichern

### brain-proactive.brainskill.md
```yaml
id: brain-proactive
name: Proaktiver Assistent
description: Brain denkt mit und schlägt vor, bevor du fragst
version: 1.0
created_by: system
permissions: [entries, calendar, contacts, notifications]
triggers:
  - type: app_open
    condition: "time >= 06:00 AND time <= 10:00"
  - type: app_open
    condition: "time >= 18:00 AND time <= 22:00"
  - type: entry_created
```
**Aktionen:**
- Morgen-Briefing (Tasks + Kalender + Überfällig + On-This-Day)
- Abend-Zusammenfassung (Was erledigt? Was offen?)
- Déjà Vu (verwandte Entries bei neuen Entries)
- Kontextuelle Vorschläge ("Soll ich Sarah informieren?")
- Vorbereitung auf Meetings (Kontakt-Entries + letzte E-Mails sammeln)

---

## Effort-Übersicht

| Phase | Name | Effort | Abhängigkeiten |
|-------|------|--------|----------------|
| **18** | Tool-Use | 2-3 Tage | — (keine) |
| **19** | Erinnerungen, Muster, Proaktivität | 3-4 Tage | Phase 18 (Tool-Use für Aktionen) |
| **20** | Apple Shortcuts & Siri | 2-3 Tage | Phase 18 (Intents nutzen gleiche Handler) |
| **21** | Share Extension & Widgets | 1-2 Tage | Braucht Xcode (neue Targets) |
| **22** | Chat-UI & UX | 2-3 Tage | Phase 18 (Tool-Visualisierung) |
| **23** | On-Device LLM | 3-5 Tage | Unabhängig |
| **24** | Skills & Ökosystem | 3-5 Tage | Phase 19+20 |
| **25** | Handschrift-Font Pipeline | 5-7 Tage | ScannerBridge, PencilBridge |

**Kritischer Pfad:** Phase 18 → 19 → 20 → 21 (parallel mit 22)
**Parallel-Track:** Phase 25 (unabhängig, nutzt bestehende Bridges)

---

## Technische Entscheidungen (vorab)

1. **Tool-Use statt Custom Actions:** Anthropic Tool-Use API ist der richtige Weg — nicht eigenes JSON-Parsing. Claude versteht die Tools und entscheidet selbst, wann welches Tool aufgerufen wird.

2. **Skills als First-Class Citizens:** Erinnerungen, Muster und Proaktivität werden als `.brainskill.md` implementiert, nicht als hardcodierte Features. Das beweist die Skill-Engine und macht alles konfigurierbar.

3. **App Group für Extensions:** Share Extension und Widgets brauchen Zugriff auf die GRDB-Datenbank. Das geht nur über einen Shared App Group Container. Einmalige Migration nötig.

4. **Background Tasks für Proaktivität:** `BGAppRefreshTask` + `BGProcessingTask` für periodische Analyse. Unzuverlässig (Apple throttled), deshalb zusätzlich Analyse bei App-Öffnung.

5. **Keine eigene NLP-Engine:** Für Unified Input Bar nutzen wir Apples NaturalLanguage Framework + ein LLM-Fallback. Kein Eigengewächs.

---

## Nächster Schritt

Phase 18 starten: **Tool-Use Implementation**

Dafür brauche ich:
1. ✅ VPS-Zugang (habe ich)
2. ✅ GitHub-Zugang (habe ich)
3. ⬜ MacVM-Tunnel (wenn Xcode-Targets nötig — ab Phase 21)
4. ⬜ Freigabe von Andy

Soll ich Phase 18 starten?
