# Auftrag: SkillRenderer UI-Tests via Xcode Cloud

## Ziel
SkillRenderer-Tests erstellen die auf dem iOS Simulator in Xcode Cloud laufen.
Alle 90 Primitives muessen mindestens 1 Render-Test haben.

## Voraussetzung
- Build laeuft erfolgreich auf Xcode Cloud (Archive + Export gruen)
- 294 BrainCore-Tests laufen bereits (swift test auf VPS)

## Schritt 1: Test-Target im Xcode-Projekt anlegen

In BrainApp.xcodeproj ein neues Test-Target erstellen:
- Name: `BrainAppTests`
- Type: Unit Testing Bundle
- Target to Test: BrainApp
- Framework: XCTest (oder Swift Testing mit @Test macro)

## Schritt 2: SkillRenderer-Tests schreiben

Fuer jede Kategorie eine Test-Datei:

```
Tests/BrainAppTests/
  SkillRendererLayoutTests.swift      (15 Primitives)
  SkillRendererContentTests.swift     (12 Primitives)
  SkillRendererInputTests.swift       (13 Primitives)
  SkillRendererInteractionTests.swift (11 Primitives)
  SkillRendererDataTests.swift        (15 Primitives)
  SkillRendererFeedbackTests.swift    (6 Primitives)
  SkillRendererContainerTests.swift   (5 Primitives)
  SkillRendererSystemTests.swift      (6 Primitives)
  SkillRendererSpecialTests.swift     (7 Primitives)
```

### Test-Pattern pro Primitive:
```swift
@testable import BrainApp
import XCTest
import SwiftUI
import BrainCore

final class SkillRendererLayoutTests: XCTestCase {
    func testStackRenders() {
        let node = ScreenNode(
            type: "stack",
            properties: ["axis": .string("vertical")],
            children: [
                ScreenNode(type: "text", properties: ["content": .string("Hello")])
            ]
        )
        // Verify no crash during view creation
        let view = SkillRenderer(node: node)
        XCTAssertNotNil(view)
    }
}
```

### Was testen:
- Jedes Primitive rendert ohne Crash (Smoke Test)
- Fehlende required Properties → graceful Fallback (kein Crash)
- Leere children → kein Crash
- Two-Way Bindings: onSetVariable wird aufgerufen bei Input-Aenderung
- Edge Cases: leere Strings, negative Zahlen, ungueltige Farben

### Optional (ViewInspector):
Falls ViewInspector als SPM Dependency hinzugefuegt wird:
- Pruefen ob korrekte SwiftUI-Views erzeugt werden
- Text-Inhalte verifizieren
- Verschachtelte Strukturen testen

## Schritt 3: Xcode Cloud Workflow erweitern

Im bestehenden "Brain" Workflow:
1. Actions → + → **Test**
2. Platform: iOS
3. Scheme: BrainApp
4. Destination: Any iOS Simulator
5. Position: VOR der Archive-Action (Tests zuerst)

## Schritt 4: Package.resolved updaten

Falls ViewInspector hinzugefuegt wird:
- Package.resolved neu generieren
- Committen unter BrainApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/

## Qualitaetskriterien
- Mindestens 90 Tests (1 pro Primitive)
- Alle Tests gruen auf Xcode Cloud iOS Simulator
- Kein Test dauert laenger als 5 Sekunden
- Tests sind unabhaengig voneinander (keine shared state)
- Test-Failures blockieren NICHT den Archive-Build (separate Action)
