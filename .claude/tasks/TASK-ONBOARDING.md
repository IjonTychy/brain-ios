# Auftrag: Onboarding-Flow

## Ziel
Neuen Usern einen gefuehrten Einstieg in Brain bieten.
3-5 Screens die Features erklaeren, Berechtigungen anfragen und API-Key einrichten.

## Prioritaet
HOCH fuer TestFlight — ohne Onboarding ist die App fuer Tester nicht verstaendlich.

## Voraussetzung
- App baut und laeuft (Xcode Cloud Build erfolgreich)
- KeychainService existiert (save/read/delete)
- Face ID Implementation existiert (BiometricAuth)
- Input-Bindings funktionieren (Two-Way Bindings)

## Auftraege

### 4.1 Welcome-Screens (Klein)
**Neue Datei:** `Sources/BrainApp/OnboardingView.swift`
- SwiftUI TabView mit PageTabViewStyle (Swipe-Pages)
- 4 Screens:

**Screen 1: Willkommen**
- Brain-Logo (oder SF Symbol "brain.head.profile")
- "Willkommen bei Brain"
- "Dein persoenliches Gehirn auf dem iPhone"
- Weiter-Button

**Screen 2: Features**
- 4 Feature-Icons mit Beschreibung:
  - "Alles an einem Ort" (Gedanken, Tasks, Termine, E-Mails)
  - "KI-Assistent" (Claude versteht deine Daten)
  - "Offline-First" (Alles funktioniert ohne Internet)
  - "Deine Daten, dein Geraet" (Privacy)
- Weiter-Button

**Screen 3: Datenschutz**
- "Deine Daten bleiben auf deinem Geraet"
- "Nur wenn du Claude fragst, werden Daten an die API gesendet"
- "API-Keys werden sicher im iOS Keychain gespeichert"
- "Kein Account noetig, kein Tracking"
- Weiter-Button

**Screen 4: Los geht's**
- "Brain ist bereit!"
- "Starten" Button → Onboarding abschliessen

### 4.2 API-Key Setup (Klein)
**Integriert in OnboardingView oder separater Screen**
- Zwischen Screen 3 und 4 einfuegen
- "Verbinde deinen KI-Assistenten"
- Anthropic API-Key Eingabe (secure-field)
- "Key erhalten? → anthropic.com/api" Link
- "Testen" Button → kurzer API-Call zur Validierung
- Erfolg: Gruener Haken + "Claude ist bereit!"
- Fehler: Roter Hinweis + "Key pruefen"
- "Ueberspringen" Option (App funktioniert auch ohne, nur kein Chat)
- Key → KeychainService.save("anthropic_api_key", key)

### 4.3 Berechtigungen anfragen (Klein)
**Integriert in OnboardingView**
- Nach API-Key, vor "Los geht's"
- Jede Berechtigung einzeln mit Erklaerung:

**Kontakte:**
- Icon: person.2
- "Brain kann deine Kontakte in der People-Ansicht anzeigen"
- "Erlauben" Button → CNContactStore.requestAccess()
- "Nicht jetzt" → ueberspringen

**Kalender:**
- Icon: calendar
- "Brain zeigt deine Termine in der Kalender-Ansicht"
- "Erlauben" Button → EKEventStore.requestAccess()
- "Nicht jetzt" → ueberspringen

**Benachrichtigungen:**
- Icon: bell
- "Brain erinnert dich an faellige Aufgaben"
- "Erlauben" Button → UNUserNotificationCenter.requestAuthorization()
- "Nicht jetzt" → ueberspringen

### 4.4 Face ID Setup (Klein)
**Integriert in OnboardingView**
- Nach Berechtigungen
- "Schuetze Brain mit Face ID"
- Icon: faceid
- "Brain verwendet Face ID, damit nur du Zugriff hast"
- "Aktivieren" Button → Test-Authentifizierung
- "Ohne Face ID fortfahren" → App ungesperrt lassen
- Einstellung in UserDefaults speichern

### 4.5 Erster Entry erstellen (Klein)
**Integriert in letztem Screen oder nach Onboarding**
- "Schreib deinen ersten Gedanken"
- TextField mit Placeholder: "Was beschaeftigt dich gerade?"
- "Speichern" Button → EntryService.create(title: text, type: .thought)
- Optional: Kann uebersprungen werden
- Zeigt wie einfach Brain funktioniert

### 4.6 Onboarding-Flag (Klein)
**Dateien:** `Sources/BrainApp/BrainApp.swift`, `Sources/BrainApp/OnboardingView.swift`
- `UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")`
- In BrainApp.swift:
  ```swift
  @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

  var body: some Scene {
      WindowGroup {
          if hasCompletedOnboarding {
              ContentView()
          } else {
              OnboardingView(onComplete: { hasCompletedOnboarding = true })
          }
      }
  }
  ```
- Face ID Lock Screen kommt NACH dem Onboarding (nicht davor)
- Reset-Option in Settings: "Onboarding erneut anzeigen" (fuer Entwicklung)

## Design-Richtlinien
- Schweizer Deutsch wo moeglich (konsistent mit App)
- Minimalistisch, nicht ueberladen
- Jeder Screen hat maximal 1 Aktion
- Farben: System-Blau fuer primaere Buttons
- Animationen: Subtile Uebergaenge zwischen Screens
- Kein "Skip All" — jeder Screen ist wichtig

## Qualitaetskriterien
- Onboarding erscheint nur beim allerersten App-Start
- Alle Berechtigungen werden korrekt angefragt
- API-Key wird sicher im Keychain gespeichert
- Face ID funktioniert nach Aktivierung
- "Ueberspringen" funktioniert ueberall ohne Crash
- Nach Onboarding: App ist sofort benutzbar
- Onboarding kann in Settings zurueckgesetzt werden
