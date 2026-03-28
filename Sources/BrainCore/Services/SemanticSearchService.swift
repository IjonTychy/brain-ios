import Foundation
import GRDB

// Semantic search result combining FTS5 text score and vector similarity.
public struct SemanticSearchResult: Sendable {
    public let entry: Entry
    public let textScore: Double
    public let similarity: Float
    public let combinedScore: Double

    public init(entry: Entry, textScore: Double = 0, similarity: Float = 0, combinedScore: Double = 0) {
        self.entry = entry
        self.textScore = textScore
        self.similarity = similarity
        self.combinedScore = combinedScore
    }
}

// Combines FTS5 text search with vector similarity for hybrid search.
public struct SemanticSearchService: Sendable {

    private let pool: DatabasePool
    private let searchService: SearchService
    private let embeddingStore: EmbeddingStore

    public init(pool: DatabasePool) {
        self.pool = pool
        self.searchService = SearchService(pool: pool)
        self.embeddingStore = EmbeddingStore(pool: pool)
    }

    // Find entries similar to a given entry by vector similarity.
    // This is the "Déjà Vu" feature.
    public func findSimilar(to entryId: Int64, limit: Int = 5) throws -> [SemanticSearchResult] {
        guard let queryVector = try embeddingStore.fetch(entryId: entryId) else {
            return []
        }
        let all = try embeddingStore.fetchAll()
        let candidates = all.filter { $0.entryId != entryId }
            .map { (index: Int($0.entryId), vector: $0.vector) }

        let topK = VectorMath.topK(query: queryVector, candidates: candidates, k: limit)

        // Fetch the actual entries
        let entryIds = topK.map { Int64($0.index) }
        let entries = try fetchEntries(ids: entryIds)

        return topK.compactMap { result in
            guard let entry = entries[Int64(result.index)] else { return nil }
            return SemanticSearchResult(
                entry: entry,
                similarity: result.similarity,
                combinedScore: Double(result.similarity)
            )
        }
    }

    // Find entries similar to arbitrary text (requires external embedding).
    public func findSimilar(toVector queryVector: [Float], excludeId: Int64? = nil, limit: Int = 5) throws -> [SemanticSearchResult] {
        let all = try embeddingStore.fetchAll()
        let candidates = all
            .filter { excludeId == nil || $0.entryId != excludeId }
            .map { (index: Int($0.entryId), vector: $0.vector) }

        let topK = VectorMath.topK(query: queryVector, candidates: candidates, k: limit)

        let entryIds = topK.map { Int64($0.index) }
        let entries = try fetchEntries(ids: entryIds)

        return topK.compactMap { result in
            guard let entry = entries[Int64(result.index)] else { return nil }
            return SemanticSearchResult(
                entry: entry,
                similarity: result.similarity,
                combinedScore: Double(result.similarity)
            )
        }
    }

    // Hybrid search: combine FTS5 text search with vector similarity.
    // textWeight and vectorWeight control the blend (default 50/50).
    public func hybridSearch(
        query: String,
        queryVector: [Float]?,
        textWeight: Double = 0.5,
        vectorWeight: Double = 0.5,
        limit: Int = 20
    ) throws -> [SemanticSearchResult] {
        // FTS5 text results
        let textResults = try searchService.search(query: query, limit: limit * 2)

        guard let queryVector, !queryVector.isEmpty else {
            // No vector — return FTS5 results only
            return textResults.map {
                SemanticSearchResult(entry: $0.entry, textScore: $0.score, combinedScore: $0.score)
            }
        }

        // Vector results
        let vectorResults = try findSimilar(toVector: queryVector, limit: limit * 2)

        // Merge: normalize scores and combine
        let maxTextScore = textResults.map { abs($0.score) }.max() ?? 1.0
        let maxVectorSim = vectorResults.map { $0.similarity }.max() ?? 1.0

        var merged: [Int64: SemanticSearchResult] = [:]

        for tr in textResults {
            guard let id = tr.entry.id else { continue }
            let normalizedText = maxTextScore > 0 ? abs(tr.score) / maxTextScore : 0
            merged[id] = SemanticSearchResult(
                entry: tr.entry,
                textScore: tr.score,
                similarity: 0,
                combinedScore: normalizedText * textWeight
            )
        }

        for vr in vectorResults {
            guard let id = vr.entry.id else { continue }
            let normalizedSim = maxVectorSim > 0 ? Double(vr.similarity) / Double(maxVectorSim) : 0
            if var existing = merged[id] {
                existing = SemanticSearchResult(
                    entry: existing.entry,
                    textScore: existing.textScore,
                    similarity: vr.similarity,
                    combinedScore: existing.combinedScore + normalizedSim * vectorWeight
                )
                merged[id] = existing
            } else {
                merged[id] = SemanticSearchResult(
                    entry: vr.entry,
                    textScore: 0,
                    similarity: vr.similarity,
                    combinedScore: normalizedSim * vectorWeight
                )
            }
        }

        return Array(merged.values)
            .sorted { $0.combinedScore > $1.combinedScore }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Private

    private func fetchEntries(ids: [Int64]) throws -> [Int64: Entry] {
        guard !ids.isEmpty else { return [:] }
        return try pool.read { db in
            let entries = try Entry.filter(ids.contains(Column("id"))).fetchAll(db)
            var dict: [Int64: Entry] = [:]
            for entry in entries {
                if let id = entry.id {
                    dict[id] = entry
                }
            }
            return dict
        }
    }
}
