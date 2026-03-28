---
name: build-check
description: SPM Build-Check fuer brain-ios. Prueft ob BrainCore kompiliert, listet Warnungen und Fehler strukturiert auf. Nutze diesen Skill nach Code-Aenderungen um Build-Probleme frueh zu erkennen.
allowed-tools: Bash(swift *), Bash(git *), Read, Grep, Glob
argument-hint: [quick|full|errors]
---

# Build-Check — brain-ios

Prueft ob das Projekt kompiliert und listet Probleme strukturiert auf.

## Umgebungserkennung

Pruefe zuerst ob Swift verfuegbar ist:

```bash
swift --version 2>/dev/null
```

- **Swift verfuegbar (VPS/Mac):** Fuehre `swift build` aus
- **Swift NICHT verfuegbar (Windows):** Fuehre statische Analyse durch (Grep-basiert)

## Bei Swift-Verfuegbarkeit

### Quick Check (Default oder $ARGUMENTS = "quick")

```bash
swift build 2>&1
```

Analysiere den Output:
- Zähle Errors und Warnings
- Gruppiere nach Datei
- Zeige die 5 wichtigsten Fehler mit Kontext

### Full Check ($ARGUMENTS = "full")

```bash
swift build 2>&1
swift test --list-tests 2>&1
```

Zusaetzlich:
- Pruefe ob alle Swift-Dateien in Sources/ auch im pbxproj referenziert sind
- Pruefe ob Package.resolved aktuell ist

### Errors Only ($ARGUMENTS = "errors")

```bash
swift build 2>&1 | grep -E "error:|fatal:"
```

## Ohne Swift (statische Analyse)

Wenn Swift nicht verfuegbar ist, fuehre folgende Checks durch:

### 1. Import-Konsistenz
```bash
# Pruefe ob importierte Module existieren
grep -rn "^import " Sources/ | sort -u
```

### 2. pbxproj-Vollstaendigkeit
```bash
# Finde Swift-Dateien die NICHT im pbxproj sind
for f in $(find Sources -name "*.swift" -not -path "*/.*"); do
  basename=$(basename "$f")
  if ! grep -q "$basename" BrainApp.xcodeproj/project.pbxproj; then
    echo "FEHLT IM PBXPROJ: $f"
  fi
done
```

### 3. Bekannte Probleme pruefen
- `static var` statt `static let` in AppIntent Structs
- `[String: Any]` ohne `@unchecked Sendable`
- Fehlende `await` auf `pool.read`/`pool.write`
- `#if canImport` korrekt verwendet

## Output-Format

```
## Build-Check Ergebnis

**Status:** OK / FEHLER / WARNUNG
**Umgebung:** Swift X.Y / Statische Analyse (kein Swift)

### Fehler (N)
- [Datei:Zeile] Beschreibung

### Warnungen (N)
- [Datei:Zeile] Beschreibung

### pbxproj-Check
- N Dateien korrekt registriert
- N Dateien FEHLEN (Liste)

### Empfehlung
- Naechste Schritte
```
