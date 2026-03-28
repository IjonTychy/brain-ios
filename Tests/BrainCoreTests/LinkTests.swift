import Testing
import GRDB
@testable import BrainCore

@Suite("Bi-directional Links")
struct LinkTests {

    private func makeServices() throws -> (LinkService, EntryService, DatabaseManager) {
        let db = try DatabaseManager.temporary()
        return (LinkService(pool: db.pool), EntryService(pool: db.pool), db)
    }

    @Test("Create link between entries")
    func createLink() throws {
        let (linkSvc, entrySvc, _) = try makeServices()

        let a = try entrySvc.create(Entry(title: "A"))
        let b = try entrySvc.create(Entry(title: "B"))

        let link = try linkSvc.create(sourceId: a.id!, targetId: b.id!)
        #expect(link.id != nil)
        #expect(link.relation == .related)
    }

    @Test("Links are bi-directional when queried")
    func bidirectional() throws {
        let (linkSvc, entrySvc, _) = try makeServices()

        let a = try entrySvc.create(Entry(title: "A"))
        let b = try entrySvc.create(Entry(title: "B"))
        try linkSvc.create(sourceId: a.id!, targetId: b.id!)

        // Query from A should find the link
        let linksFromA = try linkSvc.links(for: a.id!)
        #expect(linksFromA.count == 1)

        // Query from B should also find the link
        let linksFromB = try linkSvc.links(for: b.id!)
        #expect(linksFromB.count == 1)

        // Both should reference the same link
        #expect(linksFromA[0].id == linksFromB[0].id)
    }

    @Test("Linked entries returned bi-directionally")
    func linkedEntries() throws {
        let (linkSvc, entrySvc, _) = try makeServices()

        let a = try entrySvc.create(Entry(title: "A"))
        let b = try entrySvc.create(Entry(title: "B"))
        let c = try entrySvc.create(Entry(title: "C"))

        try linkSvc.create(sourceId: a.id!, targetId: b.id!)
        try linkSvc.create(sourceId: c.id!, targetId: a.id!)

        let linkedToA = try linkSvc.linkedEntries(for: a.id!)
        #expect(linkedToA.count == 2)
        let titles = Set(linkedToA.compactMap(\.title))
        #expect(titles.contains("B"))
        #expect(titles.contains("C"))
    }

    @Test("Delete link between specific entries")
    func deleteBetween() throws {
        let (linkSvc, entrySvc, _) = try makeServices()

        let a = try entrySvc.create(Entry(title: "A"))
        let b = try entrySvc.create(Entry(title: "B"))
        try linkSvc.create(sourceId: a.id!, targetId: b.id!)

        try linkSvc.delete(between: a.id!, and: b.id!)
        let links = try linkSvc.links(for: a.id!)
        #expect(links.isEmpty)
    }

    @Test("Delete between works in reverse direction")
    func deleteBetweenReverse() throws {
        let (linkSvc, entrySvc, _) = try makeServices()

        let a = try entrySvc.create(Entry(title: "A"))
        let b = try entrySvc.create(Entry(title: "B"))
        try linkSvc.create(sourceId: a.id!, targetId: b.id!)

        // Delete using reversed arguments
        try linkSvc.delete(between: b.id!, and: a.id!)
        let links = try linkSvc.links(for: a.id!)
        #expect(links.isEmpty)
    }

    @Test("Link uniqueness constraint")
    func uniqueConstraint() throws {
        let (linkSvc, entrySvc, _) = try makeServices()

        let a = try entrySvc.create(Entry(title: "A"))
        let b = try entrySvc.create(Entry(title: "B"))
        try linkSvc.create(sourceId: a.id!, targetId: b.id!)

        #expect(throws: (any Error).self) {
            try linkSvc.create(sourceId: a.id!, targetId: b.id!)
        }
    }

    @Test("Self-link is rejected")
    func selfLink() throws {
        let (linkSvc, entrySvc, _) = try makeServices()

        let a = try entrySvc.create(Entry(title: "A"))

        #expect(throws: LinkServiceError.self) {
            try linkSvc.create(sourceId: a.id!, targetId: a.id!)
        }
    }

    @Test("Link with custom relation type")
    func customRelation() throws {
        let (linkSvc, entrySvc, _) = try makeServices()

        let a = try entrySvc.create(Entry(title: "Parent"))
        let b = try entrySvc.create(Entry(title: "Child"))

        let link = try linkSvc.create(sourceId: a.id!, targetId: b.id!, relation: .parent)
        #expect(link.relation == .parent)
    }

    // MARK: - Phase 1: Extended queries

    @Test("Filter links by relation type")
    func filterByRelation() throws {
        let (linkSvc, entrySvc, _) = try makeServices()

        let a = try entrySvc.create(Entry(title: "A"))
        let b = try entrySvc.create(Entry(title: "B"))
        let c = try entrySvc.create(Entry(title: "C"))

        try linkSvc.create(sourceId: a.id!, targetId: b.id!, relation: .related)
        try linkSvc.create(sourceId: a.id!, targetId: c.id!, relation: .parent)

        let related = try linkSvc.links(for: a.id!, relation: .related)
        #expect(related.count == 1)

        let parent = try linkSvc.links(for: a.id!, relation: .parent)
        #expect(parent.count == 1)

        let blocks = try linkSvc.links(for: a.id!, relation: .blocks)
        #expect(blocks.isEmpty)
    }

    @Test("Link count")
    func linkCount() throws {
        let (linkSvc, entrySvc, _) = try makeServices()

        let a = try entrySvc.create(Entry(title: "A"))
        let b = try entrySvc.create(Entry(title: "B"))
        let c = try entrySvc.create(Entry(title: "C"))

        try linkSvc.create(sourceId: a.id!, targetId: b.id!)
        try linkSvc.create(sourceId: c.id!, targetId: a.id!)

        #expect(try linkSvc.linkCount(for: a.id!) == 2)
        #expect(try linkSvc.linkCount(for: b.id!) == 1)
    }

    @Test("Linked entry IDs without full fetch")
    func linkedEntryIds() throws {
        let (linkSvc, entrySvc, _) = try makeServices()

        let a = try entrySvc.create(Entry(title: "A"))
        let b = try entrySvc.create(Entry(title: "B"))
        let c = try entrySvc.create(Entry(title: "C"))

        try linkSvc.create(sourceId: a.id!, targetId: b.id!)
        try linkSvc.create(sourceId: c.id!, targetId: a.id!)

        let ids = try linkSvc.linkedEntryIds(for: a.id!)
        #expect(ids.count == 2)
        #expect(ids.contains(b.id!))
        #expect(ids.contains(c.id!))
    }
}
