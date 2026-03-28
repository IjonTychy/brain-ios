import GRDB

// A time-based reminder attached to an entry.
public struct Reminder: Codable, Sendable, Identifiable {
    public var id: Int64?
    public var entryId: Int64
    public var dueAt: String
    public var notified: Bool
    public var notificationId: String?

    public init(
        id: Int64? = nil,
        entryId: Int64,
        dueAt: String,
        notified: Bool = false,
        notificationId: String? = nil
    ) {
        self.id = id
        self.entryId = entryId
        self.dueAt = dueAt
        self.notified = notified
        self.notificationId = notificationId
    }
}

extension Reminder: FetchableRecord, MutablePersistableRecord {
    public static var databaseTableName: String { "reminders" }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
