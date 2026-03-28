import Foundation
import GRDB
import Testing
@testable import BrainCore

@Suite("CloudKit Sync Infrastructure")
struct CloudKitSyncTests {

    // MARK: - Sync State

    @Test("SyncState initialisiert als idle")
    func syncStateDefaultIdle() async {
        let engine = CloudKitSyncEngine()
        let state = await engine.state
        #expect(state == .idle)
    }

    @Test("SyncState kann deaktiviert werden")
    func syncStateDisable() async {
        let engine = CloudKitSyncEngine()
        await engine.setEnabled(false)
        let state = await engine.state
        #expect(state == .disabled)
    }

    @Test("SyncState kann reaktiviert werden")
    func syncStateReEnable() async {
        let engine = CloudKitSyncEngine()
        await engine.setEnabled(false)
        let disabled = await engine.state
        #expect(disabled == .disabled)
        await engine.setEnabled(true)
        let enabled = await engine.state
        #expect(enabled == .idle)
    }

    // MARK: - Pending Sync Records

    @Test("PendingSyncRecord erstellen")
    func pendingSyncRecordCreation() {
        let record = PendingSyncRecord(
            entityType: "entry",
            entityId: 42,
            operation: .create
        )
        #expect(record.entityType == "entry")
        #expect(record.entityId == 42)
        #expect(record.operation == .create)
        #expect(record.retryCount == 0)
    }

    @Test("SyncOperation Werte")
    func syncOperationValues() {
        #expect(SyncOperation.create.rawValue == "create")
        #expect(SyncOperation.update.rawValue == "update")
        #expect(SyncOperation.delete.rawValue == "delete")
    }

    // MARK: - Shared Zone

    @Test("SharedZoneInfo erstellen")
    func sharedZoneInfo() {
        let info = SharedZoneInfo(
            zoneId: "zone-1",
            ownerName: "Andy",
            participantCount: 3,
            entryCount: 42
        )
        #expect(info.zoneId == "zone-1")
        #expect(info.ownerName == "Andy")
        #expect(info.participantCount == 3)
        #expect(info.entryCount == 42)
    }

    @Test("SharedZoneManager gibt leere Liste zurueck (kein CloudKit auf Linux)")
    func sharedZoneManagerEmpty() async throws {
        let manager = SharedZoneManager()
        let shares = try await manager.activeShares()
        #expect(shares.isEmpty)
    }

    // MARK: - Sync Engine

    @Test("SyncNow laeuft ohne Crash (Stub auf Linux)")
    func syncNowDoesNotCrash() async {
        let engine = CloudKitSyncEngine()
        await engine.syncNow()
        // After sync completes, state should be idle (not error, since stubs succeed)
        let state = await engine.state
        #expect(state == .idle)
    }

    @Test("MultiWindowManager oeffnet und schliesst Fenster")
    func multiWindowOpenClose() async {
        let manager = MultiWindowManager()
        let config = SpatialConfig(presentation: .window, supportsMultiWindow: true)

        await manager.openWindow(skillId: "dashboard", config: config)
        var windows = await manager.activeWindows
        #expect(windows.count == 1)

        await manager.openWindow(skillId: "calendar", config: config)
        windows = await manager.activeWindows
        #expect(windows.count == 2)

        await manager.closeWindow(skillId: "dashboard")
        windows = await manager.activeWindows
        #expect(windows.count == 1)
        #expect(windows.first?.skillId == "calendar")
    }
}

@Suite("Sync Migrations")
struct SyncMigrationTests {

    @Test("Sync-Tabellen werden erstellt")
    func syncTablesCreated() throws {
        let db = try DatabaseManager.temporary()

        // Sync tables should be created automatically via Migrations.register()
        // which now calls SyncMigrations.register()
        try db.pool.read { db in
            let tables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master WHERE type='table' ORDER BY name
                """)
            #expect(tables.contains("pending_sync"))
            #expect(tables.contains("sync_tokens"))
            #expect(tables.contains("cloudkit_mapping"))
        }
    }

    @Test("pending_sync Insert und Query")
    func pendingSyncInsertQuery() throws {
        let db = try DatabaseManager.temporary()

        try db.pool.write { db in
            try db.execute(sql: """
                INSERT INTO pending_sync (entityType, entityId, operation, timestamp, retryCount)
                VALUES ('entry', 1, 'create', datetime('now'), 0)
                """)
            try db.execute(sql: """
                INSERT INTO pending_sync (entityType, entityId, operation, timestamp, retryCount)
                VALUES ('tag', 5, 'update', datetime('now'), 0)
                """)
        }

        let count = try db.pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pending_sync")
        }
        #expect(count == 2)
    }

    @Test("cloudkit_mapping Unique Constraint")
    func cloudkitMappingUnique() throws {
        let db = try DatabaseManager.temporary()

        try db.pool.write { db in
            try db.execute(sql: """
                INSERT INTO cloudkit_mapping (entityType, entityId, recordName, zoneName)
                VALUES ('entry', 1, 'rec-1', 'default')
                """)
        }

        // Duplicate should fail
        do {
            try db.pool.write { db in
                try db.execute(sql: """
                    INSERT INTO cloudkit_mapping (entityType, entityId, recordName, zoneName)
                    VALUES ('entry', 1, 'rec-2', 'default')
                    """)
            }
            Issue.record("Erwartete UNIQUE constraint violation")
        } catch {
            // Expected
        }
    }
}
