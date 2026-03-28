import Testing
import GRDB
@testable import BrainCore

@Suite("Email Deleted IDs (v13 migration)")
struct EmailDeletedIdsTests {

    // MARK: - Helpers

    private func makeDB() throws -> DatabaseManager {
        try DatabaseManager.temporary()
    }

    // Insert a row into emailDeletedIds via raw SQL and return the inserted messageId.
    @discardableResult
    private func recordDeletion(
        _ db: DatabaseManager,
        messageId: String,
        accountId: String = "default-account"
    ) throws -> String {
        try db.pool.write { conn in
            try conn.execute(
                sql: """
                    INSERT OR IGNORE INTO emailDeletedIds (messageId, accountId)
                    VALUES (?, ?)
                    """,
                arguments: [messageId, accountId]
            )
        }
        return messageId
    }

    // MARK: - Migration

    @Test("v13 migration creates emailDeletedIds table")
    func migrationCreatesTable() throws {
        let db = try makeDB()

        let tables = try db.pool.read { conn in
            try String.fetchAll(conn, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name = 'emailDeletedIds'
                """)
        }

        #expect(tables.count == 1)
    }

    @Test("emailDeletedIds table has expected columns")
    func tableHasExpectedColumns() throws {
        let db = try makeDB()

        let columnNames = try db.pool.read { conn -> [String] in
            let rows = try Row.fetchAll(conn, sql: "PRAGMA table_info(emailDeletedIds)")
            return rows.compactMap { $0["name"] as? String }
        }

        #expect(columnNames.contains("messageId"))
        #expect(columnNames.contains("accountId"))
        #expect(columnNames.contains("deletedAt"))
    }

    @Test("messageId is the primary key")
    func messageIdIsPrimaryKey() throws {
        let db = try makeDB()

        let pkColumns = try db.pool.read { conn -> [String] in
            let rows = try Row.fetchAll(conn, sql: "PRAGMA table_info(emailDeletedIds)")
            return rows.compactMap { row -> String? in
                guard let pk = row["pk"] as? Int64, pk > 0 else { return nil }
                return row["name"] as? String
            }
        }

        #expect(pkColumns == ["messageId"])
    }

    // MARK: - Basic CRUD

    @Test("Insert a deleted-id record and read it back")
    func insertAndFetch() throws {
        let db = try makeDB()

        try recordDeletion(db, messageId: "<msg001@example.com>", accountId: "account-1")

        let row = try db.pool.read { conn in
            try Row.fetchOne(conn, sql: """
                SELECT messageId, accountId, deletedAt
                FROM emailDeletedIds
                WHERE messageId = ?
                """,
                arguments: ["<msg001@example.com>"])
        }

        let fetched = try #require(row)
        #expect((fetched["messageId"] as? String) == "<msg001@example.com>")
        #expect((fetched["accountId"] as? String) == "account-1")
        // deletedAt is populated by the SQL default
        let deletedAt = fetched["deletedAt"] as? String
        #expect(deletedAt != nil)
        #expect(deletedAt?.isEmpty == false)
    }

    @Test("Same messageId on different accounts creates separate records")
    func sameMessageIdDifferentAccounts() throws {
        let db = try makeDB()

        try recordDeletion(db, messageId: "<shared@example.com>", accountId: "acc-1")
        try recordDeletion(db, messageId: "<shared@example.com>", accountId: "acc-2")

        let count = try db.pool.read { conn in
            try Int.fetchOne(conn, sql: """
                SELECT COUNT(*) FROM emailDeletedIds WHERE messageId = ?
                """,
                arguments: ["<shared@example.com>"]) ?? 0
        }

        // Composite PK (messageId, accountId) allows same messageId for different accounts
        #expect(count == 2)
    }

    @Test("Multiple records for different messageIds can coexist")
    func multipleRecords() throws {
        let db = try makeDB()

        try recordDeletion(db, messageId: "<alpha@example.com>", accountId: "acc-A")
        try recordDeletion(db, messageId: "<beta@example.com>", accountId: "acc-B")
        try recordDeletion(db, messageId: "<gamma@example.com>", accountId: "acc-A")

        let count = try db.pool.read { conn in
            try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM emailDeletedIds") ?? 0
        }

        #expect(count == 3)
    }

    // MARK: - Duplicate handling

    @Test("INSERT OR IGNORE silently ignores duplicate messageId")
    func insertOrIgnoreDuplicate() throws {
        let db = try makeDB()

        // First insertion succeeds
        try recordDeletion(db, messageId: "<dup@example.com>", accountId: "acc-1")

        // Second insertion with same messageId must not throw
        try recordDeletion(db, messageId: "<dup@example.com>", accountId: "acc-2")

        // Only one row should exist
        let count = try db.pool.read { conn in
            try Int.fetchOne(conn, sql: """
                SELECT COUNT(*) FROM emailDeletedIds WHERE messageId = ?
                """,
                arguments: ["<dup@example.com>"]) ?? 0
        }

        #expect(count == 1)
    }

    @Test("INSERT OR IGNORE preserves original accountId on duplicate")
    func insertOrIgnorePreservesOriginal() throws {
        let db = try makeDB()

        try recordDeletion(db, messageId: "<preserve@example.com>", accountId: "original-account")
        try recordDeletion(db, messageId: "<preserve@example.com>", accountId: "new-account")

        let row = try db.pool.read { conn in
            try Row.fetchOne(conn, sql: """
                SELECT accountId FROM emailDeletedIds WHERE messageId = ?
                """,
                arguments: ["<preserve@example.com>"])
        }

        let fetched = try #require(row)
        #expect((fetched["accountId"] as? String) == "original-account")
    }

    @Test("Inserting same messageId many times keeps exactly one row")
    func manyDuplicatesStillOneRow() throws {
        let db = try makeDB()

        for _ in 0..<10 {
            try recordDeletion(db, messageId: "<repeat@example.com>")
        }

        let count = try db.pool.read { conn in
            try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM emailDeletedIds") ?? 0
        }

        #expect(count == 1)
    }

    // MARK: - Sync skip logic

    @Test("messageId present in emailDeletedIds is excluded from emailCache insertion")
    func syncSkipsDeletedId() throws {
        let db = try makeDB()
        let messageId = "<sync-skip@example.com>"

        // Record the deletion before any sync attempt
        try recordDeletion(db, messageId: messageId, accountId: "acc-sync")

        // Simulate the sync guard: only insert into emailCache when messageId is NOT deleted
        let isDeleted = try db.pool.read { conn -> Bool in
            let row = try Row.fetchOne(conn, sql: """
                SELECT 1 FROM emailDeletedIds WHERE messageId = ?
                """,
                arguments: [messageId])
            return row != nil
        }

        if !isDeleted {
            try db.pool.write { conn in
                try conn.execute(sql: """
                    INSERT OR IGNORE INTO emailCache (messageId, folder)
                    VALUES (?, 'INBOX')
                    """,
                    arguments: [messageId])
            }
        }

        // The email must NOT appear in emailCache
        let cachedCount = try db.pool.read { conn in
            try Int.fetchOne(conn, sql: """
                SELECT COUNT(*) FROM emailCache WHERE messageId = ?
                """,
                arguments: [messageId]) ?? 0
        }

        #expect(cachedCount == 0)
    }

    @Test("messageId NOT in emailDeletedIds is inserted into emailCache during sync")
    func syncAllowsNonDeletedId() throws {
        let db = try makeDB()
        let messageId = "<sync-allow@example.com>"

        // No deletion recorded for this messageId
        let isDeleted = try db.pool.read { conn -> Bool in
            let row = try Row.fetchOne(conn, sql: """
                SELECT 1 FROM emailDeletedIds WHERE messageId = ?
                """,
                arguments: [messageId])
            return row != nil
        }

        if !isDeleted {
            try db.pool.write { conn in
                try conn.execute(sql: """
                    INSERT OR IGNORE INTO emailCache (messageId, folder)
                    VALUES (?, 'INBOX')
                    """,
                    arguments: [messageId])
            }
        }

        let cachedCount = try db.pool.read { conn in
            try Int.fetchOne(conn, sql: """
                SELECT COUNT(*) FROM emailCache WHERE messageId = ?
                """,
                arguments: [messageId]) ?? 0
        }

        #expect(cachedCount == 1)
    }

    @Test("Deleting a message records it in emailDeletedIds and removes from emailCache")
    func deleteMessageRecordsAndRemoves() throws {
        let db = try makeDB()
        let messageId = "<to-delete@example.com>"

        // Set up: insert email into cache
        try db.pool.write { conn in
            try conn.execute(sql: """
                INSERT INTO emailCache (messageId, folder) VALUES (?, 'INBOX')
                """,
                arguments: [messageId])
        }

        // Simulate deleteMessage(): record deletion, then hard-delete from cache
        try db.pool.write { conn in
            try conn.execute(sql: """
                INSERT OR IGNORE INTO emailDeletedIds (messageId, accountId)
                VALUES (?, ?)
                """,
                arguments: [messageId, "acc-del"])
            try conn.execute(sql: """
                DELETE FROM emailCache WHERE messageId = ?
                """,
                arguments: [messageId])
        }

        // emailCache should be empty for this messageId
        let cacheCount = try db.pool.read { conn in
            try Int.fetchOne(conn, sql: """
                SELECT COUNT(*) FROM emailCache WHERE messageId = ?
                """,
                arguments: [messageId]) ?? 0
        }
        #expect(cacheCount == 0)

        // emailDeletedIds should have the record
        let deletedCount = try db.pool.read { conn in
            try Int.fetchOne(conn, sql: """
                SELECT COUNT(*) FROM emailDeletedIds WHERE messageId = ?
                """,
                arguments: [messageId]) ?? 0
        }
        #expect(deletedCount == 1)
    }

    @Test("Sync of many messages skips only those in emailDeletedIds")
    func syncBatchSkipsOnlyDeleted() throws {
        let db = try makeDB()

        let incomingMessages = [
            "<msg-A@example.com>",
            "<msg-B@example.com>",
            "<msg-C@example.com>",
            "<msg-D@example.com>",
        ]
        let deletedIds: Set<String> = ["<msg-B@example.com>", "<msg-D@example.com>"]

        // Pre-populate the deleted-ids table
        for id in deletedIds {
            try recordDeletion(db, messageId: id)
        }

        // Simulate batch sync: fetch deleted set, then insert non-deleted
        let knownDeleted = try db.pool.read { conn -> Set<String> in
            let rows = try String.fetchAll(conn, sql: "SELECT messageId FROM emailDeletedIds")
            return Set(rows)
        }

        for messageId in incomingMessages {
            guard !knownDeleted.contains(messageId) else { continue }
            try db.pool.write { conn in
                try conn.execute(sql: """
                    INSERT OR IGNORE INTO emailCache (messageId, folder)
                    VALUES (?, 'INBOX')
                    """,
                    arguments: [messageId])
            }
        }

        let cachedIds = try db.pool.read { conn in
            try String.fetchAll(conn, sql: "SELECT messageId FROM emailCache ORDER BY messageId")
        }

        #expect(cachedIds == ["<msg-A@example.com>", "<msg-C@example.com>"])
        #expect(!cachedIds.contains("<msg-B@example.com>"))
        #expect(!cachedIds.contains("<msg-D@example.com>"))
    }
}
