import Accelerate
import Foundation

/// 向量相似度检索服务，使用 vDSP 批量计算余弦相似度。
struct VectorSearchService: Sendable {
    let embedding: EmbeddingService

    /// 在 chunks 中搜索与 query 语义最相似的 topK 个结果。
    func search(query: String, chunks: [VectorChunk], topK: Int) -> [ScoredChunk] {
        guard let queryVec = embedding.embed(text: query), !chunks.isEmpty else { return [] }

        let scores: [Float] = chunks.map { chunk in
            cosineSimilarity(queryVec, chunk.embedding)
        }

        return zip(chunks, scores)
            .map { ScoredChunk(chunk: $0.0, score: $0.1) }
            .sorted { $0.score > $1.score }
            .prefix(topK)
            .map { $0 }
    }
}

/// 带相似度评分的检索结果。
struct ScoredChunk: Sendable {
    let chunk: VectorChunk
    let score: Float
}

// MARK: - Cosine Similarity via vDSP

private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    precondition(a.count == b.count && !a.isEmpty)
    let count = vDSP_Length(a.count)

    var dot: Float = 0
    vDSP_dotpr(a, 1, b, 1, &dot, count)

    var sumSqA: Float = 0
    var sumSqB: Float = 0
    vDSP_svesq(a, 1, &sumSqA, count)
    vDSP_svesq(b, 1, &sumSqB, count)

    let denom = sqrt(sumSqA) * sqrt(sumSqB)
    guard denom > Float.ulpOfOne else { return 0 }
    return max(-1, min(1, dot / denom))
}
