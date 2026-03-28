import Foundation
import BrainCore
import GRDB

// Tag operations for ActionHandlers and Views.
// Thread-safe: uses GRDB pool operations only.
struct TagRepository: Sendable {
    private let tagService: TagService
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.tagService = TagService(pool: pool)
        self.pool = pool
    }

    // Find-or-create tag and attach in a single write transaction to avoid TOCTOU race.
    func add(entryId: Int64, tagName: String) throws {
        try pool.write { db in
            let tag: Tag
            if let existing = try Tag.filter(Column("name") == tagName).fetchOne(db) {
                tag = existing
            } else {
                var newTag = Tag(name: tagName)
                try newTag.insert(db)
                tag = newTag
            }
            guard let tagId = tag.id else { return }
            // Check if already attached
            let exists = try EntryTag
                .filter(Column("entryId") == entryId)
                .filter(Column("tagId") == tagId)
                .fetchCount(db) > 0
            if !exists {
                let entryTag = EntryTag(entryId: entryId, tagId: tagId)
                try entryTag.insert(db)
            }
        }
    }

    func remove(entryId: Int64, tagName: String) throws {
        guard let tag = try tagService.fetch(name: tagName),
              let tagId = tag.id else { return }
        try tagService.detach(tagId: tagId, from: entryId)
    }

    func list() throws -> [Tag] {
        try tagService.list()
    }

    func counts() throws -> [(tag: Tag, count: Int)] {
        try tagService.tagCounts()
    }
}
