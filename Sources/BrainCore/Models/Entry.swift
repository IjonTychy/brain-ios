import Foundation
import GRDB

// Types of entries supported by the system.
public enum EntryType: String, Codable, Sendable, DatabaseValueConvertible {
    case thought, task, event, email, note, document

    // SF Symbol name for this entry type.
    public var icon: String {
        switch self {
        case .thought: "lightbulb"
        case .task: "checkmark.circle"
        case .note: "note.text"
        case .event: "calendar"
        case .email: "envelope"
        case .document: "doc"
        }
    }

    // Filled variant of the icon.
    public var iconFilled: String {
        switch self {
        case .thought: "lightbulb.fill"
        case .task: "checkmark.circle.fill"
        case .note: "note.text"
        case .event: "calendar"
        case .email: "envelope.fill"
        case .document: "doc.fill"
        }
    }

    // German display name.
    public var label: String {
        switch self {
        case .thought: "Gedanke"
        case .task: "Aufgabe"
        case .note: "Notiz"
        case .event: "Termin"
        case .email: "E-Mail"
        case .document: "Dokument"
        }
    }

    // Plural German display name.
    public var labelPlural: String {
        switch self {
        case .thought: "Gedanken"
        case .task: "Aufgaben"
        case .note: "Notizen"
        case .event: "Termine"
        case .email: "E-Mails"
        case .document: "Dokumente"
        }
    }

    // Named color (usable with SwiftUI Color or UIColor).
    public var colorName: String {
        switch self {
        case .thought: "yellow"
        case .task: "blue"
        case .note: "green"
        case .event: "purple"
        case .email: "orange"
        case .document: "gray"
        }
    }
}

// Status of an entry.
public enum EntryStatus: String, Codable, Sendable, DatabaseValueConvertible {
    case active, done, archived

    // German display name.
    public var label: String {
        switch self {
        case .active: "Aktiv"
        case .done: "Erledigt"
        case .archived: "Archiviert"
        }
    }
}

// Source that created the entry.
public enum EntrySource: String, Codable, Sendable, DatabaseValueConvertible {
    case manual, email, caldav, shareSheet = "share-sheet", siri, scan
}

// The core data entity. Everything in the brain is an Entry.
public struct Entry: Codable, Sendable, Identifiable {
    public var id: Int64?
    public var type: EntryType
    public var title: String?
    public var body: String?
    public var status: EntryStatus
    public var priority: Int
    public var source: EntrySource
    public var sourceMeta: String?
    public var createdAt: String?
    public var updatedAt: String?
    public var deletedAt: String?

    public init(
        id: Int64? = nil,
        type: EntryType = .thought,
        title: String? = nil,
        body: String? = nil,
        status: EntryStatus = .active,
        priority: Int = 0,
        source: EntrySource = .manual,
        sourceMeta: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        deletedAt: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.status = status
        self.priority = priority
        self.source = source
        self.sourceMeta = sourceMeta
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    // MARK: - Typed date accessors (avoids string parsing in every view)

    private static let dbDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_CH")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // Parse createdAt string to Date.
    public var createdAtDate: Date? {
        createdAt.flatMap { Self.dbDateFormatter.date(from: $0) }
    }

    // Human-readable German date string (e.g. "22. März 2026, 14:30").
    public var formattedCreatedAt: String? {
        createdAtDate.map { Self.displayDateFormatter.string(from: $0) }
    }
}

// MARK: - GRDB conformances

extension Entry: FetchableRecord, MutablePersistableRecord {
    public static var databaseTableName: String { "entries" }

    // Let GRDB assign the auto-incremented id after insert.
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Associations

extension Entry {
    static let entryTagsRelation = hasMany(EntryTag.self)
    static let tagsRelation = hasMany(Tag.self, through: entryTagsRelation, using: EntryTag.tagRelation)
    static let remindersRelation = hasMany(Reminder.self)
    static let sourceLinksRelation = hasMany(Link.self, using: Link.sourceForeignKey)
    static let targetLinksRelation = hasMany(Link.self, using: Link.targetForeignKey)
}
