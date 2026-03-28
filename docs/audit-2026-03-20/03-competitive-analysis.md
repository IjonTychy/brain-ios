# Brain-iOS Wettbewerbsanalyse & Positionierung

**Datum:** 20. Maerz 2026
**Scope:** Vergleich mit iOS-, Desktop-, Web- und Android-Anwendungen im Bereich Personal Knowledge Management, AI-Assistenten und Produktivitaet

---

## Executive Summary

Brain-iOS kombiniert fuenf Eigenschaften, die in dieser Kombination einzigartig sind:

1. **"Everything is an Entry"** — einheitliches Datenmodell statt App-Silos
2. **Skill Engine** — erweiterbare .brainskill.md-Dateien mit eigenem DSL
3. **Multi-LLM mit On-Device** — Anthropic Claude, OpenAI GPT, Apple Foundation Models
4. **Kein Server** — komplett lokal, SQLite + Keychain, keine Cloud-Abhaengigkeit
5. **Einmalkauf-Modell** — kein Abo (geplant)

Keine der 25+ verglichenen Apps bietet alle fuenf Eigenschaften gleichzeitig.

---

## iOS-Wettbewerber

### Notion (iOS)

| Aspekt | Notion | Brain-iOS |
|--------|--------|-----------|
| Datenmodell | Bloecke + Datenbanken | Entries + Tags + Links |
| AI | Notion AI (Cloud, Abo) | Multi-LLM (lokal + Cloud) |
| Offline | Begrenzt (Cache) | Vollstaendig (SQLite) |
| Erweiterbarkeit | API + Integrations | Skill Engine (.brainskill.md) |
| Collaboration | Echtzeit Multi-User | Einzelnutzer |
| Preis | Free + $10/Monat (AI: +$10) | Einmalkauf (geplant) |

**Fazit:** Notion ist staerker bei Collaboration und hat ein riesiges Oekosystem. Brain-iOS gewinnt bei Privacy, Offline-Faehigkeit und LLM-Flexibilitaet.

### Obsidian (iOS)

| Aspekt | Obsidian | Brain-iOS |
|--------|----------|-----------|
| Datenmodell | Markdown-Dateien + Ordner | SQLite-Entries |
| AI | Plugins (Community) | Native Multi-LLM |
| Offline | Vollstaendig (lokale Dateien) | Vollstaendig (SQLite) |
| Erweiterbarkeit | Plugin-System (JS/TS) | Skill Engine (.brainskill.md) |
| Graph-View | Ja (interaktiv) | Nein (Links existieren, keine Visualisierung) |
| Preis | Free + $50/Jahr (Sync) | Einmalkauf (geplant) |

**Fazit:** Obsidian hat ein massives Plugin-Oekosystem und den besten Graph-View. Brain-iOS hat nativere iOS-Integration (Bridges) und integriertes LLM. Obsidians iOS-App ist allerdings Electron-basiert und fuehlt sich nicht nativ an.

### Bear

| Aspekt | Bear | Brain-iOS |
|--------|------|-----------|
| Staerke | Elegantes UI, Markdown | Skill Engine, LLM |
| Schwaeche | Keine AI, keine Automation | Kein vergleichbar poliertes UI |
| Preis | $30/Jahr | Einmalkauf (geplant) |

**Fazit:** Bear ist ein Note-Taking-Spezialist mit bestem-in-Klasse UI. Brain-iOS ist ambitionierter im Scope aber weniger poliert im visuellen Design.

### Things 3

| Aspekt | Things 3 | Brain-iOS |
|--------|----------|-----------|
| Staerke | Bestes Task-UI auf iOS | Universelles Datenmodell |
| Schwaeche | Nur Tasks, keine Notes/Knowledge | Task-Management weniger poliert |
| Preis | CHF 50 (Einmalkauf) | Einmalkauf (geplant) |

**Fazit:** Things 3 ist der Gold-Standard fuer Task-Management-UI. Brain-iOS deckt Tasks ab, kann aber nicht mit der UX-Politur von Things mithalten.

### Apple Notes + Reminders

| Aspekt | Apple Notes | Brain-iOS |
|--------|-------------|-----------|
| Staerke | Systemintegration, kostenlos | AI, Skill Engine, Tool-Use |
| Schwaeche | Keine AI, keine Automation, kein Datenmodell | Kein iCloud-Sync |

**Fazit:** Apple Notes ist der Baseline-Wettbewerber. Brain-iOS differenziert sich klar durch AI und Erweiterbarkeit.

### Reflect

| Aspekt | Reflect | Brain-iOS |
|--------|---------|-----------|
| Staerke | AI-Zusammenfassungen, Graph | Multi-LLM, Offline, Skills |
| Schwaeche | Cloud-only, $10/Monat | Kein Graph-View |

### Mem

| Aspekt | Mem | Brain-iOS |
|--------|-----|-----------|
| Staerke | AI-first, automatische Organisation | Multi-LLM, lokale Daten |
| Schwaeche | Cloud-only, US-Server, kein Skill-System | Weniger "magische" AI-Features |

### Fantastical / Spark

Spezialisierte Kalender/Email-Apps. Brain-iOS integriert beides via Bridges in ein einheitliches System, ist aber kein Ersatz fuer dedizierte Kalender/Email-Apps.

### NotePlan

| Aspekt | NotePlan | Brain-iOS |
|--------|----------|-----------|
| Staerke | Markdown + Kalender + Tasks | AI + Skill Engine + Bridges |
| Schwaeche | Keine AI, Plugin-System begrenzt | Weniger ausgereifte Kalender-Integration |

**Fazit:** NotePlan ist der naechste Wettbewerber in der "alles-in-einem"-Kategorie, aber ohne AI.

---

## Desktop/Shell-Wettbewerber

### Emacs Org-mode

| Aspekt | Org-mode | Brain-iOS |
|--------|----------|-----------|
| Flexibilitaet | Unerreicht (Elisp) | Skill Engine (begrenzter) |
| AI | Via Plugins moeglich | Native Multi-LLM |
| Mobile | Nicht existent (Termux-Hacks) | Native iOS |
| Lernkurve | Extrem steil | Moderat |

**Fazit:** Org-mode ist das ultimative Power-Tool, aber auf dem Desktop eingesperrt. Brain-iOS bringt einen Teil dieser Philosophie auf iOS.

### Logseq

| Aspekt | Logseq | Brain-iOS |
|--------|--------|-----------|
| Open-Source | Ja | Nein |
| Graph-View | Ja (interaktiv) | Nein |
| AI | Community-Plugins | Native Multi-LLM |
| Mobile | Electron-App (langsam) | Native SwiftUI |

### Taskwarrior + nb (CLI)

Leistungsfaehige CLI-Tools ohne Mobile-Story. Brain-iOS fuellt die Luecke fuer Nutzer die CLI-Power auf dem Telefon wollen.

### Dendron (VS Code)

Eingestellt (2024). Zeigt das Risiko von IDE-gebundenen PKM-Tools.

### Zettlr

Open-Source Markdown-Editor mit Zettelkasten-Fokus. Kein Mobile, kein AI.

---

## Web-Wettbewerber

### Roam Research

| Aspekt | Roam | Brain-iOS |
|--------|------|-----------|
| Innovation | Bi-directional Links Pionier | Aehnliches Link-System |
| Status | Stagnierend, Community schrumpft | Aktive Entwicklung |
| AI | Begrenzt | Native Multi-LLM |
| Preis | $15/Monat | Einmalkauf (geplant) |

### Anytype

| Aspekt | Anytype | Brain-iOS |
|--------|---------|-----------|
| Staerke | P2P, Open-Source, Object-Types | Skill Engine, On-Device LLM |
| Schwaeche | Keine native LLM-Integration | Kein P2P-Sync |

### Capacities

| Aspekt | Capacities | Brain-iOS |
|--------|------------|-----------|
| Staerke | Object-basiert (aehnlich zu Entries) | Mehr iOS-Integration |
| Schwaeche | Cloud-only, kein Skill-System | Kein Web-Interface |

**Fazit:** Capacities ist konzeptionell am naechsten an Brain-iOS (Object-basiertes Datenmodell), aber Web-first und ohne AI-Skills.

### Heptabase

Fokus auf visuelles Denken (Whiteboards). Komplementaer, nicht konkurrierend.

### AFFiNE

Open-Source Notion-Alternative mit Block-Editor. Kein AI-Skill-System, kein iOS-native.

---

## Android

**Kein direktes Aequivalent existiert.** Die Kombination aus lokalem LLM + Skill-Engine + nativer App gibt es auf Android nicht. Naechste Kandidaten:

- **Obsidian (Android)**: Markdown + Plugins, aber kein nativer LLM
- **Notion (Android)**: Cloud-basiert, kein Offline, Abo-Modell
- **Anytype (Android)**: P2P, aber keine AI-Integration
- **Tasker + AutoGPT**: DIY-Kombination, extrem technisch

Brain-iOS hat auf iOS einen klaren First-Mover-Advantage in dieser Nische.

---

## OpenClaw (Open Interpreter)

### Ueberblick

- **GitHub:** 247K Stars (eines der populaersten AI-Projekte)
- **Gruender:** Killian Lucas (inzwischen bei OpenAI)
- **Typ:** Open-Source Agent-Framework
- **Interface:** CLI / Messaging
- **LLM:** Multi-LLM (OpenAI, Anthropic, lokale Modelle)

### Vergleich

| Aspekt | OpenClaw | Brain-iOS |
|--------|----------|-----------|
| Typ | Agent-Framework (CLI/API) | Native iOS App |
| Interface | Terminal / Chat | SwiftUI |
| Skill-System | Tool-Definitionen (Python) | .brainskill.md (YAML+Markdown) |
| LLM | Multi-LLM + lokale Modelle | Multi-LLM + Apple Foundation Models |
| OS-Integration | Dateisystem, Shell-Befehle | iOS Bridges (Kalender, Kontakte, etc.) |
| Ausfuehrungsumgebung | Server / Desktop | On-Device (iPhone/iPad) |
| Sicherheit | Sandbox optional | Keychain, Cert-Pinning, Skill-Hashing |
| Zielgruppe | Entwickler | Endnutzer |
| Preis | Open Source | Einmalkauf (geplant) |

### Positionierung

OpenClaw und Brain-iOS teilen die gleiche Vision: **ein AI-Agent der mit lokalen Daten und Werkzeugen arbeitet**. Die Implementierung ist grundverschieden:

- OpenClaw: **Desktop-first, Developer-first, Shell-basiert**
- Brain-iOS: **Mobile-first, Consumer-first, GUI-basiert**

Die beiden sind **komplementaer, nicht konkurrierend**. Brain-iOS koennte als "OpenClaw fuer iOS-Endnutzer" positioniert werden.

---

## Marktpositionierung

### Unique Selling Proposition

```
Brain-iOS: Der erste lokale AI-Assistent fuer iOS mit erweiterbarem Skill-System.
Deine Daten bleiben auf deinem Geraet. Kein Abo. Kein Server.
```

### Zielgruppe

**Primaer:** Tech-affine Wissensarbeiter (25-45) die:
- Privacy-bewusst sind (kein Cloud-Zwang)
- Abo-Muedigkeit haben
- Ein "zweites Gehirn" wollen, das AI nutzt
- iOS als Hauptplattform nutzen

**Sekundaer:**
- Obsidian/Notion-Nutzer die mehr AI wollen
- Entwickler die ein programmierbares iOS-Tool suchen
- Zettelkasten-Enthusiasten

### SWOT-Analyse

| Staerken | Schwaechen |
|----------|-----------|
| Einzigartige Feature-Kombination | Einzelentwickler-Risiko |
| Privacy-first (lokal) | Kein Sync/Collaboration |
| Native iOS-Performance | DACH-only (deutsche UI) |
| Skill Engine (Erweiterbarkeit) | Kein Graph-View |
| Multi-LLM (Flexibilitaet) | LLM-Skill-Generierung fehlt |

| Chancen | Risiken |
|---------|---------|
| AI-Assistenten-Markt waechst | Apple koennte aehnliche Features in Notes/Siri einbauen |
| Keine direkte Konkurrenz in Nische | API-Key-Kosten schrecken Mainstream-User ab |
| On-Device LLM wird besser (Apple Silicon) | OpenClaw/similaere koennen iOS-App launchen |
| Skill-Marketplace moeglich | Ein-Personen-Projekt: Bus-Faktor 1 |

### Preispositionierung

| Modell | Vergleich |
|--------|-----------|
| Things 3: CHF 50 Einmalkauf | Etablierter Referenzpunkt fuer Premium-iOS-Apps |
| Bear: CHF 30/Jahr | Zeigt Akzeptanz fuer Abo bei genug Wert |
| Obsidian: Kostenlos + CHF 50/Jahr Sync | Freemium funktioniert bei Sync als Upsell |
| **Brain-iOS: CHF 30-50 Einmalkauf** | Positionierung zwischen Things 3 und Bear |

**Empfehlung:** Einmalkauf CHF 39 mit optionalem Tip-Jar. API-Keys bringt der User selbst mit — das senkt die laufenden Kosten auf null und differenziert vom Abo-Modell.

---

## Schlussfolgerung

Brain-iOS besetzt eine genuine Marktluecke: **ein lokaler, erweiterbarer AI-Assistent als native iOS-App**. Die groessten Risiken sind:

1. **Apple Siri/Notes AI** koennte den Mainstream-Bedarf abdecken
2. **Fehlende LLM-Skill-Generierung** untermininiert das zentrale Versprechen
3. **Einzelentwickler** limitiert Entwicklungsgeschwindigkeit und Vertrauen

Die groesste Chance ist der wachsende Markt fuer Privacy-bewusste AI-Tools. Wenn Apple Foundation Models besser werden (iOS 19+), wird Brain-iOS als einer der wenigen On-Device-AI-Clients massiv profitieren.
