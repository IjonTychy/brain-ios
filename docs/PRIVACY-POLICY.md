# Datenschutzerklaerung / Privacy Policy

> Brain — Dein persoenliches Gehirn
> Zuletzt aktualisiert: 23. Maerz 2026

---

## Deutsch

### Zusammenfassung

Brain speichert alle Daten lokal auf deinem Geraet. Es gibt keinen Server, kein Tracking und keine Werbung. Deine Daten gehoeren dir.

### Welche Daten verarbeitet Brain?

Brain verarbeitet ausschliesslich Daten, die du selbst eingibst oder freigibst:

- **Eintraege:** Gedanken, Aufgaben, Notizen — gespeichert in einer lokalen SQLite-Datenbank auf deinem Geraet.
- **Kontakte, Kalender, Erinnerungen:** Nur wenn du den Zugriff erlaubst. Brain liest und schreibt direkt in die iOS-Datenbanken (Contacts.framework, EventKit). Keine Kopie wird an externe Server gesendet.
- **E-Mails:** Wenn du IMAP/SMTP konfigurierst, kommuniziert Brain direkt mit deinem Mailserver. Zugangsdaten werden im iOS Keychain gespeichert.
- **Standort:** Nur wenn du den Zugriff erlaubst und ein Skill den Standort benoetigt. Wird nicht gespeichert oder weitergeleitet.
- **Gesundheitsdaten:** Nur wenn du den Zugriff erlaubst. Werden lokal verarbeitet und nie an externe Server gesendet.

### KI-Anfragen

Wenn du den KI-Chat nutzt, werden deine Nachrichten an den von dir gewaehlten KI-Anbieter gesendet:

- **Anthropic (Claude)** — api.anthropic.com (API-Key)
- **OpenAI (GPT)** — api.openai.com (API-Key)
- **Google (Gemini)** — generativelanguage.googleapis.com (API-Key oder Google OAuth)
- **Eigener Proxy / VPS** — du kannst einen selbst betriebenen OpenAI-kompatiblen Proxy konfigurieren (z.B. ein lokales LLM auf deinem eigenen Server). Deine Daten verlassen dann dein eigenes Netzwerk nicht.
- **Lokal (On-Device)** — keine Datenuebertragung, alles auf dem Geraet

Du entscheidest, welchen Anbieter du nutzt. Fuer Anthropic und OpenAI gibst du deinen eigenen API-Key ein. Fuer Google Gemini kannst du wahlweise einen API-Key oder die Google-Anmeldung (OAuth) verwenden — dabei wird nur ein Zugangstoken gespeichert, nicht dein Google-Passwort. Brain hat keinen eigenen Server und leitet keine Daten ueber Dritte weiter. Die Datenschutzrichtlinien des jeweiligen Anbieters gelten fuer die uebermittelten Nachrichten.

#### Google OAuth

Wenn du dich bei Gemini ueber Google anmeldest, oeffnet Brain ein Anmeldefenster von Google. Brain erhaelt dabei ein zeitlich begrenztes Zugangstoken (OAuth-Token), das im iOS Keychain gespeichert wird. Brain hat keinen Zugriff auf dein Google-Passwort, deine Google-Kontakte oder andere Google-Dienste — ausschliesslich auf die Gemini-API.

**Privacy Zones:** Du kannst Tags mit Datenschutzstufen versehen. Eintraege mit dem Tag "privat" koennen so konfiguriert werden, dass sie nur an das lokale On-Device-Modell oder deinen eigenen Proxy gesendet werden — nie an Cloud-Anbieter.

### Welche Daten werden NICHT erhoben?

- Keine Nutzungsanalysen (Analytics)
- Kein Tracking
- Keine Werbung
- Keine Weitergabe an Dritte (ausser den von dir gewaehlten KI-Anbietern)
- Kein Account / keine Registrierung
- Kein eigener Server

### Datenspeicherung

Alle Daten werden ausschliesslich lokal auf deinem Geraet gespeichert:
- **SQLite-Datenbank** im App-Container
- **iOS Keychain** fuer API-Keys und Passwoerter
- **UserDefaults** fuer Einstellungen

iCloud-Backup sichert die App-Daten verschluesselt, wenn du iCloud-Backup in den iOS-Einstellungen aktiviert hast.

### Deine Rechte

- **Export:** Du kannst alle Daten jederzeit als JSON exportieren (Einstellungen → Datensicherung).
- **Loeschen:** Du kannst einzelne Eintraege oder alle Daten jederzeit loeschen.
- **Deinstallation:** Beim Loeschen der App werden alle lokalen Daten entfernt.

### Kontakt

Bei Fragen zum Datenschutz: support@example.com

---

## English

### Summary

Brain stores all data locally on your device. There is no server, no tracking, and no ads. Your data belongs to you.

### What data does Brain process?

Brain only processes data that you enter or authorize:

- **Entries:** Thoughts, tasks, notes — stored in a local SQLite database on your device.
- **Contacts, Calendar, Reminders:** Only with your permission. Brain reads and writes directly to iOS databases (Contacts.framework, EventKit). No copies are sent to external servers.
- **Emails:** If you configure IMAP/SMTP, Brain communicates directly with your mail server. Credentials are stored in the iOS Keychain.
- **Location:** Only with your permission and when a skill requires it. Not stored or forwarded.
- **Health data:** Only with your permission. Processed locally and never sent to external servers.

### AI Requests

When you use the AI chat, your messages are sent to the AI provider of your choice:

- **Anthropic (Claude)** — api.anthropic.com (API key)
- **OpenAI (GPT)** — api.openai.com (API key)
- **Google (Gemini)** — generativelanguage.googleapis.com (API key or Google OAuth)
- **Self-hosted Proxy / VPS** — you can configure your own OpenAI-compatible proxy (e.g. a local LLM on your own server). Your data never leaves your own network.
- **Local (On-Device)** — no data transmission, everything stays on device

You choose which provider to use. For Anthropic and OpenAI, you enter your own API key. For Google Gemini, you can use either an API key or Google Sign-In (OAuth) — only an access token is stored, not your Google password. Brain has no server of its own and does not route data through third parties. The privacy policy of each provider applies to the messages sent.

#### Google OAuth

When you sign in to Gemini via Google, Brain opens a Google sign-in window. Brain receives a time-limited access token (OAuth token) stored in the iOS Keychain. Brain has no access to your Google password, Google contacts, or other Google services — only the Gemini API.

**Privacy Zones:** You can assign privacy levels to tags. Entries tagged "private" can be configured to only use the local on-device model or your own proxy — never sent to cloud providers.

### What data is NOT collected?

- No usage analytics
- No tracking
- No advertising
- No sharing with third parties (except AI providers you choose)
- No account / no registration
- No proprietary server

### Data Storage

All data is stored exclusively on your device:
- **SQLite database** in the app container
- **iOS Keychain** for API keys and passwords
- **UserDefaults** for settings

iCloud Backup secures app data in encrypted form if you have iCloud Backup enabled in iOS Settings.

### Your Rights

- **Export:** You can export all data as JSON at any time (Settings → Backup).
- **Delete:** You can delete individual entries or all data at any time.
- **Uninstall:** Deleting the app removes all local data.

### Contact

For privacy questions: support@example.com
