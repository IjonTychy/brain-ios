---
id: brain-handwriting-notes
name: Handschrift-Notizen
description: Scanne handgeschriebene Notizen, erkenne den Text per OCR und speichere ihn als Entry
version: 1.2
capability: app
created_by: system
icon: pencil.and.scribble
color: "#8B5CF6"
permissions: [camera, entries]
triggers:
  - type: siri
    phrase: "Handschrift scannen"
actions_json: |
  {
    "capture_photo": {
      "steps": [
        {"type": "camera.capture"},
        {"type": "scan.text", "properties": {"image": "{{lastResult}}"}},
        {"type": "set", "properties": {"key": "recognizedText", "value": "{{lastResult}}"}}
      ]
    },
    "pick_photo": {
      "steps": [
        {"type": "camera.pick"},
        {"type": "scan.text", "properties": {"image": "{{lastResult}}"}},
        {"type": "set", "properties": {"key": "recognizedText", "value": "{{lastResult}}"}}
      ]
    },
    "save_note": {
      "steps": [
        {"type": "entry.create", "properties": {"type": "note", "title": "Handschrift-Scan", "body": "{{recognizedText}}", "source": "scan"}},
        {"type": "haptic", "properties": {"style": "success"}},
        {"type": "toast", "properties": {"message": "Notiz gespeichert"}}
      ]
    }
  }
screens_json: |
  {
    "main": {
      "type": "stack",
      "properties": {"direction": "vertical", "spacing": 16, "padding": 20},
      "children": [
        {
          "type": "text",
          "properties": {"value": "Handschrift-Notizen", "style": "largeTitle"}
        },
        {
          "type": "text",
          "properties": {"value": "Scanne handgeschriebene Notizen und speichere den erkannten Text.", "style": "subheadline"}
        },
        {
          "type": "divider"
        },
        {
          "type": "stack",
          "properties": {"direction": "horizontal", "spacing": 12},
          "children": [
            {
              "type": "button",
              "properties": {"title": "Foto aufnehmen", "style": "primary", "icon": "camera.fill"},
              "onTap": "capture_photo"
            },
            {
              "type": "button",
              "properties": {"title": "Aus Bibliothek", "style": "secondary", "icon": "photo.on.rectangle"},
              "onTap": "pick_photo"
            }
          ]
        },
        {
          "type": "conditional",
          "properties": {"condition": "{{recognizedText}}"},
          "children": [
            {
              "type": "stack",
              "properties": {"direction": "vertical", "spacing": 8},
              "children": [
                {
                  "type": "text",
                  "properties": {"value": "Erkannter Text", "style": "headline"}
                },
                {
                  "type": "text",
                  "properties": {"value": "{{recognizedText}}", "style": "body"}
                },
                {
                  "type": "button",
                  "properties": {"title": "Als Notiz speichern", "style": "primary", "icon": "square.and.arrow.down"},
                  "onTap": "save_note"
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
          "properties": {"value": "Gespeicherte Notizen", "style": "headline"}
        },
        {
          "type": "conditional",
          "properties": {"condition": "{{notes | count > 0}}"},
          "children": [
            {
              "type": "list",
              "properties": {"data": "notes", "as": "note"},
              "children": [
                {
                  "type": "stack",
                  "properties": {"direction": "horizontal", "spacing": 10},
                  "children": [
                    {
                      "type": "icon",
                      "properties": {"name": "doc.text", "color": "#8B5CF6"}
                    },
                    {
                      "type": "stack",
                      "properties": {"direction": "vertical", "spacing": 2},
                      "children": [
                        {
                          "type": "text",
                          "properties": {"value": "{{note.title}}", "style": "body"}
                        },
                        {
                          "type": "text",
                          "properties": {"value": "{{note.createdAt | relative}}", "style": "caption"}
                        }
                      ]
                    },
                    {
                      "type": "spacer"
                    },
                    {
                      "type": "badge",
                      "properties": {"text": "Scan", "color": "#8B5CF6"}
                    }
                  ]
                }
              ]
            },
            {
              "type": "empty-state",
              "properties": {
                "icon": "pencil.and.scribble",
                "title": "Noch keine Notizen",
                "message": "Scanne eine handgeschriebene Notiz um zu beginnen."
              }
            }
          ]
        }
      ]
    }
  }
---

# Handschrift-Notizen

Scanne handgeschriebene Notizen mit der Kamera, erkenne den Text per OCR
(Vision Framework, on-device) und speichere ihn als durchsuchbaren Entry.

## Funktionsweise

1. **Foto aufnehmen** oder **aus Bibliothek wählen**
2. Vision Framework erkennt Handschrift (Deutsch + Englisch)
3. Erkannter Text wird angezeigt
4. Mit einem Tap als Entry gespeichert (Typ: note, Source: scan)

## Actions

### capture_photo
- `camera.capture` — Kamera öffnen, Foto aufnehmen
- `scan.text` — OCR auf dem Foto ausführen
- Ergebnis in `recognizedText` Variable speichern

### pick_photo
- `camera.pickPhoto` — Foto aus Bibliothek wählen
- `scan.text` — OCR auf dem Foto ausführen
- Ergebnis in `recognizedText` Variable speichern

### save_note
- `entry.create` — Entry erstellen mit erkanntem Text
  - type: note
  - title: Erste Zeile des erkannten Texts
  - body: Vollständiger erkannter Text
  - source: scan
- `haptic` — Erfolgsfeedback
- `toast` — "Notiz gespeichert"
