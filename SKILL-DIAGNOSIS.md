# Skill-System Diagnose — brain-ios

**Datum:** 2026-03-25
**Branch:** `claude/fix-skillviewmodel-context-LkYEV`
**Getestet auf:** iPhone 16 Simulator (iOS 18.4), MacVM xc2d8

---

## Zusammenfassung

Das Skill-System hat **zwei Hauptprobleme**:
1. **Dashboard-Skill fehlt komplett** — Installation scheitert an Validierungsfehler
2. **Inkonsistenz zwischen Renderer und Validator** — Renderer akzeptiert `text`, Validator verlangt `value` für `badge`

Die anderen 8 Skills in der DB sind korrekt installiert und haben valides JSON.

---

## Bug 1: Dashboard kann nicht installiert werden (KRITISCH)

**Status:** ✅ Gefixt (Commit 7ddbddf)

**Symptom:** Dashboard-Tab zeigt Fallback-UI (`BootstrapSkills.dashboard`) direkt aus dem Code, wird nie in die DB geschrieben.

**Log:**
```
📦 [BOOTSTRAP] dashboard: NOT in DB, installing...
❌ [BOOTSTRAP] dashboard: install FAILED: validationFailed(["Screen 'main': 'badge' requires property 'value'"])
```

**Ursache:** In `BootstrapSkills.swift` Zeile 100-102:
```swift
ScreenNode(type: "badge", properties: [
    "text": .string("{{bday.label}}"),  // ← BUG: heisst "text"
])
```
`ComponentRegistry` definiert `badge` mit `requiredProperties: ["value"]`.

**Auswirkung:** 
- Dashboard existiert nie in der DB → kann nie vom User oder Brain angepasst werden
- `ensureBootstrapSkillsInDB` versucht bei jedem App-Start erneut zu installieren (Perf-Hit)
- Der `try?` in BrainApp.swift Zeile 491-494 schluckt den Fehler still

**Fix:** In `BootstrapSkills.swift` Zeile 101 `"text"` → `"value"` ändern:
```swift
ScreenNode(type: "badge", properties: [
    "value": .string("{{bday.label}}"),
])
```

---

## Bug 2: Stille Fehlerunterdrückung in ensureBootstrapSkillsInDB (MITTEL)

**Status:** ✅ Gefixt (Commit 7ddbddf)

**Datei:** `Sources/BrainApp/BrainApp.swift` Zeile 490-494

**Problem:** `try?` verschluckt Installationsfehler komplett:
```swift
_ = try? lifecycle.installFromDefinition(
    source: source,
    definition: definition,
    createdBy: .system
)
```

**Fix:** Mindestens loggen:
```swift
do {
    _ = try lifecycle.installFromDefinition(...)
} catch {
    Logger(subsystem: "com.example.brain-ios", category: "Bootstrap")
        .error("Skill '\(id)' install failed: \(error)")
}
```

---

## Bug 3: Inkonsistenz badge — Validator vs. Renderer (MITTEL)

**Status:** ✅ Gefixt (Commit 7ddbddf)

**Problem:** 
- `ComponentRegistry` definiert `badge` mit `requiredProperties: ["value"]`
- `renderBadge()` in `SkillRendererContent.swift` Zeile 102 akzeptiert **beides**: `resolveString(node, "value") ?? resolveString(node, "text")`
- Die .brainskill.md Skills (z.B. `brain-handwriting-notes`) verwenden `"text"` und funktionieren, weil sie **ohne Validierung** installiert werden (via `SkillBundleLoader` → `installFromSource`)

**Auswirkung:** Skills die über `installFromDefinition` (mit Validierung) gehen, scheitern an `text` statt `value`. Skills über `installFromSource` (Markdown-Loader) umgehen die Validierung komplett.

**Fix-Optionen:**
1. `ComponentRegistry`: `badge` bekommt `optionalProperties: ["text"]` zusätzlich
2. Oder: Alle Skills konsistent auf `"value"` umstellen (Breaking Change für bestehende .brainskill.md)
3. Empfehlung: Option 1 + den Renderer weiterhin tolerant lassen

---

## Bug 4: badge in brain-handwriting-notes verwendet "text" statt "value" (NIEDRIG)

**Status:** 🟡 Offen

**Datei:** `Skills/brain-handwriting-notes.brainskill.md` (screens_json)

**Problem:** Badge-Node verwendet `"text": "Scan"` statt `"value": "Scan"`. Funktioniert zufällig, weil der Renderer tolerant ist und weil SkillBundleLoader nicht validiert.

**Fix:** Im screens_json des Skills `"text"` → `"value"` ändern.

---

## Bug 5: Sprach-Skills haben leere Screens (INFO)

**Status:** ✅ Gefixt (Commit 7ddbddf) — aus Skill-Liste gefiltert

**Beobachtung:**
```
brain-language-de: screens="{}", enabled=1
brain-language-en: screens="{}", enabled=1  
```

Diese Skills erscheinen in der Skill-Liste als "enabled" mit leeren Screens. Wenn ein User sie anklickt, sieht er "Skill hat keine UI". Das ist korrekt (sie sind Label-Provider), aber verwirrend.

**Vorschlag:** Sprach-Skills aus der `loadActiveSkills()`-Liste in MoreTabView filtern, oder `enabled=false` setzen.

---

## Bug 6: card-Komponente mit Properties statt Children (NIEDRIG)

**Status:** ✅ Gefixt (Commit 7ddbddf)

**Beobachtung:** In `BootstrapSkills.swift` wird `card` mit Properties wie `icon`, `title`, `subtitle`, `detail` verwendet (Zeile 65-69):
```swift
ScreenNode(type: "card", properties: [
    "icon": .string("calendar"),
    "title": .string("{{event.title}}"),
    "subtitle": .string("{{event.time}}"),
    "detail": .string("{{event.location}}"),
])
```

Aber `renderCard()` in `SkillRendererContainer.swift` rendert nur Children, nicht Properties. Die Properties `icon`, `title`, `subtitle`, `detail` werden komplett ignoriert.

**Auswirkung:** Kalender-Events im Dashboard werden als leere Cards ohne Inhalt angezeigt.

**Fix:** Entweder `renderCard()` erweitern um Properties zu unterstützen, oder die BootstrapSkills umbauen um Children statt Properties zu verwenden.

---

## DB-Inventar (Simulator)

| Skill ID | Name | Screens | Actions | Source |
|---|---|---|---|---|
| dashboard | Dashboard | ❌ NICHT IN DB | - | Bootstrap (Validierung schlägt fehl) |
| mail-inbox | Mail Inbox | ✅ 911 chars | ❌ keine | Bootstrap |
| calendar | Kalender | ✅ 1009 chars | ❌ keine | Bootstrap |
| mail-config | Mail Konfiguration | ✅ 1868 chars | ✅ 788 chars | Bootstrap |
| quick-capture | Schnellerfassung | ✅ 253 chars | ✅ 153 chars | Bootstrap |
| brain-business-card | Visitenkarten-Scanner | ✅ 2628 chars | ✅ 1376 chars | .brainskill.md |
| brain-handwriting-font | Handschrift-Font | ✅ 2905 chars | ✅ 1675 chars | .brainskill.md |
| brain-handwriting-notes | Handschrift-Notizen | ✅ 2238 chars | ✅ 710 chars | .brainskill.md |
| brain-language-de | Deutsch | ❌ leer ({}) | ❌ keine | .brainskill.md |
| brain-language-en | English | ❌ leer ({}) | ❌ keine | .brainskill.md |

---

## Validierungs-Ergebnisse (alle Skills gegen ComponentRegistry)

| Skill | Ergebnis |
|---|---|
| brain-business-card | ✅ Valide |
| brain-handwriting-font | ✅ Valide |
| brain-handwriting-notes | ⚠️ badge missing 'value' (nutzt 'text') |
| mail-inbox | ✅ Valide |
| calendar | ✅ Valide |
| mail-config | ✅ Valide |
| quick-capture | ✅ Valide |
| dashboard (BootstrapSkills) | ❌ badge missing 'value' |

---

## Architektur-Beobachtungen

1. **Zwei Installationswege, unterschiedliche Validierung:**
   - `installFromDefinition` → Validierung via ComponentRegistry → streng
   - `installFromSource` (SkillBundleLoader) → Keine Validierung → alles geht durch
   - Das ist inkonsistent und führt zu subtilen Bugs

2. **Dashboard-Fallback funktioniert:** ContentView Zeile 359-363 fällt auf `BootstrapSkills.dashboard` zurück wenn kein DB-Eintrag da ist. Das Dashboard wird also gerendert — aber nie in der DB gespeichert.

3. **mail-inbox und calendar haben keine Actions:** Diese Bootstrap-Skills definieren Actions in `BootstrapSkills.swift`, aber da sie schon in der DB sind (von einem früheren Build ohne Actions), werden die Actions nie aktualisiert. Der `ensureBootstrapSkillsInDB`-Code aktualisiert zwar screens/actions für `createdBy == .system`, aber nur die screens werden encoded — actions nur wenn `definition.actions` nicht nil ist. Lass mich das nochmal prüfen...

   **Update:** mail-inbox und calendar haben `actions: nil` in `BootstrapSkills.swift` (nur screens). Das ist korrekt — sie haben keine eigenen Actions.

---

## Empfohlene Fix-Reihenfolge

1. **Bug 1** (Dashboard badge): Einzeiler-Fix, höchste Priorität
2. **Bug 6** (card Properties): Dashboard zeigt leere Kalender-Cards
3. **Bug 2** (Stille Fehler): Verhindert künftige unsichtbare Bugs
4. **Bug 3** (Validator-Inkonsistenz): badge auch "text" als optionalProperty erlauben
5. **Bug 4** (handwriting-notes badge): Kosmetisch, funktioniert durch Renderer-Toleranz
6. **Bug 5** (Sprach-Skills): UX-Verbesserung, niedrige Prio
