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

}
