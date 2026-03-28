import Testing
import Foundation
import GRDB
@testable import BrainCore

// Tests for the data-layer queries that ConversationMemory relies on.
//
// ConversationMemory lives in BrainApp and cannot be imported here, but the
// underlying SQL/GRDB queries it delegates to are pure BrainCore.  These tests
// exercise every query category ConversationMemory uses so regressions are
// caught without needing an iOS Simulator.
@Suite("Conversation Memory Queries")
struct ConversationMemoryQueryTests {

    // MARK: - 1. Find entries by person name (LIKE on title/body)

    @Suite("Find by person name")
    struct FindByPersonNameTests {

        private func makeServices() throws -> (EntryService, DatabaseManager) {
            let db = try DatabaseManager.temporary()
            return (EntryService(pool: db.pool), db)
        }

        @Test("LIKE title match finds entry mentioning person")
        func likeMatchInTitle() throws {
            let (svc, db) = try makeServices()

            try svc.create(Entry(title: "Meeting with Sarah", body: "Discussed Q1 goals"))
            try svc.create(Entry(title: "Groceries", body: "Milk, eggs"))

            let results = try db.pool.read { db in
                try Entry
                    .filter(Column("deletedAt") == nil)
                    .filter(
                        Column("title").like("%Sarah%") ||
                        Column("body").like("%Sarah%")
                    )
                    .fetchAll(db)
            }

            #expect(results.count == 1)
            #expect(results.first?.title == "Meeting with Sarah")
        }

        @Test("LIKE body match finds entry mentioning person")
        func likeMatchInBody() throws {
            let (svc, db) = try makeServices()

            try svc.create(Entry(title: "Project update", body: "Sync with Thomas tomorrow"))
            try svc.create(Entry(title: "Standalone note", body: "No people mentioned"))

            let results = try db.pool.read { db in
                try Entry
                    .filter(Column("deletedAt") == nil)
                    .filter(
                        Column("title").like("%Thomas%") ||
                        Column("body").like("%Thomas%")
                    )
                    .fetchAll(db)
            }

            #expect(results.count == 1)
            #expect(results.first?.body?.contains("Thomas") == true)
        }

        @Test("LIKE match is case-insensitive via SQLite default collation")
        func likeIsCaseInsensitive() throws {
            let (svc, db) = try makeServices()

            try svc.create(Entry(title: "Call SARAH about the proposal"))

            let results = try db.pool.read { db in
                try Entry
                    .filter(Column("deletedAt") == nil)
                    .filter(
                        Column("title").like("%sarah%") ||
                        Column("body").like("%sarah%")
                    )
                    .fetchAll(db)
            }

            #expect(results.count == 1)
        }

        @Test("LIKE query returns multiple entries mentioning same person")
        func likeMatchesMultipleEntries() throws {
            let (svc, db) = try makeServices()

            try svc.create(Entry(title: "Email from Lena", body: "She asked about the report"))
            try svc.create(Entry(title: "Dinner plans", body: "Invited Lena and Marc"))
            try svc.create(Entry(title: "Unrelated note", body: "Nothing here"))

            let results = try db.pool.read { db in
                try Entry
                    .filter(Column("deletedAt") == nil)
                    .filter(
                        Column("title").like("%Lena%") ||
                        Column("body").like("%Lena%")
                    )
                    .fetchAll(db)
            }

            #expect(results.count == 2)
        }

        @Test("LIKE query excludes soft-deleted entries")
        func likeExcludesSoftDeleted() throws {
            let (svc, db) = try makeServices()

            let entry = try svc.create(Entry(title: "Note about Jonas"))
            try svc.delete(id: entry.id!)

            let results = try db.pool.read { db in
                try Entry
                    .filter(Column("deletedAt") == nil)
                    .filter(
                        Column("title").like("%Jonas%") ||
                        Column("body").like("%Jonas%")
                    )
                    .fetchAll(db)
            }

            #expect(results.isEmpty)
        }

        @Test("LIKE query with empty name returns all non-deleted entries")
        func likeWithEmptyNameMatchesAll() throws {
            let (svc, db) = try makeServices()

            try svc.create(Entry(title: "A"))
            try svc.create(Entry(title: "B"))

            let results = try db.pool.read { db in
                try Entry
                    .filter(Column("deletedAt") == nil)
                    .filter(
                        Column("title").like("%%") ||
                        Column("body").like("%%")
                    )
                    .fetchAll(db)
            }

            // %% matches everything — result depends on SQLite; at least both entries visible
            #expect(results.count >= 2)
        }

        @Test("LIKE query returns no results when person name not found")
        func likeNoMatch() throws {
            let (svc, db) = try makeServices()

            try svc.create(Entry(title: "Random thought", body: "About nothing specific"))

            let results = try db.pool.read { db in
                try Entry
                    .filter(Column("deletedAt") == nil)
                    .filter(
                        Column("title").like("%Zephyrine%") ||
                        Column("body").like("%Zephyrine%")
                    )
                    .fetchAll(db)
            }

            #expect(results.isEmpty)
        }
    }

    // MARK: - 2. Find entries by topic (FTS5)

    @Suite("Find by topic via FTS5")
    struct FindByTopicFTS5Tests {

        private func makeServices() throws -> (EntryService, SearchService) {
            let db = try DatabaseManager.temporary()
            return (EntryService(pool: db.pool), SearchService(pool: db.pool))
        }

        @Test("FTS5 search finds entries whose title contains the topic")
        func fts5TitleMatch() throws {
            let (svc, search) = try makeServices()

            try svc.create(Entry(title: "Architecture review", body: "Discussed database schema"))
            try svc.create(Entry(title: "Grocery list", body: "Milk, eggs, bread"))

            let results = try search.search(query: "Architecture")
            #expect(results.count == 1)
            #expect(results.first?.entry.title == "Architecture review")
        }

        @Test("FTS5 search finds entries whose body contains the topic")
        func fts5BodyMatch() throws {
            let (svc, search) = try makeServices()

            try svc.create(Entry(title: "Meeting notes", body: "Discussed the roadmap for Q2"))
            try svc.create(Entry(title: "Personal log", body: "Had a great breakfast"))

            let results = try search.search(query: "roadmap")
            #expect(results.count == 1)
            #expect(results.first?.entry.title == "Meeting notes")
        }

        @Test("FTS5 search returns empty for unknown topic")
        func fts5NoMatch() throws {
            let (svc, search) = try makeServices()

            try svc.create(Entry(title: "Ordinary note", body: "Nothing special here"))

            let results = try search.search(query: "quantum_entanglement_xyzzy")
            #expect(results.isEmpty)
        }

        @Test("FTS5 search returns results from multiple matching entries")
        func fts5MultipleMatches() throws {
            let (svc, search) = try makeServices()

            try svc.create(Entry(title: "SwiftUI tips", body: "Using View modifiers"))
            try svc.create(Entry(title: "Swift async/await", body: "Concurrency in Swift"))
            try svc.create(Entry(title: "Python notes", body: "Data science with pandas"))

            let results = try search.search(query: "Swift")
            #expect(results.count == 2)
        }

        @Test("FTS5 search excludes soft-deleted entries")
        func fts5ExcludesDeleted() throws {
            let (svc, search) = try makeServices()

            let entry = try svc.create(Entry(title: "Deleted thought", body: "findme_unique_kw"))
            try svc.delete(id: entry.id!)

            let results = try search.search(query: "findme_unique_kw")
            #expect(results.isEmpty)
        }

        @Test("FTS5 search with type filter returns only matching type")
        func fts5WithTypeFilter() throws {
            let (svc, search) = try makeServices()

            try svc.create(Entry(type: .thought, title: "Brain idea", body: "topic_xyz"))
            try svc.create(Entry(type: .task, title: "Brain task", body: "topic_xyz"))

            let thoughts = try search.searchWithFilters(query: "topic_xyz", type: .thought)
            #expect(thoughts.count == 1)
            #expect(thoughts.first?.entry.type == .thought)

            let tasks = try search.searchWithFilters(query: "topic_xyz", type: .task)
            #expect(tasks.count == 1)
            #expect(tasks.first?.entry.type == .task)
        }

        @Test("FTS5 empty query returns no results")
        func fts5EmptyQuery() throws {
            let (svc, search) = try makeServices()

            try svc.create(Entry(title: "Has content"))

            let results = try search.search(query: "")
            #expect(results.isEmpty)
        }

        @Test("FTS5 prefix autocomplete finds topic candidates")
        func fts5Autocomplete() throws {
            let (svc, search) = try makeServices()

            try svc.create(Entry(title: "machine learning intro"))
            try svc.create(Entry(title: "machine vision basics"))
            try svc.create(Entry(title: "cooking recipes"))

            let candidates = try search.autocomplete(prefix: "machine")
            #expect(candidates.count == 2)
        }
    }

    // MARK: - 3. Find entries in time range

    @Suite("Find entries in time range")
    struct FindByTimeRangeTests {

        private func makeService() throws -> (EntryService, DatabaseManager) {
            let db = try DatabaseManager.temporary()
            return (EntryService(pool: db.pool), db)
        }

        @Test("listByDateRange returns entries within the specified window")
        func dateRangeHappyPath() throws {
            let (svc, _) = try makeService()

            try svc.create(Entry(title: "January entry", createdAt: "2026-01-10T12:00:00Z"))
            try svc.create(Entry(title: "February entry", createdAt: "2026-02-15T12:00:00Z"))
            try svc.create(Entry(title: "March entry",   createdAt: "2026-03-20T12:00:00Z"))

            let results = try svc.listByDateRange(
                from: "2026-02-01T00:00:00Z",
                to:   "2026-02-28T23:59:59Z"
            )

            #expect(results.count == 1)
            #expect(results.first?.title == "February entry")
        }

        @Test("listByDateRange returns nothing for an empty window")
        func dateRangeEmptyWindow() throws {
            let (svc, _) = try makeService()

            try svc.create(Entry(title: "Old entry", createdAt: "2025-06-01T12:00:00Z"))

            let results = try svc.listByDateRange(
                from: "2026-01-01T00:00:00Z",
                to:   "2026-01-31T23:59:59Z"
            )

            #expect(results.isEmpty)
        }

        @Test("listByDateRange includes entries on boundary dates")
        func dateRangeBoundaryInclusive() throws {
            let (svc, _) = try makeService()

            try svc.create(Entry(title: "Exactly at start", createdAt: "2026-03-01T00:00:00Z"))
            try svc.create(Entry(title: "Exactly at end",   createdAt: "2026-03-31T23:59:59Z"))
            try svc.create(Entry(title: "Outside range",    createdAt: "2026-04-01T00:00:00Z"))

            let results = try svc.listByDateRange(
                from: "2026-03-01T00:00:00Z",
                to:   "2026-03-31T23:59:59Z"
            )

            #expect(results.count == 2)
            #expect(results.map(\.title).contains("Exactly at start"))
            #expect(results.map(\.title).contains("Exactly at end"))
        }

        @Test("listByDateRange excludes soft-deleted entries")
        func dateRangeExcludesDeleted() throws {
            let (svc, _) = try makeService()

            let entry = try svc.create(Entry(title: "Will be deleted", createdAt: "2026-03-10T12:00:00Z"))
            try svc.delete(id: entry.id!)

            let results = try svc.listByDateRange(
                from: "2026-03-01T00:00:00Z",
                to:   "2026-03-31T23:59:59Z"
            )

            #expect(results.isEmpty)
        }

        @Test("listByDateRange returns multiple entries ordered by createdAt descending")
        func dateRangeOrdering() throws {
            let (svc, _) = try makeService()

            try svc.create(Entry(title: "First",  createdAt: "2026-03-01T08:00:00Z"))
            try svc.create(Entry(title: "Second", createdAt: "2026-03-15T14:00:00Z"))
            try svc.create(Entry(title: "Third",  createdAt: "2026-03-28T20:00:00Z"))

            let results = try svc.listByDateRange(
                from: "2026-03-01T00:00:00Z",
                to:   "2026-03-31T23:59:59Z"
            )

            #expect(results.count == 3)
            // Descending: Third → Second → First
            #expect(results[0].title == "Third")
            #expect(results[1].title == "Second")
            #expect(results[2].title == "First")
        }

        @Test("Direct SQL time-range query mirrors EntryService listByDateRange")
        func rawSQLTimeRange() throws {
            let (svc, db) = try makeService()

            try svc.create(Entry(title: "In range",     createdAt: "2026-05-10T10:00:00Z"))
            try svc.create(Entry(title: "Out of range", createdAt: "2026-07-01T10:00:00Z"))

            let results = try db.pool.read { db in
                try Entry.filter(sql: """
                    deletedAt IS NULL
                    AND createdAt >= '2026-05-01T00:00:00Z'
                    AND createdAt <= '2026-05-31T23:59:59Z'
                """).fetchAll(db)
            }

            #expect(results.count == 1)
            #expect(results.first?.title == "In range")
        }
    }

    // MARK: - 4. Find knowledge facts about a subject

    @Suite("Knowledge facts by subject")
    struct KnowledgeFactSubjectTests {

        @Test("Insert and retrieve fact by subject")
        func insertAndFetch() throws {
            let db = try DatabaseManager.temporary()

            try insertFact(pool: db.pool,
                           subject: "Sarah",
                           predicate: "works_at",
                           object: "Acme Corp")

            let facts = try db.pool.read { db in
                try KnowledgeFact
                    .filter(Column("subject") == "Sarah")
                    .fetchAll(db)
            }

            #expect(facts.count == 1)
            #expect(facts.first?.predicate == "works_at")
            #expect(facts.first?.object == "Acme Corp")
        }

        @Test("Multiple facts about same subject are all returned")
        func multipleFactsSameSubject() throws {
            let db = try DatabaseManager.temporary()

            try insertFact(pool: db.pool, subject: "Jonas", predicate: "knows", object: "Swift")
            try insertFact(pool: db.pool, subject: "Jonas", predicate: "lives_in", object: "Berlin")
            try insertFact(pool: db.pool, subject: "Lena",  predicate: "knows", object: "Python")

            let jonasFacts = try db.pool.read { db in
                try KnowledgeFact
                    .filter(Column("subject") == "Jonas")
                    .fetchAll(db)
            }

            #expect(jonasFacts.count == 2)
            #expect(jonasFacts.map(\.predicate).contains("knows"))
            #expect(jonasFacts.map(\.predicate).contains("lives_in"))
        }

        @Test("Query by predicate narrows results")
        func queryByPredicate() throws {
            let db = try DatabaseManager.temporary()

            try insertFact(pool: db.pool, subject: "Sarah", predicate: "works_at",  object: "Acme")
            try insertFact(pool: db.pool, subject: "Sarah", predicate: "born_in",   object: "Zurich")
            try insertFact(pool: db.pool, subject: "Thomas", predicate: "works_at", object: "CERN")

            let workFacts = try db.pool.read { db in
                try KnowledgeFact
                    .filter(Column("predicate") == "works_at")
                    .fetchAll(db)
            }

            #expect(workFacts.count == 2)
        }

        @Test("Query by subject and predicate returns exact match")
        func queryBySubjectAndPredicate() throws {
            let db = try DatabaseManager.temporary()

            try insertFact(pool: db.pool, subject: "Sarah", predicate: "works_at",  object: "Acme")
            try insertFact(pool: db.pool, subject: "Sarah", predicate: "lives_in",  object: "Bern")

            let facts = try db.pool.read { db in
                try KnowledgeFact
                    .filter(Column("subject") == "Sarah")
                    .filter(Column("predicate") == "works_at")
                    .fetchAll(db)
            }

            #expect(facts.count == 1)
            #expect(facts.first?.object == "Acme")
        }

        @Test("Unknown subject returns empty result")
        func unknownSubjectEmpty() throws {
            let db = try DatabaseManager.temporary()

            try insertFact(pool: db.pool, subject: "Known", predicate: "p", object: "o")

            let facts = try db.pool.read { db in
                try KnowledgeFact
                    .filter(Column("subject") == "Unknown_Person_XYZ")
                    .fetchAll(db)
            }

            #expect(facts.isEmpty)
        }

        @Test("Fact confidence is preserved after insert")
        func confidencePreserved() throws {
            let db = try DatabaseManager.temporary()

            try insertFact(pool: db.pool,
                           subject: "Anna",
                           predicate: "speaks",
                           object: "French",
                           confidence: 0.75)

            let facts = try db.pool.read { db in
                try KnowledgeFact
                    .filter(Column("subject") == "Anna")
                    .fetchAll(db)
            }

            #expect(facts.first?.confidence == 0.75)
        }

        @Test("Fact with source entry links correctly")
        func factLinkedToSourceEntry() throws {
            let db = try DatabaseManager.temporary()
            let entrySvc = EntryService(pool: db.pool)

            let entry = try entrySvc.create(Entry(title: "Email from Marc"))
            try insertFact(pool: db.pool,
                           subject: "Marc",
                           predicate: "contacted_about",
                           object: "Q2 budget",
                           sourceEntryId: entry.id!)

            let facts = try db.pool.read { db in
                try KnowledgeFact
                    .filter(Column("subject") == "Marc")
                    .fetchAll(db)
            }

            #expect(facts.first?.sourceEntryId == entry.id)
        }

        @Test("Deleting source entry sets sourceEntryId to null (onDelete: .setNull)")
        func deletingSourceEntryNullsReference() throws {
            let db = try DatabaseManager.temporary()
            let entrySvc = EntryService(pool: db.pool)

            let entry = try entrySvc.create(Entry(title: "Source entry"))
            try insertFact(pool: db.pool,
                           subject: "Topic",
                           predicate: "mentioned_in",
                           object: "source_entry",
                           sourceEntryId: entry.id!)

            // Hard-delete the entry so the FK action fires
            try entrySvc.hardDelete(id: entry.id!)

            let facts = try db.pool.read { db in
                try KnowledgeFact
                    .filter(Column("subject") == "Topic")
                    .fetchAll(db)
            }

            #expect(facts.count == 1)
            #expect(facts.first?.sourceEntryId == nil)
        }

        @Test("LIKE subject query finds partial matches for person name")
        func likeSubjectSearch() throws {
            let db = try DatabaseManager.temporary()

            try insertFact(pool: db.pool, subject: "Dr. Sarah Müller", predicate: "is", object: "colleague")
            try insertFact(pool: db.pool, subject: "SarahB", predicate: "is", object: "contact")
            try insertFact(pool: db.pool, subject: "Thomas", predicate: "is", object: "friend")

            let facts = try db.pool.read { db in
                try KnowledgeFact
                    .filter(Column("subject").like("%Sarah%"))
                    .fetchAll(db)
            }

            #expect(facts.count == 2)
        }
    }

    // MARK: - 5. Related topics through tag co-occurrence

    @Suite("Related topics via tag co-occurrence")
    struct TagCoOccurrenceTests {

        private func makeServices() throws -> (EntryService, TagService, DatabaseManager) {
            let db = try DatabaseManager.temporary()
            return (EntryService(pool: db.pool), TagService(pool: db.pool), db)
        }

        @Test("Tags on same entry are co-occurring")
        func basicCoOccurrence() throws {
            let (entrySvc, tagSvc, db) = try makeServices()

            let swiftTag  = try tagSvc.create(Tag(name: "swift"))
            let iosTag    = try tagSvc.create(Tag(name: "ios"))
            let entry     = try entrySvc.create(Entry(title: "SwiftUI note"))

            try tagSvc.attach(tagId: swiftTag.id!, to: entry.id!)
            try tagSvc.attach(tagId: iosTag.id!,   to: entry.id!)

            // Find all tags that co-occur with "swift" (i.e. appear on the same entries)
            let coOccurring = try db.pool.read { db in
                try Tag.filter(sql: """
                    id IN (
                        SELECT et2.tagId
                        FROM entryTags et1
                        JOIN entryTags et2 ON et1.entryId = et2.entryId
                        JOIN tags t1 ON t1.id = et1.tagId
                        WHERE t1.name = 'swift'
                          AND et2.tagId != et1.tagId
                    )
                """).fetchAll(db)
            }

            #expect(coOccurring.count == 1)
            #expect(coOccurring.first?.name == "ios")
        }

        @Test("Multiple co-occurring tags are all returned")
        func multipleCoOccurring() throws {
            let (entrySvc, tagSvc, db) = try makeServices()

            let brain   = try tagSvc.create(Tag(name: "brain"))
            let ai      = try tagSvc.create(Tag(name: "ai"))
            let mobile  = try tagSvc.create(Tag(name: "mobile"))
            let project = try tagSvc.create(Tag(name: "project"))
            let entry   = try entrySvc.create(Entry(title: "AI Brain project"))

            try tagSvc.attach(tagId: brain.id!,   to: entry.id!)
            try tagSvc.attach(tagId: ai.id!,      to: entry.id!)
            try tagSvc.attach(tagId: mobile.id!,  to: entry.id!)
            try tagSvc.attach(tagId: project.id!, to: entry.id!)

            let coOccurring = try db.pool.read { db in
                try Tag.filter(sql: """
                    id IN (
                        SELECT et2.tagId
                        FROM entryTags et1
                        JOIN entryTags et2 ON et1.entryId = et2.entryId
                        JOIN tags t1 ON t1.id = et1.tagId
                        WHERE t1.name = 'brain'
                          AND et2.tagId != et1.tagId
                    )
                """).fetchAll(db)
            }

            #expect(coOccurring.count == 3)
            let names = coOccurring.map(\.name)
            #expect(names.contains("ai"))
            #expect(names.contains("mobile"))
            #expect(names.contains("project"))
        }

        @Test("Tags on different entries are not co-occurring")
        func noCoOccurrenceAcrossEntries() throws {
            let (entrySvc, tagSvc, db) = try makeServices()

            let tagA   = try tagSvc.create(Tag(name: "alpha"))
            let tagB   = try tagSvc.create(Tag(name: "beta"))
            let entry1 = try entrySvc.create(Entry(title: "Entry 1"))
            let entry2 = try entrySvc.create(Entry(title: "Entry 2"))

            try tagSvc.attach(tagId: tagA.id!, to: entry1.id!)
            try tagSvc.attach(tagId: tagB.id!, to: entry2.id!)

            let coOccurring = try db.pool.read { db in
                try Tag.filter(sql: """
                    id IN (
                        SELECT et2.tagId
                        FROM entryTags et1
                        JOIN entryTags et2 ON et1.entryId = et2.entryId
                        JOIN tags t1 ON t1.id = et1.tagId
                        WHERE t1.name = 'alpha'
                          AND et2.tagId != et1.tagId
                    )
                """).fetchAll(db)
            }

            #expect(coOccurring.isEmpty)
        }

        @Test("Tag co-occurrence count query ranks related topics")
        func coOccurrenceWithCounts() throws {
            let (entrySvc, tagSvc, db) = try makeServices()

            let swift   = try tagSvc.create(Tag(name: "swift"))
            let ios     = try tagSvc.create(Tag(name: "ios"))
            let concur  = try tagSvc.create(Tag(name: "concurrency"))
            let e1      = try entrySvc.create(Entry(title: "E1"))
            let e2      = try entrySvc.create(Entry(title: "E2"))
            let e3      = try entrySvc.create(Entry(title: "E3"))

            // swift+ios appear together on all 3 entries
            for entry in [e1, e2, e3] {
                try tagSvc.attach(tagId: swift.id!, to: entry.id!)
                try tagSvc.attach(tagId: ios.id!,   to: entry.id!)
            }
            // swift+concurrency only on e1
            try tagSvc.attach(tagId: concur.id!, to: e1.id!)

            struct CoOccRow: FetchableRecord {
                let tagName: String
                let coCount: Int
                init(row: Row) {
                    tagName = row["tagName"]
                    coCount = row["coCount"]
                }
            }

            let rows = try db.pool.read { db in
                try CoOccRow.fetchAll(db, sql: """
                    SELECT t2.name AS tagName, COUNT(*) AS coCount
                    FROM entryTags et1
                    JOIN entryTags et2 ON et1.entryId = et2.entryId
                    JOIN tags t1 ON t1.id = et1.tagId
                    JOIN tags t2 ON t2.id = et2.tagId
                    WHERE t1.name = 'swift'
                      AND et2.tagId != et1.tagId
                    GROUP BY t2.id
                    ORDER BY coCount DESC
                """)
            }

            #expect(rows.count == 2)
            // ios co-occurs 3 times, concurrency only once
            #expect(rows[0].tagName == "ios")
            #expect(rows[0].coCount == 3)
            #expect(rows[1].tagName == "concurrency")
            #expect(rows[1].coCount == 1)
        }

        @Test("Co-occurrence excludes soft-deleted entries")
        func coOccurrenceIgnoresDeletedEntries() throws {
            let (entrySvc, tagSvc, db) = try makeServices()

            let tagA    = try tagSvc.create(Tag(name: "topic-a"))
            let tagB    = try tagSvc.create(Tag(name: "topic-b"))
            let live    = try entrySvc.create(Entry(title: "Live entry"))
            let dead    = try entrySvc.create(Entry(title: "Deleted entry"))

            try tagSvc.attach(tagId: tagA.id!, to: live.id!)
            try tagSvc.attach(tagId: tagA.id!, to: dead.id!)
            try tagSvc.attach(tagId: tagB.id!, to: dead.id!)  // only on deleted entry

            try entrySvc.delete(id: dead.id!)

            // Query that filters out deleted entries
            let coOccurring = try db.pool.read { db in
                try Tag.filter(sql: """
                    id IN (
                        SELECT et2.tagId
                        FROM entryTags et1
                        JOIN entryTags et2 ON et1.entryId = et2.entryId
                        JOIN entries e ON e.id = et1.entryId
                        JOIN tags t1 ON t1.id = et1.tagId
                        WHERE t1.name = 'topic-a'
                          AND et2.tagId != et1.tagId
                          AND e.deletedAt IS NULL
                    )
                """).fetchAll(db)
            }

            // topic-b was only on the deleted entry, so it should not appear
            #expect(coOccurring.isEmpty)
        }

        @Test("tagCounts reflects entries tagged on the same entry")
        func tagCountsReflectsCoUsage() throws {
            let (entrySvc, tagSvc, _) = try makeServices()

            let alpha = try tagSvc.create(Tag(name: "alpha"))
            let beta  = try tagSvc.create(Tag(name: "beta"))
            let e1    = try entrySvc.create(Entry(title: "Entry 1"))
            let e2    = try entrySvc.create(Entry(title: "Entry 2"))

            try tagSvc.attach(tagId: alpha.id!, to: e1.id!)
            try tagSvc.attach(tagId: alpha.id!, to: e2.id!)
            try tagSvc.attach(tagId: beta.id!,  to: e1.id!)

            let counts = try tagSvc.tagCounts()
            let alphaCount = counts.first(where: { $0.tag.name == "alpha" })?.count
            let betaCount  = counts.first(where: { $0.tag.name == "beta"  })?.count

            #expect(alphaCount == 2)
            #expect(betaCount  == 1)
        }
    }

    // MARK: - 6. Integration: combined person + time range + topic

    @Suite("Combined memory queries")
    struct CombinedQueryTests {

        @Test("Find person mentions within a specific month")
        func personMentionsInMonth() throws {
            let db = try DatabaseManager.temporary()
            let svc = EntryService(pool: db.pool)

            try svc.create(Entry(title: "Jan call with Anna",  body: "discussed budget", createdAt: "2026-01-05T10:00:00Z"))
            try svc.create(Entry(title: "Feb note",           body: "no people here",   createdAt: "2026-02-10T10:00:00Z"))
            try svc.create(Entry(title: "Feb chat with Anna", body: "project update",   createdAt: "2026-02-20T10:00:00Z"))

            let results = try db.pool.read { db in
                try Entry
                    .filter(Column("deletedAt") == nil)
                    .filter(
                        Column("title").like("%Anna%") ||
                        Column("body").like("%Anna%")
                    )
                    .filter(Column("createdAt") >= "2026-02-01T00:00:00Z")
                    .filter(Column("createdAt") <= "2026-02-28T23:59:59Z")
                    .fetchAll(db)
            }

            #expect(results.count == 1)
            #expect(results.first?.title == "Feb chat with Anna")
        }

        @Test("FTS5 topic search combined with time range filter")
        func topicSearchInTimeRange() throws {
            let db = try DatabaseManager.temporary()
            let svc = EntryService(pool: db.pool)
            let search = SearchService(pool: db.pool)

            try svc.create(Entry(title: "Old Swift talk",    body: "swift concurrency", createdAt: "2025-06-01T12:00:00Z"))
            try svc.create(Entry(title: "Recent Swift note", body: "swift actors",      createdAt: "2026-03-15T12:00:00Z"))

            // FTS5 finds both; then we narrow by date at the entry-service level
            let allSwift = try search.search(query: "swift")
            #expect(allSwift.count == 2)

            let recentSwift = try svc.listByDateRange(
                from: "2026-01-01T00:00:00Z",
                to:   "2026-12-31T23:59:59Z",
                type: nil
            )
            let recentSwiftFiltered = recentSwift.filter { entry in
                (entry.title?.contains("Swift") ?? false) || (entry.body?.contains("swift") ?? false)
            }

            #expect(recentSwiftFiltered.count == 1)
            #expect(recentSwiftFiltered.first?.title == "Recent Swift note")
        }

        @Test("Knowledge fact linked to entry retrievable via source entry")
        func factToEntryRoundTrip() throws {
            let db = try DatabaseManager.temporary()
            let svc = EntryService(pool: db.pool)

            let entry = try svc.create(Entry(title: "Email from Petra about the merger"))
            try insertFact(pool: db.pool,
                           subject: "Petra",
                           predicate: "discussed",
                           object: "merger",
                           sourceEntryId: entry.id!)

            // Retrieve facts then fetch the linked entry
            let facts = try db.pool.read { db in
                try KnowledgeFact
                    .filter(Column("subject") == "Petra")
                    .fetchAll(db)
            }

            #expect(facts.count == 1)
            let fact = try #require(facts.first)
            let sourceEntryId = try #require(fact.sourceEntryId)
            let sourceEntry = try svc.fetch(id: sourceEntryId)
            #expect(sourceEntry?.title == "Email from Petra about the merger")
        }

        @Test("No results when database is empty for all query types")
        func emptyDatabaseAllQueries() throws {
            let db = try DatabaseManager.temporary()
            let svc = EntryService(pool: db.pool)
            let search = SearchService(pool: db.pool)

            let likeResults = try db.pool.read { db in
                try Entry
                    .filter(Column("deletedAt") == nil)
                    .filter(Column("title").like("%anyone%"))
                    .fetchAll(db)
            }
            #expect(likeResults.isEmpty)

            let ftsResults = try search.search(query: "anything")
            #expect(ftsResults.isEmpty)

            let rangeResults = try svc.listByDateRange(
                from: "2026-01-01T00:00:00Z",
                to:   "2026-12-31T23:59:59Z"
            )
            #expect(rangeResults.isEmpty)

            let factResults = try db.pool.read { db in
                try KnowledgeFact
                    .filter(Column("subject") == "nobody")
                    .fetchAll(db)
            }
            #expect(factResults.isEmpty)
        }
    }
}

// MARK: - Private helper (file-scoped)

@discardableResult
private func insertFact(
    pool: DatabasePool,
    subject: String,
    predicate: String,
    object: String,
    confidence: Double = 1.0,
    sourceEntryId: Int64? = nil
) throws -> KnowledgeFact {
    try pool.write { db in
        var fact = KnowledgeFact(
            subject: subject,
            predicate: predicate,
            object: object,
            confidence: confidence,
            sourceEntryId: sourceEntryId
        )
        try fact.insert(db)
        return fact
    }
}
