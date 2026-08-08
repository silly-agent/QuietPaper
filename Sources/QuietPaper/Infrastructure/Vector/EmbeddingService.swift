import Foundation
@preconcurrency import NaturalLanguage

/// 系统内置 NLP 嵌入服务，完全本地运行，无网络依赖。
struct EmbeddingService: @unchecked Sendable {
    let model: NLEmbedding
    let dimension: Int
    let language: String

    /// 创建中文 Sentence Embedding 模型，不可用时 fallback 到英文。
    init?() {
        if let embedding = NLEmbedding.sentenceEmbedding(for: .simplifiedChinese) {
            self.model = embedding
            self.language = "zh-Hans"
        } else if let embedding = NLEmbedding.sentenceEmbedding(for: .english) {
            self.model = embedding
            self.language = "en"
        } else {
            return nil
        }
        self.dimension = model.dimension
    }

    /// 单文本向量化，返回 [Float] 以节约存储。
    func embed(text: String) -> [Float]? {
        guard let doubles = model.vector(for: text), doubles.count == dimension else { return nil }
        return doubles.map { Float($0) }
    }

    /// 批量向量化。
    func embedBatch(texts: [String]) -> [[Float]] {
        texts.compactMap(embed(text:))
    }
}

// MARK: - Vector Data Models

/// 一个笔记段落的向量化结果。
struct VectorChunk: Identifiable, Sendable {
    let id: UUID
    let noteID: UUID
    let chunkIndex: Int
    let contentText: String
    let embedding: [Float]

    init(id: UUID = UUID(), noteID: UUID, chunkIndex: Int, contentText: String, embedding: [Float]) {
        self.id = id
        self.noteID = noteID
        self.chunkIndex = chunkIndex
        self.contentText = contentText
        self.embedding = embedding
    }
}
