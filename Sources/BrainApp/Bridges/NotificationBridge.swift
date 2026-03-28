import UserNotifications
import BrainCore
import GRDB
import os.log

// Bridge between Action Primitives and UNUserNotificationCenter.
// Provides reminder.schedule, reminder.cancel for local notifications.
// Implements Reschedule-on-Launch pattern for the iOS 64-notification limit.
final class NotificationBridge: Sendable {

    // iOS limits pending local notifications to 64.
    // We keep all reminders in the DB and only schedule the nearest 64.
    static let maxPendingNotifications = 64

    private let logger = Logger(subsystem: "com.example.brain-ios", category: "Notifications")

    // Request notification permission.
    func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])
    }

    // Schedule a local notification.
    func schedule(id: String, title: String, body: String, at date: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
    }

    // Cancel a scheduled notification.
    func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    // Cancel all pending notifications.
    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // Get count of pending notifications.
    func pendingCount() async -> Int {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return requests.count
    }

    // MARK: - Reschedule-on-Launch Pattern

    // Called at app launch and when returning to foreground.
    // 1. Marks past-due reminders as notified
    // 2. Removes all pending OS notifications
    // 3. Schedules the next 64 upcoming reminders from DB
    func rescheduleFromDatabase(pool: DatabasePool) async {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let nowString = formatter.string(from: now)

        do {
            // Mark past-due reminders as notified
            try await pool.write { db in
                try db.execute(
                    sql: "UPDATE reminders SET notified = 1 WHERE dueAt <= ? AND notified = 0",
                    arguments: [nowString]
                )
            }

            // Fetch next 64 upcoming reminders with their entry titles
            let reminders: [(Reminder, String?)] = try await pool.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT r.*, e.title AS entryTitle
                    FROM reminders r
                    LEFT JOIN entries e ON r.entryId = e.id
                    WHERE r.notified = 0 AND r.dueAt > ?
                    ORDER BY r.dueAt ASC
                    LIMIT ?
                    """, arguments: [nowString, Self.maxPendingNotifications])
                return try rows.map { row in
                    let reminder = try Reminder(row: row)
                    let title: String? = row["entryTitle"]
                    return (reminder, title)
                }
            }

            // Clear all pending notifications and re-register
            cancelAll()

            for (reminder, entryTitle) in reminders {
                guard let notifId = reminder.notificationId,
                      let date = formatter.date(from: reminder.dueAt) else { continue }

                let title = entryTitle ?? "Erinnerung"
                try await schedule(id: notifId, title: title, body: "Faellig: \(title)", at: date)
            }

            logger.info("Rescheduled \(reminders.count) notifications (limit: \(Self.maxPendingNotifications))")
        } catch {
            logger.error("Reschedule fehlgeschlagen: \(error)")
        }
    }

    // Save a reminder to DB and schedule if within the 64-notification window.
    func scheduleWithDB(
        pool: DatabasePool,
        entryId: Int64,
        title: String,
        body: String,
        at date: Date
    ) async throws -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let notifId = UUID().uuidString

        // Persist to DB
        let reminder = Reminder(
            entryId: entryId,
            dueAt: formatter.string(from: date),
            notified: false,
            notificationId: notifId
        )
        try await pool.write { [reminder] db in
            var mutableReminder = reminder
            try mutableReminder.insert(db)
        }

        // Check if within the 64-notification window
        let pendingCount = await pendingCount()
        if pendingCount < Self.maxPendingNotifications {
            try await schedule(id: notifId, title: title, body: body, at: date)
        } else {
            // Check if this reminder is sooner than the latest scheduled one
            // If so, reschedule to include it
            await rescheduleFromDatabase(pool: pool)
        }

        return notifId
    }

    // Cancel a reminder from both DB and OS.
    func cancelWithDB(pool: DatabasePool, notificationId: String) async throws {
        cancel(id: notificationId)
        try await pool.write { db in
            try db.execute(
                sql: "DELETE FROM reminders WHERE notificationId = ?",
                arguments: [notificationId]
            )
        }
    }
}

// MARK: - Action Handler

@MainActor final class NotificationScheduleHandler: ActionHandler {
    let type = "reminder.schedule"
    private let bridge = NotificationBridge()
    private let dataBridge: DataBridge

    init(dataBridge: DataBridge) {
        self.dataBridge = dataBridge
    }

    func execute(properties: [String: PropertyValue], context: ExpressionContext) async throws -> ActionResult {
        let title = properties["title"]?.stringValue ?? "Erinnerung"
        let body = properties["body"]?.stringValue ?? ""
        let entryId = properties["entryId"]?.intValue.flatMap({ Int64($0) }) ?? 0

        // Parse date from ISO8601 string or minutes offset
        let date: Date
        if let dateStr = properties["date"]?.stringValue {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = formatter.date(from: dateStr) ?? Date().addingTimeInterval(3600)
        } else if let minutes = properties["minutes"]?.intValue {
            date = Date().addingTimeInterval(Double(minutes) * 60)
        } else {
            date = Date().addingTimeInterval(3600)
        }

        let notifId = try await bridge.scheduleWithDB(
            pool: dataBridge.db.pool,
            entryId: entryId,
            title: title,
            body: body,
            at: date
        )
        return .value(.object(["notificationId": .string(notifId)]))
    }
}
