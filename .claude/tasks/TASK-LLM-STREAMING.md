# Auftrag: LLM Streaming

## Ziel
AnthropicProvider und OpenAIProvider mit Streaming-Support ausstatten.
Chat-UI zeigt Antworten Token-by-Token an.

## Voraussetzung
- AnthropicProvider existiert: `Sources/BrainApp/LLMProviders/AnthropicProvider.swift`
- OpenAIProvider existiert: `Sources/BrainApp/LLMProviders/OpenAIProvider.swift`
- LLMProvider Protocol in BrainCore definiert complete() mit AsyncThrowingStream
- Chat-Backend muss funktionieren (TASK-BACKEND-WIRING 1.5 muss erledigt sein)

## Auftraege

### 2.1 AnthropicProvider Streaming (Mittel)
**Datei:** `Sources/BrainApp/LLMProviders/AnthropicProvider.swift`
- `supportsStreaming` auf `true` setzen
- Neuer Endpoint: POST /v1/messages mit `"stream": true`
- SSE (Server-Sent Events) Response parsen:
  - `message_start` → Conversation ID
  - `content_block_delta` → Text Delta extrahieren
  - `message_stop` → Stream beenden
- URLSession mit `bytes(for:)` fuer async byte stream
- Fehlerbehandlung: Timeout, Netzwerkfehler, API-Fehler (429, 500)
- `AsyncThrowingStream<Delta, Error>` zurueckgeben
- Delta Typ: `.text(String)`, `.toolUse(ToolCall)`, `.done`

### 2.2 Chat-UI Streaming-Anzeige (Mittel)
**Dateien:** Chat-Skill Definition, `Sources/BrainApp/SkillViewModel.swift`
- Waehrend Streaming: Typing-Indicator (drei Punkte Animation)
- Token-by-Token: Text wird progressiv aufgebaut
- Message-Bubble waechst mit dem Text mit
- Auto-Scroll zum Ende bei neuem Text
- Cancel-Button waehrend Streaming (bricht Stream ab)
- Nach Completion: Finale Message in chat_history persistieren
- Error-State: "Verbindung fehlgeschlagen" mit Retry-Button

### 2.3 OpenAIProvider Streaming (Klein)
**Datei:** `Sources/BrainApp/LLMProviders/OpenAIProvider.swift`
- Analog zu AnthropicProvider
- POST /v1/chat/completions mit `"stream": true`
- SSE Format: `data: {"choices":[{"delta":{"content":"..."}}]}`
- `data: [DONE]` als Stream-Ende
- Selbes AsyncThrowingStream<Delta, Error> Interface

### 2.4 Markdown-Rendering in Chat (Klein)
**Datei:** Chat-Skill Definition
- AI-Antworten als `markdown` Primitive rendern (existiert bereits im SkillRenderer)
- Code-Bloecke mit Syntax-Highlighting (falls moeglich)
- Inline-Code mit monospace Font
- Links klickbar
- Listen korrekt formatiert

## Technische Details

### SSE Parsing Pattern:
```swift
func streamCompletion(_ messages: [Message]) -> AsyncThrowingStream<Delta, Error> {
    AsyncThrowingStream { continuation in
        Task {
            var request = buildRequest(messages, stream: true)
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let json = String(line.dropFirst(6))
                if json == "[DONE]" { break }

                if let delta = parseDelta(json) {
                    continuation.yield(delta)
                }
            }
            continuation.finish()
        }
    }
}
```

## Qualitaetskriterien
- Streaming funktioniert mit Anthropic Claude API
- Erste Tokens erscheinen innerhalb von 1-2 Sekunden
- UI bleibt responsive waehrend Streaming (kein Main-Thread Blocking)
- Cancel bricht den Stream sofort ab
- Netzwerkfehler zeigen verstaendliche Fehlermeldung
- Markdown wird korrekt gerendert
- Chat-History wird nach Stream-Completion gespeichert
