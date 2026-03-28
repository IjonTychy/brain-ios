---
name: xcode-cloud-deploy
description: Xcode Cloud Deployment und TestFlight fuer brain-ios. Nutze diesen Skill bei Build-Fehlern, Deployment-Fragen oder wenn ein neuer TestFlight-Build gemacht werden soll.
allowed-tools: Bash(git *), Read, Glob, Grep
argument-hint: [rebuild|status|fix]
---

# Xcode Cloud Deploy — brain-ios

## Projekt-Setup

| Feld | Wert |
|------|------|
| Bundle ID | `com.example.brain-ios` |
| Team ID | `TEAM_ID_HERE` |
| Scheme | `BrainApp` |
| Branch | `master` |
| Min iOS | 17.0 |
| Geraete | iPhone + iPad |

## Deployment ausloesen

Ein `git push origin master` triggert automatisch einen Xcode Cloud Build.
Der Build archiviert, signiert und laedt zu TestFlight hoch.

```bash
# Build-Nummer erhoehen vor Push:
# In BrainApp.xcodeproj/project.pbxproj: CURRENT_PROJECT_VERSION erhoehen
git add -A && git commit -m "..." && git push origin master
```

## Build-Status pruefen

Xcode Cloud Builds sind unter App Store Connect einsehbar:
https://appstoreconnect.apple.com → Brain → Xcode Cloud → Builds

## Bekannte Fehler und Loesungen

### Exit Code 65 — Kompilierungsfehler
- Artifacts → Logs → `xcodebuild-archive.log` herunterladen
- Nach `error:` suchen fuer die eigentlichen Fehlermeldungen
- Xcode Cloud kompiliert STRENGER als `swift test` auf Linux/VPS!

### Swift 6 Strict Concurrency (haeufigster Fehler!)
- **`static var` in AppIntent**: Muss `static let` sein
  - Betrifft: `title`, `description`, `openAppWhenRun` in AppIntent Structs
  - Fehler: "static property is not concurrency-safe because it is nonisolated global shared mutable state"
- **`[String: Any]` in Sendable Struct**: `@unchecked Sendable` verwenden
  - Fehler: "stored property of Sendable-conforming struct contains non-Sendable type"
- **Closure in AsyncThrowingStream**: `Task { @Sendable in ... }` und Parameter `@Sendable` markieren
  - Fehler: "Passing closure as a 'sending' parameter risks causing data races"
- **AVFoundation Captures**: `nonisolated(unsafe) let` fuer AVAudioEngine, SFSpeechAudioBufferRecognitionRequest
  - Fehler: "Capture of non-Sendable type in a '@Sendable' closure"
- **Missing `await`**: GRDB `pool.read` ist async in Xcode-Kontext
  - Fehler: "expression is 'async' but is not marked with 'await'"
- **`.accent` ist kein ShapeStyle-Member**: `Color.accentColor` statt `.accent` verwenden
  - Fehler: "Type 'ShapeStyle' has no member 'accent'"
- **`[weak self]` in Task mit @MainActor**: `Task { @MainActor [weak self] in }` funktioniert nicht mit Swift 6
  - Fehler: "sending 'self' risks causing data races"
  - Loesung: `[weak self]` entfernen, Klasse selbst `@MainActor` machen
- **Captured var in async Closure mutiert**: Variable wird in GRDB `pool.write` etc. mutiert
  - Fehler: "mutation of captured var in concurrently-executing code"
  - Loesung: By-value capturen `[assistantMsg]`, lokale Kopie mutieren

### Extension-Target Fehler
- **`import GRDB` fehlt**: Widgets/Extensions die GRDB-Types nutzen (z.B. `Row`) brauchen explizites `import GRDB`
- **Property-Name-Kollision**: `@State private var body` kollidiert mit `var body: some View` → umbenennen!
- **Unused `[weak self]`**: Wenn self nicht im Closure genutzt wird → `[weak self]` entfernen
  - Fehler: "Variable 'self' was written to, but never read"

### `#if canImport(FoundationModels)` richtig verwenden
- Das `import` Statement muss AUSSERHALB der Funktion stehen:
  ```swift
  #if canImport(FoundationModels)
  import FoundationModels
  #endif
  ```
- Methoden die FoundationModels-Types nutzen muessen KOMPLETT in `#if canImport` eingewickelt sein
- NICHT nur den Body, sondern die ganze Methode einwickeln
- `LanguageModelSession()` Init wirft nicht — kein do/catch noetig

### pbxproj — Dateien werden nicht kompiliert (KRITISCH!)

**Symptom:** "Cannot find 'TypeName' in scope" obwohl die Datei existiert.

Eine Datei braucht DREI Eintraege im pbxproj um kompiliert zu werden:

1. **PBXFileReference** — Datei existiert im Projekt
   ```
   B1020019 /* OpenAIProvider.swift */ = {isa = PBXFileReference; ...};
   ```
2. **PBXBuildFile** — Verknuepfung FileReference → Build-Phase
   ```
   B1010019 /* OpenAIProvider.swift in Sources */ = {isa = PBXBuildFile; fileRef = B1020019; };
   ```
3. **PBXSourcesBuildPhase** — Datei in der Compile-Liste des Targets
   ```
   B1010019 /* OpenAIProvider.swift in Sources */,
   ```

**Wenn EINES davon fehlt, wird die Datei STILL ignoriert!** Xcode zeigt keinen Fehler —
die Datei erscheint im Projekt, wird aber nie kompiliert. Alle Typen darin sind dann
"not in scope" in allen anderen Dateien.

**Checkliste bei "Cannot find in scope":**
```bash
# Pruefe ob alle 3 Eintraege existieren:
grep "MyFile.swift" BrainApp.xcodeproj/project.pbxproj

# Erwartetes Ergebnis (3 Zeilen):
# XXXX /* MyFile.swift */ = {isa = PBXFileReference; ...}   ← FileReference
# YYYY /* MyFile.swift in Sources */ = {isa = PBXBuildFile; fileRef = XXXX; }  ← BuildFile
# YYYY /* MyFile.swift in Sources */,                        ← In BuildPhase
```

**Haeufige Fallen:**
- Datei in PBXGroup + PBXFileReference, aber KEIN PBXBuildFile → wird nicht kompiliert
- Datei hat PBXBuildFile, ist aber nicht in PBXSourcesBuildPhase → wird nicht kompiliert
- Datei in Unterordner (z.B. Onboarding/) aber PBXGroup hat falschen `path` → Xcode findet Datei nicht

### Unterordner im pbxproj (Onboarding/, LLMProviders/, Bridges/)

Dateien in Unterordnern brauchen eine eigene **PBXGroup** mit `path`:
```
OB030001 /* Onboarding */ = {
    isa = PBXGroup;
    children = (
        2E2ECF4C /* OnboardingStaticPages.swift */,
    );
    path = Onboarding;    ← Xcode sucht in Sources/BrainApp/Onboarding/
    sourceTree = "<group>";
};
```

Wenn die Dateien stattdessen direkt in der BrainApp-Gruppe liegen (ohne eigene
Untergruppe mit `path`), sucht Xcode in `Sources/BrainApp/` und findet sie nicht.

### Exit Code 70 (Export fehlgeschlagen)
- **Paid Apps Agreement** in App Store Connect → Business pruefen
- Status muss **"Active"** sein, nicht "New"
- Kann bis zu 30–60 Min dauern bis Agreement propagiert
- Alle Felder muessen ausgefuellt sein (auch fuer Privatpersonen)
- Auch pruefen: developer.apple.com/account → Agreements

### Exit Code 75 — Timeout (30 Min kein Output)

Build hat 30 Min kein Output produziert. Zwei Hauptursachen:

**Ursache 1: `some View` mit komplexen `@ViewBuilder` Switches**
- Exponentieller Type-Checker-Aufwand bei verschachtelten `if/else`/`switch` in `@ViewBuilder`
- **Compile-Zeit: 31 Min → unter 2 Min** nach Fix!
- **Loesung: AnyView Type Erasure**
  ```swift
  // FALSCH — exponentieller Type-Check:
  @ViewBuilder
  func render(_ node: ScreenNode) -> some View {
      switch node.type {
      case "text": Text(node.value)
      case "stack": VStack { ... }
      // 20+ cases → Compiler explodiert
      }
  }

  // RICHTIG — linearer Type-Check:
  func render(_ node: ScreenNode) -> AnyView {
      switch node.type {
      case "text": return AnyView(Text(node.value))
      case "stack": return AnyView(VStack { ... })
      }
  }
  ```
- Kein Performance-Nachteil zur Laufzeit (AnyView-Overhead ist vernachlaessigbar)
- `@ViewBuilder` entfernen, stattdessen `return AnyView(...)`

**Ursache 2: ci_post_clone.sh ruft resolve auf**
- `xcodebuild -resolvePackageDependencies` in ci_post_clone.sh kann Timeout verursachen
- Xcode Cloud resolved selbst — das Script soll das NICHT nochmal machen

### `List(selection:content:)` nicht auf iOS verfuegbar

```swift
// FALSCH — macOS-only API:
List(items, selection: $selected) { item in ... }

// RICHTIG — iOS-kompatibel:
List { ForEach(items) { item in ... } }
```

### "The archive contains nothing that can be signed"
- `XCLocalSwiftPackageReference` fehlt in project.pbxproj
- Muss auf `relativePath = .` zeigen (lokales Package.swift)
- Symptom: Build dauert nur 3-5 Sek, kein Code wird kompiliert

### "Could not resolve package dependencies" / "a resolved file is required"
- **Package.resolved MUSS committed sein** unter:
  `BrainApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- **NIEMALS in .gitignore packen!** Xcode Cloud deaktiviert automatische Resolution
  (`CLONED_SOURCE_PACKAGES_PATH` gesetzt) und verlangt die Datei zwingend
- Auch `xcodebuild -resolvePackageDependencies` in ci_post_clone.sh kann das NICHT umgehen
- ci_post_clone.sh mit resolve als Sicherheitsnetz behalten, aber nie als Ersatz fuer committed Package.resolved
- **Wenn Package.resolved auf VPS nicht generierbar** (z.B. wegen Swift-Version-Mismatch):
  Die Datei manuell von einem erfolgreichen Xcode Cloud Build herunterladen und committen

### "Container file path is invalid"
- Workflow wurde aus Package.swift statt BrainApp.xcodeproj erstellt
- Loesung: Projekt ueber .xcodeproj oeffnen, Workflow neu erstellen

### "Create Workflow" ausgegraut
- GitHub-Account in Xcode → Settings → Source Control hinzufuegen
- Projekt ueber .xcodeproj oeffnen (nicht Package.swift)
- Signing muss funktionieren (Geraet registriert, Team gesetzt)

### SWIFT_TREAT_WARNINGS_AS_ERRORS — Versteckte Fehler

`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` in Release-Config bedeutet: Jede Warning wird
zum Error. Xcode Cloud baut in Release-Mode.

**Problem:** Wenn eine Datei (z.B. OpenAIProvider.swift) eine Warning-turned-Error hat,
zeigt Xcode manchmal NUR die Folge-Fehler ("Cannot find 'OpenAIProvider' in scope")
statt den eigentlichen Fehler in der Quelldatei.

**Diagnose:** Wenn "Cannot find X in scope" erscheint, aber die Datei korrekt registriert
ist (alle 3 pbxproj-Eintraege vorhanden), dann hat die Datei vermutlich einen internen
Kompilierfehler (oft eine Sendable-Warning).

## Extension-Targets in pbxproj (Share Extension, Widgets)

### Struktur pro Extension-Target
Jedes Extension-Target braucht diese Sektionen in project.pbxproj:
- `PBXNativeTarget` (product type: `com.apple.product-type.app-extension`)
- `PBXBuildFile` fuer jede Source-Datei
- `PBXFileReference` fuer jede Source-Datei
- `PBXGroup` fuer den Ordner
- `PBXSourcesBuildPhase` mit allen Source-Files
- `PBXFrameworksBuildPhase` mit BrainCore
- `XCBuildConfiguration` (Debug + Release)
- `XCConfigurationList`
- `PBXContainerItemProxy` (Dependency auf Main-App)
- `PBXTargetDependency`
- `PBXCopyFilesBuildPhase` ("Embed Foundation Extensions")

### Wichtige Build-Settings fuer Extensions
```
SKIP_INSTALL = YES
INFOPLIST_FILE = "" (generiert via GENERATE_INFOPLIST_FILE)
CODE_SIGN_STYLE = Automatic
PRODUCT_BUNDLE_IDENTIFIER = com.example.brain-ios.[extension-name]
SWIFT_EMIT_LOC_STRINGS = YES
GENERATE_INFOPLIST_FILE = YES
```

### SharedContainer fuer App Group DB
- Alle Targets die DB-Zugriff brauchen muessen `SharedContainer.swift` kompilieren
- App Group ID: `group.com.example.brain-ios`
- SharedContainer.swift in PBXBuildFile jedes Targets eintragen

## Kritische Dateien

```
BrainApp.xcodeproj/project.pbxproj          ← Projekt-Config, Signing, Build-Nummer
BrainApp.xcodeproj/project.xcworkspace/
  xcshareddata/swiftpm/Package.resolved      ← SPM Lock-File (MUSS committed sein, NICHT in .gitignore!)
BrainApp.xcodeproj/xcshareddata/
  xcschemes/BrainApp.xcscheme                ← Shared Scheme
ci_scripts/ci_post_clone.sh                  ← Post-Clone Hook (Sicherheitsnetz, nicht Ersatz fuer Package.resolved)
```

## Voraussetzungen-Checkliste

- [ ] Apple Developer Program aktiv ($99/Jahr)
- [ ] App ID `com.example.brain-ios` registriert (developer.apple.com → Identifiers)
- [ ] Geraet UDID registriert (developer.apple.com → Devices)
- [ ] App in App Store Connect angelegt (Name: Brain, SKU: brain-ios)
- [ ] Paid Apps Agreement akzeptiert (App Store Connect → Business)
- [ ] GitHub in Xcode Source Control verbunden
- [ ] Package.resolved committed (NICHT in .gitignore!)
- [ ] ci_post_clone.sh vorhanden und executable (Sicherheitsnetz)

## Wenn $ARGUMENTS "rebuild" ist

Erhoehe die Build-Nummer in project.pbxproj, committe und pushe.

## Wenn $ARGUMENTS "status" ist

Weise den User auf App Store Connect → Brain → Xcode Cloud → Builds hin.

## Wenn $ARGUMENTS "fix" ist

Lies die Build-Logs und vergleiche mit den bekannten Fehlern oben.

Pruefungsreihenfolge:
1. **pbxproj-Eintraege:** Fehlen PBXBuildFile-Eintraege fuer neue Dateien?
2. **PBXSourcesBuildPhase:** Sind alle PBXBuildFiles in der Build-Phase gelistet?
3. **Unterordner-Gruppen:** Haben Dateien in Unterordnern eine PBXGroup mit korrektem `path`?
4. **Package.resolved:** Committed und aktuell?
5. **Signing-Config:** Automatic, Team ID gesetzt?
6. **Agreements:** Paid Apps Agreement aktiv?
