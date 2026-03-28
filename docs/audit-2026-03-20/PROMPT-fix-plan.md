# Prompt: Projekt-Prozess-Plan fuer Brain-iOS Audit-Fixes

Kopiere den folgenden Prompt in eine neue Claude-Session:

---

Du bist ein erfahrener iOS-Architekt und Projektplaner. Deine Aufgabe ist es, einen detaillierten Projekt-Prozess-Plan zu erstellen, um alle Sicherheitsluecken und UX-Schwaechen der App "Brain-iOS" zu beheben.

## Kontext

Brain-iOS ist eine native iOS-App (Swift 6, SwiftUI, GRDB/SQLite) die als lokaler AI-Assistent mit erweiterbarem Skill-System funktioniert. Die App befindet sich auf einem VPS unter `/home/andy/brain-ios`.

Ein umfassendes Audit vom 20. Maerz 2026 hat 40 Code-Issues und zahlreiche UX-Schwaechen identifiziert. Die vollstaendigen Audit-Reports liegen unter:

- `/home/andy/brain-ios/docs/audit-2026-03-20/01-code-audit.md` (40 Findings: 4 KRITISCH, 7 HOCH, 6 MITTEL, 23 NIEDRIG)
- `/home/andy/brain-ios/docs/audit-2026-03-20/02-functional-analysis.md` (Feature-Completeness, UX-Bewertung, Quick Wins)
- `/home/andy/brain-ios/docs/audit-2026-03-20/03-competitive-analysis.md` (Marktpositionierung und Luecken)

## Aufgabe

1. **Lies alle drei Audit-Reports** vollstaendig durch.
2. **Lies die Projektdateien** um den aktuellen Code-Stand zu verstehen:
   - `CLAUDE.md` (Projektkonventionen, Architektur)
   - `Sources/BrainCore/` (Framework-Struktur)
   - `Sources/BrainApp/` (App-Struktur)
   - Die im Audit referenzierten Dateien (BiometricAuth, ChatService, KeychainService, etc.)
3. **Erstelle einen Projekt-Prozess-Plan** mit folgender Struktur:

### Gewuenschte Plan-Struktur

```
Phase 1: Kritische Sicherheitsfixes (Prioritaet: SOFORT)
  - K1, K2, K3, K4 aus dem Code-Audit
  - Fuer jedes Issue:
    - Betroffene Datei(en)
    - Konkreter Loesungsansatz (Code-Skizze wo sinnvoll)
    - Abhaengigkeiten zu anderen Issues
    - Geschaetzter Aufwand (S/M/L)
    - Testkriterien (woran erkenne ich, dass es gefixt ist?)

Phase 2: Hohe Sicherheits- und Stabilitaetsfixes
  - H1-H7 aus dem Code-Audit
  - Gleiche Detailtiefe wie Phase 1

Phase 3: UX Quick Wins (< 1 Tag Aufwand pro Item)
  - Aus der Funktionsanalyse: Confirmation-Dialog, Pull-to-Refresh, Haptic Feedback, etc.
  - Gruppiert nach Datei/View

Phase 4: Mittlere Code-Issues
  - M1-M6 aus dem Code-Audit

Phase 5: UX-Verbesserungen (groesserer Aufwand)
  - Onboarding
  - i18n-Framework
  - Accessibility-Verbesserungen

Phase 6: Architektur-Refactoring
  - DataBridge aufteilen
  - Dependency Injection
  - Protokoll-basiertes Design

Phase 7: Niedrige Issues (Backlog)
  - L1-L23 priorisiert
```

### Anforderungen an den Plan

- **Reihenfolge beachten**: Sicherheit vor UX, Quick Wins vor grossen Refactorings
- **Abhaengigkeiten markieren**: Welche Fixes muessen vor anderen erledigt werden?
- **Testbarkeit**: Jeder Fix braucht ein konkretes "Done"-Kriterium
- **Realistische Aufwandsschaetzung**: S = < 2h, M = 2-8h, L = 1-3 Tage
- **Keine Feature-Requests**: Nur Fixes fuer bestehende Issues (kein Knowledge Graph, kein HealthKit etc.)
- **Swift 6 kompatibel**: Alle Loesungen muessen `strict-concurrency=complete` einhalten
- **Kein Over-Engineering**: Minimale Aenderungen die das Problem loesen

### Output

Speichere den fertigen Plan als `/home/andy/brain-ios/docs/audit-2026-03-20/PROJECT-PLAN.md` ab.

---
