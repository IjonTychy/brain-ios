# Musterprompt: Morse-Code Dechiffrierer

> Diesen Prompt an die Brain-KI senden, um den Morse-Code-Decoder-Skill zu erstellen.

---

## Prompt

Erstelle mir einen Skill der Morse-Code entschluesseln kann — sowohl akustisch (Pieptoene ueber Mikrofon) als auch optisch (Lichtsignale wie Taschenlampen-Blinken ueber die Kamera).

Der Skill soll 4 Modi haben:

### 1. Akustische Erkennung
- Mikrofon hoert zu (konfigurierbare Dauer: 10-60 Sekunden)
- Erkennt Morse-Pieptoene automatisch
- Zeigt den erkannten Morse-Code (... --- ...) UND den Klartext (SOS) an
- Zeigt eine Konfidenz-Anzeige (wie sicher die Erkennung war)

### 2. Optische Erkennung
- Kamera erkennt Helligkeitsaenderungen (Taschenlampen-Blinken, LED-Signale)
- Gleicher Output wie akustisch

### 3. Manuelle Eingabe
- Textfeld wo man Morse-Code eintippen kann (Punkte und Striche)
- Sofortige Uebersetzung in Klartext

### 4. Text → Morse-Code
- Textfeld fuer Klartext
- Uebersetzung in Morse-Code (zum Lernen oder Senden)

Nutze diese Handler:
- morse.decodeAudio (Mikrofon → Morse → Text)
- morse.decodeVisual (Kamera → Morse → Text)
- morse.decodeText (Morse-String → Text)
- morse.encodeText (Text → Morse-String)
- entry.create um Ergebnisse zu speichern
- haptic fuer Feedback

Die UI soll haben:
- Titel "Morse-Code" (largeTitle)
- Tab-aehnliche Segmented-Picker-Buttons fuer die 4 Modi
- Pro Modus: passende Eingabe (Mikrofon-Button, Kamera-Button, Textfeld)
- Ergebnis-Bereich: Morse-Code und Klartext nebeneinander
- Konfidenz-Anzeige (progress bar) bei Audio/Video
- Referenz-Tabelle mit dem Morse-Alphabet (A = .-, B = -... etc.)
- History der letzten Dekodierungen

Icon: wave.3.right
Farbe: #10B981 (Smaragdgruen)
Berechtigungen: microphone, camera, entries
Siri-Phrases:
- "Morse-Code hoeren"
- "Morse-Code entschluesseln"

---

## Erwartetes Ergebnis

Die Brain-KI sollte einen Skill mit folgender Struktur erzeugen:

```
---
id: brain-morse-decoder
name: Morse-Code
description: Akustischer und optischer Morse-Code-Dechiffrierer
version: 1.0
capability: app
icon: wave.3.right
color: "#10B981"
permissions: [microphone, camera, entries]
triggers:
  - type: siri
    phrase: "Morse-Code hoeren"
  - type: siri
    phrase: "Morse-Code entschluesseln"
screens_json: |
  { ... UI mit picker, buttons, text-fields, progress, list, stat-card ... }
---

# Morse-Code Dechiffrierer
...
```

### Wichtige technische Details fuer die Brain-KI:

- `morse.decodeAudio` gibt zurueck: `{morseCode: "... --- ...", decodedText: "SOS", confidence: 0.95}`
- `morse.decodeVisual` gibt zurueck: dasselbe Format
- `morse.decodeText` erwartet: `{morseCode: "... --- ..."}` und gibt Klartext zurueck
- `morse.encodeText` erwartet: `{text: "SOS"}` und gibt Morse-Code zurueck
- Morse-Konventionen: `.` = Punkt (kurz), `-` = Strich (lang), 1 Leerzeichen zwischen Buchstaben, 3 Leerzeichen zwischen Woertern
