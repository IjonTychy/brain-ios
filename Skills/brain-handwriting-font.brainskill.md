---
id: brain-handwriting-font
name: Handschrift-Font
description: Erstelle eine digitale Schrift aus deiner Handschrift — fotografiere deine Buchstaben und generiere einen SVG-Font
version: 1.2
capability: app
created_by: system
icon: textformat.abc
color: "#6366F1"
permissions: [camera, entries]
triggers:
  - type: siri
    phrase: "Handschrift-Font erstellen"
actions_json: |
  {
    "capture_sample": {
      "steps": [
        {"type": "camera.capture"},
        {"type": "image.detectText", "properties": {"image": "{{lastResult}}"}},
        {"type": "set", "properties": {"key": "segmentCount", "value": "{{lastResult.count}}"}},
        {"type": "set", "properties": {"key": "segmentChars", "value": "{{lastResult.characters}}"}},
        {"type": "set", "properties": {"key": "sampleImage", "value": "{{lastResult.image}}"}}
      ]
    },
    "pick_sample": {
      "steps": [
        {"type": "camera.pick"},
        {"type": "image.detectText", "properties": {"image": "{{lastResult}}"}},
        {"type": "set", "properties": {"key": "segmentCount", "value": "{{lastResult.count}}"}},
        {"type": "set", "properties": {"key": "segmentChars", "value": "{{lastResult.characters}}"}},
        {"type": "set", "properties": {"key": "sampleImage", "value": "{{lastResult.image}}"}}
      ]
    },
    "generate_font": {
      "steps": [
        {"type": "image.traceContours", "properties": {"image": "{{sampleImage}}"}},
        {"type": "svg.generate", "properties": {"contours": "{{lastResult}}", "fontName": "{{fontName}}"}},
        {"type": "set", "properties": {"key": "fontFileName", "value": "{{lastResult.fileName}}"}},
        {"type": "set", "properties": {"key": "fontGlyphCount", "value": "{{lastResult.glyphCount}}"}},
        {"type": "set", "properties": {"key": "fontGenerated", "value": "true"}},
        {"type": "entry.create", "properties": {"type": "document", "title": "{{fontName}}", "body": "SVG Font mit {{lastResult.glyphCount}} Glyphen", "source": "font-generator"}},
        {"type": "haptic", "properties": {"style": "success"}},
        {"type": "toast", "properties": {"message": "Font erstellt!"}}
      ]
    },
    "share_font": {
      "steps": [
        {"type": "file.share", "properties": {"path": "{{fontFileName}}"}}
      ]
    }
  }
screens_json: |
  {
    "main": {
      "type": "scroll",
      "children": [
        {
          "type": "stack",
          "properties": {"direction": "vertical", "spacing": 16, "padding": 20},
          "children": [
            {
              "type": "text",
              "properties": {"value": "Handschrift-Font", "style": "largeTitle"}
            },
            {
              "type": "text",
              "properties": {"value": "Erstelle eine digitale Schrift aus deiner Handschrift. Schreibe alle Buchstaben auf Papier und fotografiere sie.", "style": "subheadline"}
            },
            {
              "type": "divider"
            },
            {
              "type": "text",
              "properties": {"value": "Schritt 1: Handschrift fotografieren", "style": "headline"}
            },
            {
              "type": "text",
              "properties": {"value": "Schreibe alle Buchstaben (A–Z, a–z, 0–9) gut lesbar auf weisses Papier. Dann fotografiere das Blatt.", "style": "body"}
            },
            {
              "type": "stack",
              "properties": {"direction": "horizontal", "spacing": 12},
              "children": [
                {
                  "type": "button",
                  "properties": {"title": "Fotografieren", "style": "primary", "icon": "camera.fill"},
                  "onTap": "capture_sample"
                },
                {
                  "type": "button",
                  "properties": {"title": "Aus Fotos", "style": "secondary", "icon": "photo.on.rectangle"},
                  "onTap": "pick_sample"
                }
              ]
            },
            {
              "type": "conditional",
              "properties": {"condition": "{{segmentCount}}"},
              "children": [
                {
                  "type": "stack",
                  "properties": {"direction": "vertical", "spacing": 8},
                  "children": [
                    {
                      "type": "divider"
                    },
                    {
                      "type": "text",
                      "properties": {"value": "Schritt 2: Buchstaben erkannt", "style": "headline"}
                    },
                    {
                      "type": "stat-card",
                      "properties": {
                        "title": "Erkannte Zeichen",
                        "value": "{{segmentCount}}",
                        "suffix": "Buchstaben"
                      }
                    },
                    {
                      "type": "text",
                      "properties": {"value": "Erkannte Zeichen: {{segmentChars}}", "style": "body"}
                    },
                    {
                      "type": "divider"
                    },
                    {
                      "type": "text",
                      "properties": {"value": "Schritt 3: Font generieren", "style": "headline"}
                    },
                    {
                      "type": "text-field",
                      "properties": {"placeholder": "Name deiner Schrift", "value": "{{fontName}}"}
                    },
                    {
                      "type": "button",
                      "properties": {"title": "Font generieren", "style": "primary", "icon": "wand.and.stars"},
                      "onTap": "generate_font"
                    }
                  ]
                }
              ]
            },
            {
              "type": "conditional",
              "properties": {"condition": "{{fontGenerated}}"},
              "children": [
                {
                  "type": "stack",
                  "properties": {"direction": "vertical", "spacing": 8},
                  "children": [
                    {
                      "type": "divider"
                    },
                    {
                      "type": "text",
                      "properties": {"value": "Font erstellt!", "style": "headline"}
                    },
                    {
                      "type": "stat-card",
                      "properties": {
                        "title": "{{fontFileName}}",
                        "value": "{{fontGlyphCount}}",
                        "suffix": "Glyphen"
                      }
                    },
                    {
                      "type": "button",
                      "properties": {"title": "Font teilen", "style": "secondary", "icon": "square.and.arrow.up"},
                      "onTap": "share_font"
                    }
                  ]
                }
              ]
            },
            {
              "type": "spacer"
            },
            {
              "type": "text",
              "properties": {"value": "Tipps", "style": "headline"}
            },
            {
              "type": "text",
              "properties": {"value": "• Schreibe jeden Buchstaben einzeln und deutlich\n• Verwende einen schwarzen Stift auf weissem Papier\n• Gute Beleuchtung verbessert die Erkennung\n• Grossbuchstaben und Kleinbuchstaben separat schreiben", "style": "caption"}
            }
          ]
        }
      ]
    }
  }
---

# Handschrift-Font Generator

Erstelle eine digitale Schrift aus deiner eigenen Handschrift.

## Workflow

1. User schreibt alle Buchstaben auf Papier (A-Z, a-z, 0-9, Satzzeichen)
2. Foto aufnehmen oder aus Bibliothek wählen
3. `font.segment` erkennt einzelne Buchstaben und ihre Positionen
4. `font.vectorize` konvertiert jeden Buchstaben in Vektordaten
5. `font.generate` erzeugt eine SVG-Schriftdatei

## Actions

### capture_sample
- `camera.capture` — Foto der Handschriftprobe aufnehmen
- `font.segment` — Buchstaben im Bild erkennen und segmentieren
- Ergebnis: segmentCount, segmentChars, segments[] in Variablen

### pick_sample
- `camera.pickPhoto` — Foto aus Bibliothek wählen
- `font.segment` — Buchstaben im Bild erkennen und segmentieren

### generate_font
- Für jeden erkannten Buchstaben: `font.vectorize` (Bitmap → Vektordaten)
- `font.generate` — SVG-Font aus allen vektorisierten Buchstaben erzeugen
- `entry.create` — Font als Entry speichern (type: document)
- `haptic` — Erfolgsfeedback
- `toast` — "Font erstellt!"

### share_font
- `file.share` — SVG-Datei via Share Sheet teilen
