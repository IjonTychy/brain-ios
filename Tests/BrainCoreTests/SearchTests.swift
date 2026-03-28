import Testing
import GRDB
@testable import BrainCore

@Suite("FTS5 Search")
struct SearchTests {

    private func makeServices() throws -> (SearchService, EntryService) {
        let db = try DatabaseManager.temporary()
        return (SearchService(pool: db.pool), EntryService(pool: db.pool))
    }

    @Test("Basic FTS5 search finds matching entries")
    func basicSearch() throws {
        let (searchSvc, entrySvc) = try makeServices()

        try entrySvc.create(Entry(title: "Swift programming", body: "Learn Swift for iOS"))
        try entrySvc.create(Entry(title: "Python scripting", body: "Python is great"))
        try entrySvc.create(Entry(title: "Swift UI", body: "Building interfaces with SwiftUI"))

        let results = try searchSvc.search(query: "Swift")
        #expect(results.count == 2)
    }

    @Test("Search in body text")
    func bodySearch() throws {
        let (searchSvc, entrySvc) = try makeServices()

        try entrySvc.create(Entry(title: "Meeting notes", body: "Discussed the database migration plan"))
        try entrySvc.create(Entry(title: "Grocery list", body: "Milk, eggs, bread"))

        let results = try searchSvc.search(query: "migration")
        #expect(results.count == 1)
        #expect(results[0].entry.title == "Meeting notes")
    }

    @Test("Empty query returns no results")
    func emptyQuery() throws {
        let (searchSvc, entrySvc) = try makeServices()

        try entrySvc.create(Entry(title: "Something"))
        let results = try searchSvc.search(query: "")
        #expect(results.isEmpty)
    }

    @Test("Search excludes soft-deleted entries")
    func excludeDeleted() throws {
        let (searchSvc, entrySvc) = try makeServices()

        let entry = try entrySvc.create(Entry(title: "Findable entry", body: "unique_keyword"))
        try entrySvc.delete(id: entry.id!)

        let results = try searchSvc.search(query: "unique_keyword")
        #expect(results.isEmpty)
    }

    @Test("Search respects limit")
    func limitResults() throws {
        let (searchSvc, entrySvc) = try makeServices()

        for i in 1...10 {
            try entrySvc.create(Entry(title: "Item \(i)", body: "searchterm"))
        }

        let results = try searchSvc.search(query: "searchterm", limit: 3)
        #expect(results.count == 3)
    }

    // MARK: - Phase 1: Advanced search

    @Test("Search with type filter")
    func searchWithTypeFilter() throws {
        let (searchSvc, entrySvc) = try makeServices()

        try entrySvc.create(Entry(type: .thought, title: "Swift thought", body: "thinking about swift"))
        try entrySvc.create(Entry(type: .task, title: "Swift task", body: "learn swift"))

        let thoughts = try searchSvc.searchWithFilters(query: "swift", type: .thought)
        #expect(thoughts.count == 1)
        #expect(thoughts.first?.entry.type == .thought)
    }

    @Test("Search with tag filter")
    func searchWithTagFilter() throws {
        let db = try DatabaseManager.temporary()
        let searchSvc = SearchService(pool: db.pool)
        let entrySvc = EntryService(pool: db.pool)
        let tagSvc = TagService(pool: db.pool)

        let e1 = try entrySvc.create(Entry(title: "Tagged entry", body: "findme"))
        let e2 = try entrySvc.create(Entry(title: "Untagged entry", body: "findme"))

        let tag = try tagSvc.create(Tag(name: "important"))
        try tagSvc.attach(tagId: tag.id!, to: e1.id!)

        let results = try searchSvc.searchWithFilters(query: "findme", tags: ["important"])
        #expect(results.count == 1)
        #expect(results.first?.entry.title == "Tagged entry")

        _ = e2 // suppress warning
    }

    @Test("Search with custom weights")
    func searchWithWeights() throws {
        let (searchSvc, entrySvc) = try makeServices()

        // Title match should rank higher with high title weight
        try entrySvc.create(Entry(title: "Swift programming", body: "unrelated body"))
        try entrySvc.create(Entry(title: "unrelated title", body: "Swift in the body"))

        let results = try searchSvc.searchWithWeights(query: "Swift", titleWeight: 10.0, bodyWeight: 1.0)
        #expect(results.count == 2)
        // Title match should come first (lower BM25 score = better)
        #expect(results.first?.entry.title == "Swift programming")
    }

    @Test("Autocomplete with prefix")
    func autocomplete() throws {
        let (searchSvc, entrySvc) = try makeServices()

        try entrySvc.create(Entry(title: "Meeting with Sarah"))
        try entrySvc.create(Entry(title: "Meeting notes"))
        try entrySvc.create(Entry(title: "Grocery list"))

        let results = try searchSvc.autocomplete(prefix: "Meet")
        #expect(results.count == 2)
    }

    @Test("Autocomplete empty prefix returns nothing")
    func autocompleteEmpty() throws {
        let (searchSvc, entrySvc) = try makeServices()

        try entrySvc.create(Entry(title: "Something"))
        let results = try searchSvc.autocomplete(prefix: "")
        #expect(results.isEmpty)
    }
}
