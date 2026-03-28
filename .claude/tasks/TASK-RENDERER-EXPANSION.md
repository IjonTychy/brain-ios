# Auftrag: SkillRenderer Primitive-Bibliothek erweitern

## Ziel
Die SkillRenderer Primitive-Bibliothek von 21 auf 92 Primitives erweitern.
Alle neuen Primitives muessen im ComponentRegistry registriert UND im SkillRenderer implementiert werden.

## Kontext
- ComponentRegistry: `/Sources/BrainCore/Engine/ComponentRegistry.swift`
- SkillRenderer: `/Sources/BrainApp/SkillRenderer.swift`
- Aktuell: 49 registriert, 21 implementiert
- Ziel: 92 registriert, 92 implementiert
- Jedes Primitive das registriert ist MUSS auch gerendert werden (kein Fallback)

## Regeln
- **Keine neue Dependency** — nur SwiftUI + UIKit wo noetig
- **Zero-Cost wenn ungenutzt** — Primitives werden nur instanziiert wenn referenziert
- **Graceful Fallback** — Unbekannte Primitives zeigen weiterhin Placeholder-Icon
- **Konsistente API** — Jedes Primitive nutzt `properties` Dict fuer Konfiguration
- **Two-Way Bindings** — Input-Primitives muessen echte Bindings unterstuetzen (nicht .constant())
- **Tests** — Fuer jede neue Kategorie mindestens 3 Render-Tests

## Batch 1: Fehlende Registry-Primitives implementieren (28 Stueck)

### Layout (3 fehlende)
- `tab-view` — TabView mit dynamischen Tabs aus children
- `split-view` — NavigationSplitView (iPad)
- `conditional` — bereits implementiert ✓ (nur Registry-Update)

### Input (9 fehlende)
- `text-editor` — TextEditor fuer mehrzeiligen Text, echtes Binding
- `picker` — Picker mit Optionen aus properties.options Array
- `slider` — Slider mit min/max/step aus properties
- `stepper` — Stepper mit min/max aus properties
- `date-picker` — DatePicker, Format aus properties.format
- `color-picker` — ColorPicker
- `search-field` — TextField mit .searchable Modifier
- `secure-field` — SecureField fuer Passwoerter/API-Keys

### Interaction (5 fehlende)
- `link` — Link/Button der URL oeffnet
- `menu` — Menu mit MenuItems aus children
- `swipe-actions` — .swipeActions Modifier auf List-Rows
- `pull-to-refresh` — .refreshable Modifier
- `long-press` — .onLongPressGesture mit Action

### Data (6 fehlende)
- `chart` — Swift Charts (LineMark default), type aus properties
- `map` — MapKit Map mit Annotations aus properties.markers
- `calendar-grid` — Custom Kalender-Grid
- `gauge` — Gauge mit currentValue/min/max
- `timer-display` — Text(date, style: .timer)
- `graph` — Placeholder fuer Knowledge Graph (spaeter Grape)

### Special (7 fehlende)
- `rich-editor` — TextEditor mit Basic-Formatting
- `canvas` — Canvas/PencilKit Zeichenflaeche
- `camera` — Camera-Capture Button/View
- `scanner` — VisionKit Document Scanner
- `audio-player` — AVAudioPlayer Controls
- `web-view` — WKWebView Wrapper
- Hinweis: Diese koennen als Placeholder implementiert werden mit "Coming Soon"

## Batch 2: Neue Primitives registrieren + implementieren (42 Stueck)

### Layout (5 neue)
- `lazy-vstack` — LazyVStack fuer performante lange Listen
- `lazy-hstack` — LazyHStack fuer horizontale Karussells
- `section` — Section mit optionalem header/footer aus properties
- `disclosure-group` — DisclosureGroup, aufklappbar, children als Inhalt
- `view-that-fits` — ViewThatFits, probiert children der Reihe nach

### Content (5 neue)
- `label` — Label(title, systemImage:) aus properties
- `async-image` — AsyncImage(url:) mit Placeholder
- `date-text` — Text(date, style:) fuer relative Zeitangaben (.relative, .timer, .offset)
- `redacted` — children mit .redacted(reason: .placeholder) Modifier
- `color-swatch` — RoundedRectangle mit Farbe aus properties.color, Groesse aus properties.size

### Input (3 neue)
- `photo-picker` — PhotosPicker, Selection-Callback als Action
- `paste-button` — PasteButton, onPaste Action
- `multi-picker` — List mit Toggle-Rows fuer Mehrfachauswahl, selection als Array

### Interaction (5 neue)
- `navigation-link` — NavigationLink mit destination aus properties.destination
- `context-menu` — .contextMenu Modifier, Menu-Items aus children
- `share-link` — ShareLink mit item aus properties.text/url
- `confirmation-dialog` — .confirmationDialog Modifier, Buttons aus children
- `double-tap` — .onTapGesture(count: 2) mit Action

### Data (7 neue)
- `line-chart` — Chart { LineMark } mit data aus properties.data Array
- `bar-chart` — Chart { BarMark } mit data aus properties.data Array
- `pie-chart` — Chart { SectorMark } mit data aus properties.data Array
- `sparkline` — Mini-Chart inline (fixe Hoehe 30pt)
- `countdown` — Text(targetDate, style: .timer) Countdown
- `metric` — Grosse Zahl mit .system(.largeTitle, design: .rounded) + Label
- `heat-map` — Grid mit farbigen Zellen basierend auf properties.data Matrix

### Feedback (6 neue — NEUE KATEGORIE)
- `alert` — .alert() Modifier, title/message/buttons aus properties
- `toast` — Overlay mit Auto-Dismiss Animation (3s default)
- `banner` — Persistenter Top-Banner (Info, Warning, Error aus properties.type)
- `loading` — ProgressView() indeterminate Spinner mit optionalem Label
- `skeleton` — children mit .redacted + Shimmer-Animation
- `haptic` — Unsichtbar, triggert UIImpactFeedbackGenerator bei onAppear

### Container (5 neue — NEUE KATEGORIE)
- `card` — RoundedRectangle + Shadow + VStack + Padding, children als Inhalt
- `grouped-list` — List(.insetGrouped), children als Sections
- `toolbar` — .toolbar { } Modifier, children als ToolbarItems
- `overlay` — .overlay() Modifier, children als Overlay-Content
- `full-screen-cover` — .fullScreenCover() Modifier, trigger aus properties.isPresented

### System (6 neue — NEUE KATEGORIE)
- `open-url` — Link/Button der openURL() aufruft
- `copy-button` — Button der properties.text in UIPasteboard kopiert + Haptic
- `qr-code` — CIFilter.qrCodeGenerator, data aus properties.data
- `video-player` — VideoPlayer(url:) mit Standard-Controls
- `live-activity` — Placeholder View (spaeter ActivityKit)
- `widget-preview` — Placeholder View (spaeter WidgetKit)

## Implementierungs-Reihenfolge

```
Schritt 1: Input-Bindings fixen (.constant() → echte Bindings)
           → text-field, toggle muessen zuerst funktionieren

Schritt 2: Batch 1 — Fehlende Registry-Primitives (28)
           → Reihenfolge: Input → Interaction → Data → Layout → Special

Schritt 3: Batch 2 — Neue Primitives (42)
           → Reihenfolge: Feedback → Container → Content → Interaction → Input → Data → Layout → System

Schritt 4: ComponentRegistry updaten
           → Alle neuen Primitives registrieren mit korrekten required/optional Properties

Schritt 5: Tests
           → Pro Kategorie: 3+ Render-Tests (Primitive erzeugen, rendern, Properties pruefen)
```

## Qualitaetskriterien
- Alle 92 Primitives rendern ohne Crash
- Input-Primitives haben echte Two-Way-Bindings
- Keine Performance-Regression (LazyVStack/LazyHStack fuer grosse Listen)
- Jedes Primitive hat mindestens 1 Property die konfigurierbar ist
- Special-Kategorie darf Placeholder zeigen ("Coming in v1.1")
- `swift build` und `swift test` muessen gruen sein
- iOS Simulator Build muss erfolgreich sein
