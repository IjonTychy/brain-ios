# Auftrag: On-Device LLM Integration

## Ziel
Lokales LLM auf dem iPhone/iPad fuer Offline-Nutzung und Privacy.
MLX Swift als Framework, kleine Modelle (3B Parameter) fuer schnelle Inferenz.

## Prioritaet
NIEDRIG fuer v1.0 — kann nach TestFlight-Release gemacht werden.

## Voraussetzung
- LLMRouter existiert mit Routing-Logik (offline → on-device)
- LLMProvider Protocol definiert
- Chat-Backend funktioniert (TASK-BACKEND-WIRING)
- Streaming funktioniert (TASK-LLM-STREAMING)
- Geraet: iPhone 15 Pro+ oder iPad mit M-Chip (fuer ausreichend RAM)

## Auftraege

### 3.1 MLX Swift Integration (Gross)
**Neue Datei:** `Sources/BrainApp/LLMProviders/MLXProvider.swift`
- SPM Dependency: `mlx-swift` (Apple)
- MLXProvider implementiert LLMProvider Protocol
- Modell laden aus App-Container (Documents/Models/)
- Tokenizer laden (SentencePiece oder tiktoken)
- complete() mit AsyncThrowingStream (Token-by-Token Generation)
- Memory Management: Modell entladen wenn nicht gebraucht
- Thermal Throttling beachten (Geraet wird heiss bei Inferenz)

### 3.2 Modell-Download UI (Mittel)
**Neue Datei:** Modell-Management Skill oder Settings-Erweiterung
- Settings → "On-Device Modell"
- Verfuegbare Modelle auflisten:
  - Llama 3.2 3B (Q4_K_M, ~1.8 GB)
  - Phi-3 Mini (Q4_K_M, ~2.3 GB)
  - Mistral 7B (Q4_K_M, ~4.1 GB) — nur iPad/Vision Pro
- Speicherplatz-Check vor Download
- Download mit Progress-Anzeige (URLSession background download)
- Modell loeschen wenn Speicher knapp
- Aktuell geladenes Modell anzeigen

### 3.3 Offline-Routing aktivieren (Klein)
**Datei:** `Sources/BrainCore/LLM/LLMRouter.swift`
- NetworkMonitor (NWPathMonitor) integrieren
- Wenn offline UND MLXProvider verfuegbar → automatisch routen
- Wenn offline UND kein On-Device Modell → Fehlermeldung:
  "Kein Internet und kein lokales Modell installiert"
- User-Praeferenz: "Sensible Daten nur On-Device" beachten

### 3.4 Modell-Auswahl UI (Klein)
**Datei:** Settings-Erweiterung
- Dropdown/Picker fuer installierte Modelle
- "Bevorzugtes Modell" Einstellung
- Modell-Info anzeigen: Groesse, Parameter, Geschwindigkeit
- Benchmark: "X Tokens/Sek auf diesem Geraet"

## Technische Details

### MLX Swift Pattern:
```swift
import MLX
import MLXLLM

class MLXProvider: LLMProvider {
    var name: String { "On-Device (\(modelName))" }
    var isOnDevice: Bool { true }
    var isAvailable: Bool { model != nil }

    private var model: LLMModel?
    private var tokenizer: Tokenizer?

    func loadModel(path: URL) async throws {
        model = try await LLMModelFactory.shared.load(from: path)
        tokenizer = try await AutoTokenizer.from(pretrained: path)
    }

    func complete(_ messages: [Message], tools: [Tool]?) -> AsyncThrowingStream<Delta, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let prompt = formatMessages(messages)
                let tokens = tokenizer!.encode(prompt)
                for await token in model!.generate(tokens) {
                    let text = tokenizer!.decode([token])
                    continuation.yield(.text(text))
                }
                continuation.finish()
            }
        }
    }
}
```

### Speicher-Anforderungen:
| Modell | RAM | Disk | Geraete |
|--------|-----|------|---------|
| Llama 3.2 3B Q4 | ~2 GB | ~1.8 GB | iPhone 15 Pro+, iPad Air M1+ |
| Phi-3 Mini Q4 | ~2.5 GB | ~2.3 GB | iPhone 15 Pro+, iPad Air M1+ |
| Mistral 7B Q4 | ~5 GB | ~4.1 GB | iPad Pro M1+, Vision Pro |

## Qualitaetskriterien
- Modell laeuft auf iPhone 15 Pro mit ~10-30 tokens/sec
- App crasht nicht bei Speichermangel (graceful degradation)
- Download im Hintergrund moeglich
- Modell wird beim App-Start NICHT automatisch geladen (on-demand)
- Offline-Chat funktioniert ohne Internet
- Antwortqualitaet ist akzeptabel fuer einfache Aufgaben
