import Foundation
import BrainCore
import GRDB

// Link operations for ActionHandlers and Views.
// Thread-safe: uses GRDB pool operations only.
struct LinkRepository: Sendable {
    private let linkService: LinkService

    init(pool: DatabasePool) {
        self.linkService = LinkService(pool: pool)
    }

    @discardableResult
    func create(sourceId: Int64, targetId: Int64, relation: String = "related") throws -> Link {
        let rel = LinkRelation(rawValue: relation) ?? .related
        return try linkService.create(sourceId: sourceId, targetId: targetId, relation: rel)
    }

    func delete(sourceId: Int64, targetId: Int64) throws {
        try linkService.delete(between: sourceId, and: targetId)
    }

    func linkedEntries(for entryId: Int64) throws -> [Entry] {
        try linkService.linkedEntries(for: entryId)
    }
}
