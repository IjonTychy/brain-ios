# Musterprompt: Handschrift-Font Generator

> Diesen Prompt an die Brain-KI senden, um den Handschrift-Font-Skill zu erstellen.

---

## Prompt

Erstelle mir einen Skill der aus meiner Handschrift eine digitale Schrift (Font) macht.

Der Skill soll so funktionieren:
1. Ich schreibe alle Buchstaben (A-Z, a-z, 0-9) auf ein Blatt Papier
2. Ich fotografiere das Blatt mit der Kamera oder waehle ein Foto aus meiner Bibliothek
3. Die App erkennt jeden einzelnen Buchstaben im Bild und zeigt mir wie viele erkannt wurden
4. Ich gebe meiner Schrift einen Namen (z.B. "Meine Handschrift")
5. Die App vektorisiert jeden Buchstaben (Bitmap → Vektorgrafik)
6. Die App generiert daraus eine SVG-Schriftdatei
7. Ich kann die Schriftdatei teilen (AirDrop, Mail, etc.)

Nutze diese Handler:
- camera.capture / camera.pickPhoto fuer Foto-Aufnahme
- font.segment fuer Buchstaben-Erkennung (Vision OCR, per-character bounding boxes)
- font.vectorize fuer Kontur-Tracing (Bitmap → Vektordaten)
- font.generate fuer SVG-Font-Erzeugung
- entry.create um den Font als Entry zu speichern
- file.share um die Datei zu teilen
- haptic + toast fuer Feedback

Die UI soll folgende Elemente haben:
- Titel "Handschrift-Font" (largeTitle)
- Erklaerungstext
- Zwei Buttons: "Fotografieren" und "Aus Fotos"
- Nach Erkennung: Statistik (Anzahl erkannte Zeichen) und Liste der Zeichen
- Textfeld fuer den Font-Namen
- "Font generieren"-Button
- Nach Generierung: Ergebnis-Anzeige mit Teilen-Button
- Tipps-Section (schwarzer Stift, weisses Papier, gute Beleuchtung)

Icon: textformat.abc
Farbe: #6366F1 (Indigo)
Siri-Phrase: "Handschrift-Font erstellen"

---

## Erwartetes Ergebnis

Die Brain-KI sollte einen Skill mit folgender Struktur erzeugen:

```
---
id: brain-handwriting-font
name: Handschrift-Font
description: ...
version: 1.0
capability: app
icon: textformat.abc
color: "#6366F1"
permissions: [camera, entries]
triggers:
  - type: siri
    phrase: "Handschrift-Font erstellen"
screens_json: |
  { ... UI-Definition mit stack, buttons, conditional, stat-card, text-field ... }
---

# Handschrift-Font Generator
...
```
