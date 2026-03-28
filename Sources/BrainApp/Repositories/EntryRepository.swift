import Foundation
import BrainCore
import GRDB

// Entry CRUD operations for ActionHandlers and Views.
// Thread-safe: uses GRDB pool operations only.
struct EntryRepository: Sendable {
    private let entryService: EntryService

    init(pool: DatabasePool) {
        self.entryService = EntryService(pool: pool)
    }

    @discardableResult
    func create(title: String, type: String = "thought", body: String? = nil) throws -> Entry {
        let entryType = EntryType(rawValue: type) ?? .thought
        return try entryService.create(Entry(type: entryType, title: title, body: body))
    }

    func fetch(id: Int64) throws -> Entry? {
        try entryService.fetch(id: id)
    }

    func list(limit: Int = 50) throws -> [Entry] {
        try entryService.list(limit: limit)
    }

    @discardableResult
    func update(id: Int64, title: String?, body: String?) throws -> Entry? {
        guard var entry = try entryService.fetch(id: id) else { return nil }
        if let title { entry.title = title }
        if let body { entry.body = body }
        return try entryService.update(entry)
    }

    func delete(id: Int64) throws {
        try entryService.delete(id: id)
    }

    @discardableResult
    func markDone(id: Int64) throws -> Entry? {
        try entryService.markDone(id: id)
    }

    @discardableResult
    func archive(id: Int64) throws -> Entry? {
        try entryService.archive(id: id)
    }

    @discardableResult
    func restore(id: Int64) throws -> Entry? {
        try entryService.restore(id: id)
    }
}
