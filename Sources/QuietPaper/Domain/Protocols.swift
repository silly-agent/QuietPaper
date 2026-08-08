import Foundation

protocol NoteSearchService: Sendable {
    func search(
        query: String,
        scope: SearchScope,
        projectID: UUID?,
        moduleID: UUID?
    ) throws -> [NoteSearchResult]
}

protocol AIProvider: Sendable {
    var name: String { get }
    var requiresNetwork: Bool { get }
    func answer(question: String, context: [NoteExcerpt]) async throws -> GroundedAnswer
}

extension AIProvider {
    var name: String { "本地检索" }
    var requiresNetwork: Bool { false }
}

enum QuietPaperError: LocalizedError {
    case database(String)
    case invalidName
    case noSelection
    case attachment(String)
    case export(String)

    var errorDescription: String? {
        switch self {
        case .database(let message): "数据库错误：\(message)"
        case .invalidName: "名称不能为空"
        case .noSelection: "请先选择一篇笔记"
        case .attachment(let message): "附件错误：\(message)"
        case .export(let message): "导出失败：\(message)"
        }
    }
}
