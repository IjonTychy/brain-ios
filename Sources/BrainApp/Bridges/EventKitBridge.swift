import EventKit
import UIKit
import BrainCore

// Bridge between Action Primitives and iOS EventKit framework.
// Provides calendar.list, calendar.create, calendar.update, calendar.delete,
// reminder.schedule, reminder.list.
@MainActor
final class EventKitBridge {
    // @MainActor: EKEventStore operations should run on main thread.
    private let store = EKEventStore()

    // M6: Calendar access state for graceful degradation
    enum CalendarAccessState {
        case authorized, denied, notDetermined
    }

    func calendarAccessState() -> CalendarAccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: return .authorized
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
    }

    func reminderAccessState() -> CalendarAccessState {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized: return .authorized
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
    }

    // Request access to calendar events.
    func requestCalendarAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    // Request access to reminders.
    func requestRemindersAccess() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    // MARK: - Calendar Events

    // List events in a date range.
    func listEvents(from startDate: Date, to endDate: Date, limit: Int = 50) -> [EventInfo] {
        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = store.events(matching: predicate)
        return Array(events.prefix(limit)).map { EventInfo(from: $0) }
    }

    // List today's events.
    func todayEvents() -> [EventInfo] {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        return listEvents(from: start, to: end)
    }

    // Create a new calendar event.
    func createEvent(title: String, startDate: Date, endDate: Date, notes: String? = nil, location: String? = nil) throws -> String {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes
        event.location = location
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    // Update an existing calendar event.
    func updateEvent(identifier: String, title: String?, startDate: String?, endDate: String?) throws -> EventInfo? {
        guard let event = store.event(withIdentifier: identifier) else { return nil }
        let formatter = ISO8601DateFormatter()
        if let title { event.title = title }
        if let startDate, let date = formatter.date(from: startDate) { event.startDate = date }
        if let endDate, let date = formatter.date(from: endDate) { event.endDate = date }
        try store.save(event, span: .thisEvent)
        return EventInfo(from: event)
    }

    // Delete a calendar event.
    func deleteEvent(identifier: String) throws {
        guard let event = store.event(withIdentifier: identifier) else { return }
        try store.remove(event, span: .thisEvent)
    }

    // MARK: - Reminders

    // List incomplete reminders.
    func listReminders() async -> [ReminderInfo] {
        let calendars = store.calendars(for: .reminder)
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: calendars
        )

        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let infos = (reminders ?? []).map { ReminderInfo(from: $0) }
                continuation.resume(returning: infos)
            }
        }
    }

    // Schedule a new reminder.
    func scheduleReminder(title: String, dueDate: Date?, notes: String? = nil) throws -> String {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = store.defaultCalendarForNewReminders()

        if let dueDate {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.dueDateComponents = components
        }

        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }
}

// Lightweight event representation for skills.
struct EventInfo: Sendable {
    let identifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String
    let isAllDay: Bool
    let calendarName: String

    let calendarColorHex: String

    init(from event: EKEvent) {
        self.identifier = event.eventIdentifier
        self.title = event.title ?? ""
        self.startDate = event.startDate
        self.endDate = event.endDate
        self.location = event.location ?? ""
        self.isAllDay = event.isAllDay
        self.calendarName = event.calendar?.title ?? ""
        // Extract calendar color from iOS as hex string
        if let cgColor = event.calendar?.cgColor {
            let uiColor = UIColor(cgColor: cgColor)
            var r: CGFloat = 0; var g: CGFloat = 0; var b: CGFloat = 0
            uiColor.getRed(&r, green: &g, blue: &b, alpha: nil)
            self.calendarColorHex = String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        } else {
            self.calendarColorHex = "#007AFF"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var expressionValue: ExpressionValue {
        return .object([
            "id": .string(identifier),
            "title": .string(title),
            "startTime": .string(Self.timeFormatter.string(from: startDate)),
            "endTime": .string(Self.timeFormatter.string(from: endDate)),
            "location": .string(location),
            "isAllDay": .bool(isAllDay),
            "calendar": .string(calendarName),
            "calendarColor": .string(calendarColorHex),
        ])
    }
}

// Lightweight reminder representation.
struct ReminderInfo: Sendable {
    let identifier: String
    let title: String
    let isCompleted: Bool

    init(from reminder: EKReminder) {
        self.identifier = reminder.calendarItemIdentifier
        self.title = reminder.title ?? ""
        self.isCompleted = reminder.isCompleted
    }
}

// MARK: - Action Handlers

@MainActor
final class CalendarListHandler: ActionHandler {
    let type = "calendar.list"
    private let bridge = EventKitBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        // M6: Graceful degradation when calendar access is denied
        switch bridge.calendarAccessState() {
        case .denied:
            return .actionError(
                code: "calendar.access_denied",
                message: "Kalender-Zugriff nicht erlaubt. Bitte in den Einstellungen aktivieren."
            )
        case .notDetermined:
            _ = try? await bridge.requestCalendarAccess()
        case .authorized:
            break
        }
        let events = bridge.todayEvents()
        return .value(.array(events.map(\.expressionValue)))
    }
}

@MainActor
final class ReminderListHandler: ActionHandler {
    let type = "reminder.list"
    private let bridge = EventKitBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        // M6: Graceful degradation when reminder access is denied
        switch bridge.reminderAccessState() {
        case .denied:
            return .actionError(
                code: "reminder.access_denied",
                message: "Erinnerungen-Zugriff nicht erlaubt. Bitte in den Einstellungen aktivieren."
            )
        case .notDetermined:
            _ = try? await bridge.requestRemindersAccess()
        case .authorized:
            break
        }
        let reminders = await bridge.listReminders()
        let values = reminders.map { r -> ExpressionValue in
            .object([
                "id": .string(r.identifier),
                "title": .string(r.title),
                "isCompleted": .bool(r.isCompleted),
            ])
        }
        return .value(.array(values))
    }
}
