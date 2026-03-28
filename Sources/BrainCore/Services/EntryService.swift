import Foundation
import GRDB

// CRUD operations for entries.
public struct EntryService: Sendable {

    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    // Create a new entry and return it with its assigned id.
    @discardableResult
    public func create(_ entry: Entry) throws -> Entry {
        try pool.write { db in
            var record = entry
            try record.insert(db)
            return record
        }
    }

    // Fetch a single entry by id (returns nil if not found or soft-deleted).
    public func fetch(id: Int64) throws -> Entry? {
        try pool.read { db in
            try Entry
                .filter(Column("id") == id)
                .filter(Column("deletedAt") == nil)
                .fetchOne(db)
        }
    }

    // List entries with optional type filter, ordered by creation date descending.
    // M5: Added offset parameter for pagination.
    public func list(type: EntryType? = nil, status: EntryStatus? = nil, limit: Int = 50, offset: Int = 0) throws -> [Entry] {
        try pool.read { db in
            var request = Entry
                .filter(Column("deletedAt") == nil)
                .order(Column("createdAt").desc)
                .limit(min(limit, 500), offset: max(offset, 0))

            if let type {
                request = request.filter(Column("type") == type)
            }
            if let status {
                request = request.filter(Column("status") == status)
            }

            return try request.fetchAll(db)
        }
    }

    // Update an existing entry. Sets updatedAt automatically.
    @discardableResult
    public func update(_ entry: Entry) throws -> Entry {
        try pool.write { db in
            var record = entry
            record.updatedAt = Self.iso8601Now()
            try record.update(db)
            return record
        }
    }

    // Soft-delete an entry by setting deletedAt.
    public func delete(id: Int64) throws {
        try pool.write { db in
            if var entry = try Entry.fetchOne(db, key: id) {
                entry.deletedAt = Self.iso8601Now()
                try entry.update(db)
            }
        }
    }

    // Hard-delete an entry permanently.
    public func hardDelete(id: Int64) throws {
        try pool.write { db in
            _ = try Entry.deleteOne(db, key: id)
        }
    }

    // MARK: - Counting

    // Count entries with optional filters.
    public func count(type: EntryType? = nil, status: EntryStatus? = nil) throws -> Int {
        try pool.read { db in
            var request = Entry.filter(Column("deletedAt") == nil)
            if let type { request = request.filter(Column("type") == type) }
            if let status { request = request.filter(Column("status") == status) }
            return try request.fetchCount(db)
        }
    }

    // MARK: - Pagination

    // Cursor-based pagination using createdAt. Pass the createdAt of the last
    // entry from the previous page as `before` to get the next page.
    public func listPaginated(
        before cursor: String? = nil,
        type: EntryType? = nil,
        status: EntryStatus? = nil,
        limit: Int = 20
    ) throws -> [Entry] {
        try pool.read { db in
            var request = Entry
                .filter(Column("deletedAt") == nil)
                .order(Column("createdAt").desc)
                .limit(min(limit, 500))

            if let cursor {
                request = request.filter(Column("createdAt") < cursor)
            }
            if let type { request = request.filter(Column("type") == type) }
            if let status { request = request.filter(Column("status") == status) }

            return try request.fetchAll(db)
        }
    }

    // MARK: - Date range queries

    // List entries created within a date range (ISO8601 strings).
    public func listByDateRange(
        from: String,
        to: String,
        type: EntryType? = nil,
        limit: Int = 100
    ) throws -> [Entry] {
        try pool.read { db in
            var request = Entry
                .filter(Column("deletedAt") == nil)
                .filter(Column("createdAt") >= from)
                .filter(Column("createdAt") <= to)
                .order(Column("createdAt").desc)
                .limit(limit)

            if let type { request = request.filter(Column("type") == type) }
            return try request.fetchAll(db)
        }
    }

    // MARK: - Status transitions

    // Mark an entry as done.
    @discardableResult
    public func markDone(id: Int64) throws -> Entry? {
        try setStatus(id: id, status: .done)
    }

    // Archive an entry.
    @discardableResult
    public func archive(id: Int64) throws -> Entry? {
        try setStatus(id: id, status: .archived)
    }

    // Restore a soft-deleted or archived entry to active.
    @discardableResult
    public func restore(id: Int64) throws -> Entry? {
        try pool.write { db in
            // Fetch even if soft-deleted
            guard var entry = try Entry.filter(Column("id") == id).fetchOne(db) else {
                return nil
            }
            entry.status = .active
            entry.deletedAt = nil
            entry.updatedAt = Self.iso8601Now()
            try entry.update(db)
            return entry
        }
    }

    // MARK: - Helpers

    private func setStatus(id: Int64, status: EntryStatus) throws -> Entry? {
        try pool.write { db in
            guard var entry = try Entry
                .filter(Column("id") == id)
                .filter(Column("deletedAt") == nil)
                .fetchOne(db)
            else { return nil }
            entry.status = status
            entry.updatedAt = Self.iso8601Now()
            try entry.update(db)
            return entry
        }
    }

    private static func iso8601Now() -> String {
        BrainDateFormatting.iso8601Now()
    }
}
