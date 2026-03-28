---
name: bug-triage
description: Bug-Triage fuer brain-ios. Kategorisiert, priorisiert und dokumentiert Bugs in BUG-REPORT.md. Nutze diesen Skill um neue Bugs einzutragen oder den Bug-Report zu aktualisieren.
allowed-tools: Read, Edit, Write, Grep, Glob, Bash(git *)
argument-hint: [new <beschreibung>|update|stats|close <id>]
---

# Bug-Triage — brain-ios

Verwaltet den Bug-Report fuer das brain-ios Projekt.

## Kommandos

### Neuer Bug ($ARGUMENTS beginnt mit "new")

1. Lies BUG-REPORT.md
2. Bestimme die naechste Bug-ID (BUG-NNN)
3. Kategorisiere den Bug:
   - **Runtime:** Skill-Engine, Render, Action, Logic
   - **UI:** SwiftUI Views, Navigation, Layout
   - **Data:** GRDB, Migrations, Queries
   - **LLM:** Provider, Router, Streaming
   - **Bridge:** iOS Bridges (Contacts, EventKit, etc.)
   - **Build:** Xcode Cloud, pbxproj, SPM
   - **Security:** Keychain, Auth, Pinning
4. Priorisiere:
   - **P0 Critical:** App crasht, Datenverlust
   - **P1 High:** Feature kaputt, Security-Issue
   - **P2 Medium:** Falsche Darstellung, UX-Problem
   - **P3 Low:** Kosmetisch, Nice-to-have
5. Trage den Bug in BUG-REPORT.md ein

### Update ($ARGUMENTS = "update")

1. Lies BUG-REPORT.md
2. Pruefe via `git log` und Code-Analyse ob Bugs behoben wurden
3. Aktualisiere Status (OFFEN → BEHOBEN) mit Commit-Referenz

### Statistik ($ARGUMENTS = "stats")

1. Lies BUG-REPORT.md
2. Zaehle nach Kategorie und Prioritaet
3. Zeige Zusammenfassung

### Bug schliessen ($ARGUMENTS beginnt mit "close")

1. Finde den Bug anhand der ID
2. Markiere als BEHOBEN mit Datum und Begruendung

## Bug-Format in BUG-REPORT.md

```markdown
### BUG-NNN: [Kurzbeschreibung]
- **Kategorie:** Runtime/UI/Data/LLM/Bridge/Build/Security
- **Prioritaet:** P0/P1/P2/P3
- **Status:** OFFEN / BEHOBEN / WONTFIX
- **Datei:** [betroffene Datei(en)]
- **Beschreibung:** [Details]
- **Behoben:** [Datum, Commit] (nur wenn behoben)
```
