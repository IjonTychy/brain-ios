import Foundation
import BrainCore

// Bootstrap Skills: shipped with the app, defined as JSON like any user-generated skill.
// No difference between "built-in" and "generated" — they're all skills.
enum BootstrapSkills {

    // MARK: - Dashboard

    static let dashboard = SkillDefinition(
        id: "dashboard",
        screens: [
            "main": ScreenNode(
                type: "stack",
                properties: ["direction": .string("vertical"), "spacing": .double(16)],
                children: [
                    // Header: Date only (compact)
                    ScreenNode(type: "text", properties: [
                        "value": .string("{{today}}"),
                        "style": .string("subheadline"),
                        "color": .string("#8E8E93"),
                    ]),

                    // Quick stats: 2 tappable columns
                    ScreenNode(type: "grid", properties: [
                        "columns": .int(2),
                        "spacing": .double(10),
                    ], children: [
                        ScreenNode(type: "button", properties: [
                            "title": .string(""),
                            "action": .string("goToMail"),
                            "style": .string("plain"),
                        ], children: [
                            ScreenNode(type: "stat-card", properties: [
                                "title": .string("E-Mails"),
                                "value": .string("{{stats.unreadMails}}"),
                                "suffix": .string("ungelesen"),
                            ]),
                        ]),
                        ScreenNode(type: "button", properties: [
                            "title": .string(""),
                            "action": .string("goToSearch"),
                            "style": .string("plain"),
                        ], children: [
                            ScreenNode(type: "stat-card", properties: [
                                "title": .string("Aufgaben"),
                                "value": .string("{{stats.openTasks}}"),
                                "suffix": .string("offen"),
                            ]),
                        ]),
                    ]),

                    // --- Upcoming Calendar Events ---
                    ScreenNode(type: "conditional", properties: [
                        "condition": .string("todayEvents | count > 0"),
                    ], children: [
                        ScreenNode(type: "text", properties: [
                            "value": .string("Nächste Termine"),
                            "style": .string("headline"),
                        ]),
                        ScreenNode(type: "repeater", properties: [
                            "data": .string("todayEvents"),
                            "as": .string("event"),
                        ], children: [
                            ScreenNode(type: "card", properties: [
                                "icon": .string("calendar"),
                                "title": .string("{{event.title}}"),
                                "subtitle": .string("{{event.time}}"),
                                "detail": .string("{{event.location}}"),
                            ]),
                        ]),
                    ]),

                    // --- Upcoming Birthdays ---
                    ScreenNode(type: "conditional", properties: [
                        "condition": .string("upcomingBirthdays | count > 0"),
                    ], children: [
                        ScreenNode(type: "text", properties: [
                            "value": .string("Geburtstage"),
                            "style": .string("headline"),
                        ]),
                        ScreenNode(type: "repeater", properties: [
                            "data": .string("upcomingBirthdays"),
                            "as": .string("bday"),
                        ], children: [
                            ScreenNode(type: "stack", properties: [
                                "direction": .string("horizontal"),
                                "spacing": .double(10),
                            ], children: [
                                ScreenNode(type: "icon", properties: [
                                    "name": .string("gift.fill"),
                                    "size": .double(18),
                                    "color": .string("#FF6B9D"),
                                ]),
                                ScreenNode(type: "text", properties: [
                                    "value": .string("{{bday.name}}"),
                                    "style": .string("body"),
                                ]),
                                ScreenNode(type: "spacer"),
                                ScreenNode(type: "badge", properties: [
                                    "value": .string("{{bday.label}}"),
                                ]),
                            ]),
                        ]),
                    ]),

                    // --- Open Tasks Section ---
                    ScreenNode(type: "text", properties: [
                        "value": .string("Offene Aufgaben"),
                        "style": .string("headline"),
                    ]),

                    ScreenNode(type: "conditional", properties: [
                        "condition": .string("openTasks | count > 0"),
                    ], children: [
                        // Then: task list
                        ScreenNode(type: "repeater", properties: [
                            "data": .string("openTasks"),
                            "as": .string("task"),
                        ], children: [
                            ScreenNode(type: "stack", properties: [
                                "direction": .string("horizontal"),
                                "spacing": .double(10),
                            ], children: [
                                ScreenNode(type: "button", properties: [
                                    "title": .string(""),
                                    "action": .string("completeTask"),
                                    "icon": .string("circle"),
                                    "style": .string("plain"),
                                ]),
                                ScreenNode(type: "text", properties: [
                                    "value": .string("{{task.title}}"),
                                    "style": .string("body"),
                                ]),
                                ScreenNode(type: "spacer"),
                            ]),
                        ]),
                        // Else: all done
                        ScreenNode(type: "stack", properties: [
                            "direction": .string("horizontal"),
                            "spacing": .double(8),
                        ], children: [
                            ScreenNode(type: "icon", properties: [
                                "name": .string("checkmark.circle.fill"),
                                "size": .double(20),
                                "color": .string("#34C759"),
                            ]),
                            ScreenNode(type: "text", properties: [
                                "value": .string("Keine offenen Aufgaben"),
                                "style": .string("subheadline"),
                                "color": .string("#8E8E93"),
                            ]),
                        ]),
                    ]),

                    // --- Quick Capture ---
                    ScreenNode(type: "stack", properties: [
                        "direction": .string("horizontal"),
                        "spacing": .double(8),
                    ], children: [
                        ScreenNode(type: "text-field", properties: [
                            "placeholder": .string("Schnellerfassung..."),
                            "value": .string("{{quickInput}}"),
                        ]),
                        ScreenNode(type: "button", properties: [
                            "title": .string(""),
                            "action": .string("quickCapture"),
                            "icon": .string("plus.circle.fill"),
                            "style": .string("plain"),
                        ]),
                    ]),
                ]
            ),
        ],
        actions: [
            "quickCapture": ActionDefinition(steps: [
                ActionStep(type: "entry.create", properties: [
                    "title": .string("{{quickInput}}"),
                    "type": .string("thought"),
                ]),
                ActionStep(type: "set", properties: [
                    "quickInput": .string(""),
                ]),
                ActionStep(type: "toast", properties: [
                    "message": .string("Gespeichert!"),
                ]),
            ]),
            "completeTask": ActionDefinition(steps: [
                ActionStep(type: "entry.markDone", properties: [
                    "id": .string("{{task.id}}"),
                ]),
                ActionStep(type: "toast", properties: [
                    "message": .string("Aufgabe erledigt"),
                ]),
            ]),
            "goToMail": ActionDefinition(steps: [
                ActionStep(type: "navigate.tab", properties: [
                    "tab": .string("mail"),
                ]),
            ]),
            "goToSearch": ActionDefinition(steps: [
                ActionStep(type: "navigate.tab", properties: [
                    "tab": .string("search"),
                ]),
            ]),
            "goToCalendar": ActionDefinition(steps: [
                ActionStep(type: "navigate.tab", properties: [
                    "tab": .string("calendar"),
                ]),
            ]),
            "goToChat": ActionDefinition(steps: [
                ActionStep(type: "navigate.tab", properties: [
                    "tab": .string("chat"),
                ]),
            ]),
            "openEntry": ActionDefinition(steps: [
                ActionStep(type: "entry.open", properties: [
                    "id": .string("{{entry.id}}"),
                ]),
            ]),
        ]
    )

    // MARK: - Mail Inbox

    static let mailInbox = SkillDefinition(
        id: "mail-inbox",
        screens: [
            "main": ScreenNode(
                type: "stack",
                properties: ["direction": .string("vertical")],
                children: [
                    ScreenNode(type: "conditional", properties: [
                        "condition": .string("emails | count > 0"),
                    ], children: [
                        ScreenNode(type: "list", properties: [
                            "data": .string("emails"),
                            "as": .string("mail"),
                        ], children: [
                            ScreenNode(type: "stack", properties: [
                                "direction": .string("horizontal"),
                                "spacing": .double(12),
                            ], children: [
                                ScreenNode(type: "avatar", properties: [
                                    "initials": .string("{{mail.fromInitials}}"),
                                    "size": .double(36),
                                ]),
                                ScreenNode(type: "stack", properties: [
                                    "direction": .string("vertical"),
                                    "spacing": .double(2),
                                ], children: [
                                    ScreenNode(type: "text", properties: [
                                        "value": .string("{{mail.from}}"),
                                        "style": .string("headline"),
                                    ]),
                                    ScreenNode(type: "text", properties: [
                                        "value": .string("{{mail.subject}}"),
                                        "style": .string("subheadline"),
                                    ]),
                                    ScreenNode(type: "text", properties: [
                                        "value": .string("{{mail.preview}}"),
                                        "style": .string("caption"),
                                    ]),
                                ]),
                                ScreenNode(type: "spacer"),
                                ScreenNode(type: "text", properties: [
                                    "value": .string("{{mail.time}}"),
                                    "style": .string("caption2"),
                                ]),
                            ]),
                        ]),
                        ScreenNode(type: "empty-state", properties: [
                            "icon": .string("envelope"),
                            "title": .string("Posteingang leer"),
                            "message": .string("Keine neuen E-Mails."),
                        ]),
                    ]),
                ]
            ),
        ]
    )

    // MARK: - Calendar

    static let calendar = SkillDefinition(
        id: "calendar",
        screens: [
            "main": ScreenNode(
                type: "stack",
                properties: ["direction": .string("vertical"), "spacing": .double(16)],
                children: [
                    // Today header
                    ScreenNode(type: "text", properties: [
                        "value": .string("{{today}}"),
                        "style": .string("title2"),
                    ]),

                    // Events
                    ScreenNode(type: "conditional", properties: [
                        "condition": .string("events | count > 0"),
                    ], children: [
                        ScreenNode(type: "repeater", properties: [
                            "data": .string("events"),
                            "as": .string("event"),
                        ], children: [
                            ScreenNode(type: "stack", properties: [
                                "direction": .string("horizontal"),
                                "spacing": .double(12),
                            ], children: [
                                // Time column
                                ScreenNode(type: "stack", properties: [
                                    "direction": .string("vertical"),
                                ], children: [
                                    ScreenNode(type: "text", properties: [
                                        "value": .string("{{event.startTime}}"),
                                        "style": .string("caption"),
                                    ]),
                                    ScreenNode(type: "text", properties: [
                                        "value": .string("{{event.endTime}}"),
                                        "style": .string("caption2"),
                                    ]),
                                ]),
                                // Color bar
                                ScreenNode(type: "divider"),
                                // Event details
                                ScreenNode(type: "stack", properties: [
                                    "direction": .string("vertical"),
                                    "spacing": .double(2),
                                ], children: [
                                    ScreenNode(type: "text", properties: [
                                        "value": .string("{{event.title}}"),
                                        "style": .string("body"),
                                    ]),
                                    ScreenNode(type: "text", properties: [
                                        "value": .string("{{event.location}}"),
                                        "style": .string("caption"),
                                    ]),
                                ]),
                                ScreenNode(type: "spacer"),
                            ]),
                        ]),
                        ScreenNode(type: "empty-state", properties: [
                            "icon": .string("calendar"),
                            "title": .string("Keine Termine heute"),
                            "message": .string("Der Tag ist frei."),
                        ]),
                    ]),
                ]
            ),
        ]
    )

    // MARK: - Mail Config

    // Mail credential setup skill — credentials are captured via the skill form UI
    // and saved directly to Keychain via email.configure action. They NEVER pass through the LLM.
    static let mailConfig = SkillDefinition(
        id: "mail-config",
        screens: [
            "main": ScreenNode(
                type: "stack",
                properties: ["direction": .string("vertical"), "spacing": .double(16)],
                children: [
                    // Header
                    ScreenNode(type: "icon", properties: [
                        "name": .string("envelope.badge.shield.half.filled"),
                        "size": .double(40),
                        "color": .string("#007AFF"),
                    ]),
                    ScreenNode(type: "text", properties: [
                        "value": .string("E-Mail einrichten"),
                        "style": .string("headline"),
                    ]),
                    ScreenNode(type: "text", properties: [
                        "value": .string("IMAP und SMTP für eingehende und ausgehende E-Mails konfigurieren."),
                        "style": .string("caption"),
                    ]),

                    // IMAP Section
                    ScreenNode(type: "text", properties: [
                        "value": .string("Eingehend (IMAP)"),
                        "style": .string("subheadline"),
                    ]),
                    ScreenNode(type: "text-field", properties: [
                        "placeholder": .string("IMAP-Server (z.B. imap.gmail.com)"),
                        "value": .string("{{imapHost}}"),
                    ]),
                    ScreenNode(type: "text-field", properties: [
                        "placeholder": .string("Port (Standard: 993)"),
                        "value": .string("{{imapPort}}"),
                    ]),

                    // SMTP Section
                    ScreenNode(type: "text", properties: [
                        "value": .string("Ausgehend (SMTP)"),
                        "style": .string("subheadline"),
                    ]),
                    ScreenNode(type: "text-field", properties: [
                        "placeholder": .string("SMTP-Server (z.B. smtp.gmail.com)"),
                        "value": .string("{{smtpHost}}"),
                    ]),
                    ScreenNode(type: "text-field", properties: [
                        "placeholder": .string("Port (Standard: 587)"),
                        "value": .string("{{smtpPort}}"),
                    ]),

                    // Credentials Section
                    ScreenNode(type: "text", properties: [
                        "value": .string("Anmeldedaten"),
                        "style": .string("subheadline"),
                    ]),
                    ScreenNode(type: "text-field", properties: [
                        "placeholder": .string("Benutzername / E-Mail"),
                        "value": .string("{{username}}"),
                    ]),
                    ScreenNode(type: "secure-field", properties: [
                        "placeholder": .string("Passwort"),
                        "value": .string("{{password}}"),
                    ]),
                    ScreenNode(type: "text-field", properties: [
                        "placeholder": .string("Absender-Adresse (optional)"),
                        "value": .string("{{address}}"),
                    ]),

                    // Quick Setup Buttons
                    ScreenNode(type: "text", properties: [
                        "value": .string("Schnelleinrichtung"),
                        "style": .string("subheadline"),
                    ]),
                    ScreenNode(type: "stack", properties: [
                        "direction": .string("horizontal"),
                        "spacing": .double(8),
                    ], children: [
                        ScreenNode(type: "button", properties: [
                            "title": .string("Gmail"),
                            "action": .string("prefillGmail"),
                            "style": .string("bordered"),
                        ]),
                        ScreenNode(type: "button", properties: [
                            "title": .string("Outlook"),
                            "action": .string("prefillOutlook"),
                            "style": .string("bordered"),
                        ]),
                        ScreenNode(type: "button", properties: [
                            "title": .string("iCloud"),
                            "action": .string("prefillICloud"),
                            "style": .string("bordered"),
                        ]),
                    ]),

                    // Save Button
                    ScreenNode(type: "button", properties: [
                        "title": .string("Speichern & Testen"),
                        "action": .string("saveMailConfig"),
                    ]),
                ]
            ),
        ],
        actions: [
            "saveMailConfig": ActionDefinition(steps: [
                ActionStep(type: "email.configure", properties: [
                    "imapHost": .string("{{imapHost}}"),
                    "imapPort": .string("{{imapPort}}"),
                    "smtpHost": .string("{{smtpHost}}"),
                    "smtpPort": .string("{{smtpPort}}"),
                    "username": .string("{{username}}"),
                    "password": .string("{{password}}"),
                    "address": .string("{{address}}"),
                ]),
                ActionStep(type: "toast", properties: [
                    "message": .string("E-Mail erfolgreich konfiguriert!"),
                ]),
            ]),
            "prefillGmail": ActionDefinition(steps: [
                ActionStep(type: "set", properties: [
                    "imapHost": .string("imap.gmail.com"),
                    "smtpHost": .string("smtp.gmail.com"),
                    "imapPort": .string("993"),
                    "smtpPort": .string("587"),
                ]),
            ]),
            "prefillOutlook": ActionDefinition(steps: [
                ActionStep(type: "set", properties: [
                    "imapHost": .string("outlook.office365.com"),
                    "smtpHost": .string("smtp.office365.com"),
                    "imapPort": .string("993"),
                    "smtpPort": .string("587"),
                ]),
            ]),
            "prefillICloud": ActionDefinition(steps: [
                ActionStep(type: "set", properties: [
                    "imapHost": .string("imap.mail.me.com"),
                    "smtpHost": .string("smtp.mail.me.com"),
                    "imapPort": .string("993"),
                    "smtpPort": .string("587"),
                ]),
            ]),
        ]
    )

    // MARK: - Quick Capture

    static let quickCapture = SkillDefinition(
        id: "quick-capture",
        screens: [
            "main": ScreenNode(
                type: "stack",
                properties: ["direction": .string("vertical"), "spacing": .double(16)],
                children: [
                    ScreenNode(type: "text-field", properties: [
                        "placeholder": .string("Was denkst du gerade?"),
                        "value": .string("{{input}}"),
                    ]),
                    ScreenNode(type: "button", properties: [
                        "title": .string("Speichern"),
                        "action": .string("save"),
                    ]),
                ]
            ),
        ],
        actions: [
            "save": ActionDefinition(steps: [
                ActionStep(type: "entry.create", properties: [
                    "title": .string("{{input}}"),
                    "type": .string("thought"),
                ]),
                ActionStep(type: "toast", properties: [
                    "message": .string("Gespeichert!"),
                ]),
            ]),
        ]
    )
}
