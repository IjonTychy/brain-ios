# On-Device-Modelle (Gemma via llama.cpp)

Stand: 04.07.2026

## Konzept

brain-ios kennt zwei On-Device-Backends. Welches antwortet, entscheidet die
**Verfügbarkeit zur Laufzeit** — nichts ist hart verdrahtet:

1. **Apple Foundation Models** (iOS 26+, unterstützte Hardware) — `OnDeviceProvider`
2. **Downloadbare GGUF-Modelle** (Gemma-Familie) via llama.cpp — `GemmaProvider`

Auswahl-Logik (in `ChatService.buildProvider()` und `DataBridge.buildLLMProvider()`):

```
selectedModel == "on-device"
  → Apple Foundation Models verfügbar?  → nutzen
  → sonst: bestes heruntergeladenes GGUF-Modell, das in den RAM passt → nutzen
  → sonst: Fallthrough auf Cloud-Provider
```

## Modell-Katalog

`OnDeviceModelCatalog` liefert die Default-Modelle:

| Modell | Datei | Grösse | Min. RAM | Kontext |
|--------|-------|--------|----------|---------|
| Gemma 4 E2B (Q4_K_M) | `gemma-4-E2B-it-Q4_K_M.gguf` | ~1.3 GB | 6 GB | 8192 |
| Gemma 4 E4B (Q4_K_M) | `gemma-4-E4B-it-Q4_K_M.gguf` | ~2.5 GB | 8 GB | 8192 |

Gemma 4 (Google, April 2026) ist Apache-2.0-lizenziert; E2B/E4B sind die
Edge-Varianten mit Per-Layer-Embeddings (effektive 2B/4B-Footprints).

**Nicht hardcoded:**

- Der gesamte Katalog kann zur Laufzeit via UserDefaults-Key
  `onDeviceModelCatalog` (JSON-Array von `OnDeviceModelSpec`) ersetzt werden —
  neue Modelle (z.B. eine künftige Gemma-Version) brauchen kein App-Update.
- Die Download-URL pro Modell ist via `onDeviceModelURL.<modelId>` übersteuerbar
  (die Defaults zeigen auf die unsloth-GGUF-Mirrors auf Hugging Face; exakte
  Dateinamen beim ersten Download verifizieren, da HF-Repos umbenannt werden können).

Modelle liegen unter `Application Support/OnDeviceModels/` (vom iCloud-Backup
ausgeschlossen). Download/Löschen: Einstellungen → KI-Anbieter → "Auf dem Gerät".

## Aktivierung der Gemma-Inferenz (einmaliger Schritt in Xcode)

Der Inferenz-Code in `GemmaRuntime` ist hinter `#if canImport(llama)` gekapselt —
dasselbe Muster wie `FoundationModels` im `OnDeviceProvider`. Ohne das Package
kompiliert und läuft alles wie bisher; `GemmaRuntime.isSupported` ist dann `false`
und die Settings-UI zeigt einen Hinweis.

Aktivieren:

1. Xcode → Projekt `BrainApp` → Package Dependencies → `+`
2. URL: `https://github.com/ggml-org/llama.cpp`
3. Dependency Rule: **exakte Revision/Tag pinnen** (z.B. aktuellen `b`-Release-Tag),
   nicht `master` — die C-API bewegt sich.
4. Produkt `llama` zum Target **BrainApp** hinzufügen.
5. Bauen. `GemmaRuntime` (GemmaProvider.swift) ist gegen die 2025/2026-C-API
   geschrieben (`llama_model_load_from_file`, `llama_init_from_model`,
   `llama_sampler_chain_*`) — beim ersten Build gegen die gepinnte Revision
   verifizieren und ggf. Symbolnamen anpassen.

## Prompt-Format

Gemma hat keine System-Rolle. `GemmaProvider.buildPrompt()` mergt den
System-Prompt in den ersten User-Turn:

```
<start_of_turn>user
{systemPrompt}

{userMessage}<end_of_turn>
<start_of_turn>model
{assistantMessage}<end_of_turn>
...
<start_of_turn>model
```

## Grenzen (bewusst)

- **Kein Tool-Use, kein Streaming** auf On-Device-Modellen. Im Chat laufen sie
  über `ToolLessProviderAdapter` (eine Antwort als ein Text-Event).
- Für Skill-Kompilierung (komplex) routet die App weiterhin bevorzugt zu
  Cloud-Modellen (siehe ARCHITECTURE.md Routing-Logik).
- Die Inferenz-Implementierung konnte in dieser Umgebung nicht auf einem Gerät
  ausgeführt werden — vor dem Release auf iPhone/iPad verifizieren
  (Erst-Download, Laden, Antwortqualität, Speicherverbrauch).
