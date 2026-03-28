import Testing
import GRDB
@testable import BrainCore

@Suite("EmailCache Model")
struct EmailCacheTests {

    @Test("Insert and fetch email cache record")
    func insertAndFetch() throws {
        let db = try DatabaseManager.temporary()

        var email = EmailCache(
            messageId: "<abc@example.com>",
            folder: "INBOX",
            fromAddr: "sender@example.com",
            toAddr: "me@example.com",
            subject: "Test Subject",
            bodyPlain: "Hello, World!",
            date: "2026-03-18T10:00:00Z",
            isRead: false,
            hasAttachments: true,
            flags: #"["\\Seen","\\Flagged"]"#
        )

        try db.pool.write { dbConn in
            try email.insert(dbConn)
        }

        let emailId = try #require(email.id)

        let fetched = try db.pool.read { dbConn in
            try EmailCache.fetchOne(dbConn, key: emailId)
        }

        #expect(fetched != nil)
        #expect(fetched?.messageId == "<abc@example.com>")
        #expect(fetched?.folder == "INBOX")
        #expect(fetched?.fromAddr == "sender@example.com")
        #expect(fetched?.subject == "Test Subject")
        #expect(fetched?.isRead == false)
        #expect(fetched?.hasAttachments == true)
    }

    @Test("Unique message-id constraint")
    func uniqueMessageId() throws {
        let db = try DatabaseManager.temporary()

        var email1 = EmailCache(
            messageId: "<unique@example.com>",
            folder: "INBOX",
            subject: "First"
        )

        try db.pool.write { dbConn in
            try email1.insert(dbConn)
        }

        var email2 = EmailCache(
            messageId: "<unique@example.com>",
            folder: "INBOX",
            subject: "Duplicate"
        )

        #expect(throws: (any Error).self) {
            try db.pool.write { dbConn in
                try email2.insert(dbConn)
            }
        }
    }

    @Test("Email cache defaults")
    func defaults() throws {
        let db = try DatabaseManager.temporary()

        var email = EmailCache(subject: "Minimal")
        try db.pool.write { dbConn in
            try email.insert(dbConn)
        }

        let minimalId = try #require(email.id)
        let fetched = try db.pool.read { dbConn in
            try EmailCache.fetchOne(dbConn, key: minimalId)
        }

        #expect(fetched?.isRead == false)
        #expect(fetched?.hasAttachments == false)
    }

    @Test("Entry foreign key reference")
    func entryReference() throws {
        let db = try DatabaseManager.temporary()

        // Create an entry first
        var entry = Entry(type: .email, title: "Linked Email")
        try db.pool.write { dbConn in
            try entry.insert(dbConn)
        }

        var email = EmailCache(
            messageId: "<linked@example.com>",
            subject: "With Entry",
            entryId: entry.id
        )
        try db.pool.write { dbConn in
            try email.insert(dbConn)
        }

        let linkedId = try #require(email.id)
        let fetched = try db.pool.read { dbConn in
            try EmailCache.fetchOne(dbConn, key: linkedId)
        }
        #expect(fetched?.entryId == entry.id)
    }
}
