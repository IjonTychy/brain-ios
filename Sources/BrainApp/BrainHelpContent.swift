import Foundation

// MARK: - BrainHelpContent
// Comprehensive help documentation for all Brain features.
// Used by BrainHelpButton to provide context-aware assistance.

enum BrainHelpContent {

    // MARK: - Full help text by screen

    static func helpText(for screenName: String) -> String {
        let s = screenName.lowercased()
        if s.contains("dashboard") { return dashboard }
        if s.contains("such") { return search }
        if s.contains("chat") { return chat }
        if s.contains("mail") { return mail }
        if s.contains("kontakte") || s.contains("people") { return contacts }
        if s.contains("kalender") || s.contains("calendar") { return calendar }
        if s.contains("skill") { return skills }
        if s.contains("einstellung") || s.contains("settings") { return settings }
        if s.contains("onboarding") { return onboarding }
        if s.contains("datei") || s.contains("file") { return files }
        if s.contains("canvas") || s.contains("capture") { return quickCapture }
        if s.contains("profil") { return profile }
        return general
    }

    // MARK: - General

    static let general = """
    Brain ist dein persoenlicher KI-Assistent fuer iOS.

    HAUPTFUNKTIONEN:
    - Dashboard: Tagesuebersicht mit Kalender, Aufgaben, Dokumenten
    - Suche: Volltextsuche ueber alle Eintraege, Kontakte, Tags
    - Chat: Direkte Konversation mit Brain (verschiedene KI-Modelle)
    - Mail: E-Mail-Verwaltung mit IMAP/SMTP
    - Mehr: Kontakte, Kalender, Dateien, Skills, Wissensbank

    TIPPS:
    - Jeder Screen hat einen Hilfe-Button (?) oben rechts
    - Brain lernt deine Vorlieben ueber die Zeit
    - In den Einstellungen kannst du alles anpassen
    - Wische in Listen nach links fuer Schnellaktionen
    """

    // MARK: - Dashboard

    static let dashboard = """
    DASHBOARD - Deine Tagesuebersicht

    Das Dashboard zeigt dir auf einen Blick:
    - Heute: Termine, Aufgaben und wichtige Eintraege des Tages
    - Kalender: Naechste Termine aus deinem iOS-Kalender
    - Dokumente: Zuletzt bearbeitete Eintraege
    - Brain Pulse: Morgendliches Briefing (wenn aktiviert)

    TILES:
    Jede Kachel (Tile) zeigt eine Zusammenfassung. Tippe darauf fuer Details.
    Die Heute-Kachel beinhaltet auch Kalendereintraege.

    BRAIN AVATAR:
    Der Avatar oben rechts oeffnet den Brain-Assistenten im Dashboard-Kontext.
    Brain kann dir helfen, deinen Tag zu planen oder Informationen zusammenzufassen.

    BRIEFING:
    Morgens zeigt Brain automatisch ein Tages-Briefing an.
    Abends gibt es einen optionalen Tagesrueckblick.
    """

    // MARK: - Search

    static let search = """
    SUCHE - Alles finden

    Die Suche durchsucht alle deine Daten:
    - Eintraege (Notizen, Aufgaben, Dokumente)
    - Kontakte (Name, Email, Telefon)
    - Tags und Kategorien

    FILTER:
    Oben siehst du Filter-Chips nach Typ (Notiz, Aufgabe, etc.).
    Tippe auf einen Chip um nur diesen Typ anzuzeigen.
    Mehrere Filter koennen kombiniert werden.

    SCHNELLAKTIONEN:
    Wische einen Eintrag nach links fuer:
    - Erledigt markieren
    - Archivieren
    - Loeschen

    TIPPS:
    - Die Suche nutzt Volltextsuche (FTS5) - auch Teilwoerter werden gefunden
    - Ohne Suchbegriff siehst du die neuesten Eintraege
    - Autocomplete schlaegt passende Begriffe vor
    """

    // MARK: - Chat

    static let chat = """
    CHAT - Mit Brain sprechen

    Im Chat kommunizierst du direkt mit Brain.

    MODELL-AUSWAHL:
    Oben rechts kannst du das KI-Modell wechseln:
    - Auto: Brain waehlt automatisch das passende Modell (empfohlen)
    - Opus: Staerkstes Modell fuer komplexe Aufgaben
    - Sonnet: Ausgewogen zwischen Qualitaet und Geschwindigkeit
    - Haiku: Schnellstes Modell fuer einfache Fragen

    AUTO-ROUTING:
    Wenn in den Einstellungen Automatisches Routing aktiviert ist,
    waehlt Brain je nach Komplexitaet deiner Frage das beste Modell.
    Du sparst damit Kosten bei einfachen Anfragen.

    SPRACHEINGABE:
    Tippe auf das Mikrofon-Symbol fuer Spracheingabe.
    Brain transkribiert und verarbeitet deine Nachricht.

    TOOL-AUFRUFE:
    Brain kann Aktionen ausfuehren (Eintraege erstellen, Mails senden etc.).
    Bei kritischen Aktionen wirst du vorher um Bestaetigung gebeten.
    """

    // MARK: - Mail

    static let mail = """
    MAIL - E-Mail-Verwaltung

    Brain integriert deine E-Mail-Konten direkt in die App.

    KONTEN EINRICHTEN:
    1. Gehe zu Mail > Einstellungen (Zahnrad-Symbol)
    2. Tippe auf Konto hinzufuegen
    3. Waehle einen Schnell-Preset (Gmail, Outlook, iCloud) oder manuell
    4. Gib deine Zugangsdaten ein
    5. Tippe auf Speichern und Testen
    Nach erfolgreichem Test wird eine Bestaetigung angezeigt.

    POSTFAECHER:
    - Posteingang, Gesendet, Entwuerfe, Archiv, Spam, Papierkorb
    - Ungelesene Nachrichten werden mit einem Badge angezeigt
    - Konten koennen ein-/ausgeklappt werden

    AKTIONEN:
    Wische auf einer Mail nach links fuer:
    - Loeschen / Archivieren / Verschieben / Als gelesen markieren

    TIPPS:
    - Bei Gmail: Verwende ein App-Passwort (nicht dein normales Passwort)
    - Brain kann Mails zusammenfassen - frage im Chat danach
    - Automatische Mail-Synchronisation alle 15 Minuten
    """

    // MARK: - Contacts

    static let contacts = """
    KONTAKTE - Dein Adressbuch

    Brain greift auf dein iOS-Adressbuch zu (mit deiner Erlaubnis).

    FUNKTIONEN:
    - Suchen: Tippe oben in die Suchleiste
    - Sortieren: Tippe auf das Sortier-Symbol (Name, Datum, Firma)
    - Filtern: Nach Gruppen oder Tags filtern
    - Details: Tippe auf einen Kontakt fuer alle Informationen

    KONTAKT-DETAILS:
    - Telefonnummern (tippe zum Anrufen)
    - E-Mail-Adressen (tippe zum Schreiben)
    - Adressen (tippe fuer Karte)
    - Geburtstag und Notizen

    BEARBEITEN:
    Tippe auf Bearbeiten in den Kontakt-Details um Informationen zu aendern.
    Aenderungen werden in dein iOS-Adressbuch zurueckgeschrieben.
    """

    // MARK: - Calendar

    static let calendar = """
    KALENDER - Termine verwalten

    Brain zeigt deine iOS-Kalender-Termine an.

    ANSICHTEN:
    - Tagesansicht: Alle Termine eines Tages
    - Wochenansicht: Ueberblick ueber die Woche
    - Monatsansicht: Kalender-Raster mit Markierungen

    TERMINE:
    Tippe auf einen Tag um dessen Termine zu sehen.
    Tippe auf einen Termin fuer Details.
    Der heutige Tag ist blau hervorgehoben.

    TIPPS:
    - Kalender-Termine erscheinen auch im Dashboard unter Heute
    - Brain kann Termine im Chat zusammenfassen
    """

    // MARK: - Skills

    static let skills = """
    SKILLS - Brains Faehigkeiten

    Skills erweitern Brains Funktionalitaet.

    UEBERSICHT:
    - Features: Eingebaute Funktionen (Profil, Backup, On This Day)
    - Self-Modifier: Regeln und Vorschlaege fuer Brains Verhalten
    - System: Statistiken und Datenbank-Info

    SKILL-DETAILS:
    Tippe auf einen Skill fuer:
    - Beschreibung und Version
    - Berechtigungen die der Skill braucht
    - Aktivieren/Deaktivieren
    - Teilen oder Loeschen

    TAGS UND VERKNUEPFUNGEN:
    Skills koennen Tags haben. Im Sub-Menu Tags und Verknuepfungen
    siehst du alle Tags und wie Skills miteinander verbunden sind.
    """

    // MARK: - Settings

    static let settings = """
    EINSTELLUNGEN - Brain konfigurieren

    LLM-PROVIDER:
    Konfiguriere deine KI-Anbieter:
    - Anthropic (Claude): Opus, Sonnet, Haiku mit Preisen pro Token
    - OpenAI (GPT): GPT-4o und weitere Modelle
    - Google (Gemini): Gemini Pro und weitere
    Jeder Provider braucht einen API-Key.

    SICHERHEIT:
    - Face ID / Touch ID: App-Sperre aktivieren
    - TOFU (Trust On First Use): Geraete-Vertrauensmodell

    TASK-ROUTING:
    Unter Erweitert findest du das automatische Modell-Routing.
    Brain waehlt je nach Aufgabenkomplexitaet das passende Modell.
    Du kannst fuer jede Komplexitaetsstufe ein Modell festlegen.

    PRIVACY-ZONEN:
    Bestimmte Eintraege koennen als privat markiert werden.
    Tags helfen bei der Kategorisierung:
    - Verwende Tags wie privat, arbeit, gesundheit
    - Privacy-Zonen respektieren diese Tags
    - Eintraege in Privacy-Zonen werden nicht an die KI gesendet

    PROXY:
    Fuer Unternehmensumgebungen: JWT-basierte Authentifizierung
    mit 2FA-Unterstuetzung.
    """

    // MARK: - Onboarding

    static let onboarding = """
    ONBOARDING - Brain einrichten

    Willkommen bei Brain! Die Einrichtung besteht aus diesen Schritten:

    1. WILLKOMMEN: Sprachauswahl und Einfuehrung
    2. FEATURES: Ueberblick ueber Brains Faehigkeiten
    3. DATENSCHUTZ: Wie Brain mit deinen Daten umgeht
    4. KI-PROVIDER: Waehle mindestens einen Anbieter
    5. API-KEY: Gib deinen API-Key ein (wird lokal gespeichert)
    6. MAIL: Optional - E-Mail-Konto einrichten
    7. BERECHTIGUNGEN: Kontakte, Kalender, Mitteilungen freischalten
    8. KENNENLERNEN: Brain stellt dir ein paar Fragen
    9. ERSTER EINTRAG: Schreibe deinen ersten Gedanken

    TIPPS:
    - Du kannst Schritte ueberspringen und spaeter nachholen
    - API-Keys werden nur lokal auf deinem Geraet gespeichert
    - Berechtigungen koennen jederzeit in den iOS-Einstellungen geaendert werden
    - Bei Problemen: Tippe auf den Hilfe-Button (?)
    """

    // MARK: - Files

    static let files = """
    DATEIEN - Dokument-Verwaltung

    Brain kann verschiedene Dateitypen verwalten:
    - Markdown-Dateien (.md)
    - Textdateien (.txt)
    - Importierte Dokumente

    IMPORT:
    Tippe auf + um Dateien zu importieren.
    Unterstuetzte Formate: Klartext, Markdown.
    """

    // MARK: - Quick Capture

    static let quickCapture = """
    QUICK CAPTURE - Schnell festhalten

    Erfasse Gedanken, Ideen und Notizen blitzschnell.

    FUNKTIONEN:
    - Texterfassung: Tippe und schreibe los
    - Foto-Import: Fotos als Eintraege speichern

    TIPPS:
    - Quick Capture ist fuer spontane Ideen gedacht
    - Eintraege koennen spaeter kategorisiert werden
    """

    // MARK: - Profile

    static let profile = """
    PROFIL - Dich und Brain anpassen

    DEIN PROFIL:
    Beschreibe dich selbst in Markdown. Brain nutzt diese
    Informationen um Antworten besser auf dich zuzuschneiden.

    BRAIN PROFIL:
    Passe Brains Persoenlichkeit an:
    - Name: Wie soll Brain heissen?
    - Stil: Formell, freundlich, humorvoll etc.
    - Humor-Regler: Wie viel Humor soll Brain zeigen?
    - Avatar: Waehle ein Bild fuer Brain

    KENNENLERNEN:
    Brain stellt dir Fragen um dich besser kennenzulernen.
    Die Antworten werden als Wissensfakten gespeichert.
    """
}
