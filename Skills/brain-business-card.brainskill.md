---
id: brain-business-card
name: Visitenkarten-Scanner
description: Scanne Visitenkarten und erstelle automatisch Kontakte
version: 1.2
capability: hybrid
created_by: system
icon: person.crop.rectangle.stack
color: "#007AFF"
permissions:
  - camera
  - contacts
triggers:
  - type: siri
    phrase: "Visitenkarte scannen"
actions_json: |
  {
    "scanCard": {
      "steps": [
        {"type": "camera.capture"},
        {"type": "scan.text", "properties": {"image": "{{lastResult}}"}},
        {"type": "scan.extractContact", "properties": {"text": "{{lastResult}}"}},
        {"type": "set", "properties": {"key": "extractedName", "value": "{{lastResult.name}}"}},
        {"type": "set", "properties": {"key": "extractedCompany", "value": "{{lastResult.company}}"}},
        {"type": "set", "properties": {"key": "extractedEmail", "value": "{{lastResult.email}}"}},
        {"type": "set", "properties": {"key": "extractedPhone", "value": "{{lastResult.phone}}"}}
      ]
    },
    "analyzeText": {
      "steps": [
        {"type": "scan.extractContact", "properties": {"text": "{{pastedText}}"}},
        {"type": "set", "properties": {"key": "extractedName", "value": "{{lastResult.name}}"}},
        {"type": "set", "properties": {"key": "extractedCompany", "value": "{{lastResult.company}}"}},
        {"type": "set", "properties": {"key": "extractedEmail", "value": "{{lastResult.email}}"}},
        {"type": "set", "properties": {"key": "extractedPhone", "value": "{{lastResult.phone}}"}}
      ]
    },
    "saveContact": {
      "steps": [
        {"type": "contact.create", "properties": {"givenName": "{{extractedName}}", "organization": "{{extractedCompany}}", "email": "{{extractedEmail}}", "phone": "{{extractedPhone}}"}},
        {"type": "haptic", "properties": {"style": "success"}},
        {"type": "toast", "properties": {"message": "Kontakt gespeichert"}}
      ]
    }
  }
screens_json: |
  {
    "main": {
      "type": "stack",
      "properties": {"direction": "vertical", "spacing": 16},
      "children": [
        {
          "type": "text",
          "properties": {"value": "Visitenkarten-Scanner", "style": "largeTitle"}
        },
        {
          "type": "text",
          "properties": {
            "value": "Scanne eine Visitenkarte oder füge Text ein — Brain extrahiert automatisch Name, Firma, E-Mail, Telefon und Adresse.",
            "style": "subheadline",
            "color": "#8E8E93"
          }
        },
        {
          "type": "button",
          "properties": {
            "title": "Visitenkarte fotografieren",
            "action": "scanCard",
            "icon": "camera.fill",
            "style": "borderedProminent"
          }
        },
        {
          "type": "text-field",
          "properties": {
            "placeholder": "Oder Text hier einfügen (z.B. E-Mail-Signatur)...",
            "value": "{{pastedText}}"
          }
        },
        {
          "type": "button",
          "properties": {
            "title": "Text analysieren",
            "action": "analyzeText",
            "icon": "text.magnifyingglass",
            "style": "bordered"
          }
        },
        {
          "type": "conditional",
          "properties": {"condition": "extractedName | count > 0"},
          "children": [
            {
              "type": "stack",
              "properties": {"direction": "vertical", "spacing": 12},
              "children": [
                {"type": "divider"},
                {"type": "text", "properties": {"value": "Erkannte Daten", "style": "headline"}},
                {
                  "type": "stack",
                  "properties": {"direction": "horizontal", "spacing": 8},
                  "children": [
                    {"type": "icon", "properties": {"name": "person.fill", "color": "#007AFF"}},
                    {"type": "text", "properties": {"value": "{{extractedName}}", "style": "body"}}
                  ]
                },
                {
                  "type": "conditional",
                  "properties": {"condition": "extractedCompany | count > 0"},
                  "children": [
                    {
                      "type": "stack",
                      "properties": {"direction": "horizontal", "spacing": 8},
                      "children": [
                        {"type": "icon", "properties": {"name": "building.2.fill", "color": "#8E8E93"}},
                        {"type": "text", "properties": {"value": "{{extractedCompany}}", "style": "body"}}
                      ]
                    }
                  ]
                },
                {
                  "type": "conditional",
                  "properties": {"condition": "extractedEmail | count > 0"},
                  "children": [
                    {
                      "type": "stack",
                      "properties": {"direction": "horizontal", "spacing": 8},
                      "children": [
                        {"type": "icon", "properties": {"name": "envelope.fill", "color": "#34C759"}},
                        {"type": "text", "properties": {"value": "{{extractedEmail}}", "style": "body"}}
                      ]
                    }
                  ]
                },
                {
                  "type": "conditional",
                  "properties": {"condition": "extractedPhone | count > 0"},
                  "children": [
                    {
                      "type": "stack",
                      "properties": {"direction": "horizontal", "spacing": 8},
                      "children": [
                        {"type": "icon", "properties": {"name": "phone.fill", "color": "#FF9500"}},
                        {"type": "text", "properties": {"value": "{{extractedPhone}}", "style": "body"}}
                      ]
                    }
                  ]
                },
                {
                  "type": "button",
                  "properties": {
                    "title": "Als Kontakt speichern",
                    "action": "saveContact",
                    "icon": "person.badge.plus",
                    "style": "borderedProminent"
                  }
                }
              ]
            }
          ]
        }
      ]
    }
  }
---

# Visitenkarten-Scanner

Scannt physische Visitenkarten per Kamera oder analysiert eingefügten Text
(z.B. E-Mail-Signaturen) und extrahiert automatisch:

- Name (Vor- und Nachname)
- Firma / Organisation
- Berufsbezeichnung
- E-Mail-Adresse(n)
- Telefonnummer(n)
- Webseite
- Postadresse
- IBAN (falls vorhanden)

## Aktionen

### Visitenkarte scannen
1. Kamera öffnen (camera.capture)
2. OCR auf Foto (scan.text)
3. Kontaktdaten extrahieren (scan.extractContact)
4. Preview der erkannten Daten anzeigen
5. Bei Bestätigung: Kontakt erstellen (contact.create)

### Text analysieren
1. Eingefuegten Text lesen
2. Kontaktdaten extrahieren (scan.extractContact)
3. Preview anzeigen
4. Bei Bestätigung: Kontakt erstellen

## Siri
- "Visitenkarte scannen" → Kamera öffnen
