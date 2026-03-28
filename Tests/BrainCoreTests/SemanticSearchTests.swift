import Testing
import Foundation
import GRDB
@testable import BrainCore

@Suite("Vector Math")
struct VectorMathTests {

    @Test("Cosine similarity of identical vectors is 1")
    func identicalVectors() {
        let v = [Float](repeating: 1.0, count: 10)
        let sim = VectorMath.cosineSimilarity(v, v)
        #expect(abs(sim - 1.0) < 0.001)
    }

    @Test("Cosine similarity of orthogonal vectors is 0")
    func orthogonalVectors() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [0, 1, 0]
        let sim = VectorMath.cosineSimilarity(a, b)
        #expect(abs(sim) < 0.001)
    }

    @Test("Cosine similarity of opposite vectors is -1")
    func oppositeVectors() {
        let a: [Float] = [1, 2, 3]
        let b: [Float] = [-1, -2, -3]
        let sim = VectorMath.cosineSimilarity(a, b)
        #expect(abs(sim + 1.0) < 0.001)
    }

    @Test("Cosine similarity of empty vectors is 0")
    func emptyVectors() {
        let sim = VectorMath.cosineSimilarity([], [])
        #expect(sim == 0)
    }

    @Test("Cosine similarity of mismatched lengths is 0")
    func mismatchedLengths() {
        let a: [Float] = [1, 2]
        let b: [Float] = [1, 2, 3]
        let sim = VectorMath.cosineSimilarity(a, b)
        #expect(sim == 0)
    }

    @Test("Top-K returns correct ordering")
    func topK() {
        let query: [Float] = [1, 0, 0]
        let candidates: [(index: Int, vector: [Float])] = [
            (index: 1, vector: [0, 1, 0]),    // orthogonal = 0
            (index: 2, vector: [1, 0, 0]),    // identical = 1
            (index: 3, vector: [0.7, 0.7, 0]) // ~0.707
        ]
        let results = VectorMath.topK(query: query, candidates: candidates, k: 2)
        #expect(results.count == 2)
        #expect(results[0].index == 2) // most similar first
        #expect(results[1].index == 3)
    }

    @Test("Serialize and deserialize round-trip")
    func serializeRoundTrip() {
        let original: [Float] = [1.5, -2.3, 0.0, 42.0, -0.001]
        let data = VectorMath.serialize(original)
        let restored = VectorMath.deserialize(data)
        #expect(original == restored)
    }

    @Test("Serialized data has correct byte size")
    func serializedSize() {
        let vector: [Float] = [1, 2, 3, 4]
        let data = VectorMath.serialize(vector)
        #expect(data.count == 4 * MemoryLayout<Float>.size)
    }
}

@Suite("Embedding Store")
struct EmbeddingStoreTests {

    private func makeStore() throws -> (EmbeddingStore, EntryService, DatabasePool) {
        let db = try DatabaseManager.temporary()
        return (EmbeddingStore(pool: db.pool), EntryService(pool: db.pool), db.pool)
    }

    @Test("Save and fetch embedding")
    func saveAndFetch() throws {
        let (store, entrySvc, _) = try makeStore()
        let entry = try entrySvc.create(Entry(title: "Test"))
        let vector: [Float] = [0.1, 0.2, 0.3]
        try store.save(entryId: entry.id!, vector: vector, model: "test")

        let fetched = try store.fetch(entryId: entry.id!)
        #expect(fetched == vector)
    }

    @Test("Fetch returns nil for missing entry")
    func fetchMissing() throws {
        let (store, _, _) = try makeStore()
        let result = try store.fetch(entryId: 9999)
        #expect(result == nil)
    }

    @Test("Count returns correct number")
    func countEmbeddings() throws {
        let (store, entrySvc, _) = try makeStore()
        let e1 = try entrySvc.create(Entry(title: "A"))
        let e2 = try entrySvc.create(Entry(title: "B"))
        try store.save(entryId: e1.id!, vector: [1, 2], model: "test")
        try store.save(entryId: e2.id!, vector: [3, 4], model: "test")
        #expect(try store.count() == 2)
    }

    @Test("Delete removes embedding")
    func deleteEmbedding() throws {
        let (store, entrySvc, _) = try makeStore()
        let entry = try entrySvc.create(Entry(title: "Test"))
        try store.save(entryId: entry.id!, vector: [1, 2, 3], model: "test")
        #expect(try store.count() == 1)
        try store.delete(entryId: entry.id!)
        #expect(try store.count() == 0)
    }

    @Test("Entries without embedding are found")
    func entriesWithoutEmbedding() throws {
        let (store, entrySvc, _) = try makeStore()
        let e1 = try entrySvc.create(Entry(title: "Has embedding"))
        _ = try entrySvc.create(Entry(title: "No embedding"))
        try store.save(entryId: e1.id!, vector: [1, 2], model: "test")

        let missing = try store.entriesWithoutEmbedding()
        #expect(missing.count == 1)
        #expect(missing[0].title == "No embedding")
    }

    @Test("Batch save stores multiple embeddings")
    func batchSave() throws {
        let (store, entrySvc, _) = try makeStore()
        let e1 = try entrySvc.create(Entry(title: "A"))
        let e2 = try entrySvc.create(Entry(title: "B"))
        let e3 = try entrySvc.create(Entry(title: "C"))

        try store.saveBatch([
            (entryId: e1.id!, vector: [1, 0]),
            (entryId: e2.id!, vector: [0, 1]),
            (entryId: e3.id!, vector: [1, 1])
        ], model: "test")

        #expect(try store.count() == 3)
    }

    @Test("Upsert overwrites existing embedding")
    func upsertOverwrite() throws {
        let (store, entrySvc, _) = try makeStore()
        let entry = try entrySvc.create(Entry(title: "Test"))
        try store.save(entryId: entry.id!, vector: [1, 2, 3], model: "v1")
        try store.save(entryId: entry.id!, vector: [4, 5, 6], model: "v2")

        #expect(try store.count() == 1)
        let fetched = try store.fetch(entryId: entry.id!)
        #expect(fetched == [4, 5, 6])
    }

    @Test("Cascade delete removes embedding when entry is deleted")
    func cascadeDelete() throws {
        let (store, entrySvc, pool) = try makeStore()
        let entry = try entrySvc.create(Entry(title: "Test"))
        try store.save(entryId: entry.id!, vector: [1, 2], model: "test")
        #expect(try store.count() == 1)

        // Hard-delete the entry
        try pool.write { db in
            try db.execute(sql: "DELETE FROM entries WHERE id = ?", arguments: [entry.id!])
        }
        #expect(try store.count() == 0)
    }
}

@Suite("Semantic Search")
struct SemanticSearchServiceTests {

    private func makeServices() throws -> (SemanticSearchService, EmbeddingStore, EntryService) {
        let db = try DatabaseManager.temporary()
        return (
            SemanticSearchService(pool: db.pool),
            EmbeddingStore(pool: db.pool),
            EntryService(pool: db.pool)
        )
    }

    @Test("Find similar entries by vector")
    func findSimilar() throws {
        let (semantic, store, entrySvc) = try makeServices()

        let e1 = try entrySvc.create(Entry(title: "Swift iOS"))
        let e2 = try entrySvc.create(Entry(title: "Python ML"))
        let e3 = try entrySvc.create(Entry(title: "Swift macOS"))

        // Vectors: e1 and e3 are similar, e2 is different
        try store.save(entryId: e1.id!, vector: [1, 0, 0], model: "test")
        try store.save(entryId: e2.id!, vector: [0, 1, 0], model: "test")
        try store.save(entryId: e3.id!, vector: [0.9, 0.1, 0], model: "test")

        let results = try semantic.findSimilar(to: e1.id!, limit: 2)
        #expect(results.count == 2)
        #expect(results[0].entry.id == e3.id) // most similar
    }

    @Test("Find similar returns empty when no embedding")
    func findSimilarNoEmbedding() throws {
        let (semantic, _, entrySvc) = try makeServices()
        _ = try entrySvc.create(Entry(title: "Test"))
        let results = try semantic.findSimilar(to: 9999)
        #expect(results.isEmpty)
    }

    @Test("Find similar to vector excludes specified ID")
    func excludeId() throws {
        let (semantic, store, entrySvc) = try makeServices()
        let e1 = try entrySvc.create(Entry(title: "A"))
        let e2 = try entrySvc.create(Entry(title: "B"))

        try store.save(entryId: e1.id!, vector: [1, 0], model: "test")
        try store.save(entryId: e2.id!, vector: [1, 0], model: "test")

        let results = try semantic.findSimilar(toVector: [1, 0], excludeId: e1.id!, limit: 10)
        #expect(results.count == 1)
        #expect(results[0].entry.id == e2.id)
    }

    @Test("Hybrid search with text only")
    func hybridTextOnly() throws {
        let (semantic, _, entrySvc) = try makeServices()
        try entrySvc.create(Entry(title: "Swift programming guide"))
        try entrySvc.create(Entry(title: "Python scripting"))

        let results = try semantic.hybridSearch(query: "Swift", queryVector: nil, limit: 10)
        #expect(results.count == 1)
        #expect(results[0].entry.title == "Swift programming guide")
    }
}
