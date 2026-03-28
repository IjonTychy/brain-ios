import Testing
import GRDB
@testable import BrainCore

@Suite("Database & Schema")
struct DatabaseTests {

    @Test("In-memory database can be created and all tables exist")
    func createDatabase() throws {
        let db = try DatabaseManager.temporary()

        try db.pool.read { db in
            // Verify all expected tables exist
            let tables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
                ORDER BY name
                """)

            #expect(tables.contains("entries"))
            #expect(tables.contains("tags"))
            #expect(tables.contains("entryTags"))
            #expect(tables.contains("links"))
            #expect(tables.contains("reminders"))
            #expect(tables.contains("emailCache"))
            #expect(tables.contains("chatHistory"))
            #expect(tables.contains("knowledgeFacts"))
            #expect(tables.contains("rules"))
            #expect(tables.contains("improvementProposals"))
            #expect(tables.contains("skills"))
            #expect(tables.contains("syncState"))
        }
    }

    @Test("FTS5 virtual table exists")
    func ftsTable() throws {
        let db = try DatabaseManager.temporary()

        try db.pool.read { db in
            let tables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master WHERE type='table' AND name='entries_fts'
                """)
            #expect(tables.count == 1)
        }
    }

    @Test("FTS triggers exist")
    func ftsTriggers() throws {
        let db = try DatabaseManager.temporary()

        try db.pool.read { db in
            let triggers = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master WHERE type='trigger' ORDER BY name
                """)
            #expect(triggers.contains("entries_ai"))
            #expect(triggers.contains("entries_ad"))
            #expect(triggers.contains("entries_au"))
        }
    }

    @Test("Migration is idempotent")
    func migrationIdempotent() throws {
        let db = try DatabaseManager.temporary()
        // Running migrate again should not fail
        var migrator = DatabaseMigrator()
        Migrations.register(&migrator)
        try migrator.migrate(db.pool)
    }
}
