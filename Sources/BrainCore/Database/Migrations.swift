import GRDB

// Tracks and applies database migrations in order.
// Each migration is identified by a unique string and runs exactly once.
public enum Migrations {

    // Register all migrations with a DatabaseMigrator.
    public static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_initial") { db in
            try Schema.createTables(db)
        }

        migrator.registerMigration("v2_skills_table") { db in
            // Skills table may already exist from v1 if Schema.createTables
            // was updated. The ifNotExists flag in Schema handles this gracefully.
            // This migration ensures existing databases get the table.
            try db.create(table: "skills", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("description", .text)
                t.column("version", .text).defaults(to: "1.0")
                t.column("icon", .text)
                t.column("color", .text)
                t.column("permissions", .text)
                t.column("triggers", .text)
                t.column("screens", .text).notNull()
                t.column("actions", .text)
                t.column("sourceMarkdown", .text)
                t.column("createdBy", .text).defaults(to: "user")
                t.column("enabled", .boolean).defaults(to: true)
                t.column("installedAt", .text).defaults(sql: "(datetime('now'))")
                t.column("updatedAt", .text).defaults(sql: "(datetime('now'))")
            }
        }

        migrator.registerMigration("v3_indexes") { db in
            // Performance indexes for frequently queried columns
            try db.create(indexOn: "entries", columns: ["type", "status"])
            try db.create(indexOn: "entries", columns: ["deletedAt"])
            try db.create(indexOn: "entries", columns: ["createdAt"])
            try db.create(indexOn: "emailCache", columns: ["folder"])
            try db.create(indexOn: "emailCache", columns: ["isRead"])
            try db.create(indexOn: "reminders", columns: ["dueAt", "notified"])
        }

        // Sprint 6 (F-43): Add integrityHash column for skill tamper detection
        migrator.registerMigration("v4_skill_integrity_hash") { db in
            // Column may already exist if database was created with latest Schema.createTables
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(skills)")
            let hasColumn = columns.contains { ($0["name"] as? String) == "integrityHash" }
            if !hasColumn {
                try db.alter(table: "skills") { t in
                    t.add(column: "integrityHash", .text)
                }
            }
        }

        // M4: FTS5 porter stemming for German (e.g. "Besprechungen" matches "Besprechung")
        migrator.registerMigration("v5_fts5_porter_stemming") { db in
            // Rebuild FTS5 with porter tokenizer (wraps unicode61)
            try db.execute(sql: "DROP TABLE IF EXISTS entries_fts")
            try db.execute(sql: """
                CREATE VIRTUAL TABLE entries_fts USING fts5(
                    title, body,
                    content=entries, content_rowid=id,
                    tokenize='porter unicode61 remove_diacritics 2'
                )
                """)
            // Re-populate FTS5 index from existing entries
            try db.execute(sql: """
                INSERT INTO entries_fts(rowid, title, body)
                SELECT id, title, body FROM entries WHERE deletedAt IS NULL
                """)
            // Re-create sync triggers
            try db.execute(sql: "DROP TRIGGER IF EXISTS entries_ai")
            try db.execute(sql: "DROP TRIGGER IF EXISTS entries_ad")
            try db.execute(sql: "DROP TRIGGER IF EXISTS entries_au")
            try db.execute(sql: """
                CREATE TRIGGER entries_ai AFTER INSERT ON entries BEGIN
                    INSERT INTO entries_fts(rowid, title, body) VALUES (new.id, new.title, new.body);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER entries_ad AFTER DELETE ON entries BEGIN
                    INSERT INTO entries_fts(entries_fts, rowid, title, body) VALUES('delete', old.id, old.title, old.body);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER entries_au AFTER UPDATE ON entries BEGIN
                    INSERT INTO entries_fts(entries_fts, rowid, title, body) VALUES('delete', old.id, old.title, old.body);
                    INSERT INTO entries_fts(rowid, title, body) VALUES (new.id, new.title, new.body);
                END
                """)
        }

        // B1: Add capability column for skill categorization (app/brain/hybrid)
        migrator.registerMigration("v6_skill_capability") { db in
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(skills)")
            let hasColumn = columns.contains { ($0["name"] as? String) == "capability" }
            if !hasColumn {
                try db.alter(table: "skills") { t in
                    t.add(column: "capability", .text)
                }
            }
        }

        // Phase 30: LLM usage tracking for cost control
        migrator.registerMigration("v7_llm_usage") { db in
            try db.create(table: "llmUsage", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("provider", .text).notNull()
                t.column("model", .text).notNull()
                t.column("inputTokens", .integer).notNull().defaults(to: 0)
                t.column("outputTokens", .integer).notNull().defaults(to: 0)
                t.column("totalTokens", .integer).notNull().defaults(to: 0)
                t.column("costCents", .double).notNull().defaults(to: 0)
                t.column("requestType", .text).notNull().defaults(to: "chat")
                t.column("createdAt", .text).defaults(sql: "(datetime('now'))")
            }
            try db.create(indexOn: "llmUsage", columns: ["createdAt"])
        }

        // B3: Entry embeddings for semantic search (replaces sqlite-vec)
        migrator.registerMigration("v8_entry_embeddings") { db in
            try db.create(table: "entryEmbeddings", ifNotExists: true) { t in
                t.column("entryId", .integer).primaryKey().references("entries", onDelete: .cascade)
                t.column("embedding", .blob).notNull()
                t.column("model", .text).notNull()
                t.column("updatedAt", .text).defaults(sql: "(datetime('now'))")
            }
        }

        // Phase 31: Privacy Zones — tag-based LLM routing restrictions
        migrator.registerMigration("v9_privacy_zones") { db in
            try db.create(table: "privacyZones", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("tagId", .integer).notNull().unique()
                    .references("tags", onDelete: .cascade)
                t.column("level", .text).notNull().defaults(to: "unrestricted")
                t.column("createdAt", .text).defaults(sql: "(datetime('now'))")
            }
        }

        // Multi-account email: accounts table + accountId on emailCache
        migrator.registerMigration("v10_email_accounts") { db in
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

            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(emailCache)")
            let hasColumn = columns.contains { ($0["name"] as? String) == "accountId" }
            if !hasColumn {
                try db.alter(table: "emailCache") { t in
                    t.add(column: "accountId", .text)
                        .references("emailAccounts", onDelete: .cascade)
                }
            }
        }

        migrator.registerMigration("v11_autonomous_analysis") { db in
            // Backfill progress tracking
            try db.create(table: "analysisState", ifNotExists: true) { t in
                t.column("entityType", .text).notNull().primaryKey()
                t.column("lastProcessedId", .integer).defaults(to: 0)
                t.column("lastRunAt", .text)
                t.column("itemsProcessed", .integer).defaults(to: 0)
            }

            // Behavior signals for adaptive learning
            try db.create(table: "behaviorSignals", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("signalType", .text).notNull()
                t.column("context", .text)
                t.column("positive", .integer).defaults(to: 1)
                t.column("createdAt", .text).defaults(sql: "(datetime('now'))")
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_behaviorSignals_type ON behaviorSignals(signalType)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_behaviorSignals_date ON behaviorSignals(createdAt)")

            // Auto-generated links marker
            let linkColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(links)")
            let hasAutoGenerated = linkColumns.contains { ($0["name"] as? String) == "autoGenerated" }
            if !hasAutoGenerated {
                try db.alter(table: "links") { t in
                    t.add(column: "autoGenerated", .integer).defaults(to: 0)
                }
            }

            // Knowledge facts source type
            let factColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(knowledgeFacts)")
            let hasSourceType = factColumns.contains { ($0["name"] as? String) == "sourceType" }
            if !hasSourceType {
                try db.alter(table: "knowledgeFacts") { t in
                    t.add(column: "sourceType", .text).defaults(to: "manual")
                }
            }
        }

        // Phase 11: CloudKit sync tables
        migrator.registerMigration("v12_skill_groups") { db in
            try db.alter(table: "skills") { t in
                t.add(column: "group", .text)
            }
        }

        migrator.registerMigration("v13_email_deleted_ids") { db in
            try db.create(table: "emailDeletedIds", ifNotExists: true) { t in
                t.column("messageId", .text).notNull()
                t.column("accountId", .text).notNull()
                t.column("deletedAt", .text).defaults(sql: "(datetime('now'))")
                t.primaryKey(["messageId", "accountId"])
            }
        }

        migrator.registerMigration("v14_chat_model_tracking") { db in
            // Track which model generated each chat response
            try db.alter(table: "chatHistory") { t in
                t.add(column: "model", .text)
            }
        }

        // C1: Additional performance indices for 100k+ entries scale
        migrator.registerMigration("v15_performance_indices") { db in
            // emailCache: fast unread count per account
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_emailCache_account_read
                ON emailCache(accountId, isRead)
            """)
            // knowledgeFacts: fast lookup by subject (used in consolidation + chat context)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_knowledgeFacts_subject
                ON knowledgeFacts(subject)
            """)
            // chatHistory: fast channel-based queries
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_chatHistory_created
                ON chatHistory(createdAt)
            """)
        }

        SyncMigrations.register(&migrator)
    }
}
