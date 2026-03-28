---
id: xcode-cloud-lessons-learned
name: Xcode Cloud & TestFlight — Lessons Learned
description: Erkenntnisse aus der ersten Veroeffentlichung von brain-ios via Xcode Cloud und TestFlight
version: 3.0
created_by: user
approved_by: user
category: dokumentation
tags: [devops, xcode-cloud, testflight, deployment]
triggers:
  - type: manual
---

# Xcode Cloud & TestFlight — Lessons Learned

Erkenntnisse aus der Erstveroeffentlichung von brain-ios (19.03.2026 – 24.03.2026).
190+ Builds, dutzende verschiedene Fehler, alle geloest.

## Kernaussage

Xcode Cloud ersetzt den XcodeClub-Mac fuer CI/CD komplett. Kein SSH-Tunnel,
kein Keychain-Entsperren, kein manuelles Archivieren. Einmal eingerichtet,
baut und deployt es bei jedem `git push origin master` automatisch.

## Voraussetzungen (muessen VOR dem ersten Build erledigt sein)

### 1. Apple Developer Program ($99/Jahr)
- Ohne bezahlte Mitgliedschaft kein TestFlight, kein App Store
- Status pruefen: https://developer.apple.com/account → Membership

### 2. Agreements in App Store Connect
- **Business → Paid Apps Agreement** muss Status **"Active"** haben
- Ohne dieses Agreement schlaegt JEDER Export fehl (Exit Code 70)
- Auch fuer kostenlose Apps und TestFlight-Builds erforderlich
- Als Privatperson: Keine Bankdaten noetig, nur Akzeptieren
- Kann bis zu 30 Minuten dauern bis das Agreement aktiv wird

### 3. App ID registrieren
- https://developer.apple.com/account → Identifiers → +
- Bundle ID: `com.example.brain-ios` (Explicit, nicht Wildcard)
- Muss VOR dem ersten Build existieren

### 4. Geraet registrieren (UDID)
- Fuer Development Signing braucht Xcode mindestens ein registriertes Geraet
- UDID findet man NICHT unter Einstellungen → Info (dort steht nur IMEI)
- Bester Weg: iPhone an Mac → Finder → auf Seriennummer klicken bis UDID erscheint
- Oder: https://udid.io auf dem iPhone oeffnen

### 5. App in App Store Connect anlegen
- Apps → + → New App
- Platform: iOS, Name: Brain, Bundle ID: com.example.brain-ios, SKU: brain-ios

## Xcode Cloud Workflow einrichten

### GitHub-Account in Xcode verbinden
- Xcode → Settings → **Source Control** → GitHub hinzufuegen
- WICHTIG: Nicht nur unter "Apple Accounts", sondern unter "Source Control"!
- Ohne GitHub-Verbindung bleibt "Create Workflow" ausgegraut

### Projekt korrekt oeffnen
- Das Projekt MUSS ueber **BrainApp.xcodeproj** geoeffnet werden
- NICHT ueber Package.swift (sonst erkennt Xcode nur das SPM Package)
- Bei "Container file path is invalid": Falsches Projekt-Format geoeffnet
- Am besten: Integrate → Clone in Xcode, dann .xcodeproj oeffnen

### Workflow erstellen
- Integrate → Xcode Cloud → Create Workflow
- Start Condition: Custom Branches → `master`
- Action: Archive → iOS → Scheme `BrainApp`
- Unnoetige Plattformen (macOS, tvOS, watchOS) loeschen
- Post-Actions: TestFlight Internal Testing (erst nach erstem erfolgreichen Build verfuegbar)

### Grant Access to Source Code
- Xcode Cloud braucht Zugriff auf DEIN Repo (IjonTychy/brain-ios)
- Fuer oeffentliche Dependencies (z.B. groue/GRDB.swift) ist KEIN Grant noetig

## Haeufige Fehler und Loesungen

### Exit Code 65 — Kompilierungsfehler
- **Ursache:** Swift-Code kompiliert nicht auf Xcode Cloud
- **Typische Probleme:**
  - `import UIKit` fehlt (UIKit wird NICHT automatisch importiert wie in Xcode lokal)
  - `DateFormatters` oder andere Types aus BrainCore nicht `public`
  - iOS API-Inkompatibilitaeten (z.B. `List` init deprecated in iOS 17)
- **Loesung:** Artifacts → Logs herunterladen, `error:` suchen
- **Lesson Learned:** Xcode Cloud kompiliert strenger als lokaler Build!

### Exit Code 70 — "Command exited with non-zero exit code: 70"
- **Ursache:** Paid Apps Agreement nicht aktiv, ODER Agreement noch nicht propagiert
- **Loesung:** App Store Connect → Business → Paid Apps Agreement akzeptieren
- **Falle:** Die Xcode Cloud Logs zeigen NUR "exit code 70" — keine Details!
- **Detail-Logs:** Artifacts → "Logs for BrainApp archive" herunterladen

### "The archive contains nothing that can be signed"
- **Ursache 1:** Das Xcode-Projekt hat keine Referenz auf das lokale SPM Package
  - **Loesung:** `XCLocalSwiftPackageReference` mit `relativePath = .` in project.pbxproj
- **Ursache 2:** `PBXFileSystemSynchronizedRootGroup` (objectVersion 77) wird von Xcode Cloud nicht unterstuetzt
  - **Loesung:** Projekt auf objectVersion 56 downgraden mit expliziten PBXFileReference + PBXBuildFile + PBXSourcesBuildPhase Eintraegen
  - JEDE .swift-Datei braucht einen PBXFileReference UND PBXBuildFile Eintrag
  - BrainCore braucht einen PBXBuildFile in der Frameworks Build Phase
- **Symptom:** Build dauert nur 3-5 Sekunden (kein Code wird kompiliert!)
- **Symptom:** "Signing Identity: Sign to Run Locally" statt echtem Zertifikat
- **Symptom:** `Target 'BrainApp' (no dependencies)` im Build-Log
- **Symptom:** `Didn't find executable for bundle` im Detail-Log

### "Could not resolve package dependencies" / Package.resolved fehlt
- **Ursache:** Xcode Cloud setzt `CLONED_SOURCE_PACKAGES_PATH`, was automatische Resolution DEAKTIVIERT
- **Loesung:** `Package.resolved` MUSS committed sein
- **Pfad:** `BrainApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- **CRITICAL: NIEMALS in .gitignore packen!** Auch `xcodebuild -resolvePackageDependencies` im ci_post_clone.sh kann das nicht umgehen — der Befehl scheitert mit dem gleichen Fehler
- **ci_post_clone.sh:** Nur als Sicherheitsnetz, NICHT als Ersatz fuer committed Package.resolved
- **Achtung:** Der `originHash` in Package.resolved muss zum Xcode-Projekt passen,
  nicht zum SPM-Package

### "Container file path is invalid"
- **Ursache:** Workflow wurde aus Package.swift statt BrainApp.xcodeproj erstellt
- **Loesung:** Projekt schliessen, BrainApp.xcodeproj explizit oeffnen, Workflow neu erstellen

### "errSecInternalComponent" (lokaler Mac-Build)
- **Ursache:** Keychain auf dem Mac ist gesperrt
- **Loesung:** `security unlock-keychain ~/Library/Keychains/login.keychain-db`
- **Irrelevant fuer Xcode Cloud** — betrifft nur lokale Builds

### "Create Workflow" ist ausgegraut
- **Ursache 1:** Kein GitHub-Account unter Xcode → Settings → Source Control
- **Ursache 2:** Kein Apple Developer Account in Xcode → Settings → Apple Accounts
- **Ursache 3:** Signing fehlgeschlagen (kein registriertes Geraet)
- **Ursache 4:** Projekt via Package.swift statt .xcodeproj geoeffnet

## Xcode-Projekt Konfiguration (kritisch!)

### objectVersion 56 verwenden, NICHT 77
- Xcode 16 erstellt Projekte mit objectVersion 77 und `PBXFileSystemSynchronizedRootGroup`
- Xcode Cloud (Stand Maerz 2026) kompiliert damit KEINE Source Files
- **Loesung:** Manuell auf objectVersion 56 downgraden:
  - Jede .swift-Datei als `PBXFileReference` eintragen
  - Jede .swift-Datei als `PBXBuildFile` eintragen
  - Alle PBXBuildFile-Eintraege in eine `PBXSourcesBuildPhase` packen
  - BrainCore-Dependency als PBXBuildFile in `PBXFrameworksBuildPhase`
  - Unterordner (Bridges/, LLMProviders/) als eigene `PBXGroup` Eintraege

### Neue Dateien hinzufuegen — Die 3-Eintraege-Regel
Bei jeder neuen .swift-Datei muessen DREI Eintraege in project.pbxproj existieren:

1. **PBXFileReference** — Datei existiert im Projekt
2. **PBXBuildFile** — Verknuepft FileReference mit Build-Phase
3. **PBXSourcesBuildPhase** — Datei in der Compile-Liste des Targets

**Wenn EINES davon fehlt, wird die Datei STILL ignoriert!** Xcode zeigt keinen Fehler.
Die Datei erscheint im Projekt-Navigator, wird aber nie kompiliert. Alle Typen darin
sind dann "not in scope" in allen anderen Dateien.

Pruef-Befehl:
```bash
grep "MyFile.swift" BrainApp.xcodeproj/project.pbxproj
# Erwartet: 3 Zeilen (FileReference, BuildFile, BuildPhase-Eintrag)
```

### Unterordner brauchen eigene PBXGroup mit path
Dateien in Unterordnern (z.B. `Onboarding/`, `LLMProviders/`, `Bridges/`) brauchen
eine eigene PBXGroup mit `path = Onboarding`. Ohne das sucht Xcode die Dateien im
falschen Verzeichnis. Die PBXFileReference innerhalb der Gruppe hat dann nur den
Dateinamen als `path` (nicht den vollen Pfad).

## Projektstruktur fuer Xcode Cloud

```
brain-ios/
├── BrainApp.xcodeproj/          ← Xcode Cloud baut hiervon (objectVersion 56!)
│   ├── project.pbxproj          ← Explizite File References fuer JEDE .swift Datei
│   ├── project.xcworkspace/
│   │   └── xcshareddata/
│   │       └── swiftpm/
│   │           └── Package.resolved  ← MUSS committed sein
│   └── xcshareddata/
│       └── xcschemes/
│           └── BrainApp.xcscheme     ← MUSS "Shared" sein
├── Package.swift                ← SPM Package (BrainCore Library)
├── Sources/
│   ├── BrainCore/               ← Pure Swift Library (kein iOS, internal→public wo noetig)
│   └── BrainApp/                ← SwiftUI App Target (braucht import UIKit!)
│       ├── Bridges/             ← iOS Framework Bridges
│       └── LLMProviders/        ← Cloud LLM Implementierungen
├── ci_scripts/
│   └── ci_post_clone.sh         ← Loest SPM Dependencies auf
└── Skills/                      ← .brainskill.md Dateien
```

## Wichtige Erkenntnisse

### Kein Mac noetig
- Xcode Cloud baut auf Apples Servern (macOS + Xcode)
- 25 Compute-Stunden/Monat gratis
- Kein XcodeClub-Abo, kein SSH-Tunnel, kein AnyDesk
- Code kann komplett auf dem VPS entwickelt werden

### Signing wird automatisch verwaltet
- Xcode Cloud erstellt Zertifikate und Provisioning Profiles selbst
- `CODE_SIGN_STYLE = Automatic` + `DEVELOPMENT_TEAM` reichen aus
- Kein manuelles Zertifikat-Management noetig
- `CODE_SIGN_IDENTITY=-` im Build-Log ist NORMAL (Xcode Cloud signiert beim Export)

### Fehlersuche ist muehsam
- Xcode Cloud Logs im Web zeigen oft nur Exit Codes, keine Details
- Immer die **Artifacts → Logs** herunterladen fuer echte Fehlermeldungen
- `IDEDistribution.standard.log` enthaelt die Export-Fehlermeldung
- `xcodebuild-archive.log` enthaelt Kompilierungsfehler
- Lokale Builds auf einem Mac koennen hilfreich sein fuer Debugging

### Cross-Module-Zugriff beachten
- BrainCore ist ein separates SPM-Modul
- Alles was BrainApp braucht MUSS `public` sein
- `import UIKit` wird in Xcode Cloud NICHT automatisch hinzugefuegt
- Xcode Cloud kompiliert strenger als lokaler Build

### Build-Nummer erhoehen
- Bei jedem Upload muss `CURRENT_PROJECT_VERSION` erhoeht werden
- Xcode Cloud kann das automatisch (`manageAppVersionAndBuildNumber`)

### Auto-Cancel Builds
- Wenn "Auto-cancel Builds" aktiv ist, wird bei jedem neuen Push der
  laufende Build abgebrochen
- Bei schnellen Iterationen (Fix → Push → Fix → Push) werden Builds uebersprungen
- Das ist gewollt und spart Compute-Stunden

### Vision Pro kann spaeter
- `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad) reicht fuer MVP
- Vision Pro (7) kann nach erstem erfolgreichen Build hinzugefuegt werden

## Timeline (zur Referenz)

| Build | Fehler | Ursache | Fix |
|-------|--------|---------|-----|
| 1-4 | Exit Code 70 | Paid Apps Agreement "New" | Agreement akzeptieren |
| 5 | Package.resolved fehlt | Nicht committed | Package.resolved + ci_post_clone.sh |
| 6-7 | Auto-cancelled | Neue Pushes | — |
| 8 | Archive leer | PBXFileSystemSynchronizedRootGroup | objectVersion 56 + explizite Refs |
| 9 | Auto-cancelled | Neuer Push | — |
| 10 | Exit Code 65 | import UIKit fehlt, DateFormatters internal | Imports + public access |
| 11-36 | Diverse | Swift 6 Concurrency, Signing, Export Compliance | Iterative Fixes |
| 36 | Erfolg! | — | TestFlight Live! |
| 37-46 | Diverse | Phase 19-24 neue Features | Iterative Fixes |
| 47 | Exit 65 (34 Errors) | Swift 6: static var statt let, missing await, [String:Any] nicht Sendable, FoundationModels scope | var→let, @unchecked Sendable, #if canImport um Methoden |
| 48 | Exit 65 (2 Errors) | import GRDB fehlt in Widget, body Property-Kollision | import GRDB, body→notes |
| 49 | Exit 65 (1 Error) | Data race in AsyncThrowingStream closure | @Sendable closure + Task |
| 50-53 | Auto-cancelled | Mehrere Pushes | — |
| 54 | AppIntents Metadata | String-Params in Phrases, missing applicationName | Params entfernen, applicationName in jede Phrase |
| 55-56 | Package.resolved fehlt | War in .gitignore, ci_post_clone kann das NICHT kompensieren | Aus .gitignore entfernt, Package.resolved committed |
| 57+ | Diverse | Weitere Iterationen | — |
| 154 | Exit 65 (5 Errors) | List(data, id:) in verschachteltem Group: Compiler kann Generic-Parameter nicht inferieren (TableColumn) | contactListView als separate computed property extrahiert |
| 188+ | Exit 65 (29 Errors) | 8 neue Dateien: PBXBuildFile + PBXSourcesBuildPhase fehlten | Alle 3 pbxproj-Eintraege pro Datei sicherstellen |
| 189+ | Exit 65 (3 Errors) | .accent kein ShapeStyle-Member + OpenAIProvider PBXBuildFile fehlte | Color.accentColor, fehlendes PBXBuildFile ergaenzt |
| 190+ | Exit 65 (2 Errors) | OpenAIProvider.swift: PBXBuildFile-Objekt fehlte (nur FileRef + BuildPhase vorhanden) | PBXBuildFile-Zeile ergaenzt |

## Swift 6 Strict Concurrency — Die wichtigsten Patterns

### 1. AppIntent static Properties
```swift
// FALSCH — Xcode Cloud Error:
struct MyIntent: AppIntent {
    static var title: LocalizedStringResource = "..."
    static var openAppWhenRun: Bool = false
}

// RICHTIG:
struct MyIntent: AppIntent {
    static let title: LocalizedStringResource = "..."
    static let openAppWhenRun: Bool = false
}
```

### 2. Structs mit [String: Any]
```swift
// FALSCH:
struct ToolDef: Sendable {
    let schema: [String: Any]  // Any ist nicht Sendable!
}

// RICHTIG:
struct ToolDef: @unchecked Sendable {
    let schema: [String: Any]
}
```

### 3. AsyncThrowingStream + Closures
```swift
// FALSCH:
AsyncThrowingStream { continuation in
    Task {  // ← data race warning
        ...
    }
}

// RICHTIG:
AsyncThrowingStream { continuation in
    Task { @Sendable in
        ...
    }
}
```

### 4. AVFoundation in Closures
```swift
// FALSCH:
let engine = AVAudioEngine()  // nicht Sendable
someAsyncClosure { engine.stop() }  // ← capture warning

// RICHTIG:
nonisolated(unsafe) let engine = AVAudioEngine()
someAsyncClosure { engine.stop() }  // OK
```

### 5. #if canImport richtig verwenden
```swift
// FALSCH — LanguageModelSession nicht im Scope:
@available(iOS 26.0, *)
func check() -> Bool {
    #if canImport(FoundationModels)
    let s = LanguageModelSession()  // Error!
    #endif
}

// RICHTIG — Import UND Methode einwickeln:
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
@available(iOS 26.0, *)
func check() -> Bool {
    let s = LanguageModelSession()  // OK
}
#endif
```

### 6. List/ForEach in verschachteltem Group
```swift
// FALSCH — Compiler kann Generic-Parameter nicht inferieren:
Group {
    if isLoading {
        ProgressView("Laden...")
    } else {
        List(items, id: \.identifier) { item in  // ← Error: TableColumn<R, C, Content, Label>
            Text(item.name)
        }
    }
}

// RICHTIG — List in separate computed property extrahieren:
Group {
    if isLoading {
        ProgressView("Laden...")
    } else {
        itemListView  // ← Typ ist klar
    }
}

private var itemListView: some View {
    List {
        ForEach(items, id: \.identifier) { item in
            Text(item.name)
        }
    }
}
```
Hintergrund: Tief verschachtelte `Group` mit mehreren Branches (`if/else if/else`)
ueberfordert den Swift Type-Checker. `List(data, id:)` hat mehrere Overloads
(inkl. `TableColumn`-basierte fuer macOS), und der Compiler kann in der tiefen
Verschachtelung nicht disambiguieren. Extrahieren in eine eigene Property loest das.

### 7. Bundled Resources und pbxproj
- `.brainskill.md`-Dateien muessen als `PBXBuildFile` in der Resources Build Phase stehen
- Beim Entfernen: ALLE 4 Referenzen pro Datei loeschen (PBXBuildFile, PBXFileReference, PBXGroup children, Resources Build Phase)
- Am einfachsten: `grep -v 'brainskill\.md' project.pbxproj > clean.pbxproj && mv clean.pbxproj project.pbxproj`

### 8. VPS swift test vs Xcode Cloud
- `swift test` auf Linux prueft KEINE Sendable-Compliance!
- Xcode Cloud mit `-strict-concurrency=complete` findet viel mehr Fehler
- Immer davon ausgehen: was auf VPS kompiliert, kann auf Xcode Cloud failen

### 9. pbxproj: Die 3-Eintraege-Regel (KRITISCH!)
```
# Jede .swift-Datei braucht genau 3 Eintraege:

# 1. PBXFileReference (Datei existiert)
B1020019 /* OpenAIProvider.swift */ = {isa = PBXFileReference; path = OpenAIProvider.swift; ...};

# 2. PBXBuildFile (verknuepft FileRef → Build)
B1010019 /* OpenAIProvider.swift in Sources */ = {isa = PBXBuildFile; fileRef = B1020019; };

# 3. In PBXSourcesBuildPhase (wird tatsaechlich kompiliert)
B1010019 /* OpenAIProvider.swift in Sources */,
```
**Fehlt auch nur EINER dieser Eintraege, wird die Datei STILL ignoriert.**
Xcode zeigt keinen Fehler — nur nachgelagerte "Cannot find in scope"-Fehler
in anderen Dateien die den Typ referenzieren.

Typisches Muster: Datei hat PBXFileReference + PBXGroup-Eintrag (erscheint im
Projekt-Navigator), aber kein PBXBuildFile → Typ ist unsichtbar.

### 10. SWIFT_TREAT_WARNINGS_AS_ERRORS versteckt echte Fehler
Mit `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` (Release-Config) werden Warnings
zu Errors. Xcode Cloud baut in Release-Mode. Wenn eine Datei eine
Warning-turned-Error hat, zeigt Xcode manchmal NUR die Folge-Fehler
("Cannot find X in scope") statt den eigentlichen Fehler.

**Diagnose:** Wenn "Cannot find X" erscheint aber die Datei korrekt registriert
ist (alle 3 pbxproj-Eintraege vorhanden), hat die Datei vermutlich einen
internen Kompilierfehler (oft eine Sendable-Warning).

### 11. ShapeStyle: .accent existiert nicht
`.foregroundStyle(.accent)` kompiliert NICHT. Korrekt: `.foregroundStyle(Color.accentColor)`

### 12. Unterordner brauchen eigene PBXGroup
Dateien in `Sources/BrainApp/Onboarding/` brauchen eine eigene PBXGroup:
```
OB030001 /* Onboarding */ = {
    isa = PBXGroup;
    children = ( /* Dateien */ );
    path = Onboarding;      ← WICHTIG: path muss gesetzt sein
    sourceTree = "<group>";
};
```
Ohne eigene Gruppe mit `path` sucht Xcode die Dateien im Eltern-Verzeichnis.

### 13. pbxproj komplett neu generieren statt patchen
Wenn Python-Scripts den pbxproj editieren und dabei die Struktur beschaedigen
("parse error"), ist ein kompletter Rebuild sicherer als Patch-Versuche.
Pattern: Alle .swift-Dateien per `find` sammeln, dann pbxproj komplett
neu generieren mit korrekten Sections (PBXBuildFile, PBXFileReference,
PBXGroup, PBXSourcesBuildPhase). Dabei UUIDs als 24-stellige Hex-Strings
generieren (wie Xcode es macht).

**Warnung:** pbxproj-Edits via Python sind fehleranfaellig. Besser:
Xcode oder ruby xcodeproj-Gem (cocoapods/xcodeproj) nutzen.

### 14. Unicode-Escapes in Python-generierten Swift-Dateien
Python schreibt `\u00fc` statt `ue` in Swift-Strings. Swift interpretiert
`\u{00fc}` aber erwartet geschweifte Klammern (`\u{00FC}`), nicht
das Python-Format (`\u00fc`).

**Fix:** Nach jeder Python-generierten Datei pruefen:
`grep -r u00 Sources/BrainApp/` und ersetzen mit echten UTF-8 Zeichen.

### 15. .breathe SymbolEffect ist iOS 18+
`.symbolEffect(.breathe)` und die Konformitaet von `BreatheSymbolEffect`
zu `IndefiniteSymbolEffect` sind erst ab iOS 18.0 verfuegbar.
Fuer iOS 17.0 Targets: `.symbolEffect(.pulse)` verwenden.

### 16. Swift 6 Concurrency: UIKit Delegates
`CNContactViewControllerDelegate` und aehnliche UIKit-Delegate-Protokolle
erfordern in Swift 6:
```swift
nonisolated func contactViewController(_ vc: CNContactViewController,
    didCompleteWith contact: CNContact?) {
    MainActor.assumeIsolated {
        // UI-Code hier
    }
}
```
`@preconcurrency` auf Conformance hat keinen Effekt wenn das Protokoll
bereits Concurrency-Annotationen hat. `@MainActor` auf der Klasse reicht
nicht fuer nonisolated Protocol-Requirements.

### 17. Merge-Konflikte: Monolithisch vs. Split-Files
Wenn ein Branch Views in Unterordner aufteilt (z.B. OnboardingView.swift →
Onboarding/OnboardingStaticPages.swift etc.) und der andere Branch die
monolithische Datei behaelt, fuehrt ein Merge zu doppelten Deklarationen.

**Loesung:** Entweder die Split-Dateien ODER die monolithische Datei behalten,
nie beides. Bei `--ours` Merge-Strategie: pruefen ob der andere Branch
neue Dateien hinzugefuegt hat die dieselben Typen definieren.
