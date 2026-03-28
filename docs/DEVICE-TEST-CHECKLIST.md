# Brain — Device-Test-Checkliste

> Systematische Checkliste fuer manuelles Testen auf dem iPhone/iPad.
> Vor jedem TestFlight-Release durchgehen. Reihenfolge = empfohlene Test-Reihenfolge.

---

## 1. Erster Start & Onboarding

- [ ] App starten — Onboarding-Screen erscheint (nicht Dashboard)
- [ ] Seite 1: Willkommen — Logo, Text, "Weiter" Button
- [ ] Seite 2: Features — 4 Feature-Highlights sichtbar
- [ ] Seite 3: Datenschutz — Privacy-Garantien angezeigt
- [ ] Seite 4: API-Key — Eingabefeld fuer Claude API-Key
  - [ ] Key eingeben → "Testen & Speichern" → Validierung laeuft
  - [ ] Gueltiger Key: Erfolgsmeldung, automatisch weiter
  - [ ] Ungueltiger Key: Fehlermeldung sichtbar
  - [ ] "Ueberspringen" funktioniert
- [ ] Seite 5: Mail-Konfiguration
  - [ ] Quick-Setup Buttons (Gmail, Outlook, iCloud) sichtbar
  - [ ] IMAP/SMTP-Felder ausfuellbar
  - [ ] "Ueberspringen" funktioniert
- [ ] Seite 6: Berechtigungen
  - [ ] Kontakte-Zugriff anfragen → iOS-Dialog erscheint
  - [ ] Kalender-Zugriff anfragen → iOS-Dialog erscheint
  - [ ] Benachrichtigungen anfragen → iOS-Dialog erscheint
- [ ] Seite 7: Erster Eintrag erstellen
  - [ ] Textfeld funktioniert, Typ waehlbar
  - [ ] Eintrag wird gespeichert
- [ ] "Los geht's" → Dashboard erscheint
- [ ] Tastatur verschwindet bei jedem "Weiter"/"Ueberspringen"

---

## 2. Navigation & Layout

### iPhone
- [ ] 5 Tabs sichtbar am unteren Rand
- [ ] 6. Tab "Mehr" mit weiteren Optionen
- [ ] Jeder Tab oeffnet die richtige Ansicht
- [ ] Tab-Icons und Labels korrekt (deutsch)

### iPad
- [ ] NavigationSplitView (Sidebar + Detail)
- [ ] Sidebar zeigt alle Bereiche
- [ ] Skills-Sektion in Sidebar sichtbar

---

## 3. Dashboard (Home-Tab)

- [ ] Begruessung mit Tageszeit ("Guten Morgen/Tag/Abend")
- [ ] Datum korrekt (deutsch, z.B. "Sonntag, 23. Maerz")
- [ ] Quick-Stats: Offene Tasks, Ungelesene Mails, Heute neu
- [ ] Offene Aufgaben-Liste (nach Prioritaet sortiert)
- [ ] Schnellerfassung: Textfeld + Plus-Button
  - [ ] Text eingeben → Plus → Eintrag wird erstellt
  - [ ] Textfeld leert sich nach Erstellen
- [ ] Letzte Eintraege mit Typ-Badges
- [ ] Footer-Stats: Gesamt-Entries, Tags, Skills

---

## 4. Suche (Search-Tab)

- [ ] Suchfeld oben, Autocomplete bei Tippen
- [ ] Typ-Filter-Chips (Alle, Gedanke, Aufgabe, Notiz, etc.)
- [ ] Ergebnisse erscheinen mit farbcodierten Typ-Icons
- [ ] Tippen auf Ergebnis → Detail-Ansicht
- [ ] Swipe-Gesten auf Ergebnissen (Erledigt, Archivieren, Loeschen)
- [ ] Pull-to-Refresh funktioniert
- [ ] Privacy-Zone-Badge sichtbar bei geschuetzten Eintraegen

---

## 5. KI-Chat (Chat-Tab)

- [ ] Chat-Eingabefeld am unteren Rand
- [ ] Nachricht senden → Antwort kommt (Streaming)
- [ ] Markdown-Rendering in Antworten (fett, Listen, Code)
- [ ] Timestamps auf Chat-Bubbles
- [ ] Long-Press auf Nachricht → "Kopieren" Kontextmenue
- [ ] Modell-Auswahl Dropdown in der Toolbar
- [ ] Tool-Use sichtbar (Spinner waehrend Ausfuehrung, Checkmark danach)
  - [ ] "Erstelle eine Aufgabe: Einkaufen" → Tool wird aufgerufen → Aufgabe erscheint
  - [ ] "Wie viele Eintraege habe ich?" → Korrekte Zahl
  - [ ] "Zeige meine offenen Aufgaben" → Liste wird angezeigt
- [ ] Retry-Button bei Fehler
- [ ] Chat-History bleibt beim Tab-Wechsel erhalten
- [ ] Brain kennt User-Profil-Fakten (wenn eingegeben)

---

## 6. E-Mail (Posteingang-Tab)

- [ ] Ordner-Navigation: Posteingang, Gesendet, Entwuerfe, Archiv, Spam, Papierkorb
- [ ] Unread-Badges auf Ordnern
- [ ] E-Mail-Liste: Absender, Betreff, Datum, Vorschau
- [ ] Tippen auf E-Mail → Detail-Ansicht mit Body
- [ ] Swipe rechts: Loeschen + Verschieben
- [ ] Swipe links: Gelesen/Ungelesen + Archivieren
- [ ] Toolbar: Antworten, Weiterleiten, Verschieben, Loeschen
- [ ] Antworten: "Re:" Prefix, Zitat im Body
- [ ] Weiterleiten: "Fwd:" Prefix
- [ ] Neue Mail: Empfaenger, Betreff, Body → Senden
- [ ] Verschieben-Sheet: Standard + Server-Ordner
- [ ] Multi-Account (falls konfiguriert): "Alle Posteingaenge" + pro Account

---

## 7. Kalender (Kalender-Tab)

- [ ] Kalender-Ansicht laedt (Monats/Wochen/Agenda)
- [ ] Events werden aus iOS-Kalender angezeigt
- [ ] Farbige Kalender-Markierungen
- [ ] Tippen auf Event → Details
- [ ] Neues Event erstellen
- [ ] Erinnerungen werden angezeigt

---

## 8. Kontakte (Kontakte-Tab)

- [ ] Alphabet-Sektionen (A-Z, #)
- [ ] Kontaktzahl im Toolbar
- [ ] Kontakt tippen → Detail-Ansicht
  - [ ] Avatar/Initialen, Name, Beruf, Organisation
  - [ ] Quick-Action-Buttons: Anrufen, Nachricht, E-Mail
  - [ ] Telefonnummern mit Tap → Anruf
  - [ ] E-Mail-Adressen mit Tap → Mail
  - [ ] Adresse mit Tap → Karten
  - [ ] Geburtstag, Notiz
- [ ] Kontakt-Suche funktioniert

---

## 9. Eintraege (CRUD)

- [ ] Neuen Eintrag erstellen (via Schnellerfassung oder Chat)
- [ ] Eintrag bearbeiten → Titel, Body, Typ aendern
- [ ] Eintrag loeschen (Soft-Delete)
- [ ] Aufgabe als erledigt markieren → Haptic Feedback
- [ ] Eintrag archivieren → Haptic Feedback
- [ ] Tags hinzufuegen / entfernen
- [ ] Eintraege verlinken
- [ ] Eintrag in Spotlight indiziert (iOS-Suche "Brain" + Stichwort)

---

## 10. Skills

### Skill Manager (Mehr → Skills)
- [ ] Liste der installierten Skills
- [ ] Capability-Badge (App/KI/Hybrid) sichtbar
- [ ] Skill aktivieren/deaktivieren (Toggle)
- [ ] Skill loeschen → Bestaetigungsdialog → Haptic
- [ ] Berechtigungen-DisclosureGroup mit Icons

### Skill-Erstellung per Chat
- [ ] "Erstelle einen Skill fuer..." → Brain generiert Skill
- [ ] Skill erscheint im Skill Manager
- [ ] Skill oeffnen → UI wird gerendert

### Skill-Import
- [ ] .brainskill.md Datei oeffnen → Import-Preview
- [ ] Berechtigungen werden angezeigt
- [ ] "Installieren" → Skill erscheint in der Liste

### Aktive Skills in Navigation
- [ ] Aktivierte Skills erscheinen im Mehr-Tab (iPhone) / Sidebar (iPad)
- [ ] Tippen → Skill-View oeffnet direkt

---

## 11. Proaktive Intelligenz

### Brain-Profil (Mehr → Features → Brain-Profil)
- [ ] Name, Stil, Humor, Anrede konfigurierbar
- [ ] Erweitertes Markdown-Profil editierbar
- [ ] Aenderungen werden im Chat-Verhalten reflektiert

### User-Profil (Mehr → Features → Mein Profil)
- [ ] Markdown-Editor fuer persoenliche Infos
- [ ] "Key: Value" Zeilen werden als Facts extrahiert
- [ ] Anzahl extrahierter Fakten wird angezeigt

### Kennenlern-Dialog (Mehr → Features → Kennenlern-Dialog)
- [ ] Brain stellt Fragen (Name, Beruf, Hobbys, etc.)
- [ ] Antworten werden als Knowledge Facts gespeichert
- [ ] Dialog kann jederzeit wiederholt werden

### Chat-to-Knowledge Extraction
- [ ] Im Chat erwaehnen: "Ich wohne in Zuerich"
- [ ] Spaeter fragen: "Wo wohne ich?" → Brain antwortet korrekt

### Morgen-Briefing
- [ ] App morgens oeffnen → Briefing-Vorschlag/Notification
- [ ] Offene Tasks, Termine, On-This-Day Erinnerungen

---

## 12. Settings (Einstellungen)

- [ ] API-Key: Eingabe, Test-Button, Validierung
- [ ] Modus-Wechsel: Standard API / Anthropic Max / Proxy
- [ ] Proxy-URL: Eingabe und Test
- [ ] Standard-Modell waehlbar
- [ ] Face ID Toggle → aktiviert/deaktiviert Biometrie
- [ ] Privacy Zones: Tag + Level konfigurieren
  - [ ] Tag waehlen → Level (On-Device Only / Approved Cloud / Unrestricted)
  - [ ] Lock-Badge auf geschuetzten Eintraegen sichtbar
- [ ] Sprache: DE/EN umschaltbar
- [ ] Mail-Konten: Hinzufuegen, Bearbeiten, Loeschen
- [ ] TOFU Certificate Pinning Toggle (unter Sicherheit)

---

## 13. Weitere Features

### Karte (Karten-Tab)
- [ ] MapKit-Ansicht laedt
- [ ] Geo-getaggte Eintraege als Marker sichtbar
- [ ] Tippen auf Marker → Detail-Sheet

### An diesem Tag (Mehr → Features)
- [ ] Eintraege vom gleichen Kalendertag in frueheren Perioden
- [ ] Gruppierung: "Vor einer Woche", "Vor einem Monat", etc.

### Datensicherung (Mehr → Features)
- [ ] JSON-Export → Share-Sheet oeffnet
- [ ] JSON-Import → Bestaetigungsdialog → Import-Statistiken
- [ ] Datenbank-Info sichtbar (Groesse, Eintraege, Tags)

### Verbesserungsvorschlaege (Mehr → Features)
- [ ] Proposals-Liste mit Status-Filter
- [ ] Swipe: Anwenden / Ablehnen
- [ ] Detail-Sheet mit JSON-Aenderungsvorschau

### Regeln (Mehr → Skills → Regeln)
- [ ] Regeln-Liste mit Kategoriefilter
- [ ] Neue Regel erstellen (Formular)
- [ ] Regel bearbeiten / loeschen

---

## 14. Widgets

- [ ] QuickCaptureWidget (small): Entry-Count + Tap → App oeffnet
- [ ] TasksWidget (medium/large): Offene Tasks mit Prioritaet
- [ ] BrainPulseWidget (medium): Tageszeit-Gruss + Stats
- [ ] Widgets aktualisieren sich automatisch

---

## 15. Siri & Shortcuts

- [ ] "Hey Siri, fueg meinem Brain hinzu..." → Entry erstellt
- [ ] "Hey Siri, wie viele Eintraege hat mein Brain?" → Zahl
- [ ] Shortcuts-App: Brain-Aktionen sichtbar (12 Intents)
- [ ] Shortcut erstellen und ausfuehren

---

## 16. Share Extension

- [ ] In Safari: Teilen → Brain → Text/URL wird uebernommen
- [ ] Typ waehlbar (Gedanke/Aufgabe/Notiz)
- [ ] Titel wird automatisch aus geteiltem Inhalt generiert
- [ ] Speichern → Eintrag erscheint in Brain

---

## 17. Hardware-Features

### Dokument-Scanner
- [ ] Scanner oeffnen → Kamera-Ansicht
- [ ] Dokument scannen → OCR-Text extrahiert → Entry erstellt

### Apple Pencil (iPad)
- [ ] Zeichenflaeche oeffnen
- [ ] Handschrift → Text-Erkennung

### Spracheingabe
- [ ] Mikrofon-Taste → Aufnahme startet
- [ ] Sprache wird als Text transkribiert

### NFC (falls verfuegbar)
- [ ] NFC-Tag lesen

---

## 18. Systemverhalten

- [ ] App in Background → wieder oeffnen: Zustand erhalten
- [ ] App killen → neu starten: Daten erhalten (SQLite)
- [ ] Face ID bei App-Start (wenn aktiviert)
- [ ] Spotlight-Suche: "Brain Einkaufen" → Eintrag gefunden
- [ ] Dark Mode: Alle Screens korrekt
- [ ] Landscape-Modus (iPad): Layout passt sich an
- [ ] Grosse Schrift (Accessibility): Text skaliert korrekt
- [ ] Offline: App funktioniert ohne Internet (lokale Daten, On-Device LLM)
- [ ] Benachrichtigungen: Erinnerung kommt zur eingestellten Zeit

---

## 19. Datenintegritaet

- [ ] 100+ Eintraege erstellen → Suche bleibt schnell
- [ ] Eintrag loeschen → verschwindet sofort aus allen Listen
- [ ] Tag loeschen → wird von allen Eintraegen entfernt
- [ ] App beenden waehrend Schreibvorgang → kein Datenverlust

---

## 20. Edge Cases & Fehler

- [ ] Leerer API-Key → Chat zeigt klare Fehlermeldung
- [ ] Kein Internet + Cloud-LLM → Fehlermeldung, kein Crash
- [ ] Sehr langer Text (10'000+ Zeichen) → Eingabe funktioniert, Zeichenzaehler
- [ ] Sonderzeichen in Titeln (Emojis, Umlaute, CJK)
- [ ] Doppeltippen auf Senden → nur eine Nachricht (isSending Guard)
- [ ] Kontakte-Zugriff verweigert → klare Meldung, kein Crash
- [ ] Kalender-Zugriff verweigert → klare Meldung, kein Crash

---

## Notizen

| Datum | Tester | Bereich | Ergebnis | Bemerkung |
|-------|--------|---------|----------|-----------|
| | | | | |
