import GRDB

// All CREATE TABLE statements for the brain-ios database.
// Derived from ARCHITECTURE.md (single source of truth).
//
// IMPORTANT: This file defines the v1 schema (initial tables).
// Tables added in later migrations (llmUsage, emailAccounts, analysisState,
// behaviorSignals, privacyZones, etc.) are defined ONLY in Migrations.swift.
// Do NOT add new tables here — add a new migration instead.
//
// Note: entries_vec (sqlite-vec) is excluded — added later.
//
// TODO (Sprint 6.1 – F-42): Evaluate SQLCipher for at-rest database encryption.
// SQLCipher replaces the standard SQLite with an encrypted variant. GRDB supports
// it via the GRDBCipher package. Before adopting, evaluate: key management
// (Keychain vs. Secure Enclave), performance impact on FTS5 and sqlite-vec
// queries, and migration path for existing unencrypted databases.
enum Schema {

    // MARK: - Current schema version

    static let version = 4

    // MARK: - Table creation

    static func createTables(_ db: Database) throws {
        // -- Entries (core entity)
        try db.create(table: "entries", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("type", .text).notNull().defaults(to: "thought")
            t.column("title", .text)
            t.column("body", .text)
            t.column("status", .text).defaults(to: "active")
            t.column("priority", .integer).defaults(to: 0)
            t.column("source", .text).defaults(to: "manual")
            t.column("sourceMeta", .text) // JSON
            t.column("createdAt", .text).defaults(sql: "(datetime('now'))")
            t.column("updatedAt", .text).defaults(sql: "(datetime('now'))")
            t.column("deletedAt", .text)
        }

        // -- Full-Text Search (FTS5)
        try db.execute(sql: """
            CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
                title, body,
                content=entries, content_rowid=id,
                tokenize='unicode61 remove_diacritics 2'
            )
            """)

        // -- FTS sync triggers
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS entries_ai AFTER INSERT ON entries BEGIN
                INSERT INTO entries_fts(rowid, title, body) VALUES (new.id, new.title, new.body);
            END
            """)
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS entries_ad AFTER DELETE ON entries BEGIN
                INSERT INTO entries_fts(entries_fts, rowid, title, body) VALUES('delete', old.id, old.title, old.body);
            END
            """)
        try db.execute(sql: """
            CREATE TRIGGER IF NOT EXISTS entries_au AFTER UPDATE ON entries BEGIN
                INSERT INTO entries_fts(entries_fts, rowid, title, body) VALUES('delete', old.id, old.title, old.body);
                INSERT INTO entries_fts(rowid, title, body) VALUES (new.id, new.title, new.body);
            END
            """)

        // -- Tags
        try db.create(table: "tags", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("name", .text).notNull().unique()
            t.column("color", .text)
        }

        // -- Entry-Tag join table
        try db.create(table: "entryTags", ifNotExists: true) { t in
            t.column("entryId", .integer)
                .notNull()
                .references("entries", onDelete: .cascade)
            t.column("tagId", .integer)
                .notNull()
                .references("tags", onDelete: .cascade)
            t.primaryKey(["entryId", "tagId"])
        }

        // -- Links (bi-directional)
        try db.create(table: "links", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("sourceId", .integer)
                .notNull()
                .references("entries", onDelete: .cascade)
            t.column("targetId", .integer)
                .notNull()
                .references("entries", onDelete: .cascade)
            t.column("relation", .text).defaults(to: "related")
            t.column("createdAt", .text).defaults(sql: "(datetime('now'))")
            t.uniqueKey(["sourceId", "targetId"])
        }

        // -- Reminders
        try db.create(table: "reminders", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("entryId", .integer)
                .notNull()
                .references("entries", onDelete: .cascade)
            t.column("dueAt", .text).notNull()
            t.column("notified", .boolean).defaults(to: false)
            t.column("notificationId", .text)
        }

        // -- Email Accounts
        try db.create(table: "emailAccounts", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull()
            t.column("emailAddress", .text).notNull()
            t.column("imapHost", .text).notNull()
            t.column("imapPort", .integer).notNull().defaults(to: 993)
            t.column("smtpHost", .text).notNull()
            t.column("smtpPort", .integer).notNull().defaults(to: 587)
            t.column("username", .text).notNull()
            t.column("sortOrder", .integer).notNull().defaults(to: 0)
            t.column("createdAt", .text).defaults(sql: "(datetime('now'))")
        }

        // -- Email Cache
        try db.create(table: "emailCache", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("messageId", .text).unique()
            t.column("folder", .text)
            t.column("fromAddr", .text)
            t.column("toAddr", .text)
            t.column("subject", .text)
            t.column("bodyPlain", .text)
            t.column("bodyHtml", .text)
            t.column("date", .text)
            t.column("isRead", .boolean).defaults(to: false)
            t.column("hasAttachments", .boolean).defaults(to: false)
            t.column("flags", .text) // JSON array
            t.column("entryId", .integer).references("entries", onDelete: .setNull)
            t.column("accountId", .text).references("emailAccounts", onDelete: .cascade)
        }

        // -- Chat History
        try db.create(table: "chatHistory", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("role", .text).notNull()
            t.column("content", .text).notNull()
            t.column("toolCalls", .text) // JSON
            t.column("sources", .text) // JSON
            t.column("channel", .text).defaults(to: "app")
            t.column("createdAt", .text).defaults(sql: "(datetime('now'))")
        }

        // -- Knowledge Facts
        try db.create(table: "knowledgeFacts", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("subject", .text)
            t.column("predicate", .text)
            t.column("object", .text)
            t.column("confidence", .double).defaults(to: 1.0)
            t.column("sourceEntryId", .integer).references("entries", onDelete: .setNull)
            t.column("learnedAt", .text).defaults(sql: "(datetime('now'))")
        }

        // -- Rules Engine
        try db.create(table: "rules", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("category", .text).notNull()
            t.column("name", .text).notNull().unique()
            t.column("condition", .text) // JSON
            t.column("action", .text).notNull() // JSON
            t.column("priority", .integer).defaults(to: 0)
            t.column("enabled", .boolean).defaults(to: true)
            t.column("createdAt", .text).defaults(sql: "(datetime('now'))")
            t.column("modifiedAt", .text).defaults(sql: "(datetime('now'))")
            t.column("modifiedBy", .text).defaults(to: "system")
        }

        // -- Improvement Proposals
        try db.create(table: "improvementProposals", ifNotExists: true) { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("title", .text).notNull()
            t.column("description", .text)
            t.column("category", .text).notNull()
            t.column("changeSpec", .text) // JSON
            t.column("status", .text).defaults(to: "pending")
            t.column("createdAt", .text).defaults(sql: "(datetime('now'))")
            t.column("appliedAt", .text)
            t.column("rollbackData", .text) // JSON
        }

        // -- Skills (installed JSON skills — the "proteins" of the runtime engine)
        try db.create(table: "skills", ifNotExists: true) { t in
            t.column("id", .text).primaryKey()          // e.g. "pomodoro-timer"
            t.column("name", .text).notNull()
            t.column("description", .text)
            t.column("version", .text).defaults(to: "1.0")
            t.column("icon", .text)
            t.column("color", .text)
            t.column("capability", .text)                // app, brain, hybrid
            t.column("permissions", .text)               // JSON array: ["notifications", "haptics"]
            t.column("triggers", .text)                  // JSON array: [{type, phrase, ...}]
            t.column("screens", .text).notNull()         // JSON: full UI definition tree
            t.column("actions", .text)                   // JSON: workflow definitions
            t.column("sourceMarkdown", .text)            // Original .brainskill.md
            t.column("createdBy", .text).defaults(to: "user")
            t.column("enabled", .boolean).defaults(to: true)
            t.column("integrityHash", .text)           // SHA-256 hash for tamper detection (F-43)
            t.column("installedAt", .text).defaults(sql: "(datetime('now'))")
            t.column("updatedAt", .text).defaults(sql: "(datetime('now'))")
        }

        // -- Sync State
        try db.create(table: "syncState", ifNotExists: true) { t in
            t.column("key", .text).primaryKey()
            t.column("value", .text)
            t.column("updatedAt", .text).defaults(sql: "(datetime('now'))")
        }
    }
}
