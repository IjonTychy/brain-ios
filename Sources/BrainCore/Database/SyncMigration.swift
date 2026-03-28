import GRDB

// Database migration for CloudKit sync support.
// Adds sync tracking tables to the existing schema.
public enum SyncMigrations {

    // Register sync-related migrations.
    public static func register(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("addSyncTracking") { db in
            // Track local changes that need to be synced
            try db.create(table: "pending_sync", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("entityType", .text).notNull()     // "entry", "tag", "link"
                t.column("entityId", .integer).notNull()
                t.column("operation", .text).notNull()       // "create", "update", "delete"
                t.column("timestamp", .datetime).notNull()
                t.column("retryCount", .integer).notNull().defaults(to: 0)
            }

            // Store the last CloudKit sync token per zone
            try db.create(table: "sync_tokens", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("zoneId", .text).notNull().unique()
                t.column("tokenData", .blob)                 // Serialized CKServerChangeToken
                t.column("lastSync", .datetime)
            }

            // Track CloudKit record IDs for local entities
            try db.create(table: "cloudkit_mapping", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("entityType", .text).notNull()
                t.column("entityId", .integer).notNull()
                t.column("recordName", .text).notNull()      // CKRecord.ID.recordName
                t.column("zoneName", .text).notNull()         // CKRecordZone.ID.zoneName
                t.column("lastModified", .datetime)
            }

            // Index for quick lookup
            try db.create(
                index: "idx_cloudkit_mapping_entity",
                on: "cloudkit_mapping",
                columns: ["entityType", "entityId"],
                unique: true,
                ifNotExists: true
            )
            try db.create(
                index: "idx_pending_sync_type",
                on: "pending_sync",
                columns: ["entityType", "operation"],
                ifNotExists: true
            )
        }
    }
}
