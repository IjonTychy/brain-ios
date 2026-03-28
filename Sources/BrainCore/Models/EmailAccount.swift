import Foundation
import GRDB

// An email account with IMAP/SMTP configuration.
// Password stored separately in iOS Keychain (key: "email.{id}.password").
public struct EmailAccount: Codable, Sendable, Identifiable {
    public var id: String                // UUID
    public var name: String              // Display name (e.g. "Gmail Privat")
    public var emailAddress: String      // Primary email address
    public var imapHost: String
    public var imapPort: Int
    public var smtpHost: String
    public var smtpPort: Int
    public var username: String
    public var sortOrder: Int
    public var createdAt: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        emailAddress: String,
        imapHost: String,
        imapPort: Int = 993,
        smtpHost: String,
        smtpPort: Int = 587,
        username: String,
        sortOrder: Int = 0,
        createdAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.emailAddress = emailAddress
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.username = username
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

// MARK: - GRDB conformances

extension EmailAccount: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "emailAccounts" }
}
