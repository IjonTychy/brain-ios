import Foundation

// Calendar, Reminders, Files, Storage, Location, HTTP, Bluetooth, HomeKit,
// Scanner, Camera, Audio, Health, Sensors, Stopwatch, Signal, Morse, Image tool definitions.
extension BrainTools {

    static let systemTools: [ToolDefinition] = [
        // MARK: - Calendar
        ToolDefinition(
            name: "calendar_list",
            description: "Listet heutige Kalender-Events auf (via iOS EventKit).",
            inputSchema: [
                "type": "object",
                "properties": [:]
            ]
        ),
        ToolDefinition(
            name: "calendar_create",
            description: "Erstellt einen neuen Kalender-Event.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "Titel des Events"],
                    "startDate": ["type": "string", "description": "Start-Zeitpunkt (ISO 8601 Format)"],
                    "duration": ["type": "integer", "description": "Dauer in Minuten (Standard: 60)"],
                    "location": ["type": "string", "description": "Ort"],
                    "notes": ["type": "string", "description": "Notizen"]
                ],
                "required": ["title", "startDate"]
            ]
        ),
        ToolDefinition(
            name: "calendar_delete",
            description: "Löscht einen Kalender-Event.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Event-ID aus dem Kalender"]
                ],
                "required": ["id"]
            ]
        ),
        ToolDefinition(
            name: "calendar_update",
            description: "Aktualisiert einen bestehenden Kalender-Termin (Titel, Start, Ende).",
            inputSchema: ["type": "object", "properties": [
                "eventId": ["type": "string", "description": "Event-Identifier"],
                "title": ["type": "string", "description": "Neuer Titel"],
                "startDate": ["type": "string", "description": "Neues Startdatum (ISO8601)"],
                "endDate": ["type": "string", "description": "Neues Enddatum (ISO8601)"],
            ], "required": ["eventId"]]
        ),

        // MARK: - Reminders
        ToolDefinition(
            name: "reminder_set",
            description: "Setzt eine Erinnerung als lokale iOS-Notification.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "Titel der Erinnerung"],
                    "body": ["type": "string", "description": "Optionaler Beschreibungstext"],
                    "minutes": ["type": "integer", "description": "In wie vielen Minuten erinnert werden soll"],
                    "date": ["type": "string", "description": "Alternativ: fester Zeitpunkt (ISO 8601)"]
                ],
                "required": ["title"]
            ]
        ),
        ToolDefinition(
            name: "reminder_cancel",
            description: "Storniert eine geplante Erinnerung.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "ID der Erinnerung"]
                ],
                "required": ["id"]
            ]
        ),
        ToolDefinition(
            name: "reminder_list",
            description: "Listet alle geplanten Erinnerungen auf.",
            inputSchema: [
                "type": "object",
                "properties": [:]
            ]
        ),
        ToolDefinition(
            name: "reminder_pendingCount",
            description: "Gibt die Anzahl ausstehender Erinnerungen zurück.",
            inputSchema: [
                "type": "object",
                "properties": [:]
            ]
        ),

        // MARK: - Location
        ToolDefinition(
            name: "location_current",
            description: "Gibt den aktuellen Standort des Geräts zurück (Breitengrad, Längengrad).",
            inputSchema: [
                "type": "object",
                "properties": [:]
            ]
        ),
        ToolDefinition(
            name: "location_geofence",
            description: "Richtet einen Geofence ein. Benachrichtigt bei Betreten/Verlassen eines Bereichs.",
            inputSchema: ["type": "object", "properties": [
                "latitude": ["type": "number", "description": "Breitengrad"],
                "longitude": ["type": "number", "description": "Längengrad"],
                "radius": ["type": "number", "description": "Radius in Metern (Standard: 100)"],
                "identifier": ["type": "string", "description": "Eindeutiger Name für den Geofence"],
            ], "required": ["latitude", "longitude"]]
        ),

        // MARK: - File operations
        ToolDefinition(
            name: "file_read",
            description: "Liest eine Datei aus dem Brain-Dokumentenordner. Gibt den Textinhalt zurück.",
            inputSchema: ["type": "object", "properties": [
                "path": ["type": "string", "description": "Relativer Pfad im Dokumentenordner"],
            ], "required": ["path"]]
        ),
        ToolDefinition(
            name: "file_write",
            description: "Schreibt eine Datei in den Brain-Dokumentenordner.",
            inputSchema: ["type": "object", "properties": [
                "path": ["type": "string", "description": "Relativer Pfad im Dokumentenordner"],
                "content": ["type": "string", "description": "Dateiinhalt"],
            ], "required": ["path", "content"]]
        ),
        ToolDefinition(
            name: "file_delete",
            description: "Löscht eine Datei aus dem Brain-Dokumentenordner.",
            inputSchema: ["type": "object", "properties": [
                "path": ["type": "string", "description": "Relativer Pfad im Dokumentenordner"],
            ], "required": ["path"]]
        ),

        // MARK: - HTTP
        ToolDefinition(
            name: "http_request",
            description: "Sendet eine HTTPS-Anfrage. Nur HTTPS erlaubt. Nutze dieses Tool um Daten von APIs abzurufen oder zu senden.",
            inputSchema: ["type": "object", "properties": [
                "url": ["type": "string", "description": "HTTPS-URL"],
                "method": ["type": "string", "enum": ["GET", "POST", "PUT", "DELETE"], "description": "HTTP-Methode (Standard: GET)"],
                "body": ["type": "string", "description": "Request-Body (JSON)"],
            ], "required": ["url"]]
        ),

        // MARK: - Storage
        ToolDefinition(
            name: "storage_get",
            description: "Liest einen gespeicherten Wert aus dem lokalen Schluessel-Wert-Speicher.",
            inputSchema: ["type": "object", "properties": [
                "key": ["type": "string", "description": "Schluessel"],
            ], "required": ["key"]]
        ),
        ToolDefinition(
            name: "storage_set",
            description: "Speichert einen Wert im lokalen Schluessel-Wert-Speicher.",
            inputSchema: ["type": "object", "properties": [
                "key": ["type": "string", "description": "Schluessel"],
                "value": ["type": "string", "description": "Wert"],
            ], "required": ["key", "value"]]
        ),

        // MARK: - Bluetooth
        ToolDefinition(
            name: "bluetooth_scan",
            description: "Sucht nach BLE-Geräten in der Nähe.",
            inputSchema: ["type": "object", "properties": [
                "duration": ["type": "number", "description": "Scan-Dauer in Sekunden (Standard: 5, Max: 30)"],
            ] as [String: Any]]
        ),

        // MARK: - HomeKit
        ToolDefinition(
            name: "home_scene",
            description: "Aktiviert eine HomeKit-Szene (z.B. 'Gute Nacht', 'Filmabend').",
            inputSchema: ["type": "object", "properties": [
                "name": ["type": "string", "description": "Name der Szene"],
            ], "required": ["name"]]
        ),
        ToolDefinition(
            name: "home_device",
            description: "Listet oder steuert HomeKit-Geräte.",
            inputSchema: ["type": "object", "properties": [
                "mode": ["type": "string", "enum": ["list", "control"], "description": "list = Geräte auflisten, control = Gerät steuern"],
            ] as [String: Any]]
        ),

        // MARK: - Scanner / Kamera
        ToolDefinition(
            name: "scan_text",
            description: """
            OCR-Texterkennung auf einem Bild. Erkennt Text in einem Base64-kodierten Bild \
            und gibt den erkannten Text zurück. Nutze dieses Tool wenn der User Text aus \
            einem Foto oder Screenshot extrahieren will.
            """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "imageData": ["type": "string", "description": "Base64-kodierte Bilddaten (PNG/JPEG)"]
                ],
                "required": ["imageData"]
            ]
        ),

        // MARK: - Camera
        ToolDefinition(
            name: "camera_capture",
            description: """
            Nimmt ein Foto mit der Kamera auf. Erfordert physische Interaktion — \
            das Ergebnis wird über die UI ausgeloest. Nutze dieses Tool wenn der \
            User ein Foto machen will.
            """,
            inputSchema: [
                "type": "object",
                "properties": [:] as [String: Any],
            ]
        ),

        // MARK: - Audio
        ToolDefinition(
            name: "audio_record",
            description: """
            Nimmt Audio über das Mikrofon auf. Gibt die URL der Aufnahme zurück. \
            Nutze dieses Tool wenn der User eine Sprachnotiz oder Audioaufnahme machen will.
            """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "Aufnahmedauer in Sekunden (Standard: 30, Max: 300)"],
                    "quality": ["type": "string", "enum": ["low", "medium", "high"], "description": "Audioqualitaet (Standard: medium)"],
                ],
            ]
        ),
        ToolDefinition(
            name: "audio_play",
            description: "Spielt eine lokale Audiodatei ab. Erwartet eine file:// URL.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "file:// URL der Audiodatei"],
                ],
                "required": ["url"],
            ]
        ),

        // MARK: - Health
        ToolDefinition(
            name: "health_read",
            description: """
            Liest Gesundheitsdaten aus HealthKit. Unterstuetzte Typen: steps (Schritte), \
            heartrate (Herzfrequenz), calories (Kalorien), distance (Strecke), weight (Gewicht), \
            water (Wasser), oxygen (Sauerstoff), temperature (Temperatur). \
            Nutze dieses Tool wenn der User nach seinen Gesundheitsdaten fragt.
            """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "type": ["type": "string", "description": "Gesundheitsdaten-Typ (z.B. 'steps', 'heartrate', 'weight')"],
                    "mode": ["type": "string", "enum": ["today", "recent"], "description": "today = Tagessumme, recent = letzte Messwerte (Standard: today)"],
                    "limit": ["type": "integer", "description": "Anzahl Messwerte bei mode=recent (Standard: 10)"],
                ],
                "required": ["type"],
            ]
        ),
        ToolDefinition(
            name: "health_write",
            description: """
            Speichert einen Gesundheitswert in HealthKit. Unterstuetzte Typen: weight, water, temperature. \
            Nutze dieses Tool wenn der User einen Messwert eintragen will.
            """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "type": ["type": "string", "description": "Gesundheitsdaten-Typ (z.B. 'weight', 'water')"],
                    "value": ["type": "number", "description": "Messwert (z.B. 75.5 für Gewicht in kg)"],
                ],
                "required": ["type", "value"],
            ]
        ),

        // MARK: - Image analysis
        ToolDefinition(
            name: "image_detectText",
            description: "Erkennt Text in einem Bild mit Positionen für jeden Buchstaben. Gibt Zeichen, Bounding Boxes und Konfidenz zurück. Für OCR mit Positionen, Font-Erstellung, AR-Overlays, Übersetzungs-Overlays.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "imageData": ["type": "string", "description": "Base64-kodiertes Bild"]
                ],
                "required": ["imageData"]
            ]
        ),
        ToolDefinition(
            name: "image_traceContours",
            description: "Erkennt Konturen in einem Bild(ausschnitt) und gibt Vektordaten zurück. Für Font-Vektorisierung, Logo-Tracing, Silhouetten-Extraktion, Schablonen-Erstellung.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "imageData": ["type": "string", "description": "Base64-kodiertes Bild"],
                    "x": ["type": "number", "description": "X-Position des Ausschnitts (optional, ohne = ganzes Bild)"],
                    "y": ["type": "number", "description": "Y-Position des Ausschnitts"],
                    "width": ["type": "number", "description": "Breite des Ausschnitts"],
                    "height": ["type": "number", "description": "Hoehe des Ausschnitts"]
                ],
                "required": ["imageData"]
            ]
        ),
        ToolDefinition(
            name: "svg_generate",
            description: "Erzeugt eine SVG-Datei aus benannten Vektorpfaden. Format 'font' für SVG-Font, 'shapes' für SVG-Grafik. Speichert im Documents-Ordner.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Dateiname (Standard: output)"],
                    "format": ["type": "string", "enum": ["font", "shapes"], "description": "SVG-Format: font oder shapes"],
                    "paths": ["type": "object", "description": "Dictionary: Name → {width, height, paths: [[{x,y}]]}"]
                ],
                "required": ["paths"]
            ]
        ),

        // MARK: - Signal analysis
        ToolDefinition(
            name: "signal_analyzeAudio",
            description: "Analysiert Audio-Amplitude über Mikrofon und erkennt An/Aus-Muster. Für Morse-Code, Rhythmus-Erkennung, Klopfmuster, Lärmmonitoring.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "Aufnahmedauer in Sekunden (Standard: 10, Max: 60)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "signal_analyzeBrightness",
            description: "Analysiert Helligkeitsänderungen via Kamera und erkennt An/Aus-Muster. Für Morse-Taschenlampe, LED-Blinkmuster, Beacon-Erkennung.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "Aufnahmedauer in Sekunden (Standard: 15, Max: 60)"]
                ],
                "required": []
            ]
        ),

        // MARK: - Morse code
        ToolDefinition(
            name: "morse_decode",
            description: "Dekodiert Morse-Code-Text (Punkte und Striche) in Klartext. '... --- ...' → 'SOS'",
            inputSchema: [
                "type": "object",
                "properties": [
                    "morseCode": ["type": "string", "description": "Morse-Code (. und -, Leerzeichen zwischen Buchstaben, 3 Leerzeichen zwischen Wörtern)"]
                ],
                "required": ["morseCode"]
            ]
        ),
        ToolDefinition(
            name: "morse_encode",
            description: "Kodiert Klartext in Morse-Code. 'SOS' → '... --- ...'",
            inputSchema: [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "Text zum Kodieren"]
                ],
                "required": ["text"]
            ]
        ),
        ToolDefinition(
            name: "morse_decodeAudio",
            description: "Hoert über Mikrofon zu und dekodiert Morse-Pieptoene in Klartext (Convenience: signal.analyzeAudio + morse.decode).",
            inputSchema: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "Aufnahmedauer in Sekunden (Standard: 10, Max: 60)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "morse_decodeVisual",
            description: "Nutzt Kamera um Morse-Lichtsignale (Taschenlampe, LED) in Klartext zu dekodieren (Convenience: signal.analyzeBrightness + morse.decode).",
            inputSchema: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "Aufnahmedauer in Sekunden (Standard: 15, Max: 60)"]
                ],
                "required": []
            ]
        ),

        // MARK: - Sensor data (Phyphox-style)
        ToolDefinition(
            name: "sensor_accelerometer",
            description: "Liest Beschleunigungsdaten (in G) vom Accelerometer. Für Vibrationsmessung, Neigungssensor, Wasserwaage, Schrittzähler, Erdbebendetector.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "Messdauer in Sekunden (Standard: 5, Max: 60)"],
                    "sampleRate": ["type": "number", "description": "Abtastrate in Hz (Standard: 50, Max: 100)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "sensor_gyroscope",
            description: "Liest Drehrate (in rad/s) vom Gyroskop. Für Rotationsmessung, Pendel-Experimente, Spin-Erkennung.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "Messdauer in Sekunden (Standard: 5, Max: 60)"],
                    "sampleRate": ["type": "number", "description": "Abtastrate in Hz (Standard: 50, Max: 100)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "sensor_magnetometer",
            description: "Liest Magnetfeld (in µT) vom Magnetometer. Für Kompass, Metalldetektor, elektromagnetische Feldmessung.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "Messdauer in Sekunden (Standard: 5, Max: 60)"],
                    "sampleRate": ["type": "number", "description": "Abtastrate in Hz (Standard: 50, Max: 100)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "sensor_barometer",
            description: "Liest Luftdruck (kPa) und relative Höhenveraenderung vom Barometer. Für Wetterstation, Höhenmesser, Stockwerk-Erkennung.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "Messdauer in Sekunden (Standard: 5, Max: 60)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "sensor_deviceMotion",
            description: "Liest fusionierte Bewegungsdaten (Neigung, Schwerkraft, Beschleunigung, Magnetfeld, Kompass). Präziseste Messung. Für Wasserwaage, AR, Gesten.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "Messdauer in Sekunden (Standard: 5, Max: 60)"],
                    "sampleRate": ["type": "number", "description": "Abtastrate in Hz (Standard: 50, Max: 100)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "sensor_proximity",
            description: "Liest den Näherungssensor (nah/fern). Für Taschendetector, Handgesten, automatische Bildschirmabschaltung.",
            inputSchema: [
                "type": "object",
                "properties": [:],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "sensor_battery",
            description: "Liest Batteriestatus (Ladestand, Ladezustand). Für Batterie-Monitor, Energiespar-Skills.",
            inputSchema: [
                "type": "object",
                "properties": [:],
                "required": []
            ]
        ),

        // MARK: - Audio analysis (Phyphox-style)
        ToolDefinition(
            name: "audio_amplitude",
            description: "Misst Audio-Amplitude (RMS, Peak, dB) über Zeit. Für Applausmeter, Lärmmessung, Lautstärke-Monitoring. Gibt Zeitreihe mit RMS, Peak und dB zurück.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "Messdauer in Sekunden (Standard: 5, Max: 60)"],
                    "sampleRate": ["type": "number", "description": "Abtastrate in Hz (Standard: 50)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "audio_spectrum",
            description: "Berechnet das Frequenz-Spektrum via FFT. Zeigt welche Frequenzen im Signal enthalten sind. Für Spektralanalyse, Oberton-Erkennung, Klanganalyse.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "Aufnahmedauer in Sekunden (Standard: 2, Max: 30)"],
                    "fftSize": ["type": "integer", "description": "FFT-Grösse (Standard: 4096, Potenz von 2)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "audio_pitch",
            description: "Erkennt die Grundfrequenz (Tonhöhe) via Autokorrelation. Gibt Frequenz in Hz, Notenname, Oktave und Cents-Abweichung zurück. Für Stimmgerät, Tonhöhenmessung.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "Messdauer in Sekunden (Standard: 3, Max: 30)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "audio_oscilloscope",
            description: "Nimmt Wellenform-Daten auf (Oszilloskop). Gibt Zeitreihe der Amplituden-Samples zurück. Für Wellenform-Visualisierung, Signal-Analyse.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "Aufnahmedauer in Sekunden (Standard: 0.1, Max: 2)"],
                    "sampleRate": ["type": "number", "description": "Abtastrate in Hz (Standard: 44100)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "audio_tone",
            description: "Generiert einen Sinuston mit bestimmter Frequenz. Für Tongenerator, Stimmgabel, Hoertest, akustische Experimente.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "frequency": ["type": "number", "description": "Frequenz in Hz (Standard: 440, Bereich: 20-20000)"],
                    "duration": ["type": "number", "description": "Dauer in Sekunden (Standard: 1, Max: 30)"],
                    "volume": ["type": "number", "description": "Lautstärke 0.0-1.0 (Standard: 0.5)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "audio_sonar",
            description: "Sendet einen kurzen Chirp-Ton und misst die Echo-Laufzeit. Berechnet Entfernung basierend auf Schallgeschwindigkeit (~343 m/s). Für Entfernungsmessung, Raumgroesse.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "frequency": ["type": "number", "description": "Chirp-Frequenz in Hz (Standard: 5000)"],
                    "maxDistance": ["type": "number", "description": "Maximale Entfernung in Metern (Standard: 10)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "audio_frequencyTrack",
            description: "Verfolgt Frequenzänderungen über Zeit. Für Dopplereffekt-Messung, Frequenzverlauf, Tonhöhen-Tracking. Optional mit Referenzfrequenz für Shift-Berechnung.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "Messdauer in Sekunden (Standard: 10, Max: 60)"],
                    "referenceFrequency": ["type": "number", "description": "Referenzfrequenz in Hz für Shift-Berechnung (optional)"]
                ],
                "required": []
            ]
        ),

        // MARK: - Sensor spectrum (FFT on motion sensor data)
        ToolDefinition(
            name: "sensor_accSpectrum",
            description: "Berechnet das Frequenz-Spektrum der Beschleunigungsdaten via FFT. Zeigt periodische Bewegungen (Vibrationen, Oszillationen, Schrittfrequenz). Achse: x/y/z/magnitude.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "Messdauer in Sekunden (Standard: 5, Max: 60)"],
                    "sampleRate": ["type": "number", "description": "Abtastrate in Hz (Standard: 100)"],
                    "axis": ["type": "string", "enum": ["x", "y", "z", "magnitude"], "description": "Achse (Standard: magnitude)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "sensor_gyroSpectrum",
            description: "Berechnet das Frequenz-Spektrum der Gyroskop-Daten via FFT. Zeigt Rotations-Oszillationen, Wobble-Frequenzen.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "Messdauer in Sekunden (Standard: 5, Max: 60)"],
                    "sampleRate": ["type": "number", "description": "Abtastrate in Hz (Standard: 100)"],
                    "axis": ["type": "string", "enum": ["x", "y", "z", "magnitude"], "description": "Achse (Standard: magnitude)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "sensor_magSpectrum",
            description: "Berechnet das Frequenz-Spektrum der Magnetfelddaten via FFT. Erkennt oszillierende Magnetfelder, Wechselstrom-Interferenz (50/60 Hz).",
            inputSchema: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "Messdauer in Sekunden (Standard: 5, Max: 60)"],
                    "sampleRate": ["type": "number", "description": "Abtastrate in Hz (Standard: 100)"],
                    "axis": ["type": "string", "enum": ["x", "y", "z", "magnitude"], "description": "Achse (Standard: magnitude)"]
                ],
                "required": []
            ]
        ),

        // MARK: - Camera analysis
        ToolDefinition(
            name: "camera_color",
            description: "Bestimmt die Farbe im Kamerabild (HSV + RGB + Hex). Analysiert den Mittelpunkt des Bildes. Für Farbmessung, Colorimeter, pH-Streifen ablesen.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "regionSize": ["type": "number", "description": "Grösse der Messregion (0.0-1.0, Standard: 0.1 = 10% des Bildes)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "camera_luminance",
            description: "Misst die Helligkeit/Leuchtdichte über Zeit via Kamera. Gibt Zeitreihe der Helligkeitswerte (0.0-1.0) zurück. Für Leuchtdichtemessung, optische Experimente.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "duration": ["type": "number", "description": "Messdauer in Sekunden (Standard: 5, Max: 60)"],
                    "sampleRate": ["type": "number", "description": "Abtastrate in Hz (Standard: 30)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "camera_depth",
            description: "Misst Entfernungen mit dem LiDAR/ToF-Tiefensensor (nur Pro-Modelle). Gibt Tiefe am Mittelpunkt und Statistiken (min/max/avg) in Metern zurück.",
            inputSchema: [
                "type": "object",
                "properties": [:],
                "required": []
            ]
        ),

        // MARK: - Stopwatch experiments
        ToolDefinition(
            name: "stopwatch_acoustic",
            description: "Misst die Zeit zwischen zwei lauten Geraueschen (Klatschen, Schnipsen). Für Schallgeschwindigkeit, Reaktionszeit, Echo-Messung.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "threshold": ["type": "number", "description": "Lautstärke-Schwellwert 0.0-1.0 (Standard: 0.1)"],
                    "maxWait": ["type": "number", "description": "Maximale Wartezeit in Sekunden (Standard: 30)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "stopwatch_motion",
            description: "Misst die Zeit zwischen zwei Beschleunigungsspitzen (Stoss, Fall, Erschuetterung). Für Fallzeit, Kollisions-Timing, Pendel-Periode.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "threshold": ["type": "number", "description": "Beschleunigungs-Schwellwert in G (Standard: 1.5)"],
                    "maxWait": ["type": "number", "description": "Maximale Wartezeit in Sekunden (Standard: 30)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "stopwatch_optical",
            description: "Misst die Zeit zwischen zwei Helligkeitsänderungen via Kamera. Für Lichtschranke, LED-Timing, optische Experimente.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "threshold": ["type": "number", "description": "Helligkeitsänderungs-Schwellwert 0.0-1.0 (Standard: 0.2)"],
                    "maxWait": ["type": "number", "description": "Maximale Wartezeit in Sekunden (Standard: 30)"]
                ],
                "required": []
            ]
        ),
        ToolDefinition(
            name: "stopwatch_proximity",
            description: "Misst die Zeit zwischen zwei Näherungssensor-Ereignissen. Für Handwellen-Timing, Objekt-Durchgangs-Erkennung.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "maxWait": ["type": "number", "description": "Maximale Wartezeit in Sekunden (Standard: 30)"]
                ],
                "required": []
            ]
        ),
    ]
}
