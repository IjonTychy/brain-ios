# TestFlight ohne Mac: GitHub-Actions-Pipeline

Der Workflow **TestFlight** (`.github/workflows/testflight.yml`, nur manuell
startbar) archiviert die App auf einem GitHub-macOS-Runner, signiert sie mit
fastlane `match` und laedt sie zu TestFlight hoch. Er ersetzt Xcode Cloud
funktional; beide koennen parallel existieren. Fuer oeffentliche Repos sind die
GitHub-Runner kostenlos.

## Einmaliges Setup (alles im Browser)

### 1. App Store Connect API-Key

App Store Connect -> Users and Access -> Integrations -> App Store Connect API ->
Team Keys -> "+" -> Name z.B. "GitHub Actions", Access **Admin** (noetig, damit
der Key Zertifikate anlegen darf) -> Generate. Die `.p8`-Datei sofort
herunterladen (geht nur einmal). Notieren: **Key ID** (Zeile des Keys) und
**Issuer ID** (oben auf der Seite).

### 2. Identifier im Developer-Portal pruefen

developer.apple.com -> Certificates, Identifiers & Profiles -> Identifiers:

- App ID `<Bundle-ID-Basis>`: Capabilities App Groups (Gruppe `group.<Basis>`
  zugewiesen), iCloud (CloudKit, Container `iCloud.<Basis>`), HealthKit.
- App ID `<Basis>.share-extension`: App Groups (dieselbe Gruppe).
- App ID `<Basis>.widgets`: App Groups (dieselbe Gruppe).

Fehlt eine Capability, scheitert das Signieren mit einem Entitlements-Fehler.

### 3. Privates Zertifikats-Repo und Token

- GitHub -> New repository -> Name `brain-ios-certificates`, **Private**, leer
  (kein README). Hier landen Zertifikat und Profile, verschluesselt.
- GitHub -> Profil-Settings -> Developer settings -> Personal access tokens ->
  Fine-grained tokens -> Generate new token: Repository access nur
  `brain-ios-certificates`; Permissions -> Repository permissions -> Contents:
  **Read and write**. Token notieren (wird nur einmal angezeigt).

### 4. Secrets im brain-ios-Repo

GitHub -> brain-ios -> Settings -> Secrets and variables -> Actions ->
New repository secret:

| Secret | Inhalt |
|---|---|
| `BRAIN_BUNDLE_ID_BASE` | echte Bundle-ID-Basis, z.B. `ch.beispiel.brain` |
| `BRAIN_TEAM_ID` | Team-ID (developer.apple.com -> Membership) |
| `BRAIN_GOOGLE_CLIENT_ID` | optional: Google-OAuth-Client-ID ohne `.apps.googleusercontent.com` |
| `ASC_KEY_ID` | Key ID aus Schritt 1 |
| `ASC_ISSUER_ID` | Issuer ID aus Schritt 1 |
| `ASC_API_KEY_P8` | kompletter Inhalt der `.p8`-Datei, inklusive BEGIN- und END-Zeile |
| `MATCH_PAT` | Token aus Schritt 3 |
| `MATCH_PASSWORD` | frei gewaehltes, starkes Passwort; verschluesselt die Zertifikate im Repo |
| `MATCH_GIT_URL` | optional, nur wenn das Zertifikats-Repo anders heisst als `brain-ios-certificates` |

Variable (Reiter "Variables", kein Secret): `BUILD_NUMBER_OFFSET`, nur noetig,
wenn TestFlight meldet, die Build-Nummer muesse hoeher sein. Default 1000;
Build-Nummer = Offset + Run-Nummer des Workflows.

## Build ausloesen

GitHub -> brain-ios -> Actions -> **TestFlight** -> Run workflow -> Branch `main`
-> Run workflow. Dauer etwa 15 bis 25 Minuten. Danach: App Store Connect ->
Brain -> TestFlight; der Build erscheint nach Apples Verarbeitung. Falls die
Gruppe "Intern" ihn nicht automatisch erhaelt, den Build der Gruppe zuweisen.
Auf dem iPhone in der TestFlight-App installieren.

## Was der Workflow tut

1. Schreibt `Config/Local.xcconfig` aus den Secrets (wie `ci_post_clone.sh` bei
   Xcode Cloud); das oeffentliche Repo bleibt anonym.
2. `match`: legt beim ersten Lauf ein Apple-Distribution-Zertifikat und drei
   App-Store-Profile (App, Share Extension, Widgets) an und speichert sie
   verschluesselt im Zertifikats-Repo; spaetere Laeufe verwenden sie wieder.
3. Archiviert die Release-Konfiguration mit manueller Signierung, Build-Nummer
   = Offset + Run-Nummer.
4. Laedt die IPA zu TestFlight hoch (`pilot`). Die IPA wird nie als Artifact
   gespeichert, weil Artifacts eines oeffentlichen Repos oeffentlich sind.

## Fehlerbilder

- "Could not find App ID with bundle identifier": bis 03.09.2026 typischerweise ein
  Zeilenumbruch am Ende eines eingefuegten Secrets; der Workflow trimmt Secrets
  seither selbst. Die Liste "Available apps" darunter zeigt, was Apple kennt.
- "Secret X fehlt": Schritt 4 unvollstaendig.
- Entitlements- oder Provisioning-Fehler beim Signieren: Capability, Gruppe oder
  Container im Developer-Portal fehlt (Schritt 2). Danach Workflow erneut starten.
- "Maximum number of certificates": alte Apple-Distribution-Zertifikate im Portal
  widerrufen (Certificates), falls fruehere Setups welche hinterlassen haben.
- Build-Nummer abgelehnt: Variable `BUILD_NUMBER_OFFSET` erhoehen.
- Compiler-Fehler: Step "Show build errors" zeigt die `error:`-Zeilen.

Sicherheit: GitHub maskiert Secret-Werte in den oeffentlichen Logs; Zertifikate
und Profile liegen nur verschluesselt im privaten Repo; der API-Key nur als Secret.
