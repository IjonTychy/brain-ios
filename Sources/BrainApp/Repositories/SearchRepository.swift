import Foundation
import BrainCore
import GRDB

// Search operations for ActionHandlers and Views.
// Thread-safe: uses GRDB pool operations only.
struct SearchRepository: Sendable {
    private let searchService: SearchService

    init(pool: DatabasePool) {
        self.searchService = SearchService(pool: pool)
    }

    func search(query: String, limit: Int = 20) throws -> [Entry] {
        try searchService.search(query: query, limit: limit).map(\.entry)
    }

    func autocomplete(prefix: String, limit: Int = 10) throws -> [Entry] {
        try searchService.autocomplete(prefix: prefix, limit: limit)
    }
}
