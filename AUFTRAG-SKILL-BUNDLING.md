# Auftrag: Skill-Bundling & Parser-Erweiterung

> Prioritaet: HOCH — Voraussetzung dafuer, dass vorinstallierte Skills beim App-Start aktiv sind.
> Geschaetzter Aufwand: 1-2 Stunden
> Abhaengigkeiten: Keine (nutzt bestehende Infrastruktur)

---

## Problem

Die `.brainskill.md`-Dateien unter `Skills/` liegen im Repo, werden aber **nicht in die App geladen**.
Es fehlt:

1. **Bundling**: Die Dateien werden nicht ins App-Bundle kopiert
2. **Startup-Loading**: Kein Code laedt die gebundleten Skills beim App-Start
3. **Parser-Felder**: `BrainSkillParser` kennt die neuen Frontmatter-Felder nicht
   (`capability`, `llm.required`, `llm.fallback`, `llm.complexity`)

Die gesamte Infrastruktur existiert bereits:
- `BrainSkillParser.parse()` → parsed Frontmatter + Markdown Body
- `SkillLifecycle.installFromDefinition()` → installiert in SQLite
- `SkillManagerView` → zeigt installierte Skills

---

## Schritt 1: Parser-Erweiterung (BrainSkillSource)

**Datei:** `Sources/BrainCore/Engine/SkillCompiler.swift`

### Neue Felder in `BrainSkillSource`

```swift
public struct BrainSkillSource: Codable, Sendable, Equatable {
    // ... bestehende Felder ...
    public var capability: SkillCapability?    // NEU: app, brain, hybrid
    public var llmRequired: Bool?             // NEU: aus llm.required
    public var llmFallback: String?           // NEU: aus llm.fallback (z.B. "on-device")
    public var llmComplexity: String?         // NEU: aus llm.complexity (low, medium, high)
    public var createdBy: String?             // NEU: system, user, brain
    public var enabled: Bool?                 // NEU: default true
}

public enum SkillCapability: String, Codable, Sendable {
    case app
    case brain
    case hybrid
}
```

### Parser erweitern

Im `BrainSkillParser.parse()` die neuen Keys erkennen:

```
capability: hybrid         → source.capability = .hybrid
created_by: system         → source.createdBy = "system"
enabled: true              → source.enabled = true
```

Fuer verschachtelte `llm:`-Felder: Der bestehende Parser ueberspringt indentierte Zeilen.
Zwei Optionen:
- **Option A (einfach):** Flache Keys im Frontmatter: `llm_required: true`, `llm_fallback: on-device`, `llm_complexity: medium`
- **Option B (korrekt):** Parser erkennt verschachtelte YAML eine Ebene tief:
  ```yaml
  llm:
    required: true
    fallback: on-device
    complexity: medium
  ```
  Wird zu `source.llmRequired = true`, `source.llmFallback = "on-device"`, etc.

**Empfehlung:** Option B — die Skill-Dateien nutzen bereits das verschachtelte Format.
Der Parser muss dafuer nur eine Ebene Verschachtelung unterstuetzen (Zeilen die mit
2 Spaces eingerueckt sind und unter einem bekannten Parent-Key stehen).

### Tests

Neue Tests in `SkillCompilerTests.swift`:
- Parse Skill mit `capability: hybrid` → `.hybrid`
- Parse Skill mit verschachteltem `llm:` Block → `llmRequired`, `llmFallback`, `llmComplexity`
- Parse Skill ohne neue Felder → Defaults (capability = nil, llm* = nil)

---

## Schritt 2: Skills ins App-Bundle (pbxproj)

### Copy Bundle Resources

Die `.brainskill.md`-Dateien muessen als Ressourcen ins App-Bundle:

1. **PBXBuildFile + PBXFileReference** fuer jede `.brainskill.md` in `Skills/`
2. **PBXResourcesBuildPhase** des BrainApp-Targets: Dateien hinzufuegen
3. **PBXGroup** "Skills" erstellen (analog zu "Repositories" Gruppe)

Alternativ: Einen Ordner-Verweis ("folder reference") statt einzelner Dateien,
damit neue Skills automatisch mit-gebundlet werden.

### Welche Skills bundlen (16 total)

Bestehend (3):
- `brain-reminders.brainskill.md`
- `brain-patterns.brainskill.md`
- `brain-proactive.brainskill.md`

Neu (13):
- `brain-pomodoro.brainskill.md`
- `brain-translate.brainskill.md`
- `brain-shopping.brainskill.md`
- `brain-routines.brainskill.md`
- `brain-summarize.brainskill.md`
- `brain-meeting-prep.brainskill.md`
- `brain-weekly-review.brainskill.md`
- `brain-habits.brainskill.md`
- `brain-email-draft.brainskill.md`
- `brain-project.brainskill.md`
- `brain-contact-intel.brainskill.md`
- `brain-journal.brainskill.md`
- `brain-handwriting-font.brainskill.md`

**NICHT bundlen:**
- `xcode-cloud-lessons-learned.brainskill.md` (internes Dokument, kein echter Skill)

---

## Schritt 3: Startup-Loading

**Datei:** Neue Datei `Sources/BrainApp/SkillBundleLoader.swift`

```swift
import BrainCore

struct SkillBundleLoader {

    static func loadBundledSkills(lifecycle: SkillLifecycle) {
        guard let skillURLs = Bundle.main.urls(
            forResourcesWithExtension: "md",
            subdirectory: nil
        )?.filter({ $0.lastPathComponent.hasSuffix(".brainskill.md") })
        else { return }

        let parser = BrainSkillParser()

        for url in skillURLs {
            guard let content = try? String(contentsOf: url) else { continue }

            do {
                let source = try parser.parse(content)

                // Nur installieren wenn noch nicht vorhanden ODER Version hoeher
                if let existing = try lifecycle.fetch(id: source.id) {
                    if existing.version >= source.version { continue }
                    // Update: Neue Version → neu installieren
                    try lifecycle.uninstall(id: source.id)
                }

                // Installieren (ohne SkillDefinition — wird bei Bedarf vom LLM kompiliert)
                try lifecycle.installFromSource(
                    source: source,
                    createdBy: .system
                )
            } catch {
                // Fehler loggen, aber nicht crashen — andere Skills weiter laden
                Logger.brainApp.error("Skill bundle load failed: \(url.lastPathComponent): \(error)")
            }
        }
    }
}
```

### Aufruf beim App-Start

**Datei:** `Sources/BrainApp/BrainApp.swift` (oder wo die App initialisiert wird)

Im `init()` oder `.onAppear` des Root-Views:

```swift
SkillBundleLoader.loadBundledSkills(lifecycle: skillLifecycle)
```

### Neue Methode auf SkillLifecycle

`installFromSource()` muss ohne `SkillDefinition` funktionieren — die gebundleten
Skills haben nur Markdown + Frontmatter, keine kompilierte JSON-Definition.
Die Definition wird erst generiert wenn der Skill tatsaechlich ausgefuehrt wird
(vom LLM kompiliert oder — fuer `capability: app` Skills — deterministisch geparsed).

```swift
// In SkillLifecycle:
public func installFromSource(
    source: BrainSkillSource,
    createdBy: SkillCreator = .user
) throws -> Skill {
    var skill = Skill(
        id: source.id,
        name: source.name,
        version: source.version,
        // ... weitere Felder aus source
    )
    skill.sourceMarkdown = source.markdownBody
    skill.capability = source.capability?.rawValue
    return try service.install(skill)
}
```

### Achtung: Skill-Model erweitern

Das `Skill`-Model in `Sources/BrainCore/Models/Skill.swift` braucht eventuell
ein neues Feld `capability` (TEXT in SQLite). Pruefen ob das Feld bereits existiert
oder ob eine Migration noetig ist.

---

## Schritt 4: SkillManagerView anpassen

Die SkillManagerView sollte die neuen Felder anzeigen:

### Capability-Badge
```swift
// In SkillRow:
HStack {
    Text(skill.name)
    Spacer()
    // Capability-Badge
    switch skill.capability {
    case "app":    Badge("App").tint(.blue)
    case "brain":  Badge("KI").tint(.purple)
    case "hybrid": Badge("Hybrid").tint(.orange)
    default: EmptyView()
    }
}
```

### LLM-Hinweis
Wenn `llmRequired == true` und kein LLM verfuegbar: Skill als "eingeschraenkt" markieren.
Wenn `llmFallback == "on-device"`: Hinweis "Funktioniert offline mit reduzierter Qualitaet".

---

## Zusammenfassung der Aenderungen

| Datei | Aenderung |
|-------|-----------|
| `SkillCompiler.swift` | `BrainSkillSource` + neue Felder, Parser verschachteltes YAML |
| `SkillCompilerTests.swift` | Tests fuer neue Felder |
| `Skill.swift` | `capability` Feld (optional) |
| `Schema.swift` | Migration: `capability TEXT` Spalte auf `skills`-Tabelle |
| `SkillLifecycle.swift` | `installFromSource()` Methode |
| `SkillBundleLoader.swift` | **NEU** — Bundled Skills beim Start laden |
| `BrainApp.swift` (o.ae.) | `SkillBundleLoader.loadBundledSkills()` Aufruf |
| `SkillManagerView.swift` | Capability-Badge, LLM-Hinweis |
| `project.pbxproj` | 16 `.brainskill.md` als Bundle Resources, neue Swift-Datei |

### Gate-Kriterien

- [ ] App startet → 16 Skills in SkillManagerView sichtbar
- [ ] Jeder Skill zeigt Capability-Badge (App/KI/Hybrid)
- [ ] Brain-Skills zeigen LLM-Hinweis
- [ ] Zweiter Start: Skills werden nicht doppelt installiert (Version-Check)
- [ ] Neuer Skill hinzufuegen (Datei in Skills/) → erscheint nach Rebuild
- [ ] Alle bestehenden Tests gruen + neue Parser-Tests
