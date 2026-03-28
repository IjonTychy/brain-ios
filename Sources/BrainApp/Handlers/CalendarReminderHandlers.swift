import Foundation
import BrainCore
import GRDB
import os.log

// Per-call ISO8601 formatter factory to avoid shared mutable state across threads.
private func makeISO8601Formatter() -> ISO8601DateFormatter {
    ISO8601DateFormatter()
}

// MARK: - Calendar actions

@MainActor
final class CalendarCreateHandler: ActionHandler {
    let type = "calendar.create"
    private let bridge = EventKitBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let title = properties["title"]?.stringValue ?? ""
        let durationMinutes = properties["duration"]?.intValue ?? 60

        // Parse start date from ISO8601 or default to now
        let startDate: Date
        if let dateStr = properties["startDate"]?.stringValue,
           let parsed = makeISO8601Formatter().date(from: dateStr) {
            startDate = parsed
        } else {
            startDate = Date()
        }
        let endDate = startDate.addingTimeInterval(Double(durationMinutes) * 60)

        let notes = properties["notes"]?.stringValue
        let location = properties["location"]?.stringValue

        let eventId = try bridge.createEvent(
            title: title, startDate: startDate, endDate: endDate,
            notes: notes, location: location
        )
        return .value(.object(["eventId": .string(eventId)]))
    }
}

@MainActor
final class CalendarDeleteHandler: ActionHandler {
    let type = "calendar.delete"
    private let bridge = EventKitBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let identifier = properties["id"]?.stringValue else {
            return .error("calendar.delete: id fehlt")
        }
        try bridge.deleteEvent(identifier: identifier)
        return .success
    }
}

@MainActor
final class CalendarUpdateHandler: ActionHandler {
    let type = "calendar.update"
    private let bridge = EventKitBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let eventId = properties["eventId"]?.stringValue else {
            return .error("calendar.update: eventId fehlt")
        }
        guard bridge.calendarAccessState() == .authorized else {
            return .error("calendar.update: Kalender-Zugriff nicht erlaubt")
        }
        let result = try bridge.updateEvent(
            identifier: eventId,
            title: properties["title"]?.stringValue,
            startDate: properties["startDate"]?.stringValue,
            endDate: properties["endDate"]?.stringValue
        )
        guard let result else {
            return .error("calendar.update: Event nicht gefunden")
        }
        return .value(.object([
            "eventId": .string(result.identifier),
            "title": .string(result.title),
        ]))
    }
}

// MARK: - Reminder actions

@MainActor final class ReminderSetHandler: ActionHandler {
    let type = "reminder.set"
    private let bridge = NotificationBridge()
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let title = properties["title"]?.stringValue ?? "Erinnerung"
        let body = properties["body"]?.stringValue ?? ""
        let entryId = properties["entryId"]?.intValue.flatMap({ Int64($0) }) ?? 0

        // Parse date from ISO8601 string or default to 1 hour from now
        let date: Date
        if let dateStr = properties["date"]?.stringValue,
           let parsed = makeISO8601Formatter().date(from: dateStr) {
            date = parsed
        } else if let minutes = properties["minutes"]?.intValue {
            date = Date().addingTimeInterval(Double(minutes) * 60)
        } else {
            date = Date().addingTimeInterval(3600)
        }

        // DB-backed scheduling with 64-notification limit handling
        let notifId = try await bridge.scheduleWithDB(
            pool: data.databasePool,
            entryId: entryId,
            title: title,
            body: body,
            at: date
        )
        return .value(.object(["notificationId": .string(notifId)]))
    }
}

@MainActor final class ReminderCancelHandler: ActionHandler {
    let type = "reminder.cancel"
    private let bridge = NotificationBridge()
    private let data: any DataProviding

    init(data: any DataProviding) { self.data = data }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        guard let id = properties["id"]?.stringValue else {
            return .error("reminder.cancel: id fehlt")
        }
        try await bridge.cancelWithDB(pool: data.databasePool, notificationId: id)
        return .success
    }
}

@MainActor final class ReminderCancelAllHandler: ActionHandler {
    let type = "reminder.cancelAll"
    private let bridge = NotificationBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        bridge.cancelAll()
        return .success
    }
}

@MainActor final class ReminderPendingCountHandler: ActionHandler {
    let type = "reminder.pendingCount"
    private let bridge = NotificationBridge()

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let count = await bridge.pendingCount()
        return .value(.int(count))
    }
}
