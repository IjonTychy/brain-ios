# brain-ios — Architektur & Vision

> 2ndBrain als native iOS-App. Kein VPS. Alles auf dem Gerät.
> iPhone + iPad + Apple Vision Pro. SwiftUI + Swift 6.
> **Runtime-Engine mit KI-generierten Skills. Multi-LLM. On-Device ML-ready.**

---

## Vision

Ein persönliches Gehirn, das auf Deinem iPhone lebt — und sich selbst erweitern kann.

Die App ist kein fertiges Produkt mit festcodierten Modulen. Sie ist eine **Runtime-Engine**,
die von einer KI mit neuen Fähigkeiten bestückt wird. Die KI liest Skill-Definitionen
(Markdown), übersetzt sie in ausführbare Konfigurationen (JSON), und die Engine rendert
daraus native UIs und führt Workflows aus. Neue Features brauchen kein App-Update — nur
einen neuen Skill.

**Die Metapher:** Markdown ist die DNA, die KI ist das Ribosom, JSON ist das Protein,
die App ist die Zelle. Die Proteine können nur Funktionen ausführen, für die die Zelle
Maschinerie hat — aber das Vokabular der Zelle ist gross genug, dass fast alles möglich ist.

Daneben steht eine **Proaktive Intelligenz**: Die KI erkennt Muster in Deinen Daten,
setzt Zusammenhänge in Kontext und handelt vorausschauend. Dieser Teil ist nativer Code,
nicht JSON-getrieben, weil Mustererkennung über tausende Einträge mit Embeddings
Performance und direkten DB-Zugriff braucht.

Deine Daten verlassen Dein Gerät nur verschlüsselt (iCloud Backup) oder wenn Du ein
Cloud-LLM fragst (Anthropic API, OpenAI, etc.). Lokale LLMs für maximale Privatsphäre.

---

## Implementierungsstand (25.03.2026)

Die Architektur-Vision unten bleibt gueltig, aber ein paar technische Details haben sich in der
konkreten Implementierung verschoben:

- **Datenbank heute:** GRDB auf einer gemeinsamen SQLite-Datei im **App-Group-Container**.
  App, Widgets, Share Extension und App Intents greifen ueber `SharedContainer` auf dieselbe DB zu.
- **Semantische Suche heute:** Embeddings werden aktuell ueber `EmbeddingBridge` und die Tabelle
  `entryEmbeddings` gespeichert. `sqlite-vec` ist in dieser Codebasis derzeit nicht aktiv.
- **E-Mail heute:** Die App nutzt `EmailBridge` plus lokale `emailCache`-Persistenz statt einer
  separaten SwiftMail-Abhaengigkeit.
- **LLM-Stack heute:** Anthropic, OpenAI, Gemini, On-Device sowie xAI/custom ueber
  `OpenAICompatibleProvider`. Gemini-OAuth ist implementiert; Anthropic-Max/Session-Tokens sind
  bewusst entfernt.
- **Self-Improve heute:** Skill-Vorschlaege werden als Proposals persistiert; bei Anwendung wird die
  Skill-Generierung an den Chat/Compiler-Pfad uebergeben.

---

## Zwei-Schichten-Architektur

### Schicht 1: Skill Engine (JSON-getrieben)

```
.brainskill.md  →  KI (Ribosom)  →  skill.json  →  Runtime Engine  →  Native UI + Aktionen
   (DNA)                              (Protein)       (Zelle)
```

- **User-facing:** Alles was der User sieht und bedient
- **Konfigurierbar:** KI generiert neue Skills, User kann sie anpassen
- **Persistent:** Skills bleiben installiert, über Sessions hinweg
- **Offline-fähig:** JSON wird lokal gespeichert, braucht kein Internet zum Ausführen

### Schicht 2: Proaktive Intelligenz (nativer Code)

- **Mustererkennung** über alle Entries (Embeddings, zeitliche Muster, Frequenzanalyse)
- **Knowledge Facts** extrahieren und konsolidieren
- **Self-Modifier:** Verbesserungsvorschläge für bestehende Skills
- **Proaktive Notifications:** "Du hast Sarah seit 2 Wochen nicht geantwortet"
- Nutzt dieselben **Action Primitives** wie die Skill Engine
- Logik ist nativer Swift-Code (nicht JSON), weil Performance-kritisch

---

## Tech-Stack

| Schicht | Technologie | Warum |
|---------|------------|-------|
| **UI** | SwiftUI + Adaptive Layout + BrainTheme Design System | Native Feel: iPhone/iPad/Vision Pro |
| **Navigation** | NavigationSplitView (iPad/Vision) / NavigationStack (iPhone) | Apple-Standard |
| **Plattformen** | `#if os(iOS)` / `#if os(visionOS)` | Ein Codebase, drei Geräte |
| **Datenbank** | GRDB + gemeinsame SQLite im App-Group-Container | Ein DB-Pfad fuer App, Widgets, Share Extension und Intents |
| **Vektor-Suche** | EmbeddingBridge + `entryEmbeddings` | On-Device Embeddings ohne separate `sqlite-vec`-Runtime |
| **JSON-Rendering** | Eigene Render Engine (inspiriert von SwiftUI JSON Render / DivKit) | App-Store-konform, nativ |
| **LLM/Chat** | LLMRouter + Provider-Abstraktion | Multi-LLM: Claude, GPT, Gemini, On-Device, xAI/custom |
| **E-Mail** | EmailBridge + lokale Cache-Tabellen | Multi-Account-Sync und lokale Mail-Ansichten |
| **Kontakte** | Contacts.framework | Direkter Zugriff auf iOS-Kontakte |
| **Kalender** | EventKit | Direkter Zugriff auf iOS-Kalender + Reminders |
| **Auth** | Face ID / Touch ID (LocalAuthentication) | Kein Passwort nötig |
| **Secrets** | iOS Keychain | API-Keys sicher gespeichert |
| **Notifications** | UNUserNotificationCenter | Lokale Notifications, kein Server |
| **Background** | BGAppRefreshTask + App Intents | Sync, proaktive Analyse |
| **Shortcuts** | App Intents Framework | Siri, Shortcuts Automations |
| **Suche** | CoreSpotlight | System-weite Suche über alle Brain-Inhalte |
| **Widgets** | WidgetKit + App Intents | Quick Capture, Today's Tasks, Events |
| **Sync/Family** | SharedContainer heute, CloudKit optional/spaeter | Gemeinsame lokale DB jetzt, Family-Sync spaeter |
| **Graph** | Grape (SwiftGraphs) | Force-Directed Knowledge Graph |
| **Scanner** | VisionKit + Vision | Dokument-Scanner + OCR |
| **Handschrift** | PencilKit + Vision | iPad: Zeichnen + Handschrift → Text |
| **Sprache** | SpeechAnalyzer (iOS 26) / WhisperKit | On-Device Transkription |
| **On-Device LLM** | MLX Swift / llama.cpp | Lokales LLM für offline + privacy |

---

## App-Architektur

```
┌─────────────────────────────────────────────────────────────┐
│                      SwiftUI Views                           │
│  iPhone: TabView     │     iPad: NavigationSplitView         │
├──────────────────────┴──────────────────────────────────────┤
│                   Render Engine                               │
│  JSON → Native SwiftUI Components (UI Primitives)            │
│  Vorkompilierte Bibliothek, dynamisch zusammengesetzt        │
├──────────────────────────────────────────────────────────────┤
│          Skill Compiler          │    Proactive Engine        │
│  .brainskill.md → LLM → JSON    │  Pattern Detection (nativ) │
│  Skill Lifecycle Management      │  Knowledge Extraction      │
│                                  │  Self-Modifier Proposals   │
├──────────────────────────────────┴───────────────────────────┤
│                    Action Engine                              │
│  Action Primitives: Entry CRUD, Email, Calendar, HTTP,       │
│  Notifications, Clipboard, Haptics, Navigation, LLM, ...     │
├──────────────────────────────────────────────────────────────┤
│                    Logic Engine                               │
│  Conditions, Iteration, Variables, Templates, Date Math      │
├──────────────────────────────────────────────────────────────┤
│                 Service Layer (ViewModels)                    │
│  @Observable, async/await, kein Combine                      │
├──────────────────────────────────────────────────────────────┤
│                    Data Layer                                 │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  GRDB + Shared SQLite                                │    │
│  │  ├── entries + entryEmbeddings                       │    │
│  │  ├── tags, links, reminders                          │    │
│  │  ├── email_cache                                     │    │
│  │  ├── chat_history                                    │    │
│  │  ├── skills (installierte JSON-Skills)               │    │
│  │  ├── rules (Self-Modifier Konfig)                    │    │
│  │  ├── knowledge_facts                                 │    │
│  │  └── improvement_proposals                           │    │
│  └──────────────────────────────────────────────────────┘    │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                     │
│  │ CloudKit │ │ Keychain │ │UserDefaults│                    │
│  └──────────┘ └──────────┘ └──────────┘                     │
├──────────────────────────────────────────────────────────────┤
│              iOS System Frameworks (Bridges)                  │
│  Contacts │ EventKit │ CoreSpotlight │ WidgetKit │ Vision    │
│  VisionKit │ PencilKit │ LocalAuth │ BackgroundTasks         │
│  App Intents │ NaturalLanguage │ CoreBluetooth │ HealthKit   │
│  HomeKit │ CoreNFC │ CoreLocation │ MapKit │ AVFoundation    │
└──────────────────────────────────────────────────────────────┘
```

---

## Runtime Engine — Das Herzstück

Die Runtime Engine ist der Kern der App. Sie besteht aus drei Teilen:
Render Engine (UI), Action Engine (Operationen), Logic Engine (Kontrollfluss).

Alle drei interpretieren JSON. Alle Komponenten sind **vorkompiliert** und im App-Binary
enthalten. Das JSON beschreibt nur die **Komposition** — welche Komponenten, in welcher
Reihenfolge, mit welchen Daten. Das ist App-Store-konform (Airbnb, Uber, Netflix machen
dasselbe unter dem Namen "Server-Driven UI").

### Render Engine — UI Primitives

Jedes UI Primitive ist eine SwiftUI-View, die via JSON konfiguriert wird.
Die Render Engine löst den JSON-Baum rekursiv auf und rendert native Views.

#### Layout-Primitives

| Primitive | Beschreibung | SwiftUI-Basis |
|-----------|-------------|---------------|
| `stack` | Horizontal / Vertical / Z Stack | HStack, VStack, ZStack |
| `scroll` | Scrollbarer Container | ScrollView |
| `list` | Scrollbare Liste mit Item-Template | List / LazyVStack |
| `grid` | Grid-Layout | LazyVGrid / LazyHGrid |
| `tab-view` | Tab-Container | TabView |
| `split-view` | Sidebar + Detail (iPad) | NavigationSplitView |
| `sheet` | Modal Sheet | .sheet() |
| `conditional` | Zeigt/versteckt basierend auf Bedingung | if/else in ViewBuilder |
| `repeater` | Wiederholt Template für jedes Item | ForEach |
| `spacer` | Flexibler Abstand | Spacer |

#### Content-Primitives

| Primitive | Beschreibung | SwiftUI-Basis |
|-----------|-------------|---------------|
| `text` | Text mit Stil (headline, body, caption, ...) | Text + font modifier |
| `image` | Bild (lokal, URL, SF Symbol) | Image / AsyncImage |
| `icon` | SF Symbol | Image(systemName:) |
| `avatar` | Rundes Bild mit Initialen-Fallback | Custom View |
| `badge` | Chip / Tag / Label | Custom View |
| `divider` | Trennlinie | Divider |
| `markdown` | Markdown-Rendering | Text(AttributedString) |

#### Input-Primitives

| Primitive | Beschreibung | SwiftUI-Basis |
|-----------|-------------|---------------|
| `text-field` | Einzeiliges Textfeld | TextField |
| `text-editor` | Mehrzeiliges Textfeld | TextEditor |
| `toggle` | An/Aus-Schalter | Toggle |
| `picker` | Auswahl (Dropdown, Segmented, Wheel) | Picker |
| `slider` | Schieberegler | Slider |
| `stepper` | +/- Inkrement | Stepper |
| `date-picker` | Datum/Zeit-Auswahl | DatePicker |
| `color-picker` | Farbauswahl | ColorPicker |
| `search-field` | Suchfeld | .searchable() |
| `secure-field` | Passwort-Eingabe | SecureField |

#### Interaktions-Primitives

| Primitive | Beschreibung | SwiftUI-Basis |
|-----------|-------------|---------------|
| `button` | Tap-Action | Button |
| `link` | Navigation oder URL | NavigationLink / Link |
| `menu` | Kontextmenü | Menu |
| `swipe-actions` | Swipe-Aktionen auf Listenelementen | .swipeActions() |
| `pull-to-refresh` | Pull-to-Refresh | .refreshable() |
| `long-press` | Long-Press-Menü | .contextMenu() |

#### Daten-Primitives

| Primitive | Beschreibung | SwiftUI-Basis |
|-----------|-------------|---------------|
| `chart` | Line, Bar, Pie, Area | Swift Charts |
| `map` | Karte mit Annotationen | MapKit |
| `calendar-grid` | Monats-/Wochen-Grid | Custom View |
| `progress` | Fortschrittsanzeige (linear, zirkulär) | ProgressView |
| `gauge` | Gauge-Anzeige | Gauge |
| `stat-card` | Zahl + Label + Trend | Custom View |
| `timer-display` | Countdown / Stoppuhr | Custom View |
| `graph` | Force-Directed Node Graph | Grape / Custom |

#### Spezial-Primitives

| Primitive | Beschreibung | SwiftUI-Basis |
|-----------|-------------|---------------|
| `rich-editor` | Rich-Text-Editor (für Notizen) | Custom (TipTap-equivalent) |
| `canvas` | Zeichenfläche (iPad) | PencilKit |
| `camera` | Kamera-View | Camera / UIImagePickerController |
| `scanner` | Dokument-Scanner | VNDocumentCameraViewController |
| `audio-player` | Audio-Wiedergabe | AVFoundation |
| `web-view` | Eingebettete Webseite | WKWebView |
| `empty-state` | Leerzustand mit Icon + Text + Action | Custom View |

#### JSON-Beispiel: Skill "Habit Tracker"

```json
{
  "id": "habit-tracker",
  "version": "1.0",
  "screens": {
    "main": {
      "type": "stack",
      "direction": "vertical",
      "children": [
        {
          "type": "text",
          "value": "Habits",
          "style": "largeTitle"
        },
        {
          "type": "calendar-grid",
          "mode": "month",
          "data": "{{query('entries', {type: 'habit-log', month: current_month})}}",
          "cell_template": {
            "type": "conditional",
            "condition": "{{item.status == 'done'}}",
            "then": {"type": "icon", "name": "checkmark.circle.fill", "color": "green"},
            "else": {"type": "icon", "name": "circle", "color": "gray"}
          },
          "on_tap_cell": {"action": "toggle_habit", "date": "{{cell.date}}"}
        },
        {
          "type": "stat-card",
          "title": "Streak",
          "value": "{{compute('streak', {type: 'habit-log'})}}",
          "suffix": "Tage"
        }
      ]
    }
  },
  "actions": {
    "toggle_habit": {
      "steps": [
        {
          "type": "entry.toggle",
          "query": {"type": "habit-log", "date": "{{params.date}}"},
          "field": "status",
          "values": ["done", "skipped"]
        },
        {"type": "haptic", "style": "success"}
      ]
    }
  }
}
```

### Action Engine — Action Primitives

Action Primitives sind die "Verben" der Runtime. Jedes Primitive ist ein vorkompilierter
Swift-Handler, der via JSON-Konfiguration aufgerufen wird.

#### Entry-Operationen

| Primitive | Beschreibung |
|-----------|-------------|
| `entry.create` | Neuen Entry erstellen |
| `entry.read` | Entry lesen (by ID) |
| `entry.update` | Entry aktualisieren |
| `entry.delete` | Entry soft-deleten |
| `entry.list` | Entries abfragen (Filter, Sort, Pagination) |
| `entry.search` | Volltext + Semantische Suche |
| `entry.toggle` | Feld-Wert togglen |
| `entry.link` | Zwei Entries verlinken |
| `entry.unlink` | Verlinkung entfernen |
| `entry.tag` | Tag hinzufügen |
| `entry.untag` | Tag entfernen |

#### Kommunikation

| Primitive | Beschreibung |
|-----------|-------------|
| `email.list` | E-Mails aus Ordner laden |
| `email.read` | Einzelne E-Mail lesen |
| `email.send` | E-Mail senden |
| `email.reply` | Antworten |
| `email.forward` | Weiterleiten |
| `email.move` | In Ordner verschieben |
| `email.flag` | Flag setzen/entfernen |
| `email.delete` | Löschen |
| `email.sync` | IMAP-Sync auslösen |

#### Kalender & Reminders

| Primitive | Beschreibung |
|-----------|-------------|
| `calendar.list` | Events abfragen (Zeitraum) |
| `calendar.create` | Event erstellen |
| `calendar.update` | Event bearbeiten |
| `calendar.delete` | Event löschen |
| `reminder.schedule` | Erinnerung setzen |
| `reminder.cancel` | Erinnerung löschen |
| `reminder.list` | Anstehende Erinnerungen |

#### Kontakte

| Primitive | Beschreibung |
|-----------|-------------|
| `contact.search` | Kontakt suchen |
| `contact.read` | Kontaktdetails lesen |
| `contact.create` | Neuen Kontakt anlegen |
| `contact.update` | Kontakt bearbeiten |

#### System & UI

| Primitive | Beschreibung |
|-----------|-------------|
| `navigate.to` | Zu Screen/Skill navigieren |
| `navigate.back` | Zurück |
| `navigate.tab` | Tab wechseln |
| `alert` | Alert-Dialog anzeigen |
| `confirm` | Bestätigungs-Dialog |
| `toast` | Kurze Nachricht (Toast/Snackbar) |
| `sheet.open` | Sheet öffnen |
| `sheet.close` | Sheet schliessen |
| `haptic` | Haptisches Feedback (impact, notification, selection) |
| `clipboard.copy` | In Zwischenablage kopieren |
| `clipboard.paste` | Aus Zwischenablage lesen |
| `share` | iOS Share Sheet öffnen |
| `open-url` | URL in Safari öffnen |

#### Daten & Netzwerk

| Primitive | Beschreibung |
|-----------|-------------|
| `http.request` | HTTP GET/POST/PUT/DELETE |
| `http.download` | Datei herunterladen |
| `file.read` | Lokale Datei lesen |
| `file.write` | Lokale Datei schreiben |
| `file.delete` | Datei löschen |
| `file.share` | Datei teilen |
| `storage.get` | Key-Value lesen |
| `storage.set` | Key-Value speichern |
| `storage.delete` | Key-Value löschen |
| `spotlight.index` | In Spotlight indizieren |
| `spotlight.remove` | Aus Spotlight entfernen |

#### KI & Analyse

| Primitive | Beschreibung |
|-----------|-------------|
| `llm.complete` | LLM-Anfrage (via Router) |
| `llm.stream` | Streaming LLM-Anfrage |
| `llm.embed` | Embedding generieren |
| `llm.classify` | Text klassifizieren |
| `llm.summarize` | Text zusammenfassen |
| `llm.extract` | Strukturierte Daten extrahieren |

#### Hardware & Sensoren

| Primitive | Beschreibung |
|-----------|-------------|
| `camera.capture` | Foto aufnehmen |
| `camera.scan` | Dokument scannen (OCR) |
| `audio.record` | Audio aufnehmen |
| `audio.transcribe` | Audio → Text (On-Device) |
| `audio.play` | Audio abspielen |
| `location.current` | Aktuellen Standort abfragen |
| `location.geofence` | Geofence einrichten |
| `bluetooth.scan` | BLE-Geräte suchen |
| `bluetooth.connect` | BLE-Gerät verbinden |
| `nfc.read` | NFC-Tag lesen |
| `nfc.write` | NFC-Tag beschreiben |
| `health.read` | HealthKit-Daten lesen |
| `health.write` | HealthKit-Daten schreiben |
| `home.scene` | HomeKit-Szene aktivieren |
| `home.device` | HomeKit-Gerät steuern |

### Logic Engine — Kontrollfluss

Die Logic Engine interpretiert Bedingungen, Schleifen und Transformationen.
Sie ist bewusst **eingeschränkt** (kein Turing-komplett) um App-Store-konform zu bleiben.

| Primitive | Beschreibung | Beispiel |
|-----------|-------------|---------|
| `if` | Bedingung | `{"if": "{{count > 0}}", "then": [...], "else": [...]}` |
| `forEach` | Über Collection iterieren | `{"forEach": "{{items}}", "as": "item", "do": [...]}` |
| `map` | Collection transformieren | `{"map": "{{items}}", "to": "{{item.name}}"}` |
| `filter` | Collection filtern | `{"filter": "{{items}}", "where": "{{item.done == false}}"}` |
| `set` | Variable setzen | `{"set": "count", "value": "{{items.length}}"}` |
| `template` | String-Interpolation | `"Hallo {{user.name}}, du hast {{count}} Einträge"` |
| `math` | Arithmetik | `{{price * quantity}}` |
| `date` | Datum berechnen | `{{now + 7d}}`, `{{entry.date \| relative}}` |
| `compare` | Vergleich | `==`, `!=`, `<`, `>`, `contains`, `matches` |
| `and/or/not` | Boolesche Logik | `{"and": [cond1, cond2]}` |
| `try` | Fehlerbehandlung | `{"try": [...], "catch": {"action": "toast", "message": "Fehler"}}` |
| `delay` | Verzögerung | `{"delay": "500ms", "then": [...]}` |
| `sequence` | Sequenzielle Ausführung | `{"sequence": [step1, step2, step3]}` |
| `parallel` | Parallele Ausführung | `{"parallel": [task1, task2]}` |
| `query` | DB-Abfrage | `{{query('entries', {type: 'task', status: 'open'})}}` |
| `compute` | Berechnete Werte | `{{compute('streak', {type: 'habit-log'})}}` |
| `format` | Formatierung | `{{value \| currency('CHF')}}`, `{{date \| short}}` |

### Expressions — Template-Sprache

Die Template-Sprache in `{{...}}` unterstützt:

```
# Variablen
{{user.name}}
{{params.id}}
{{item.title}}

# Pfade
{{items[0].name}}
{{settings.theme.primary}}

# Operatoren
{{count + 1}}
{{price * 1.077}}
{{name == "Andy"}}
{{tags contains "wichtig"}}

# Pipe-Filter
{{date | relative}}          → "vor 3 Stunden"
{{amount | currency('CHF')}} → "CHF 1'234.50"
{{text | truncate(100)}}     → "Erster Satz..."
{{list | count}}             → 42
{{text | uppercase}}
{{date | format('dd.MM.yyyy')}}

# Funktionen
{{now}}                      → aktuelles Datum
{{query('entries', filter)}} → DB-Abfrage
{{compute('streak', params)}} → berechneter Wert
```

---

## Skill Engine — Brain baut seine eigenen Fähigkeiten

### Was ist ein BrainSkill?

Ein BrainSkill ist eine `.brainskill.md`-Datei: Markdown mit YAML-Frontmatter.
Menschen lesen es als Dokumentation, die KI parsed es als strukturierte Definition.

```markdown
---
id: pomodoro-timer
name: Pomodoro Timer
description: Focus-Timer mit 25/5-Minuten-Zyklen und Statistik
version: 1.0
created_by: brain-ai
approved_by: user
permissions: [notifications, haptics]
triggers:
  - type: siri
    phrase: "Starte Pomodoro"
  - type: shortcut
    name: "Focus starten"
icon: timer
color: "#FF6347"
---

# Pomodoro Timer

Ein einfacher Focus-Timer basierend auf der Pomodoro-Technik.

## Screens

### Hauptscreen
- Grosser Countdown-Timer (25 Minuten)
- Start/Pause/Reset Buttons
- Aktuelle Session-Nummer (z.B. "Session 3 von 4")
- Fortschrittsring um den Timer

### Statistik
- Abgeschlossene Sessions heute/Woche/Monat als Chart
- Durchschnittliche Focus-Zeit pro Tag
- Streak (aufeinanderfolgende Tage mit mindestens 4 Sessions)

## Aktionen

### Timer starten
- Countdown 25 Minuten
- Bei Ablauf: Notification "Pause!" + Haptic
- Automatisch 5-Minuten-Pause starten
- Nach 4 Sessions: 15-Minuten-Pause

### Session loggen
- Entry erstellen: type=pomodoro, status=completed
- Tag: focus, pomodoro
- Spotlight indizieren

## Siri
- "Starte Pomodoro" → Timer starten
- "Wie viele Pomodoros heute?" → Zähler anzeigen
```

### Wie die KI einen Skill baut

```
1. Auslöser: User fragt "Ich hätte gern einen Pomodoro-Timer"
   ODER Brain erkennt Muster: "User startet oft Timer-Apps, braucht Focus-Tracking"

2. KI analysiert:
   - Welche UI Primitives werden gebraucht? (timer-display, button, chart, stat-card)
   - Welche Action Primitives? (entry.create, notification.schedule, haptic)
   - Welche Permissions? (notifications, haptics)

3. KI generiert: skill.json (aus dem Markdown)
   - screens: {...}  (UI-Baum aus Primitives)
   - actions: {...}  (Workflows aus Action + Logic Primitives)
   - triggers: {...} (Siri, Shortcuts, Schedule)

4. Preview an User:
   "Ich möchte einen Pomodoro Timer installieren.
    Benötigte Berechtigungen: Notifications, Haptics.
    [Preview] [Installieren] [Ablehnen]"

5. User genehmigt → JSON wird in SQLite gespeichert → sofort aktiv
   → Tab/Sidebar-Eintrag erscheint
   → Siri-Shortcut wird registriert
   → Widget wird verfügbar

6. Optional: KI verbessert den Skill über Zeit
   "Du nutzt den Pomodoro-Timer meist morgens. Soll ich ihn
    automatisch vorschlagen wenn du die App zwischen 7-9 Uhr öffnest?"
```

### Skill-Lifecycle

```
[.brainskill.md]  →  [KI: Kompilierung]  →  [skill.json]
                                                  │
                              ┌────────────────────┤
                              ▼                    ▼
                        [Preview]           [Installation]
                              │                    │
                              ▼                    ▼
                       [User: Ja/Nein]      [SQLite: skills]
                                                   │
                              ┌─────────────────────┤
                              ▼                     ▼
                    [Runtime: Render]      [Self-Modifier]
                              │              (Verbesserungen)
                              ▼                     │
                    [Native SwiftUI]                ▼
                                           [Update-Vorschlag]
```

### Skill Import/Export

- **Dateiformat:** `.brainskill.md` (Markdown + YAML)
- **Teilen:** via AirDrop, iMessage, E-Mail, oder jeder Marktplatz
- **Import:** Datei öffnen → Preview + Berechtigungen → Genehmigen
- **URL-Schema:** `brain://import-skill?url=...`
- **Kein eigener Marktplatz:** Dritte können Marktplätze betreiben
- **Versionierung:** Skill-Updates vergleichen alt vs. neu

---

## Multi-LLM & On-Device LLM

### LLM Router — Abstraktionsschicht

```swift
protocol LLMProvider {
    var name: String { get }
    var isAvailable: Bool { get }
    var supportsStreaming: Bool { get }
    var isOnDevice: Bool { get }
    var contextWindow: Int { get }

    func complete(_ messages: [Message], tools: [Tool]?) -> AsyncThrowingStream<Delta, Error>
    func embed(_ text: String) -> [Float]
}

// Implementierungen (aktiv)
class AnthropicProvider: LLMProvider { ... }         // Claude (API-Key + Proxy)
class OpenAIProvider: LLMProvider { ... }            // GPT + o-Serie
class GeminiProvider: LLMProvider { ... }            // Gemini (API-Key + Google OAuth)
class OpenAICompatibleProvider: LLMProvider { ... }  // xAI + Custom Endpoints
class OnDeviceProvider: LLMProvider { ... }          // On-Device / Apple Foundation Models

// Bewusst entfernt
// Anthropic Max / Session-Key Modus

// Geplant (nicht implementiert)
class OllamaProvider: LLMProvider { ... }
class MLXProvider: LLMProvider { ... }
class LlamaCppProvider: LLMProvider { ... }
```

### Routing-Logik

| Situation | Routing |
|-----------|---------|
| Kein Internet | On-Device LLM |
| Sensible Daten (Privacy Zone) | On-Device bevorzugt |
| Skill kompilieren (komplex) | Stärkstes Cloud-Modell |
| Einfache Klassifizierung/Tagging | On-Device (schneller, gratis) |
| Chat / Analyse | User-Präferenz (Default: Claude) |

### On-Device LLM

**Heute (2026):** MLX Swift mit Llama 3.2 3B oder Phi-3 Mini. ~10-30 tokens/sec
auf A17/M-Chips. Gut für: Zusammenfassungen, Tagging, einfache Fragen, Klassifizierung.

**Morgen (2027+):** Grössere Modelle, bessere Quantisierung, Apple Intelligence API.
Der LLM Router wählt automatisch das beste verfügbare Modell.

---

## Datenbank-Schema (SQLite via GRDB)

> Hinweis: Das SQL in diesem Abschnitt ist konzeptionell. Die aktuelle Implementierung nutzt
> `entryEmbeddings` statt `entries_vec` und speichert die gemeinsame Datenbank im App-Group-Container.

### Kern-Tabellen

```sql
-- Entries (Herzstück — alles ist ein Entry)
CREATE TABLE entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL DEFAULT 'thought',
  title TEXT,
  body TEXT,
  status TEXT DEFAULT 'active',
  priority INTEGER DEFAULT 0,
  source TEXT DEFAULT 'manual',
  source_meta TEXT,                       -- JSON
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  deleted_at TEXT                          -- Soft delete
);

-- Full-Text Search
CREATE VIRTUAL TABLE entries_fts USING fts5(
  title, body, content=entries, content_rowid=id,
  tokenize='unicode61 remove_diacritics 2'
);

-- Vector Embeddings (konzeptionell; aktuelle Tabelle heisst entryEmbeddings)
CREATE TABLE entryEmbeddings (
  entryId INTEGER PRIMARY KEY,
  embedding BLOB NOT NULL,
  model TEXT NOT NULL,
  updatedAt TEXT
);

-- Tags (hierarchisch: "projekt/brain/ios")
CREATE TABLE tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT UNIQUE NOT NULL,
  color TEXT
);

CREATE TABLE entry_tags (
  entry_id INTEGER REFERENCES entries(id),
  tag_id INTEGER REFERENCES tags(id),
  PRIMARY KEY (entry_id, tag_id)
);

-- Links (Bidirektional)
CREATE TABLE links (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_id INTEGER REFERENCES entries(id),
  target_id INTEGER REFERENCES entries(id),
  relation TEXT DEFAULT 'related',
  created_at TEXT DEFAULT (datetime('now')),
  UNIQUE(source_id, target_id)
);

-- Reminders
CREATE TABLE reminders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entry_id INTEGER REFERENCES entries(id),
  due_at TEXT NOT NULL,
  notified INTEGER DEFAULT 0,
  notification_id TEXT
);

-- Email Cache
CREATE TABLE email_cache (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  message_id TEXT UNIQUE,
  folder TEXT,
  from_addr TEXT,
  to_addr TEXT,
  subject TEXT,
  body_plain TEXT,
  body_html TEXT,
  date TEXT,
  is_read INTEGER DEFAULT 0,
  has_attachments INTEGER DEFAULT 0,
  flags TEXT,
  entry_id INTEGER REFERENCES entries(id)
);

-- Chat History
CREATE TABLE chat_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  tool_calls TEXT,
  sources TEXT,
  channel TEXT DEFAULT 'app',
  created_at TEXT DEFAULT (datetime('now'))
);

-- Skills (installierte JSON-Skills)
CREATE TABLE skills (
  id TEXT PRIMARY KEY,                    -- z.B. "pomodoro-timer"
  name TEXT NOT NULL,
  description TEXT,
  version TEXT DEFAULT '1.0',
  icon TEXT,
  color TEXT,
  permissions TEXT,                        -- JSON array
  triggers TEXT,                           -- JSON array
  screens TEXT NOT NULL,                   -- JSON: UI-Definition
  actions TEXT,                            -- JSON: Workflows
  source_markdown TEXT,                    -- Original .brainskill.md
  created_by TEXT DEFAULT 'user',          -- user, brain-ai, import
  enabled INTEGER DEFAULT 1,
  installed_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Knowledge Facts
CREATE TABLE knowledge_facts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  subject TEXT,
  predicate TEXT,
  object TEXT,
  confidence REAL DEFAULT 1.0,
  source_entry_id INTEGER REFERENCES entries(id),
  learned_at TEXT DEFAULT (datetime('now'))
);

-- Rules Engine (Self-Modifier)
CREATE TABLE rules (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  category TEXT NOT NULL,
  name TEXT UNIQUE NOT NULL,
  condition TEXT,
  action TEXT NOT NULL,
  priority INTEGER DEFAULT 0,
  enabled INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now')),
  modified_at TEXT DEFAULT (datetime('now')),
  modified_by TEXT DEFAULT 'system'
);

-- Improvement Proposals
CREATE TABLE improvement_proposals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  description TEXT,
  category TEXT NOT NULL,
  change_spec TEXT,
  status TEXT DEFAULT 'pending',
  created_at TEXT DEFAULT (datetime('now')),
  applied_at TEXT,
  rollback_data TEXT
);

-- Sync State
CREATE TABLE sync_state (
  key TEXT PRIMARY KEY,
  value TEXT,
  updated_at TEXT DEFAULT (datetime('now'))
);
```

---

## iOS-Native Features

### Tier 1: Launch Features (MVP)

| Feature | Framework | Beschreibung |
|---------|-----------|-------------|
| **Face ID Login** | LocalAuthentication | Ein Blick → App offen |
| **Share Sheet** | Share Extension | Aus jeder App Inhalte ins Brain |
| **Spotlight-Suche** | CoreSpotlight | Brain-Entries in Spotlight |
| **Widgets** | WidgetKit | Quick Capture, Tasks, Termine |
| **Siri** | App Intents | "Hey Siri, füg meinem Brain hinzu..." |
| **Dokument-Scanner** | VisionKit | Kamera → Dokument → OCR → Entry |
| **Lokale Notifications** | UNUserNotificationCenter | Erinnerungen |
| **Haptic Feedback** | UIImpactFeedbackGenerator | Bei Aktionen |

### Tier 2: Power Features (v1.1)

| Feature | Framework | Beschreibung |
|---------|-----------|-------------|
| **Apple Pencil** | PencilKit | Handschriftliche Notizen (iPad) |
| **Handschrift → Text** | Vision + PencilKit | Durchsuchbar |
| **Live Activities** | ActivityKit | Focus-Task auf Lock Screen |
| **Focus Filter** | SetFocusFilterIntent | Modus-abhängige Inhalte |
| **NFC Tags** | CoreNFC | Physische Trigger |
| **Voice Capture** | SpeechAnalyzer / WhisperKit | Sprache → Text → Entry |
| **Natural Language** | NaturalLanguage | "Treffen morgen 15 Uhr" → Event |

### Tier 3: Differenzierung (v2.0)

| Feature | Framework | Beschreibung |
|---------|-----------|-------------|
| **Knowledge Graph** | Grape | Visuelles Netzwerk |
| **HealthKit** | HealthKit | "Du schreibst besser nach 7h+ Schlaf" |
| **HomeKit** | HomeKit | Deep Focus → Licht dimmen |
| **Map View** | MapKit | Entries mit Geo-Daten |
| **Business Card Scanner** | Vision + Camera | Visitenkarte → Kontakt |

---

## UX-Prinzipien

### 1. Progressive Disclosure
3 Optionen zeigen, nicht 30. Komplexität hinter Gesten und Long-Press.

### 2. Unified Input Bar
Eine Eingabezeile die alles versteht (Fantastical/Cardhop Pattern):
- "Einkaufen gehen morgen 10 Uhr" → Task + Termin
- "Notiz: Brain-App Architektur" → Entry
- "Mail an Sarah: Projektupdate" → E-Mail Compose

### 3. Alles ist ein Entry
Gedanken, Tasks, Events, E-Mails, Notizen, Dokumente — alles Entries.
Unterschied nur im `type` und `source`. Alles verlinkbar, taggbar, durchsuchbar.

### 4. AI ist Werkzeug, nicht Belästigung
AI erscheint nur wenn gefragt. Transparenz bei jeder AI-Aktion.
Quellen zeigen: Jede AI-Antwort verlinkt auf die Basis-Entries.

### 5. Offline-First
Alles funktioniert ohne Internet. Sync passiert im Hintergrund.
Nie ein Spinner für lokale Daten.

### 6. Skills sind erste Klasse
Installierte Skills erscheinen in der Navigation wie native Module.
Kein Unterschied zwischen "eingebauten" und "generierten" Features.
Die App shipped mit Bootstrap-Skills (Dashboard, Inbox, Kalender),
die genauso via JSON definiert sind wie user-generierte Skills.

---

## Self-Modifier auf iOS

### Rules Engine

```json
{
  "category": "analysis",
  "name": "morning_briefing_format",
  "condition": {"time": "07:00-09:00", "trigger": "app_open"},
  "action": {
    "type": "generate_briefing",
    "prompt_template": "Erstelle ein Morgen-Briefing...",
    "include": ["tasks_due_today", "calendar_events", "unread_emails"],
    "format": "bullet_points"
  }
}
```

### Proposal-Flow
1. Brain analysiert Nutzungsverhalten
2. Erstellt Improvement Proposal
3. Zeigt als Notification: "Vorschlag: Wetter im Morgen-Briefing?"
4. User tippt: Approve/Reject
5. Bei Approve: Rule/Skill wird geändert → sofort wirksam
6. Rollback jederzeit möglich

---

## Apple Vision Pro Support

Phase 1: iPhone + iPad (100% Fokus)
Phase 2: visionOS Support (SwiftUI macht 80% gratis)
Phase 3: Spatial-spezifische Features (3D Graph, Multi-Window)

```swift
#if os(visionOS)
    WindowGroup { BrainSpatialView() }
    .windowStyle(.volumetric)
    ImmersiveSpace(id: "knowledge-graph") {
        KnowledgeGraph3DView()
    }
#else
    WindowGroup { ContentView() }
#endif
```

---

## Migration von brain-api → brain-ios

### Übergangsphase
1. brain-ios liest von brain-api (REST API als Datenquelle)
2. brain-ios hat eigene SQLite + synct mit brain-api
3. brain-ios ist standalone, brain-api wird optional

### Daten-Export
- `GET /api/me/export` — brain-api Export-Endpoint
- JSON → SQLite Import beim ersten App-Start

---

## Phasen-Plan

| Phase | Name | Scope |
|-------|------|-------|
| **0** | Projekt-Setup | Xcode, SPM, SQLite Schema, GRDB, CI |
| **1** | Core Foundation | Entry CRUD, Tags, Links, FTS5, Face ID, Navigation Shell |
| **2** | Render Engine | UI Primitive Library, JSON→SwiftUI Renderer, Screen-Routing |
| **3** | Action & Logic Engine | Action Primitives, Logic Interpreter, Expression Parser |
| **4** | LLM Router & Skill Compiler | Multi-LLM, .brainskill.md→JSON, Skill Lifecycle |
| **5** | iOS Bridges | Contacts, EventKit, EmailBridge, CoreLocation, CoreBluetooth, HealthKit, HomeKit, CoreNFC, Camera/Scanner |
| **6** | Bootstrap Skills | Dashboard, Inbox, Kalender, Quick Capture — als .brainskill.md |
| **7** | Advanced Skills | Files, Canvas/Notes, People, Knowledge Graph — als .brainskill.md |
| **8** | Proaktive Intelligenz | Pattern Engine, Self-Modifier, Proposals, Knowledge Facts |
| **9** | System-Integration | Widgets, Shortcuts, Siri, Share Extension, Spotlight, Notifications |
| **10** | On-Device LLM | MLX Swift / llama.cpp, Offline-Chat, Privacy Routing |
| **11** | Family & Sync | CloudKit / Family-Sync (optional, spaeter) |
| **12** | Vision Pro | visionOS Target, 3D Knowledge Graph, Multi-Window |
| **13** | Migration & Polish | brain-api Import, Performance, TestFlight |

### Phase 0: Projekt-Setup

- Xcode-Projekt erstellen (brain-ios)
- SPM Dependencies: GRDB, swift-crypto (weitere Libs nur bei Bedarf)
- SQLite-Schema anlegen (alle Tabellen inkl. `skills`)
- GRDB-Models definieren (Entry, Tag, Link, Reminder, Skill, ...)
- GitHub Actions CI (macOS Runner: Build + Test)
- Basis-App mit leerer Navigation

**Gate 0:** Projekt baut, Tests laufen, DB-Schema migriert.

### Phase 1: Core Foundation

- Entry CRUD (create, read, update, delete, list, search)
- Tags (hierarchisch: "projekt/brain/ios")
- Links (bidirektional)
- FTS5 Volltext-Suche
- Face ID / Touch ID
- Navigation Shell (TabView iPhone, NavigationSplitView iPad)
- Leere Tabs als Platzhalter

**Gate 1:** Entries erstellen/bearbeiten/suchen, Face ID funktioniert, Navigation steht.

### Phase 2: Render Engine

- **JSON Parser:** skill.json → interner View-Baum
- **Component Registry:** Alle UI Primitives als SwiftUI-Views registriert
- **Renderer:** Rekursiver Renderer der JSON-Baum → SwiftUI-Views erzeugt
- **Data Binding:** Template-Expressions auflösen (`{{entry.title}}`)
- **Screen Router:** Navigation zwischen Skill-Screens
- **Style System:** Theme-Farben, Schriftgrössen, Dark/Light Mode
- **Test-Skill:** Ein einfacher "Hello World"-Skill als Proof of Concept

**Gate 2:** JSON-definierter Skill wird als native SwiftUI gerendert.
Data Binding funktioniert. Navigation zwischen Screens funktioniert.

### Phase 3: Action & Logic Engine

- **Action Dispatcher:** JSON-Action → Swift-Handler Mapping
- **Entry-Actions:** CRUD via Action Primitives
- **System-Actions:** navigate, alert, toast, haptic, clipboard
- **Logic Interpreter:** if/else, forEach, set, template
- **Expression Parser:** `{{...}}` Syntax mit Operatoren und Pipes
- **Fehlerbehandlung:** try/catch in Workflows
- **Test-Skill:** Ein interaktiver Skill (z.B. einfache Todo-Liste)

**Gate 3:** Skill mit Interaktion funktioniert (Buttons lösen Actions aus,
Bedingungen steuern UI, Daten werden geschrieben/gelesen).

### Phase 4: LLM Router & Skill Compiler

- **LLM Router:** Provider-Abstraktion, Routing-Logik
- **Anthropic Provider:** Claude API mit Streaming + Tool-Use
- **Chat-UI:** Grundlegendes Chat-Interface
- **Skill Compiler:** .brainskill.md → JSON-Konvertierung via LLM
- **Skill Lifecycle:** Install, Enable, Disable, Delete, Update
- **Skill Preview:** Vorschau vor Installation
- **Permissions:** Berechtigungsanfrage pro Skill

**Gate 4:** User kann einen Skill in natürlicher Sprache beschreiben,
KI generiert ihn, User sieht Preview und kann installieren.

### Phase 5: iOS Bridges

- **Contacts Bridge:** contact.* Primitives → Contacts.framework
- **EventKit Bridge:** calendar.* Primitives → EventKit
- **EmailBridge:** email.* Primitives → IMAP/SMTP + lokale Cache-Tabellen
- **Location Bridge:** location.* Primitives → CoreLocation
- **Camera/Scanner Bridge:** camera.* Primitives → VisionKit
- **Audio Bridge:** audio.* Primitives → AVFoundation + Speech
- **Weitere:** Bluetooth, Health, Home, NFC (je nach Bedarf)

**Gate 5:** Skills können auf iOS-Frameworks zugreifen.
E-Mail senden, Kalender lesen, Kontakt nachschlagen via Action Primitives.

### Phase 6: Bootstrap Skills

Die "eingebauten" Module als .brainskill.md:

- **Dashboard:** Tagesübersicht, Stat-Cards, Quick Actions
- **Inbox:** E-Mail-Client (Ordner, Liste, Detail, Compose)
- **Kalender:** Monats-/Wochen-/Agenda-Ansicht, Event CRUD
- **Quick Capture:** Unified Input Bar + Siri
- **Chat:** Brain-Chat mit Streaming

Diese Skills werden mit der App ausgeliefert. Sie sind nicht hardcodiert,
sondern genauso JSON-definiert wie user-generierte Skills.

**Gate 6:** App ist benutzbar. Dashboard, E-Mail, Kalender und Chat funktionieren.
User merkt nicht, dass diese "Module" Skills sind.

### Phase 7: Advanced Skills

- **Files:** Datei-Browser, Upload, Preview, Tags
- **Canvas/Notes:** Rich-Text-Editor, PencilKit (iPad), Bidirektionale Links
- **People:** Kontaktverwaltung mit Kontext (letzte Mails, Termine, Notizen)
- **Knowledge Graph:** Force-Directed Graph (Grape)
- **Globale Suche:** FTS5 + Semantic Search über alle Inhalte

**Gate 7:** Alle geplanten Module existieren als Skills. Knowledge Graph visualisiert
Verknüpfungen.

### Phase 8: Proaktive Intelligenz

- **Pattern Engine:** Mustererkennung über Entries (nativer Code)
- **Knowledge Extraction:** Fakten aus Entries/Mails/Chat extrahieren
- **Self-Modifier:** Verbesserungsvorschläge für Skills und Rules
- **Proaktive Notifications:** "Du hast Sarah seit 2 Wochen nicht geantwortet"
- **Morgen-Briefing:** Automatische Tagesübersicht
- **Déjà Vu:** Verwandte alte Entries bei neuem Input anzeigen

**Gate 8:** Brain erkennt Muster, schlägt Verbesserungen vor, erinnert proaktiv.

### Phase 9: System-Integration

- **Widgets:** Quick Capture, Today's Tasks, Nächste Termine
- **Shortcuts:** App Intents für alle wichtigen Aktionen
- **Siri:** Sprachbefehle für Brain-Aktionen
- **Share Extension:** "Teilen → Brain" aus jeder App
- **Spotlight:** Brain-Entries in System-Suche
- **Notifications:** Lokale Notifications für Reminders

**Gate 9:** Brain ist tief in iOS integriert. Widgets, Siri, Share Sheet, Spotlight.

### Phase 10–13: Erweiterungen

- **Phase 10: On-Device LLM** — MLX Swift, Offline-Chat, Privacy Routing
- **Phase 11: Family & Sync** — CloudKit / Family-Sync optional spaeter
- **Phase 12: Vision Pro** — visionOS, 3D Graph, Multi-Window
- **Phase 13: Migration & Polish** — brain-api Import, Performance, TestFlight

---

## Risiken & Mitigationen

| Risiko | Mitigation |
|--------|-----------|
| App Store: JSON-Runtime = "Code Execution"? | Alle Komponenten vorkompiliert. JSON ist Konfiguration, nicht Code. Airbnb/Uber machen dasselbe. |
| API-Key im App-Binary | User gibt eigenen Key ein → iOS Keychain |
| Runtime-Performance bei komplexen Skills | Profiling + Caching. Native SwiftUI bleibt schnell. |
| Skill-Qualität (KI generiert Müll) | Preview vor Installation. User kann ablehnen. Rollback. |
| 64 Notification Limit | Reschedule-on-Launch Pattern |
| Background Fetch unzuverlässig | Shortcuts Automations als Backup |
| CloudKit Sync Konflikte | Last-Writer-Wins + Konflikt-UI |
| Kein Xcode auf VPS | GitHub Actions macOS Runner |
| Primitive-Lücke (Handler fehlt) | Neue Primitive per App-Update. Grosszügig vorab definieren. |

---

## Geschäftsmodell

- **App:** Einmalkauf (kein Abo)
- **Major Updates:** Neuer Kauf (wie früher)
- **Skills:** Gratis Infrastruktur, Dritte monetarisieren wie sie wollen
- **Keine Provision, keine Abhängigkeit**
- **API-Kosten:** User trägt eigene LLM-Kosten (eigener API-Key)

---

## Entscheidungen (geklärt)

| Frage | Entscheidung |
|-------|-------------|
| App-Architektur | Runtime-Engine + JSON-Skills, nicht hardcodierte Module |
| UI-Rendering | Vorkompilierte SwiftUI Primitives, JSON beschreibt Komposition |
| Skill-Format | .brainskill.md (Markdown + YAML), KI kompiliert zu JSON |
| Proaktive Intelligenz | Nativer Swift-Code, nicht JSON-getrieben |
| DB | GRDB + SQLite (nicht SwiftData/CoreData) |
| LLM | Multi-LLM Router, nie an einen Anbieter gebunden |
| Offline | Offline-First, alles lokal |
| Bootstrap-Skills | Dashboard, Inbox, Kalender als .brainskill.md (nicht hardcodiert) |
| Marktplatz | Keiner. Offene Import/Export-Schnittstelle |
| Geschäftsmodell | Einmalkauf |
| Vision Pro | Phase 12 (SwiftUI macht 80% gratis) |
