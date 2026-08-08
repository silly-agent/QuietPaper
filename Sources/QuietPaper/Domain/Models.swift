import Foundation

struct Project: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}

struct NoteModule: Identifiable, Hashable, Sendable {
    let id: UUID
    let projectID: UUID
    var name: String
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var isProjectRoot: Bool
}

enum DocumentKind: String, Codable, CaseIterable, Sendable {
    case markdown
    case request
    case connection
}

struct Note: Identifiable, Hashable, Sendable {
    let id: UUID
    var moduleID: UUID
    var title: String
    var contentMarkdown: String
    var kind: DocumentKind
    let createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}

struct NoteFoldGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    let moduleID: UUID
    let noteIDs: [UUID]
    let createdAt: Date
}

struct NoteSearchResult: Identifiable, Hashable, Sendable {
    let noteID: UUID
    let projectID: UUID
    let moduleID: UUID
    let projectName: String
    let moduleName: String
    let noteTitle: String
    let excerpt: String
    let updatedAt: Date
    let isProjectRoot: Bool

    var id: UUID { noteID }
    var path: String {
        isProjectRoot ? "\(projectName) / \(noteTitle)" : "\(projectName) / \(moduleName) / \(noteTitle)"
    }
}

enum SearchScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case project
    case module

    var id: Self { self }

    var label: String {
        switch self {
        case .all: "全部项目"
        case .project: "当前项目"
        case .module: "当前模块"
        }
    }
}

enum DeletedItemKind: String, Sendable {
    case project = "项目"
    case module = "模块"
    case note = "笔记"
}

struct DeletedItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: DeletedItemKind
    let name: String
    let deletedAt: Date
    let detail: String
}

enum SaveState: Equatable, Sendable {
    case idle
    case pending
    case saving
    case saved(Date)
    case failed(String)

    var label: String {
        switch self {
        case .idle: ""
        case .pending: "待自动保存"
        case .saving: "保存中…"
        case .saved: "已保存"
        case .failed: "保存失败"
        }
    }
}

struct NoteExcerpt: Identifiable, Hashable, Sendable {
    let id = UUID()
    let result: NoteSearchResult
}

struct GroundedAnswer: Sendable {
    let text: String
    let sources: [NoteSearchResult]
}
