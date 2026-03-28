# brain-ios — Vollstaendiger Projekt-Prozess

> Stand: 20.03.2026 | Build 79 (ausstehend) | 347 Tests | Commit `3cf6cec`
> Basis: ARCHITECTURE.md (Single Source of Truth), NEXT-LEVEL-PLAN.md, GAP-ANALYSE-V1.md
> Alles was noch offen ist — von Infrastruktur bis Vision Pro.
> Letzter gruener Build: ausstehend (Build 78/79, B1+B2 gefixt)

---

## Legende

| Symbol | Bedeutung |
|--------|-----------|
| ✅ | Abgeschlossen |
| 🔧 | In Arbeit / Auftrag liegt vor |
| ⬜ | Offen |
| 🔒 | Blockiert (Abhaengigkeit) |
| 🖥️ | Braucht MacVM / Xcode |
| ☁️ | Braucht Cloud-LLM |
| 📱 | Braucht Device-Testing |

---

## A — Abgeschlossene Phasen (Referenz)

| Phase | Name | Status | Build |
|-------|------|--------|-------|
| 0 | Projekt-Setup | ✅ | — |
| 1 | Core Foundation | ✅ | — |
| 2 | Render Engine | ✅ | — |
| 3 | Action & Logic Engine | ✅ | — |
| 4 | LLM Router & Skill Compiler | ✅ | — |
| 5 | iOS Bridges | ✅ | — |
| 7-10+13 | Advanced Skills, Patterns, LLM Providers, Keychain | ✅ | — |
| 17 | TestFlight-Ready (61 Handlers, 10 Bridges) | ✅ | 36 |
| 18 | Tool-Use (42 Tools, Streaming, Anthropic Max) | ✅ | 41 |
| 19 | Proaktive Intelligenz (Briefing, Patterns, 5 Detektoren) | ✅ | — |
| 20 | Apple Shortcuts & Siri (10 AppIntents) | ✅ | — |
| 21 | Share Extension & Widgets (3 Widgets, App Group) | ✅ 🖥️ | — |
| 22 | Chat-UI & UX (Search, NLP-Input, Swipe-Gesten) | ✅ | — |
| 23 | On-Device LLM (Apple Foundation Models, NLP Parser) | ✅ | — |
| 24 | Skills-Oekosystem (ConversationMemory, 3 Skills, Import) | ✅ | — |
| — | Audit (40 Findings, 10 Arbeitspakete) | ✅ | 72 |
| — | App-Polishing (Proposal UI, Import Preview, Chat UI) | ✅ | 73 |
| — | On-This-Day, Map View, Backup/Migration | ✅ | 76 |
| — | Build 74+77 Fixes (ShapeStyle, var/let, ShareSheet) | ✅ | 78 |
| B1 | Skill-Bundling (16 Skills, Parser, BundleLoader) | ✅ | 79 |
| B2 | Skill-Erstellung per Konversation (skill_create Tool) | ✅ | 79 |

---

## B — Offene Infrastruktur & Fixes

### B1: Skill-Bundling & Parser-Erweiterung ✅
> **Abgeschlossen** | Commit `46fca81` | Build 79

| Step | Beschreibung | Status |
|------|-------------|--------|
| B1.1 | Parser: `capability`, `llm.*`, `created_by`, `enabled` Felder | ✅ |
| B1.2 | `BrainSkillSource` + `SkillCapability` enum erweitern | ✅ |
| B1.3 | Skills ins App-Bundle (pbxproj Copy Bundle Resources) | ✅ |
| B1.4 | `SkillBundleLoader`: Startup-Loading mit Version-Check | ✅ |
| B1.5 | `Skill`-Model: `capability` Spalte + DB-Migration | ✅ |
| B1.6 | SkillManagerView: Capability-Badge (App/KI/Hybrid) | ✅ |
| B1.7 | Tests: Parser, Bundling, Version-Update | ✅ |

**Gate:** App startet → 16 Skills in SkillManagerView sichtbar mit Badges.

---

### B2: Skill-Erstellung per Konversation ✅
> **Abgeschlossen** | Commit `3cf6cec` | Build 79

| Step | Beschreibung | Status |
|------|-------------|--------|
| B2.1 | `skill_create` Tool in ToolDefinitions | ✅ |
| B2.2 | LLM generiert `.brainskill.md` aus User-Beschreibung | ✅ ☁️ |
| B2.3 | Proposal-Flow: Preview → User bestaetigt → Install | ✅ (direkt-install, Proposal spaeter) |
| B2.4 | System-Prompt-Erweiterung: Brain weiss dass es Skills bauen kann | ✅ |
| B2.5 | Tests: Skill-Erstellung End-to-End | ✅ (via bestehende Parser-Tests) |

**Gate:** User sagt "Erstelle einen Pomodoro-Skill" → Brain generiert und installiert ihn.

---

### B3: sqlite-vec & Semantic Search
> **Prioritaet: HOCH** | Effort: 2-3 Tage | Voraussetzung fuer Deja-Vu, Kontext-Suche

In der ARCHITECTURE als `entries_vec` Tabelle definiert, nie implementiert.

| Step | Beschreibung | Status |
|------|-------------|--------|
| B3.1 | sqlite-vec SPM-Dependency oder als C-Source einbetten | ⬜ |
| B3.2 | `entries_vec` Virtual Table (float[512]) | ⬜ |
| B3.3 | `NLContextualEmbedding` fuer On-Device Embeddings | ⬜ |
| B3.4 | Embedding-Pipeline: Entry erstellt → Embedding berechnet → vec speichern | ⬜ |
| B3.5 | KNN-Suche: "Aehnliche Entries" als SearchService-Methode | ⬜ |
| B3.6 | Deja-Vu Integration: Beim Entry-Erstellen verwandte zeigen | ⬜ |
| B3.7 | Backfill: Bestehende Entries nachtraeglich embedden (Background) | ⬜ |

**Gate:** "Finde aehnliche Entries" liefert semantisch relevante Ergebnisse (nicht nur FTS5-Keyword-Match).

---

### B4: Rules Engine UI & Self-Modifier
> **Prioritaet: MITTEL** | Effort: 1 Tag

Rules Engine existiert in DB und Service, hat aber keine dedizierte UI. ProposalView ist da, aber Rules-Visualisierung fehlt.

| Step | Beschreibung | Status |
|------|-------------|--------|
| B4.1 | `RulesView`: Liste aller aktiven Rules mit Kategorie-Filter | ⬜ |
| B4.2 | Rule-Detail: Condition + Action als lesbarer Text | ⬜ |
| B4.3 | Rule erstellen/bearbeiten (Formular oder Brain-generiert) | ⬜ |
| B4.4 | Self-Modifier: Brain schlaegt Rule-Aenderungen vor → Proposal | ⬜ ☁️ |
| B4.5 | Navigation: RulesView erreichbar via BrainAdmin | ⬜ |

**Gate:** User sieht alle aktiven Rules, kann neue erstellen, Brain schlaegt Verbesserungen vor.

---

## C — Neue Features (nach Prioritaet)

### Phase 25: Handschrift-Font Pipeline
> **Prioritaet: MITTEL** | Effort: 5-7 Tage | Auftrag: `AUFTRAG-HANDSCHRIFT-FONT-HANDLERS.md`

| Step | Beschreibung | Status |
|------|-------------|--------|
| 25.1 | `font.segment` Handler (Vision, Raster, Bigramm-Splitting) | 🔧 |
| 25.2 | `font.vectorize` Handler (Konturen, Bezier, Normalisierung) | 🔧 |
| 25.3 | `font.generate` Handler (OpenType-Writer, ~2500 LOC) | 🔧 |
| 25.4 | CFF Type 2 Encoder | 🔧 |
| 25.5 | GSUB Builder (`calt` Contextual Alternates) | 🔧 |
| 25.6 | GPOS Builder (`curs` Cursive Attachment, `kern` Auto-Kerning) | 🔧 |
| 25.7 | Skill-Definition + UI-Flow fuer 7 Boegen | ✅ (`brain-handwriting-font.brainskill.md`) |
| 25.8 | iPad Pencil-Pfad (PencilBridge Alternative) | 🔧 |

**Gate:** 7 Boegen scannen → Font mit ~200 Glyphen + kursive Verbindungen → .otf validiert.

---

### Phase 26: Live Activities & Lock Screen
> **Prioritaet: MITTEL** | Effort: 1-2 Tage | 🖥️ (neues Target)

| Step | Beschreibung | Status |
|------|-------------|--------|
| 26.1 | ActivityKit Integration: Focus-Task auf Lock Screen | ⬜ 🖥️ |
| 26.2 | Live Activity starten/stoppen via Pomodoro-Skill | ⬜ |
| 26.3 | Dynamic Island: Kompakte + erweiterte Ansicht | ⬜ |
| 26.4 | Brain Pulse als Live Activity (Tages-Zusammenfassung) | ⬜ |

**Gate:** Pomodoro laeuft → Timer auf Lock Screen + Dynamic Island sichtbar.

---

### Phase 27: Knowledge Graph UI
> **Prioritaet: MITTEL** | Effort: 2-3 Tage

| Step | Beschreibung | Status |
|------|-------------|--------|
| 27.1 | Grape (SwiftGraphs) SPM-Dependency hinzufuegen | ⬜ |
| 27.2 | `KnowledgeGraphView`: Force-Directed 2D Layout | ⬜ |
| 27.3 | Nodes = Entries, Edges = Links (farbcodiert nach Relation) | ⬜ |
| 27.4 | Interaktion: Tap → Detail, Pinch → Zoom, Drag → Verschieben | ⬜ |
| 27.5 | Filter: Nach Tags, Typ, Zeitraum | ⬜ |
| 27.6 | Cluster-Erkennung: Zusammengehoerige Entries gruppieren | ⬜ ☁️ |
| 27.7 | Neuer Tab oder via BrainAdmin erreichbar | ⬜ |

**Gate:** Graph zeigt Entries + Links, Cluster sind erkennbar, interaktiv navigierbar.

---

### Phase 28: Family & CloudKit Sync
> **Prioritaet: MITTEL** | Effort: 3-5 Tage

| Step | Beschreibung | Status |
|------|-------------|--------|
| 28.1 | CloudKit Container Setup (`iCloud.com.example.brain-ios`) | ⬜ 🖥️ |
| 28.2 | SQLiteData CloudKit Integration (GRDB + CKRecord) | ⬜ |
| 28.3 | `sync_state` Tabelle nutzen fuer Change Tracking | ⬜ |
| 28.4 | Sync-Konflikte: Last-Writer-Wins + Konflikt-UI fuer wichtige Aenderungen | ⬜ |
| 28.5 | CloudKit Shared Zones fuer Family Sharing | ⬜ |
| 28.6 | Shared Entries: Wer hat Zugriff, wer hat editiert | ⬜ |
| 28.7 | Einladungs-Flow: Family Member hinzufuegen | ⬜ |
| 28.8 | Offline-Sync: Aenderungen puffern, bei Verbindung synchronisieren | ⬜ |

**Gate:** Zwei Geraete synchronisieren Entries ueber iCloud. Family Member sieht geteilte Entries.

---

### Phase 29: Skill URL-Schema & Marktplatz-Infrastruktur
> **Prioritaet: NIEDRIG** | Effort: 1-2 Tage

| Step | Beschreibung | Status |
|------|-------------|--------|
| 29.1 | URL-Schema: `brain://import-skill?url=...` registrieren | ⬜ |
| 29.2 | Deep-Link Handler: URL → Download → Import-Preview → Install | ⬜ |
| 29.3 | AirDrop Import: `.brainskill.md` Dateityp registrieren (UTType) | ⬜ |
| 29.4 | Export: Skill als `.brainskill.md` teilen via Share Sheet | ⬜ (teilweise in SkillManagerView) |
| 29.5 | Dokumentation: Wie Drittanbieter Skill-Marktplaetze bauen koennen | ⬜ |

**Gate:** Link in Safari oeffnen → Brain importiert Skill mit Preview. AirDrop Skill → Import.

---

### Phase 30: LLM Kosten-Kontrolle
> **Prioritaet: MITTEL** | Effort: 0.5-1 Tag

| Step | Beschreibung | Status |
|------|-------------|--------|
| 30.1 | Token-Zaehler pro LLM-Request (Input + Output Tokens) | ⬜ |
| 30.2 | Kosten-Berechnung pro Provider (Preis/Token konfigurierbar) | ⬜ |
| 30.3 | Monats-Budget in Einstellungen (z.B. 10€/Monat) | ⬜ |
| 30.4 | Warnung bei 80% des Budgets, Sperre bei 100% (Fallback auf On-Device) | ⬜ |
| 30.5 | Kosten-Statistik-View: Diesen Monat, pro Tag, pro Skill | ⬜ |

**Gate:** User sieht aktuelle Kosten, wird gewarnt, Fallback auf On-Device bei Limit.

---

### Phase 31: Privacy Zones (Detail)
> **Prioritaet: MITTEL** | Effort: 1 Tag

| Step | Beschreibung | Status |
|------|-------------|--------|
| 31.1 | Tag-basierte Privacy-Regeln: `medizinisch` → nur On-Device | ⬜ |
| 31.2 | Automatische Erkennung sensibler Inhalte (LLM-Klassifizierung) | ⬜ ☁️ |
| 31.3 | UI: Privacy-Zone pro Tag konfigurieren | ⬜ |
| 31.4 | LLM Router: Respektiert Privacy Zones vor Cloud-Routing | ⬜ |
| 31.5 | Visueller Hinweis: Schloss-Icon bei On-Device-Only Entries | ⬜ |

**Gate:** Entry mit Tag "medizinisch" wird nie an Cloud-LLM gesendet. User sieht Routing-Entscheidung.

---

### Phase 32: Business Card Scanner
> **Prioritaet: NIEDRIG** | Effort: 1 Tag

| Step | Beschreibung | Status |
|------|-------------|--------|
| 32.1 | Kamera → VisionKit Scan (Visitenkarten-Modus) | ⬜ |
| 32.2 | Vision OCR: Text extrahieren | ⬜ |
| 32.3 | LLM: Strukturierte Daten extrahieren (Name, Firma, Tel, Mail, Adresse) | ⬜ ☁️ |
| 32.4 | Kontakt erstellen via ContactsBridge | ⬜ |
| 32.5 | Entry erstellen mit Link zum Kontakt | ⬜ |
| 32.6 | Als Brainskill implementieren (`brain-businesscard.brainskill.md`) | ⬜ |

**Gate:** Visitenkarte scannen → Kontakt + Entry erstellt. Offline: OCR-Text als Entry ohne Strukturierung.

---

## D — Plattform-Erweiterungen

### Phase 33: Keyboard Extension
> **Prioritaet: NIEDRIG** | Effort: 2-3 Tage | 🖥️ (neues Target)

| Step | Beschreibung | Status |
|------|-------------|--------|
| 33.1 | Neues Target: `BrainKeyboard` | ⬜ 🖥️ |
| 33.2 | Quick-Capture direkt aus jeder App via Keyboard | ⬜ |
| 33.3 | Text-Vorschlaege basierend auf Kontext (On-Device LLM) | ⬜ |
| 33.4 | Schnell-Uebersetzen im Keyboard | ⬜ |
| 33.5 | App Group DB-Zugriff fuer Entries | ⬜ |

**Gate:** Brain-Keyboard in jeder App nutzbar. Quick-Capture erstellt Entry.

---

### Phase 34: Apple Vision Pro
> **Prioritaet: NIEDRIG** | Effort: 5-7 Tage | 🖥️

| Step | Beschreibung | Status |
|------|-------------|--------|
| 34.1 | visionOS Target hinzufuegen | ⬜ 🖥️ |
| 34.2 | Adaptive Layout: `#if os(visionOS)` Conditionals | ⬜ |
| 34.3 | Multi-Window Support (WindowGroup + Scenes) | ⬜ |
| 34.4 | Knowledge Graph 3D (RealityKit, Force-Directed im Raum) | ⬜ |
| 34.5 | Spatial Capture: Blick auf Objekt → Entry erstellen | ⬜ |
| 34.6 | Handtracking Notes: Pinch → Notiz-Blase → Diktieren | ⬜ |
| 34.7 | Immersive Focus: Nur aktuelles Projekt sichtbar | ⬜ |
| 34.8 | Shared Space: Family Brain im Raum navigieren | ⬜ |

**Gate:** App laeuft auf Vision Pro. Multi-Window funktioniert. Knowledge Graph in 3D navigierbar.

---

## E — Hardware-Integrationen (Tier 2+3)

### Phase 35: HealthKit Integration
> **Prioritaet: NIEDRIG** | Effort: 1-2 Tage

| Step | Beschreibung | Status |
|------|-------------|--------|
| 35.1 | HealthKit Bridge: Schlaf, Schritte, Workout lesen | ⬜ |
| 35.2 | Korrelations-Analyse: Produktivitaet vs. Schlaf/Bewegung | ⬜ ☁️ |
| 35.3 | Insights: "Du schreibst besser nach 7h+ Schlaf" | ⬜ |
| 35.4 | Wellness-Dashboard in Wochen-Rueckblick integrieren | ⬜ |
| 35.5 | Als Brainskill: `brain-wellness.brainskill.md` | ⬜ |

**Gate:** Brain korreliert Schlaf mit Produktivitaet und zeigt Insight im Wochen-Rueckblick.

---

### Phase 36: HomeKit Integration
> **Prioritaet: NIEDRIG** | Effort: 1 Tag

| Step | Beschreibung | Status |
|------|-------------|--------|
| 36.1 | HomeKit Bridge: Geraete lesen, Szenen ausloesen | ⬜ |
| 36.2 | Focus-Automation: "Deep Focus → Licht dimmen, DnD an" | ⬜ |
| 36.3 | Shortcut-Integration: Brain steuert Home-Szenen | ⬜ |
| 36.4 | Als Brainskill: `brain-smart-home.brainskill.md` | ⬜ |

**Gate:** "Deep Focus" aktiviert → Licht wird gedimmt.

---

### Phase 37: AirPod & Audio Features
> **Prioritaet: NIEDRIG** | Effort: 1-2 Tage

| Step | Beschreibung | Status |
|------|-------------|--------|
| 37.1 | MediaPlayer Integration: AirPod Doppel-Squeeze → Quick Capture | ⬜ |
| 37.2 | AVFoundation: Spatial Audio Memos (AirPods Pro 3D) | ⬜ |
| 37.3 | Audio-Entry-Typ: Aufnahme + Transkription + Entry | ⬜ |
| 37.4 | MusicKit: Aktueller Song als Kontext in Entries | ⬜ |

**Gate:** Doppel-Squeeze → Notiz aufnehmen. Audio-Entry mit Transkription erstellt.

---

### Phase 38: Geo-Fencing & Standort-Automatisierung
> **Prioritaet: NIEDRIG** | Effort: 1 Tag

| Step | Beschreibung | Status |
|------|-------------|--------|
| 38.1 | CoreLocation: Geo-Fence Regionen definieren | ⬜ |
| 38.2 | Automatische Actions bei Betreten/Verlassen einer Zone | ⬜ |
| 38.3 | Reise-Logger: Standort-Wechsel als Timeline | ⬜ |
| 38.4 | Map View erweitern: Geo-Fences als Overlays anzeigen | ⬜ |
| 38.5 | Als Brainskill: `brain-geo.brainskill.md` | ⬜ |

**Gate:** "Wenn ich das Buero verlasse → offene Tasks zusammenfassen" funktioniert automatisch.

---

### Phase 39: MusicKit Integration
> **Prioritaet: NIEDRIG** | Effort: 0.5-1 Tag

| Step | Beschreibung | Status |
|------|-------------|--------|
| 39.1 | MusicKit Bridge: Aktueller Song, Playlists | ⬜ |
| 39.2 | Podcast-Notizen: "Erstelle Entry zum aktuellen Podcast" | ⬜ |
| 39.3 | Stimmungs-Erkennung: Musik-Genre als Kontext in Briefings | ⬜ |
| 39.4 | Shortcut: Brain startet Playlist basierend auf Focus-Modus | ⬜ |

**Gate:** "Was hoere ich gerade?" → Brain antwortet mit Song + erstellt optionalen Entry.

---

## F — UX-Verfeinerung

### Phase 40: Progressive Disclosure (Gesten-System)
> **Prioritaet: MITTEL** | Effort: 1-2 Tage

| Step | Beschreibung | Status |
|------|-------------|--------|
| 40.1 | Systematisches Gesten-Mapping ueber alle Listen-Views | ⬜ |
| 40.2 | Swipe → = Kontextaktion (Things 3: Termin setzen) | ⬜ (teilweise) |
| 40.3 | Swipe ← = Archivieren/Loeschen | ⬜ (teilweise) |
| 40.4 | Long Press = Alle Optionen (Taggen, Verlinken, Teilen) | ⬜ |
| 40.5 | Pinch = AI-Zusammenfassung (Arc Search Pattern) | ⬜ |
| 40.6 | Konsistenz: Gleiche Gesten in allen Views | ⬜ |

**Gate:** Alle Listen-Views haben konsistente Swipe/Long-Press/Pinch Gesten.

---

### Phase 41: Unified Input Bar (Fantastical-Modus)
> **Prioritaet: MITTEL** | Effort: 1 Tag

NLP-Parser existiert (Phase 23), aber die Input Bar nutzt ihn nur teilweise.

| Step | Beschreibung | Status |
|------|-------------|--------|
| 41.1 | Input Bar erkennt: "Mail an Sarah: Projektupdate" → E-Mail Compose | ⬜ |
| 41.2 | Input Bar erkennt: "Suche Meeting-Notizen Maerz" → Search | ⬜ |
| 41.3 | Live-Preview: Erkannte Struktur in Echtzeit anzeigen | ⬜ (teilweise) |
| 41.4 | Autocomplete fuer Personen, Tags, Projekte | ⬜ |

**Gate:** Input Bar versteht alle 5 Fantastical-Patterns (Task, Event, Mail, Reminder, Search).

---

### Phase 42: Temporal Map (Zeitachse + Karte)
> **Prioritaet: NIEDRIG** | Effort: 1 Tag

Map View existiert (Build 74), aber ohne Zeitachsen-Dimension.

| Step | Beschreibung | Status |
|------|-------------|--------|
| 42.1 | Timeline-Slider unter der Karte: Zeitraum waehlen | ⬜ |
| 42.2 | Karte zeigt nur Entries im gewaehlten Zeitraum | ⬜ |
| 42.3 | Reise-Modus: Verbindungslinien zwischen Orten in chronologischer Reihenfolge | ⬜ |
| 42.4 | "Was habe ich in Berlin notiert?" als Suchfunktion | ⬜ |

**Gate:** Timeline-Slider filtert Karte. Reisen sind als Pfade sichtbar.

---

## G — Abhaengigkeits-Graph

```
B1 (Skill-Bundling) ←── Alle Skills brauchen das
│
├── B2 (Skill-Erstellung per Chat)
├── Phase 29 (URL-Schema Import)
│
B3 (sqlite-vec) ←── Semantic Search
│
├── Deja-Vu (in Phase 19, teilweise)
├── Kontext-Suche
│
Phase 25 (Handschrift-Font) ←── Unabhaengig, parallel
│
Phase 26 (Live Activities) ←── Braucht MacVM (neues Target)
Phase 28 (CloudKit Sync) ←── Braucht MacVM (CloudKit Container)
Phase 33 (Keyboard Extension) ←── Braucht MacVM (neues Target)
Phase 34 (Vision Pro) ←── Braucht MacVM (visionOS Target)
│
Phase 27 (Knowledge Graph) ←── Grape SPM Dependency
│
Phasen 35-39 (Hardware) ←── Unabhaengig voneinander, brauchen Device-Testing
│
Phasen 40-42 (UX) ←── Unabhaengig, jederzeit machbar
```

---

## H — Empfohlene Reihenfolge

### Sofort (auf VPS machbar)

| # | Phase | Effort | Warum jetzt |
|---|-------|--------|-------------|
| 1 | **B1: Skill-Bundling** | 0.5 Tage | Blocker: Keine Skills aktiv |
| 2 | **B2: Skill-Erstellung** | 1-2 Tage | Kern-Feature der Skill Engine |
| 3 | **B3: sqlite-vec** | 2-3 Tage | Voraussetzung fuer Semantic Search / Deja-Vu |
| 4 | **30: Kosten-Kontrolle** | 0.5 Tage | Wichtig fuer User-Vertrauen |
| 5 | **31: Privacy Zones** | 1 Tag | Datenschutz-Differenzierung |
| 6 | **B4: Rules Engine UI** | 1 Tag | Self-Modifier sichtbar machen |

### Naechste Iteration (auf VPS machbar)

| # | Phase | Effort | Warum |
|---|-------|--------|-------|
| 7 | **25: Handschrift-Font** | 5-7 Tage | Differenzierungs-Feature, Auftrag liegt vor |
| 8 | **27: Knowledge Graph** | 2-3 Tage | Visuelles Alleinstellungsmerkmal |
| 9 | **29: Skill URL-Schema** | 1-2 Tage | Oekosystem oeffnen |
| 10 | **32: Business Card Scanner** | 1 Tag | Nutzt bestehende Bridges |
| 11 | **40-42: UX Polish** | 3 Tage | Systematische Gesten + Input Bar + Temporal Map |

### Braucht MacVM

| # | Phase | Effort | Warum MacVM |
|---|-------|--------|-------------|
| 12 | **26: Live Activities** | 1-2 Tage | ActivityKit braucht neues Target |
| 13 | **28: CloudKit Sync** | 3-5 Tage | CloudKit Container in Xcode |
| 14 | **33: Keyboard Extension** | 2-3 Tage | Neues Extension-Target |
| 15 | **34: Vision Pro** | 5-7 Tage | visionOS-Target |

### Braucht Device-Testing (+ evtl. Hardware)

| # | Phase | Effort | Hardware |
|---|-------|--------|----------|
| 16 | **35: HealthKit** | 1-2 Tage | iPhone + Apple Watch |
| 17 | **36: HomeKit** | 1 Tag | HomeKit-Geraete |
| 18 | **37: AirPods** | 1-2 Tage | AirPods Pro |
| 19 | **38: Geo-Fencing** | 1 Tag | iPhone (GPS) |
| 20 | **39: MusicKit** | 0.5 Tage | Apple Music Abo |

---

## I — Gesamtuebersicht

| Kategorie | Phasen | Gesamt-Effort |
|-----------|--------|---------------|
| **Infrastruktur & Fixes** (B1-B4) | 2 offen (B3, B4) | ~4 Tage |
| **Neue Features** (25-32) | 8 | ~16 Tage |
| **Plattform-Erweiterungen** (33-34) | 2 | ~10 Tage |
| **Hardware-Integrationen** (35-39) | 5 | ~5 Tage |
| **UX-Verfeinerung** (40-42) | 3 | ~4 Tage |
| **Total** | **20 Phasen offen** | **~39 Tage** |

Davon brauchen 4 Phasen (26, 28, 33, 34) die MacVM und 5 Phasen (35-39) echte Hardware.
Die restlichen 11 Phasen sind vom VPS aus umsetzbar.
