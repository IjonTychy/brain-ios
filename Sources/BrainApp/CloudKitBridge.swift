import CloudKit
import GRDB
import BrainCore
import os.log

// Phase 11: CloudKit Sync Bridge — real implementation for iOS.
// Syncs entries, tags, and links between local GRDB and CloudKit private database.
// Architecture: local GRDB is always source of truth (offline-first).
// Changes tracked via pending_sync table, pushed on demand or via background task.
//
// Container: iCloud.com.example.brain-ios (must be configured in Xcode entitlements)
// Zone: "BrainZone" (custom zone for incremental fetch)

final class CloudKitBridge: @unchecked Sendable {
    // @unchecked Sendable: pool is thread-safe (GRDB), container is immutable after init.

    private let pool: DatabasePool
    private let container: CKContainer
    private let privateDB: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let logger = Logger(subsystem: "com.example.brain-ios", category: "CloudKit")

    static let containerID = "iCloud.com.example.brain-ios"
    static let zoneName = "BrainZone"

    init(pool: DatabasePool) {
        self.pool = pool
        self.container = CKContainer(identifier: Self.containerID)
        self.privateDB = container.privateCloudDatabase
        self.zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    // MARK: - Zone Setup

    /// Ensure the custom zone exists. Call once at app start.
    func ensureZoneExists() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        do {
            _ = try await privateDB.save(zone)
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Zone already exists — OK
            logger.info("Zone already exists: \(Self.zoneName)")
        }
    }

    // MARK: - Push Local Changes

    /// Push all pending local changes to CloudKit.
    /// Reads from pending_sync table, converts to CKRecords, batch saves.
    func pushLocalChanges() async throws {
        let pending: [(id: Int64, entityType: String, entityId: Int64, operation: String)] = try await pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, entityType, entityId, operation FROM pending_sync
                ORDER BY timestamp ASC LIMIT 100
                """)
            return rows.compactMap { row -> (id: Int64, entityType: String, entityId: Int64, operation: String)? in
                guard let id = row["id"] as? Int64,
                      let entityType = row["entityType"] as? String,
                      let entityId = row["entityId"] as? Int64,
                      let operation = row["operation"] as? String
                else { return nil }
                return (id: id, entityType: entityType, entityId: entityId, operation: operation)
            }
        }

        guard !pending.isEmpty else { return }
        logger.info("Pushing \(pending.count) local changes to CloudKit")

        var recordsToSave: [CKRecord] = []
        var recordIDsToDelete: [CKRecord.ID] = []
        var processedIds: [Int64] = []

        for item in pending {
            let recordName = "\(item.entityType)_\(item.entityId)"
            let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)

            if item.operation == "delete" {
                recordIDsToDelete.append(recordID)
                processedIds.append(item.id)
            } else {
                // Fetch the entity from local DB and create CKRecord
                if let record = try await buildCKRecord(entityType: item.entityType, entityId: item.entityId, recordID: recordID) {
                    recordsToSave.append(record)
                    processedIds.append(item.id)
                }
            }
        }

        // Batch save/delete via CKModifyRecordsOperation
        if !recordsToSave.isEmpty || !recordIDsToDelete.isEmpty {
            let (saved, deleted) = try await privateDB.modifyRecords(
                saving: recordsToSave,
                deleting: recordIDsToDelete,
                savePolicy: .changedKeys
            )
            logger.info("CloudKit push: \(saved.count) saved, \(deleted.count) deleted")
        }

        // Remove processed items from pending_sync
        let idsToDelete = processedIds
        if !idsToDelete.isEmpty {
            try await pool.write { db in
                let placeholders = idsToDelete.map { _ in "?" }.joined(separator: ", ")
                try db.execute(
                    sql: "DELETE FROM pending_sync WHERE id IN (\(placeholders))",
                    arguments: StatementArguments(idsToDelete)
                )
            }
        }
    }

    // MARK: - Pull Remote Changes

    /// Fetch changes from CloudKit since last sync token.
    /// Uses CKFetchRecordZoneChangesOperation for incremental sync.
    func pullRemoteChanges() async throws {
        // Load last sync token
        let tokenData: Data? = try await pool.read { db in
            let row = try Row.fetchOne(db, sql:
                "SELECT tokenData FROM sync_tokens WHERE zoneId = ?",
                arguments: [Self.zoneName])
            return row?["tokenData"] as? Data
        }

        var serverToken: CKServerChangeToken?
        if let data = tokenData {
            serverToken = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
        }

        // Fetch changes
        let changes = try await privateDB.recordZoneChanges(
            inZoneWith: zoneID,
            since: serverToken
        )

        var upserted = 0
        var deleted = 0

        // Process changed records
        for (_, result) in changes.modificationResultsByID {
            switch result {
            case .success(let modification):
                try applyRemoteRecord(modification.record)
                upserted += 1
            case .failure(let error):
                logger.error("Record fetch error: \(error)")
            }
        }

        // Apply remote deletions — soft-delete entries, hard-delete tags.
        // Currently synced entity types: Entry, Tag. Other entities are local-only.
        for deletion in changes.deletions {
            let recordName = deletion.recordID.recordName
            do {
                try await pool.write { db in
                    if let mapping = try Row.fetchOne(db, sql:
                        "SELECT entityType, entityId FROM cloudkit_mapping WHERE recordName = ?",
                        arguments: [recordName]) {
                        let entityType: String? = mapping["entityType"]
                        let entityId: Int64? = mapping["entityId"]
                        if let entityType, let entityId {
                            switch entityType {
                            case "entry":
                                try db.execute(sql: "UPDATE entries SET deletedAt = datetime('now') WHERE id = ?", arguments: [entityId])
                            case "tag":
                                try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [entityId])
                            default:
                                break
                            }
                        }
                        try db.execute(sql: "DELETE FROM cloudkit_mapping WHERE recordName = ?", arguments: [recordName])
                    }
                }
                deleted += 1
            } catch {
                logger.error("Failed to apply remote deletion for \(recordName): \(error)")
            }
        }

        // Save new sync token
        let newToken = changes.changeToken
        let newTokenData = try NSKeyedArchiver.archivedData(withRootObject: newToken, requiringSecureCoding: true)
        try await pool.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO sync_tokens (zoneId, tokenData, lastSync)
                VALUES (?, ?, datetime('now'))
                """, arguments: [Self.zoneName, newTokenData])
        }

        if upserted > 0 || deleted > 0 {
            logger.info("CloudKit pull: \(upserted) upserted, \(deleted) deleted")
        }
    }

    // MARK: - Full Sync Cycle

    /// Run a complete sync: push local, then pull remote.
    func sync() async {
        do {
            try await ensureZoneExists()
            try await pushLocalChanges()
            try await pullRemoteChanges()
        } catch {
            logger.error("CloudKit sync failed: \(error)")
        }
    }

    // MARK: - Record Building

    private func buildCKRecord(entityType: String, entityId: Int64, recordID: CKRecord.ID) async throws -> CKRecord? {
        switch entityType {
        case "entry":
            return try await pool.read { db -> CKRecord? in
                guard let entry = try Entry.fetchOne(db, key: entityId) else { return nil }
                let record = CKRecord(recordType: "Entry", recordID: recordID)
                record["type"] = entry.type.rawValue as NSString
                record["title"] = entry.title as NSString?
                record["body"] = entry.body as NSString?
                record["status"] = entry.status.rawValue as NSString
                record["priority"] = entry.priority as NSNumber
                record["source"] = entry.source.rawValue as NSString
                record["createdAt"] = entry.createdAt as NSString?
                record["updatedAt"] = entry.updatedAt as NSString?
                return record
            }
        case "tag":
            return try await pool.read { db -> CKRecord? in
                guard let row = try Row.fetchOne(db, sql: "SELECT * FROM tags WHERE id = ?", arguments: [entityId]) else { return nil }
                let record = CKRecord(recordType: "Tag", recordID: recordID)
                record["name"] = ((row["name"] as? String) ?? "") as NSString
                record["color"] = (row["color"] as? String) as NSString?
                return record
            }
        default:
            return nil
        }
    }

    // MARK: - Apply Remote Record

    private func applyRemoteRecord(_ record: CKRecord) throws {
        switch record.recordType {
        case "Entry":
            try pool.write { db in
                let title = record["title"] as? String
                let body = record["body"] as? String
                let type = record["type"] as? String ?? "thought"
                let status = record["status"] as? String ?? "active"
                let priority = record["priority"] as? Int ?? 0

                // Check if entry exists via cloudkit_mapping
                let recordName = record.recordID.recordName
                if let mapping = try Row.fetchOne(db, sql:
                    "SELECT entityId FROM cloudkit_mapping WHERE recordName = ?",
                    arguments: [recordName]) {
                    guard let entityId = mapping["entityId"] as? Int64 else { return }
                    // Update existing
                    try db.execute(sql: """
                        UPDATE entries SET title = ?, body = ?, type = ?, status = ?, priority = ?,
                        updatedAt = datetime('now') WHERE id = ?
                        """, arguments: [title, body, type, status, priority, entityId])
                } else {
                    // Insert new
                    try db.execute(sql: """
                        INSERT INTO entries (title, body, type, status, priority, source, createdAt, updatedAt)
                        VALUES (?, ?, ?, ?, ?, 'cloudkit', datetime('now'), datetime('now'))
                        """, arguments: [title, body, type, status, priority])
                    let entityId = db.lastInsertedRowID
                    try db.execute(sql: """
                        INSERT INTO cloudkit_mapping (entityType, entityId, recordName, zoneName, lastModified)
                        VALUES ('entry', ?, ?, ?, datetime('now'))
                        """, arguments: [entityId, recordName, Self.zoneName])
                }
            }
        case "Tag":
            try pool.write { db in
                let name = record["name"] as? String ?? ""
                let color = record["color"] as? String
                // Upsert tag by name
                try db.execute(sql: """
                    INSERT INTO tags (name, color) VALUES (?, ?)
                    ON CONFLICT(name) DO UPDATE SET color = excluded.color
                    """, arguments: [name, color])
            }
        default:
            break
        }
    }
}
