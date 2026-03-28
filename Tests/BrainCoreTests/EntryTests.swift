import Testing
import GRDB
@testable import BrainCore

@Suite("Entry CRUD")
struct EntryTests {

    private func makeService() throws -> (EntryService, DatabaseManager) {
        let db = try DatabaseManager.temporary()
        return (EntryService(pool: db.pool), db)
    }

    @Test("Create and fetch entry")
    func createAndFetch() throws {
        let (svc, _) = try makeService()

        let created = try svc.create(Entry(type: .thought, title: "Hello", body: "World"))
        #expect(created.id != nil)
        #expect(created.title == "Hello")

        let fetched = try svc.fetch(id: created.id!)
        #expect(fetched != nil)
        #expect(fetched?.title == "Hello")
        #expect(fetched?.body == "World")
        #expect(fetched?.type == .thought)
    }

    @Test("List entries with type filter")
    func listWithFilter() throws {
        let (svc, _) = try makeService()

        try svc.create(Entry(type: .thought, title: "Thought 1"))
        try svc.create(Entry(type: .task, title: "Task 1"))
        try svc.create(Entry(type: .thought, title: "Thought 2"))

        let thoughts = try svc.list(type: .thought)
        #expect(thoughts.count == 2)

        let tasks = try svc.list(type: .task)
        #expect(tasks.count == 1)

        let all = try svc.list()
        #expect(all.count == 3)
    }

    @Test("Update entry")
    func update() throws {
        let (svc, _) = try makeService()

        var entry = try svc.create(Entry(type: .thought, title: "Original"))
        entry.title = "Updated"
        let updated = try svc.update(entry)

        #expect(updated.title == "Updated")
        #expect(updated.updatedAt != nil)

        let fetched = try svc.fetch(id: entry.id!)
        #expect(fetched?.title == "Updated")
    }

    @Test("Soft delete hides entry from list and fetch")
    func softDelete() throws {
        let (svc, _) = try makeService()

        let entry = try svc.create(Entry(type: .thought, title: "To Delete"))
        try svc.delete(id: entry.id!)

        let fetched = try svc.fetch(id: entry.id!)
        #expect(fetched == nil)

        let all = try svc.list()
        #expect(all.isEmpty)
    }

    @Test("Hard delete removes entry permanently")
    func hardDelete() throws {
        let (svc, db) = try makeService()

        let entry = try svc.create(Entry(type: .thought, title: "To Delete"))
        try svc.hardDelete(id: entry.id!)

        // Even a direct DB query should find nothing
        let count = try db.pool.read { db in
            try Entry.fetchCount(db)
        }
        #expect(count == 0)
    }

    @Test("List with status filter")
    func listWithStatus() throws {
        let (svc, _) = try makeService()

        try svc.create(Entry(type: .task, title: "Active", status: .active))
        try svc.create(Entry(type: .task, title: "Done", status: .done))

        let active = try svc.list(status: .active)
        #expect(active.count == 1)
        #expect(active.first?.title == "Active")
    }

    @Test("Entry defaults are correct")
    func defaults() throws {
        let (svc, _) = try makeService()

        let entry = try svc.create(Entry())
        #expect(entry.type == .thought)
        #expect(entry.status == .active)
        #expect(entry.priority == 0)
        #expect(entry.source == .manual)
    }

    // MARK: - Phase 1: Extended operations

    @Test("Count entries with filters")
    func count() throws {
        let (svc, _) = try makeService()

        try svc.create(Entry(type: .thought, title: "T1"))
        try svc.create(Entry(type: .thought, title: "T2"))
        try svc.create(Entry(type: .task, title: "Task1", status: .done))

        #expect(try svc.count() == 3)
        #expect(try svc.count(type: .thought) == 2)
        #expect(try svc.count(type: .task) == 1)
        #expect(try svc.count(status: .done) == 1)
    }

    @Test("Count excludes soft-deleted entries")
    func countExcludesDeleted() throws {
        let (svc, _) = try makeService()

        let entry = try svc.create(Entry(type: .thought, title: "Will delete"))
        try svc.create(Entry(type: .thought, title: "Stays"))
        try svc.delete(id: entry.id!)

        #expect(try svc.count() == 1)
    }

    @Test("Paginated listing with cursor")
    func pagination() throws {
        let (svc, _) = try makeService()

        // Create entries with known ordering
        let e1 = try svc.create(Entry(type: .thought, title: "First", createdAt: "2026-01-01T00:00:00Z"))
        let e2 = try svc.create(Entry(type: .thought, title: "Second", createdAt: "2026-01-02T00:00:00Z"))
        let e3 = try svc.create(Entry(type: .thought, title: "Third", createdAt: "2026-01-03T00:00:00Z"))

        // First page (newest first)
        let page1 = try svc.listPaginated(limit: 2)
        #expect(page1.count == 2)
        #expect(page1[0].title == "Third")
        #expect(page1[1].title == "Second")

        // Second page using cursor from last entry
        let cursor = page1.last!.createdAt!
        let page2 = try svc.listPaginated(before: cursor, limit: 2)
        #expect(page2.count == 1)
        #expect(page2[0].title == "First")

        // Suppress unused variable warnings
        _ = e1; _ = e2; _ = e3
    }

    @Test("List by date range")
    func dateRange() throws {
        let (svc, _) = try makeService()

        try svc.create(Entry(type: .thought, title: "Jan", createdAt: "2026-01-15T00:00:00Z"))
        try svc.create(Entry(type: .thought, title: "Feb", createdAt: "2026-02-15T00:00:00Z"))
        try svc.create(Entry(type: .thought, title: "Mar", createdAt: "2026-03-15T00:00:00Z"))

        let febEntries = try svc.listByDateRange(
            from: "2026-02-01T00:00:00Z",
            to: "2026-02-28T23:59:59Z"
        )
        #expect(febEntries.count == 1)
        #expect(febEntries.first?.title == "Feb")
    }

    @Test("Mark entry as done")
    func markDone() throws {
        let (svc, _) = try makeService()

        let entry = try svc.create(Entry(type: .task, title: "Todo"))
        let done = try svc.markDone(id: entry.id!)

        #expect(done?.status == .done)
        #expect(done?.updatedAt != nil)

        let fetched = try svc.fetch(id: entry.id!)
        #expect(fetched?.status == .done)
    }

    @Test("Archive entry")
    func archive() throws {
        let (svc, _) = try makeService()

        let entry = try svc.create(Entry(type: .thought, title: "Old thought"))
        let archived = try svc.archive(id: entry.id!)
        #expect(archived?.status == .archived)
    }

    @Test("Restore soft-deleted entry")
    func restore() throws {
        let (svc, _) = try makeService()

        let entry = try svc.create(Entry(type: .thought, title: "Deleted"))
        try svc.delete(id: entry.id!)

        // Can't fetch normally (soft-deleted)
        #expect(try svc.fetch(id: entry.id!) == nil)

        // Restore brings it back
        let restored = try svc.restore(id: entry.id!)
        #expect(restored != nil)
        #expect(restored?.status == .active)
        #expect(restored?.deletedAt == nil)

        // Now fetchable again
        #expect(try svc.fetch(id: entry.id!) != nil)
    }

    @Test("Restore archived entry")
    func restoreArchived() throws {
        let (svc, _) = try makeService()

        let entry = try svc.create(Entry(type: .thought, title: "Archived"))
        try svc.archive(id: entry.id!)
        let restored = try svc.restore(id: entry.id!)
        #expect(restored?.status == .active)
    }
}
