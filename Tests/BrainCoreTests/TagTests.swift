import Testing
import GRDB
@testable import BrainCore

@Suite("Tag Operations")
struct TagTests {

    private func makeServices() throws -> (TagService, EntryService, DatabaseManager) {
        let db = try DatabaseManager.temporary()
        return (TagService(pool: db.pool), EntryService(pool: db.pool), db)
    }

    @Test("Create and fetch tag")
    func createAndFetch() throws {
        let (svc, _, _) = try makeServices()

        let tag = try svc.create(Tag(name: "project/brain", color: "#ff0000"))
        #expect(tag.id != nil)

        let fetched = try svc.fetch(id: tag.id!)
        #expect(fetched?.name == "project/brain")
        #expect(fetched?.color == "#ff0000")
    }

    @Test("Fetch tag by name")
    func fetchByName() throws {
        let (svc, _, _) = try makeServices()

        try svc.create(Tag(name: "important"))

        let found = try svc.fetch(name: "important")
        #expect(found != nil)

        let notFound = try svc.fetch(name: "nonexistent")
        #expect(notFound == nil)
    }

    @Test("List tags ordered by name")
    func listOrdered() throws {
        let (svc, _, _) = try makeServices()

        try svc.create(Tag(name: "zebra"))
        try svc.create(Tag(name: "alpha"))
        try svc.create(Tag(name: "middle"))

        let tags = try svc.list()
        #expect(tags.count == 3)
        #expect(tags[0].name == "alpha")
        #expect(tags[1].name == "middle")
        #expect(tags[2].name == "zebra")
    }

    @Test("Attach and detach tags from entries")
    func attachDetach() throws {
        let (tagSvc, entrySvc, _) = try makeServices()

        let entry = try entrySvc.create(Entry(title: "Test"))
        let tag1 = try tagSvc.create(Tag(name: "tag1"))
        let tag2 = try tagSvc.create(Tag(name: "tag2"))

        try tagSvc.attach(tagId: tag1.id!, to: entry.id!)
        try tagSvc.attach(tagId: tag2.id!, to: entry.id!)

        var tags = try tagSvc.tags(for: entry.id!)
        #expect(tags.count == 2)

        try tagSvc.detach(tagId: tag1.id!, from: entry.id!)
        tags = try tagSvc.tags(for: entry.id!)
        #expect(tags.count == 1)
        #expect(tags[0].name == "tag2")
    }

    @Test("Tag names are unique")
    func uniqueNames() throws {
        let (svc, _, _) = try makeServices()

        try svc.create(Tag(name: "unique"))
        #expect(throws: (any Error).self) {
            try svc.create(Tag(name: "unique"))
        }
    }

    @Test("Delete tag")
    func deleteTag() throws {
        let (svc, _, _) = try makeServices()

        let tag = try svc.create(Tag(name: "to-delete"))
        try svc.delete(id: tag.id!)

        let fetched = try svc.fetch(id: tag.id!)
        #expect(fetched == nil)
    }

    // MARK: - Hierarchical queries

    @Test("Tags under prefix")
    func tagsUnder() throws {
        let (svc, _, _) = try makeServices()

        try svc.create(Tag(name: "projekt/brain"))
        try svc.create(Tag(name: "projekt/brain/ios"))
        try svc.create(Tag(name: "projekt/valitas"))
        try svc.create(Tag(name: "personal"))

        let projektTags = try svc.tagsUnder(prefix: "projekt/")
        #expect(projektTags.count == 3)
        #expect(projektTags.map(\.name).contains("projekt/brain"))
        #expect(projektTags.map(\.name).contains("projekt/brain/ios"))
        #expect(projektTags.map(\.name).contains("projekt/valitas"))

        let brainTags = try svc.tagsUnder(prefix: "projekt/brain")
        #expect(brainTags.count == 2)
    }

    @Test("Entries with tag prefix")
    func entriesWithTagPrefix() throws {
        let (tagSvc, entrySvc, _) = try makeServices()

        let tag1 = try tagSvc.create(Tag(name: "projekt/brain"))
        let tag2 = try tagSvc.create(Tag(name: "projekt/valitas"))
        let tag3 = try tagSvc.create(Tag(name: "personal"))

        let e1 = try entrySvc.create(Entry(title: "Brain entry"))
        let e2 = try entrySvc.create(Entry(title: "Valitas entry"))
        let e3 = try entrySvc.create(Entry(title: "Personal entry"))

        try tagSvc.attach(tagId: tag1.id!, to: e1.id!)
        try tagSvc.attach(tagId: tag2.id!, to: e2.id!)
        try tagSvc.attach(tagId: tag3.id!, to: e3.id!)

        let projektEntries = try tagSvc.entriesWithTagPrefix("projekt/")
        #expect(projektEntries.count == 2)

        let personalEntries = try tagSvc.entriesWithTagPrefix("personal")
        #expect(personalEntries.count == 1)
    }

    @Test("Tag counts")
    func tagCounts() throws {
        let (tagSvc, entrySvc, _) = try makeServices()

        let tag1 = try tagSvc.create(Tag(name: "popular"))
        let tag2 = try tagSvc.create(Tag(name: "rare"))
        let tag3 = try tagSvc.create(Tag(name: "empty"))

        let e1 = try entrySvc.create(Entry(title: "E1"))
        let e2 = try entrySvc.create(Entry(title: "E2"))
        let e3 = try entrySvc.create(Entry(title: "E3"))

        try tagSvc.attach(tagId: tag1.id!, to: e1.id!)
        try tagSvc.attach(tagId: tag1.id!, to: e2.id!)
        try tagSvc.attach(tagId: tag1.id!, to: e3.id!)
        try tagSvc.attach(tagId: tag2.id!, to: e1.id!)

        let counts = try tagSvc.tagCounts()
        #expect(counts.count == 3)
        // Sorted by count desc
        #expect(counts[0].tag.name == "popular")
        #expect(counts[0].count == 3)
        #expect(counts[1].tag.name == "rare")
        #expect(counts[1].count == 1)
        #expect(counts[2].tag.name == "empty")
        #expect(counts[2].count == 0)
    }

    @Test("Tag counts exclude soft-deleted entries")
    func tagCountsExcludeDeleted() throws {
        let (tagSvc, entrySvc, _) = try makeServices()

        let tag = try tagSvc.create(Tag(name: "test"))
        let e1 = try entrySvc.create(Entry(title: "Active"))
        let e2 = try entrySvc.create(Entry(title: "Deleted"))

        try tagSvc.attach(tagId: tag.id!, to: e1.id!)
        try tagSvc.attach(tagId: tag.id!, to: e2.id!)
        try entrySvc.delete(id: e2.id!)

        let counts = try tagSvc.tagCounts()
        #expect(counts.first?.count == 1)
    }

    @Test("Empty prefix returns all tags")
    func emptyPrefixReturnsAll() throws {
        let (svc, _, _) = try makeServices()

        try svc.create(Tag(name: "a"))
        try svc.create(Tag(name: "b"))

        let all = try svc.tagsUnder(prefix: "")
        #expect(all.count == 2)
    }
}
