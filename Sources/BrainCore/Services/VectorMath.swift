import Foundation

// Pure-Swift vector operations for semantic search.
// Works on any platform (iOS + Linux/VPS for tests).
public enum VectorMath: Sendable {

    // Cosine similarity between two vectors. Returns value in [-1, 1].
    // 1 = identical direction, 0 = orthogonal, -1 = opposite.
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 0 }
        return dot / denom
    }

    // Top-K nearest neighbors by cosine similarity.
    // Returns (index, similarity) pairs sorted by descending similarity.
    public static func topK(
        query: [Float],
        candidates: [(index: Int, vector: [Float])],
        k: Int
    ) -> [(index: Int, similarity: Float)] {
        let scored = candidates.map { (index: $0.index, similarity: cosineSimilarity(query, $0.vector)) }
        let sorted = scored.sorted { $0.similarity > $1.similarity }
        return Array(sorted.prefix(k))
    }

    // Serialize a float array to Data (for BLOB storage).
    public static func serialize(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    // Deserialize Data back to float array.
    public static func deserialize(_ data: Data) -> [Float] {
        data.withUnsafeBytes { raw in
            let buffer = raw.bindMemory(to: Float.self)
            return Array(buffer)
        }
    }
}
