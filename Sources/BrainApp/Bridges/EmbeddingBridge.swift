import Foundation
import NaturalLanguage
import BrainCore
import GRDB

// Generates text embeddings using Apple's NLEmbedding framework.
// Stores results via EmbeddingStore for semantic search.
final class EmbeddingBridge: Sendable {

    private let store: EmbeddingStore
    private let pool: DatabasePool

    // NLEmbedding model identifier
    static let modelName = "NLEmbedding-de"

    init(pool: DatabasePool) {
        self.pool = pool
        self.store = EmbeddingStore(pool: pool)
    }

    // Generate embedding for a single text string.
    // Uses German sentence embedding (falls back to multilingual).
    func embed(text: String) -> [Float]? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        // Try German first, fall back to English
        let embedding = NLEmbedding.sentenceEmbedding(for: .german)
            ?? NLEmbedding.sentenceEmbedding(for: .english)
        guard let embedding else { return nil }

        // NLEmbedding returns [Double], convert to [Float] for compact storage
        guard let vector = embedding.vector(for: text) else { return nil }
        return vector.map { Float($0) }
    }

    // Generate and store embedding for a single entry.
    func embedEntry(_ entry: Entry) throws -> Bool {
        guard let id = entry.id else { return false }
        let text = Self.entryText(entry)
        guard let vector = embed(text: text) else { return false }
        try store.save(entryId: id, vector: vector, model: Self.modelName)
        return true
    }

    // Batch-embed entries that don't have embeddings yet.
    // Returns count of newly embedded entries.
    func embedMissing(batchSize: Int = 50) throws -> Int {
        let entries = try store.entriesWithoutEmbedding(limit: batchSize)
        var embedded = 0
        var batch: [(entryId: Int64, vector: [Float])] = []

        for entry in entries {
            guard let id = entry.id else { continue }
            let text = Self.entryText(entry)
            guard let vector = embed(text: text) else { continue }
            batch.append((entryId: id, vector: vector))
            embedded += 1
        }

        if !batch.isEmpty {
            try store.saveBatch(batch, model: Self.modelName)
        }
        return embedded
    }

    // Find entries semantically similar to given text.
    func findSimilar(text: String, excludeId: Int64? = nil, limit: Int = 5) throws -> [SemanticSearchResult] {
        guard let queryVector = embed(text: text) else { return [] }
        let service = SemanticSearchService(pool: pool)
        return try service.findSimilar(toVector: queryVector, excludeId: excludeId, limit: limit)
    }

    // Hybrid search combining text and semantic similarity.
    func hybridSearch(query: String, limit: Int = 20) throws -> [SemanticSearchResult] {
        let queryVector = embed(text: query)
        let service = SemanticSearchService(pool: pool)
        return try service.hybridSearch(
            query: query,
            queryVector: queryVector,
            limit: limit
        )
    }

    // Embedding dimension (depends on NLEmbedding model).
    var dimension: Int? {
        let embedding = NLEmbedding.sentenceEmbedding(for: .german)
            ?? NLEmbedding.sentenceEmbedding(for: .english)
        return embedding?.dimension
    }

    // MARK: - Private

    // Combine title and body for embedding (title weighted by repetition).
    static func entryText(_ entry: Entry) -> String {
        let title = entry.title ?? ""
        let body = entry.body ?? ""
        if title.isEmpty { return body }
        if body.isEmpty { return title }
        // Repeat title to give it more weight in the embedding
        return "\(title). \(title). \(body)"
    }
}
