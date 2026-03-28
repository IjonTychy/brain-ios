# TestFlight Build & Upload — Anleitung

> Stand: 19.03.2026 | Voraussetzung: Apple Developer Membership muss aktiv sein

## Voraussetzungen pruefen

1. **Apple Developer Membership aktiv?**
   - https://developer.apple.com/account -> Membership -> Status muss "Active" sein
   - Falls "In Process": warten

2. **SSH-Tunnel zum XcodeClub-Mac aktiv?**
   ```bash
   # Auf dem VPS pruefen:
   ss -tlnp | grep 2222
   # Falls nicht aktiv: Andy muss auf dem Mac ausfuehren:
   # ssh -R 2222:localhost:22 -N -f -o ServerAliveInterval=60 ubuntu@YOUR_VPS_IP
   ```

3. **SSH-Zugang zum Mac (vom VPS aus):**
   ```bash
   ssh -i ~/.ssh/id_ed25519 -p 2222 YOUR_MAC_USER@localhost "whoami"
   # Muss "YOUR_MAC_USER" ausgeben
   ```

## Schritt 1: App ID registrieren (falls noch nicht geschehen)

Andy muss auf https://developer.apple.com/account:
1. Certificates, Identifiers & Profiles -> Identifiers -> +
2. App IDs -> App -> Continue
3. Description: Brain, Bundle ID: Explicit -> com.example.brain-ios
4. Register

## Schritt 2: iPhone UDID registrieren

Andy muss auf https://developer.apple.com/account:
1. Devices -> +
2. Device Name: z.B. Andys iPhone
3. UDID: Vom iPhone (Einstellungen -> Allgemein -> Info -> runterscrollen)
4. Register

## Schritt 3: Xcode Signing einrichten

```bash
# Vom VPS aus:
ssh -i ~/.ssh/id_ed25519 -p 2222 YOUR_MAC_USER@localhost "open ~/brain-ios/BrainApp.xcodeproj"
```

In Xcode (per AnyDesk):
- Target "BrainApp" -> Signing & Capabilities
- Team: Andys Developer Account auswaehlen
- "Automatically manage signing" muss an sein
- Warten bis Status gruen ist (kein gelbes Dreieck)
- Falls Keychain-Passwort gefragt: Mac-Passwort eingeben, "Immer erlauben"

## Schritt 4: Keychain entsperren (fuer CLI-Build)

```bash
# Auf dem Mac (via SSH oder AnyDesk Terminal):
security unlock-keychain ~/Library/Keychains/login.keychain-db
# Passwort eingeben wenn gefragt
```

## Schritt 5: Archive erstellen

```bash
ssh -i ~/.ssh/id_ed25519 -p 2222 YOUR_MAC_USER@localhost \
  "cd ~/brain-ios && git pull origin master && xcodebuild archive \
  -project BrainApp.xcodeproj \
  -scheme BrainApp \
  -destination 'generic/platform=iOS' \
  -archivePath ~/BrainApp.xcarchive \
  -allowProvisioningUpdates"
```

Falls "User interaction is not allowed" -> Schritt 4 wiederholen.
Falls "No profiles found" -> Schritt 1-3 pruefen.

## Schritt 6: ExportOptions.plist erstellen

Datei ~/ExportOptions.plist auf dem Mac erstellen mit diesem Inhalt:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>TEAM_ID_HERE</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
    <key>destination</key>
    <string>upload</string>
</dict>
</plist>
```

## Schritt 7: Export & Upload zu App Store Connect

```bash
ssh -i ~/.ssh/id_ed25519 -p 2222 YOUR_MAC_USER@localhost \
  "xcodebuild -exportArchive \
  -archivePath ~/BrainApp.xcarchive \
  -exportOptionsPlist ~/ExportOptions.plist \
  -exportPath ~/BrainAppExport \
  -allowProvisioningUpdates"
```

## Schritt 8: In App Store Connect pruefen

1. https://appstoreconnect.apple.com
2. "My Apps" -> Brain (falls noch nicht angelegt: + New App)
   - Platform: iOS
   - Name: Brain
   - Bundle ID: com.example.brain-ios
   - SKU: brain-ios
3. TestFlight -> Build sollte nach 15-30 Min Processing erscheinen
4. Internal Testing -> Tester hinzufuegen (Andys Apple ID)
5. TestFlight-App auf iPhone oeffnen -> Build installieren

## Projekt-Details

| Feld | Wert |
|------|------|
| Bundle ID | com.example.brain-ios |
| Team ID | TEAM_ID_HERE |
| Xcode-Projekt | ~/brain-ios/BrainApp.xcodeproj |
| Scheme | BrainApp |
| Swift Version | 6.0 |
| Min. iOS | 17.0 |
| Geraete | iPhone, iPad, Vision Pro |
| Marketing Version | 1.0 |
| Build Number | 1 |
| Mac-User | YOUR_MAC_USER |
| Mac-Zugang | SSH via VPS Port 2222 |

---

## Alternative: Xcode Cloud (empfohlen)

Statt manuell auf dem XcodeClub-Mac zu bauen, kann Xcode Cloud den gesamten
Build-und-Upload-Prozess automatisieren. Kein Mac noetig, kein SSH-Tunnel,
kein Keychain-Problem.

### Voraussetzungen
- Aktive Apple Developer Membership
- GitHub-Repo (IjonTychy/brain-ios) — haben wir
- App ID registriert (com.example.brain-ios) — siehe Schritt 1 oben
- 25 Compute-Stunden/Monat gratis

### Einrichtung

1. **App Store Connect** -> https://appstoreconnect.apple.com
2. **Neue App anlegen** (falls noch nicht vorhanden):
   - "My Apps" -> + -> New App
   - Platform: iOS
   - Name: Brain
   - Bundle ID: com.example.brain-ios
   - SKU: brain-ios
3. **Xcode Cloud Tab** -> "Get Started"
4. **GitHub verbinden:**
   - "Connect to GitHub" -> Autorisieren
   - Repository: IjonTychy/brain-ios
   - Branch: master
5. **Workflow erstellen:**
   - Name: "TestFlight Build"
   - Start Condition: Push auf master
   - Action: Archive -> Scheme "BrainApp"
   - Post-Action: TestFlight (Internal Testing)
6. **Signing:** Xcode Cloud verwaltet Zertifikate und Provisioning Profiles
   automatisch. Team ID TEAM_ID_HERE wird aus dem Projekt gelesen.
7. **Start:** Erster Build wird sofort getriggert.

### Workflow-Datei (optional, fuer Feinsteuerung)

Falls noetig kann ein `ci_scripts/ci_post_clone.sh` im Repo liegen:
```bash
#!/bin/bash
# Wird nach dem Klonen ausgefuehrt
# z.B. Swift Package Resolution forcieren:
cd "$CI_PRIMARY_REPOSITORY_PATH"
swift package resolve
```

### Danach

Bei jedem `git push origin master` passiert automatisch:
1. Xcode Cloud klont das Repo
2. Baut das Archive (Release)
3. Signiert mit Apples Managed Signing
4. Laedt zu TestFlight hoch
5. Andy bekommt eine Notification in der TestFlight-App

### Vorteile gegenueber manuellem Build
- Kein XcodeClub-Mac noetig (spart Kosten + Komplexitaet)
- Kein SSH-Tunnel, kein Keychain-Entsperren
- Automatisch bei jedem Push
- Build-Logs in App Store Connect einsehbar
- Signing wird serverseitig gehandelt

---

## Bekannte Probleme

- **VM Auto-Shutdown:** XcodeClub-VM schaltet nach 30-60 Min Inaktivitaet ab.
  Andy muss die VM am Control Panel starten und den SSH-Tunnel neu aufbauen.
- **Kein physisches iPhone am Mac:** TestFlight ist der einzige Weg zum Testen.
- **Info.plist Keys:** NSContactsUsageDescription, NSCalendarsUsageDescription,
  NSLocationWhenInUseUsageDescription, NSFaceIDUsageDescription sind bereits
  im Xcode-Projekt konfiguriert (via INFOPLIST_KEY_ Build Settings).
- **Build Number erhoehen:** Bei jedem neuen Upload muss CURRENT_PROJECT_VERSION
  im Xcode-Projekt erhoeht werden (1 -> 2 -> 3 etc.).
