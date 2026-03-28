import GRDB

// A cached email message from the IMAP server.
// Mirrors the emailCache table for offline-first email access.
public struct EmailCache: Codable, Sendable, Identifiable {
    public var id: Int64?
    public var messageId: String?       // IMAP Message-ID header
    public var folder: String?          // e.g. "INBOX", "Sent"
    public var fromAddr: String?
    public var toAddr: String?
    public var subject: String?
    public var bodyPlain: String?
    public var bodyHtml: String?
    public var date: String?
    public var isRead: Bool
    public var hasAttachments: Bool
    public var flags: String?           // JSON array of IMAP flags
    public var entryId: Int64?          // Link to entries table
    public var accountId: String?        // FK to emailAccounts.id

    public init(
        id: Int64? = nil,
        messageId: String? = nil,
        folder: String? = nil,
        fromAddr: String? = nil,
        toAddr: String? = nil,
        subject: String? = nil,
        bodyPlain: String? = nil,
        bodyHtml: String? = nil,
        date: String? = nil,
        isRead: Bool = false,
        hasAttachments: Bool = false,
        flags: String? = nil,
        entryId: Int64? = nil,
        accountId: String? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.folder = folder
        self.fromAddr = fromAddr
        self.toAddr = toAddr
        self.subject = subject
        self.bodyPlain = bodyPlain
        self.bodyHtml = bodyHtml
        self.date = date
        self.isRead = isRead
        self.hasAttachments = hasAttachments
        self.flags = flags
        self.entryId = entryId
        self.accountId = accountId
    }
}

// MARK: - GRDB conformances

extension EmailCache: FetchableRecord, MutablePersistableRecord {
    public static var databaseTableName: String { "emailCache" }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Associations

extension EmailCache {
    static let entryRelation = belongsTo(Entry.self, using: ForeignKey(["entryId"]))
}
