import Foundation

struct LocalGroundedAIProvider: AIProvider {
    let name = "本地检索"
    let requiresNetwork = false

    func answer(question: String, context: [NoteExcerpt]) async throws -> GroundedAnswer {
        guard !context.isEmpty else {
            return GroundedAnswer(
                text: "没有在现有笔记中找到足够依据。可以换一个更精确的关键词，或扩大搜索范围。",
                sources: []
            )
        }

        let sources = Array(context.prefix(4).map(\.result))
        let evidence = sources.enumerated().map { index, source in
            "\(index + 1). \(source.excerpt)"
        }.joined(separator: "\n")
        return GroundedAnswer(
            text: "根据已有笔记，与“\(question)”最相关的记录如下：\n\n\(evidence)\n\n请打开下方来源核对完整原文。",
            sources: sources
        )
    }
}
