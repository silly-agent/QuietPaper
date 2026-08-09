import CSQLite
import Foundation

final class WorkspaceDatabase: @unchecked Sendable, NoteSearchService {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    let databaseURL: URL?

    init(url: URL, seedIfEmpty: Bool = true) throws {
        databaseURL = url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try open(path: url.path)
        try migrate()
        if seedIfEmpty { try seedIfNeeded() }
    }

    init(inMemory: Bool = true, seedIfEmpty: Bool = false) throws {
        databaseURL = nil
        try open(path: ":memory:")
        try migrate()
        if seedIfEmpty { try seedIfNeeded() }
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    /// 用户可在设置中选择自定义存储目录（路径保存在 UserDefaults）。
    static let storageDirectoryDefaultsKey = "QuietPaper.storageDirectory"

    /// 默认存储目录：`~/Library/Application Support/QuietPaper`。
    static func defaultStorageDirectory() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("QuietPaper", isDirectory: true)
    }

    /// 返回设置中选择的存储目录；未配置时使用默认目录。
    static func configuredStorageDirectory() -> URL {
        if let path = UserDefaults.standard.string(forKey: storageDirectoryDefaultsKey),
           !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return defaultStorageDirectory()
    }

    static func applicationDatabaseURL() -> URL {
        configuredStorageDirectory().appendingPathComponent("quiet-paper.sqlite")
    }

    private func open(path: String) throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            throw error("无法打开数据库")
        }
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
    }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS projects (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            deleted_at REAL,
            is_ai_unreadable INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS modules (
            id TEXT PRIMARY KEY NOT NULL,
            project_id TEXT NOT NULL REFERENCES projects(id),
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            deleted_at REAL,
            is_project_root INTEGER NOT NULL DEFAULT 0,
            is_ai_unreadable INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS notes (
            id TEXT PRIMARY KEY NOT NULL,
            module_id TEXT NOT NULL REFERENCES modules(id),
            title TEXT NOT NULL DEFAULT '',
            content_markdown TEXT NOT NULL DEFAULT '',
            kind TEXT NOT NULL DEFAULT 'markdown',
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            deleted_at REAL
        );
        CREATE TABLE IF NOT EXISTS attachments (
            id TEXT PRIMARY KEY NOT NULL,
            note_id TEXT NOT NULL REFERENCES notes(id),
            relative_path TEXT NOT NULL,
            mime_type TEXT NOT NULL,
            size INTEGER NOT NULL,
            created_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS note_fold_groups (
            id TEXT PRIMARY KEY NOT NULL,
            module_id TEXT NOT NULL REFERENCES modules(id) ON DELETE CASCADE,
            created_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS note_fold_group_members (
            group_id TEXT NOT NULL REFERENCES note_fold_groups(id) ON DELETE CASCADE,
            note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
            member_order INTEGER NOT NULL,
            PRIMARY KEY (group_id, note_id),
            UNIQUE (note_id)
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
            note_id UNINDEXED,
            title,
            plain_text,
            tokenize = 'unicode61'
        );
        CREATE INDEX IF NOT EXISTS modules_project_idx ON modules(project_id, sort_order);
        CREATE INDEX IF NOT EXISTS notes_module_idx ON notes(module_id, updated_at DESC);
        CREATE TABLE IF NOT EXISTS note_chunks (
            id TEXT PRIMARY KEY NOT NULL,
            note_id TEXT NOT NULL REFERENCES notes(id),
            chunk_index INTEGER NOT NULL,
            content_text TEXT NOT NULL,
            embedding BLOB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS note_chunks_note_idx ON note_chunks(note_id);
        CREATE INDEX IF NOT EXISTS note_fold_groups_module_idx ON note_fold_groups(module_id, created_at);
        CREATE INDEX IF NOT EXISTS note_fold_group_members_group_idx ON note_fold_group_members(group_id, member_order);
        """)
        if !(try rows("PRAGMA table_info(modules)")).contains(where: { $0.text("name") == "is_project_root" }) {
            try execute("ALTER TABLE modules ADD COLUMN is_project_root INTEGER NOT NULL DEFAULT 0")
        }
        if !(try rows("PRAGMA table_info(notes)")).contains(where: { $0.text("name") == "kind" }) {
            try execute("ALTER TABLE notes ADD COLUMN kind TEXT NOT NULL DEFAULT 'markdown'")
        }
        if !(try rows("PRAGMA table_info(projects)")).contains(where: { $0.text("name") == "is_ai_unreadable" }) {
            try execute("ALTER TABLE projects ADD COLUMN is_ai_unreadable INTEGER NOT NULL DEFAULT 0")
        }
        if !(try rows("PRAGMA table_info(modules)")).contains(where: { $0.text("name") == "is_ai_unreadable" }) {
            try execute("ALTER TABLE modules ADD COLUMN is_ai_unreadable INTEGER NOT NULL DEFAULT 0")
        }
        try execute("DELETE FROM note_chunks WHERE note_id IN (SELECT id FROM notes WHERE kind <> 'markdown')")
        try execute("""
            DELETE FROM note_chunks WHERE note_id IN (
                SELECT n.id FROM notes n
                JOIN modules m ON m.id = n.module_id
                JOIN projects p ON p.id = m.project_id
                WHERE m.is_ai_unreadable = 1 OR p.is_ai_unreadable = 1
            )
            """)
    }

    func fetchProjects() throws -> [Project] {
        try rows("""
            SELECT id, name, sort_order, created_at, updated_at, deleted_at, is_ai_unreadable
            FROM projects WHERE deleted_at IS NULL ORDER BY sort_order, created_at
        """).compactMap(project(from:))
    }

    func fetchModules(projectID: UUID) throws -> [NoteModule] {
        try rows("""
            SELECT id, project_id, name, sort_order, created_at, updated_at, deleted_at, is_project_root, is_ai_unreadable
            FROM modules WHERE project_id = ? AND deleted_at IS NULL
            ORDER BY sort_order, created_at
        """, [.text(projectID.uuidString)]).compactMap(module(from:))
    }

    func fetchAllModules() throws -> [NoteModule] {
        try rows("""
            SELECT m.id, m.project_id, m.name, m.sort_order, m.created_at, m.updated_at, m.deleted_at, m.is_project_root, m.is_ai_unreadable
            FROM modules m JOIN projects p ON p.id = m.project_id
            WHERE m.deleted_at IS NULL AND p.deleted_at IS NULL
            ORDER BY p.sort_order, m.sort_order, m.created_at
        """).compactMap(module(from:))
    }

    func fetchNotes(moduleID: UUID) throws -> [Note] {
        try rows("""
            SELECT id, module_id, title, content_markdown, kind, created_at, updated_at, deleted_at
            FROM notes WHERE module_id = ? AND deleted_at IS NULL
            ORDER BY updated_at DESC
        """, [.text(moduleID.uuidString)]).compactMap(note(from:))
    }

    func fetchAllNotes() throws -> [Note] {
        try rows("""
            SELECT n.id, n.module_id, n.title, n.content_markdown, n.kind, n.created_at, n.updated_at, n.deleted_at
            FROM notes n
            JOIN modules m ON m.id = n.module_id
            JOIN projects p ON p.id = m.project_id
            WHERE n.deleted_at IS NULL AND m.deleted_at IS NULL AND p.deleted_at IS NULL
            ORDER BY p.sort_order, m.sort_order, n.updated_at DESC
        """).compactMap(note(from:))
    }

    func fetchNoteFoldGroups(moduleID: UUID) throws -> [NoteFoldGroup] {
        let groupRows = try rows("""
            SELECT id, module_id, created_at
            FROM note_fold_groups
            WHERE module_id = ?
            ORDER BY created_at, id
        """, [.text(moduleID.uuidString)])
        var groups: [NoteFoldGroup] = []
        for row in groupRows {
            guard let id = row.uuid("id"),
                  let storedModuleID = row.uuid("module_id"),
                  let createdAt = row.date("created_at") else { continue }
            let noteIDs = try rows("""
                SELECT member.note_id
                FROM note_fold_group_members member
                JOIN notes note ON note.id = member.note_id
                WHERE member.group_id = ? AND note.module_id = ?
                ORDER BY member.member_order
            """, [.text(id.uuidString), .text(moduleID.uuidString)]).compactMap { $0.uuid("note_id") }
            guard noteIDs.count >= 2 else { continue }
            groups.append(NoteFoldGroup(id: id, moduleID: storedModuleID, noteIDs: noteIDs, createdAt: createdAt))
        }
        return groups
    }

    func note(id: UUID) throws -> Note? {
        try rows("""
            SELECT id, module_id, title, content_markdown, kind, created_at, updated_at, deleted_at
            FROM notes WHERE id = ? LIMIT 1
        """, [.text(id.uuidString)]).compactMap(note(from:)).first
    }

    @discardableResult
    func createProject(name: String) throws -> Project {
        let clean = try validated(name)
        let project = Project(id: UUID(), name: clean, sortOrder: try nextSortOrder(table: "projects"), createdAt: Date(), updatedAt: Date(), deletedAt: nil, isAIUnreadable: false)
        try execute(
            "INSERT INTO projects (id, name, sort_order, created_at, updated_at, deleted_at, is_ai_unreadable) VALUES (?, ?, ?, ?, ?, NULL, 0)",
            [.text(project.id.uuidString), .text(project.name), .integer(project.sortOrder), .double(project.createdAt.timeIntervalSince1970), .double(project.updatedAt.timeIntervalSince1970)]
        )
        return project
    }

    @discardableResult
    func createModule(projectID: UUID, name: String) throws -> NoteModule {
        let clean = try validated(name)
        let order = try scalarInt("SELECT COALESCE(MAX(sort_order), -1) + 1 FROM modules WHERE project_id = ?", [.text(projectID.uuidString)])
        let item = NoteModule(id: UUID(), projectID: projectID, name: clean, sortOrder: order, createdAt: Date(), updatedAt: Date(), deletedAt: nil, isProjectRoot: false, isAIUnreadable: false)
        try execute(
            "INSERT INTO modules (id, project_id, name, sort_order, created_at, updated_at, deleted_at, is_project_root) VALUES (?, ?, ?, ?, ?, ?, NULL, 0)",
            [.text(item.id.uuidString), .text(projectID.uuidString), .text(item.name), .integer(item.sortOrder), .double(item.createdAt.timeIntervalSince1970), .double(item.updatedAt.timeIntervalSince1970)]
        )
        return item
    }

    func projectRootModule(projectID: UUID) throws -> NoteModule {
        if let existing = try rows("""
            SELECT id, project_id, name, sort_order, created_at, updated_at, deleted_at, is_project_root, is_ai_unreadable
            FROM modules WHERE project_id = ? AND is_project_root = 1 AND deleted_at IS NULL LIMIT 1
        """, [.text(projectID.uuidString)]).compactMap(module(from:)).first {
            return existing
        }
        let now = Date()
        let item = NoteModule(id: UUID(), projectID: projectID, name: "项目文件", sortOrder: -1, createdAt: now, updatedAt: now, deletedAt: nil, isProjectRoot: true, isAIUnreadable: false)
        try execute(
            "INSERT INTO modules (id, project_id, name, sort_order, created_at, updated_at, deleted_at, is_project_root) VALUES (?, ?, ?, ?, ?, ?, NULL, 1)",
            [.text(item.id.uuidString), .text(projectID.uuidString), .text(item.name), .integer(item.sortOrder), .double(now.timeIntervalSince1970), .double(now.timeIntervalSince1970)]
        )
        return item
    }

    @discardableResult
    func createNote(moduleID: UUID, title: String = "未命名笔记", content: String = "", kind: DocumentKind = .markdown) throws -> Note {
        let now = Date()
        let item = Note(id: UUID(), moduleID: moduleID, title: title, contentMarkdown: content, kind: kind, createdAt: now, updatedAt: now, deletedAt: nil)
        try transaction {
            try execute(
                "INSERT INTO notes (id, module_id, title, content_markdown, kind, created_at, updated_at, deleted_at) VALUES (?, ?, ?, ?, ?, ?, ?, NULL)",
                [.text(item.id.uuidString), .text(moduleID.uuidString), .text(title), .text(content), .text(kind.rawValue), .double(now.timeIntervalSince1970), .double(now.timeIntervalSince1970)]
            )
            try updateFTS(note: item)
            try updateChunks(for: item)
        }
        return item
    }

    func save(note: Note) throws {
        var copy = note
        copy.updatedAt = Date()
        try transaction {
            try execute(
                "UPDATE notes SET module_id = ?, title = ?, content_markdown = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL",
                [.text(copy.moduleID.uuidString), .text(copy.title), .text(copy.contentMarkdown), .double(copy.updatedAt.timeIntervalSince1970), .text(copy.id.uuidString)]
            )
            try updateFTS(note: copy)
            try updateChunks(for: copy)
        }
    }

    func rename(kind: DeletedItemKind, id: UUID, name: String) throws {
        let clean = try validated(name)
        let table = switch kind { case .project: "projects"; case .module: "modules"; case .note: "notes" }
        let column = kind == .note ? "title" : "name"
        try execute("UPDATE \(table) SET \(column) = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL", [.text(clean), .double(Date().timeIntervalSince1970), .text(id.uuidString)])
        if kind == .note, let item = try note(id: id) { try updateFTS(note: item) }
    }

    func registerAttachment(noteID: UUID, relativePath: String, mimeType: String, size: Int) throws {
        try execute(
            "INSERT INTO attachments VALUES (?, ?, ?, ?, ?, ?)",
            [.text(UUID().uuidString), .text(noteID.uuidString), .text(relativePath), .text(mimeType), .integer(size), .double(Date().timeIntervalSince1970)]
        )
    }

    func move(noteID: UUID, to moduleID: UUID) throws {
        try transaction {
            try removeNoteFromFoldGroups(noteID)
            try execute("UPDATE notes SET module_id = ?, updated_at = ? WHERE id = ?", [.text(moduleID.uuidString), .double(Date().timeIntervalSince1970), .text(noteID.uuidString)])
            if let moved = try note(id: noteID) {
                try updateFTS(note: moved)
                try updateChunks(for: moved)
            }
        }
    }

    func setAIUnreadable(kind: DeletedItemKind, id: UUID, value: Bool) throws {
        guard kind != .note else { return }
        let flag: SQLiteValue = .integer(value ? 1 : 0)
        let now: SQLiteValue = .double(Date().timeIntervalSince1970)
        try transaction {
            switch kind {
            case .project:
                try execute(
                    "UPDATE projects SET is_ai_unreadable = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL",
                    [flag, now, .text(id.uuidString)]
                )
                if value {
                    try execute("""
                        DELETE FROM note_chunks WHERE note_id IN (
                            SELECT n.id FROM notes n JOIN modules m ON m.id = n.module_id
                            WHERE m.project_id = ?
                        )
                        """, [.text(id.uuidString)])
                }
            case .module:
                try execute(
                    "UPDATE modules SET is_ai_unreadable = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL",
                    [flag, now, .text(id.uuidString)]
                )
                if value {
                    try execute(
                        "DELETE FROM note_chunks WHERE note_id IN (SELECT id FROM notes WHERE module_id = ?)",
                        [.text(id.uuidString)]
                    )
                }
            case .note:
                break
            }
        }
    }

    func isAIUnreadable(projectID: UUID) throws -> Bool {
        try scalarInt(
            "SELECT COUNT(*) FROM projects WHERE id = ? AND is_ai_unreadable = 1",
            [.text(projectID.uuidString)]
        ) > 0
    }

    func isAIUnreadable(moduleID: UUID) throws -> Bool {
        try scalarInt("""
            SELECT COUNT(*) FROM modules m
            JOIN projects p ON p.id = m.project_id
            WHERE m.id = ? AND (m.is_ai_unreadable = 1 OR p.is_ai_unreadable = 1)
            """, [.text(moduleID.uuidString)]) > 0
    }

    func isAIUnreadable(noteID: UUID) throws -> Bool {
        try scalarInt("""
            SELECT COUNT(*) FROM notes n
            JOIN modules m ON m.id = n.module_id
            JOIN projects p ON p.id = m.project_id
            WHERE n.id = ? AND (m.is_ai_unreadable = 1 OR p.is_ai_unreadable = 1)
            """, [.text(noteID.uuidString)]) > 0
    }

    @discardableResult
    func createNoteFoldGroup(moduleID: UUID, noteIDs: [UUID]) throws -> NoteFoldGroup {
        var seen = Set<UUID>()
        let uniqueNoteIDs = noteIDs.filter { seen.insert($0).inserted }
        guard uniqueNoteIDs.count >= 2 else {
            throw QuietPaperError.database("快速折叠至少需要两个文件")
        }
        for noteID in uniqueNoteIDs {
            guard let item = try note(id: noteID), item.moduleID == moduleID, item.deletedAt == nil else {
                throw QuietPaperError.database("只能折叠当前模块中的有效文件")
            }
        }

        let group = NoteFoldGroup(id: UUID(), moduleID: moduleID, noteIDs: uniqueNoteIDs, createdAt: Date())
        try transaction {
            for noteID in uniqueNoteIDs {
                try execute("DELETE FROM note_fold_group_members WHERE note_id = ?", [.text(noteID.uuidString)])
            }
            try removeUndersizedFoldGroups()
            try execute(
                "INSERT INTO note_fold_groups (id, module_id, created_at) VALUES (?, ?, ?)",
                [.text(group.id.uuidString), .text(moduleID.uuidString), .double(group.createdAt.timeIntervalSince1970)]
            )
            for (index, noteID) in uniqueNoteIDs.enumerated() {
                try execute(
                    "INSERT INTO note_fold_group_members (group_id, note_id, member_order) VALUES (?, ?, ?)",
                    [.text(group.id.uuidString), .text(noteID.uuidString), .integer(index)]
                )
            }
        }
        return group
    }

    func deleteNoteFoldGroup(id: UUID) throws {
        try execute("DELETE FROM note_fold_groups WHERE id = ?", [.text(id.uuidString)])
    }

    func moveProject(id: UUID, offset: Int) throws {
        var items = try fetchProjects()
        guard let source = items.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard items.indices.contains(destination) else { return }
        items.swapAt(source, destination)
        try transaction {
            for (index, item) in items.enumerated() {
                try execute("UPDATE projects SET sort_order = ?, updated_at = ? WHERE id = ?", [.integer(index), .double(Date().timeIntervalSince1970), .text(item.id.uuidString)])
            }
        }
    }

    func moveModule(id: UUID, offset: Int) throws {
        guard let item = try rows("SELECT project_id FROM modules WHERE id = ?", [.text(id.uuidString)]).first,
              let projectID = item.uuid("project_id") else { return }
        var items = try fetchModules(projectID: projectID).filter { !$0.isProjectRoot }
        guard let source = items.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard items.indices.contains(destination) else { return }
        items.swapAt(source, destination)
        try transaction {
            for (index, module) in items.enumerated() {
                try execute("UPDATE modules SET sort_order = ?, updated_at = ? WHERE id = ?", [.integer(index), .double(Date().timeIntervalSince1970), .text(module.id.uuidString)])
            }
        }
    }

    func softDelete(kind: DeletedItemKind, id: UUID) throws {
        if kind == .note {
            try softDeleteNotes(ids: [id])
            return
        }

        let timestamp = Date().timeIntervalSince1970
        try transaction {
            switch kind {
            case .project:
                try execute("UPDATE projects SET deleted_at = ? WHERE id = ?", [.double(timestamp), .text(id.uuidString)])
                try execute("UPDATE modules SET deleted_at = ? WHERE project_id = ? AND deleted_at IS NULL", [.double(timestamp), .text(id.uuidString)])
                try execute("UPDATE notes SET deleted_at = ? WHERE module_id IN (SELECT id FROM modules WHERE project_id = ?) AND deleted_at IS NULL", [.double(timestamp), .text(id.uuidString)])
            case .module:
                try execute("UPDATE modules SET deleted_at = ? WHERE id = ?", [.double(timestamp), .text(id.uuidString)])
                try execute("UPDATE notes SET deleted_at = ? WHERE module_id = ? AND deleted_at IS NULL", [.double(timestamp), .text(id.uuidString)])
            case .note:
                break
            }
            try removeDeletedNoteIndexes()
        }
    }

    func softDeleteNotes(ids: [UUID]) throws {
        var seen = Set<UUID>()
        let uniqueIDs = ids.filter { seen.insert($0).inserted }
        guard !uniqueIDs.isEmpty else { return }

        let placeholders = Array(repeating: "?", count: uniqueIDs.count).joined(separator: ", ")
        let timestamp = Date().timeIntervalSince1970
        let values: [SQLiteValue] = [.double(timestamp)] + uniqueIDs.map { .text($0.uuidString) }
        try transaction {
            for id in uniqueIDs {
                try removeNoteFromFoldGroups(id)
            }
            try execute(
                "UPDATE notes SET deleted_at = ? WHERE id IN (\(placeholders)) AND deleted_at IS NULL",
                values
            )
            try removeDeletedNoteIndexes()
        }
    }

    func deletedItems() throws -> [DeletedItem] {
        var output: [DeletedItem] = []
        for row in try rows("SELECT id, name, deleted_at FROM projects WHERE deleted_at IS NOT NULL") {
            if let id = row.uuid("id"), let date = row.date("deleted_at") { output.append(.init(id: id, kind: .project, name: row.text("name"), deletedAt: date, detail: "包含的模块和笔记")) }
        }
        for row in try rows("SELECT id, name, deleted_at FROM modules WHERE deleted_at IS NOT NULL AND is_project_root = 0") {
            if let id = row.uuid("id"), let date = row.date("deleted_at") { output.append(.init(id: id, kind: .module, name: row.text("name"), deletedAt: date, detail: "包含的笔记")) }
        }
        for row in try rows("SELECT id, title AS name, deleted_at FROM notes WHERE deleted_at IS NOT NULL") {
            if let id = row.uuid("id"), let date = row.date("deleted_at") { output.append(.init(id: id, kind: .note, name: row.text("name"), deletedAt: date, detail: "笔记")) }
        }
        return output.sorted { $0.deletedAt > $1.deletedAt }
    }

    func restore(kind: DeletedItemKind, id: UUID) throws {
        try transaction {
            switch kind {
            case .project:
                try execute("UPDATE projects SET deleted_at = NULL WHERE id = ?", [.text(id.uuidString)])
                try execute("UPDATE modules SET deleted_at = NULL WHERE project_id = ?", [.text(id.uuidString)])
                try execute("UPDATE notes SET deleted_at = NULL WHERE module_id IN (SELECT id FROM modules WHERE project_id = ?)", [.text(id.uuidString)])
            case .module:
                try execute("UPDATE modules SET deleted_at = NULL WHERE id = ?", [.text(id.uuidString)])
                try execute("UPDATE projects SET deleted_at = NULL WHERE id = (SELECT project_id FROM modules WHERE id = ?)", [.text(id.uuidString)])
                try execute("UPDATE notes SET deleted_at = NULL WHERE module_id = ?", [.text(id.uuidString)])
            case .note:
                try execute("UPDATE notes SET deleted_at = NULL WHERE id = ?", [.text(id.uuidString)])
                try execute("UPDATE modules SET deleted_at = NULL WHERE id = (SELECT module_id FROM notes WHERE id = ?)", [.text(id.uuidString)])
                try execute("UPDATE projects SET deleted_at = NULL WHERE id = (SELECT project_id FROM modules WHERE id = (SELECT module_id FROM notes WHERE id = ?))", [.text(id.uuidString)])
            }
            try rebuildFTS()
            for note in try notesWithoutChunks() {
                try updateChunks(for: note)
            }
        }
    }

    func permanentlyDelete(kind: DeletedItemKind, id: UUID) throws {
        try transaction {
            switch kind {
            case .project:
                try execute("DELETE FROM note_chunks WHERE note_id IN (SELECT n.id FROM notes n JOIN modules m ON m.id = n.module_id WHERE m.project_id = ?)", [.text(id.uuidString)])
                try execute("DELETE FROM notes_fts WHERE note_id IN (SELECT n.id FROM notes n JOIN modules m ON m.id = n.module_id WHERE m.project_id = ?)", [.text(id.uuidString)])
                try execute("DELETE FROM attachments WHERE note_id IN (SELECT n.id FROM notes n JOIN modules m ON m.id = n.module_id WHERE m.project_id = ?)", [.text(id.uuidString)])
                try execute("DELETE FROM notes WHERE module_id IN (SELECT id FROM modules WHERE project_id = ?)", [.text(id.uuidString)])
                try execute("DELETE FROM modules WHERE project_id = ?", [.text(id.uuidString)])
                try execute("DELETE FROM projects WHERE id = ?", [.text(id.uuidString)])
            case .module:
                try execute("DELETE FROM note_chunks WHERE note_id IN (SELECT id FROM notes WHERE module_id = ?)", [.text(id.uuidString)])
                try execute("DELETE FROM notes_fts WHERE note_id IN (SELECT id FROM notes WHERE module_id = ?)", [.text(id.uuidString)])
                try execute("DELETE FROM attachments WHERE note_id IN (SELECT id FROM notes WHERE module_id = ?)", [.text(id.uuidString)])
                try execute("DELETE FROM notes WHERE module_id = ?", [.text(id.uuidString)])
                try execute("DELETE FROM modules WHERE id = ?", [.text(id.uuidString)])
            case .note:
                try execute("DELETE FROM note_chunks WHERE note_id = ?", [.text(id.uuidString)])
                try execute("DELETE FROM notes_fts WHERE note_id = ?", [.text(id.uuidString)])
                try execute("DELETE FROM attachments WHERE note_id = ?", [.text(id.uuidString)])
                try execute("DELETE FROM notes WHERE id = ?", [.text(id.uuidString)])
            }
        }
    }

    func descendantNoteIDs(kind: DeletedItemKind, id: UUID) throws -> [UUID] {
        let sql: String
        switch kind {
        case .project:
            sql = "SELECT n.id FROM notes n JOIN modules m ON m.id = n.module_id WHERE m.project_id = ?"
        case .module:
            sql = "SELECT id FROM notes WHERE module_id = ?"
        case .note:
            return [id]
        }
        return try rows(sql, [.text(id.uuidString)]).compactMap { $0.uuid("id") }
    }

    func search(query: String, scope: SearchScope, projectID: UUID?, moduleID: UUID?) throws -> [NoteSearchResult] {
        try search(query: query, scope: scope, projectID: projectID, moduleID: moduleID, excludesAIUnreadable: false)
    }

    func searchForAI(query: String, scope: SearchScope, projectID: UUID?, moduleID: UUID?) throws -> [NoteSearchResult] {
        try search(query: query, scope: scope, projectID: projectID, moduleID: moduleID, excludesAIUnreadable: true)
    }

    private func search(
        query: String,
        scope: SearchScope,
        projectID: UUID?,
        moduleID: UUID?,
        excludesAIUnreadable: Bool
    ) throws -> [NoteSearchResult] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        if let results = try? ftsSearch(
            query: clean,
            scope: scope,
            projectID: projectID,
            moduleID: moduleID,
            excludesAIUnreadable: excludesAIUnreadable
        ), !results.isEmpty {
            return results
        }
        return try fallbackSearch(
            query: clean,
            scope: scope,
            projectID: projectID,
            moduleID: moduleID,
            excludesAIUnreadable: excludesAIUnreadable
        )
    }

    private func ftsSearch(
        query: String,
        scope: SearchScope,
        projectID: UUID?,
        moduleID: UUID?,
        excludesAIUnreadable: Bool
    ) throws -> [NoteSearchResult] {
        var clauses = ["n.deleted_at IS NULL", "m.deleted_at IS NULL", "p.deleted_at IS NULL", "notes_fts MATCH ?"]
        if excludesAIUnreadable {
            clauses.append("m.is_ai_unreadable = 0")
            clauses.append("p.is_ai_unreadable = 0")
        }
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map { token in
            "\"\(token.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        var values: [SQLiteValue] = [.text(terms.joined(separator: " AND "))]
        appendScope(scope, projectID: projectID, moduleID: moduleID, clauses: &clauses, values: &values)
        let resultRows = try rows("""
            SELECT n.id AS note_id, p.id AS project_id, m.id AS module_id,
                   p.name AS project_name, m.name AS module_name, m.is_project_root, n.title AS note_title,
                   snippet(notes_fts, 2, '', '', ' … ', 18) AS excerpt, n.updated_at
            FROM notes_fts
            JOIN notes n ON n.id = notes_fts.note_id
            JOIN modules m ON m.id = n.module_id
            JOIN projects p ON p.id = m.project_id
            WHERE \(clauses.joined(separator: " AND "))
            ORDER BY bm25(notes_fts, 0.0, 5.0, 1.0), n.updated_at DESC
            LIMIT 80
        """, values)
        return searchResults(from: resultRows, query: query, excerptColumn: "excerpt")
    }

    private func fallbackSearch(
        query clean: String,
        scope: SearchScope,
        projectID: UUID?,
        moduleID: UUID?,
        excludesAIUnreadable: Bool
    ) throws -> [NoteSearchResult] {
        var clauses = ["n.deleted_at IS NULL", "m.deleted_at IS NULL", "p.deleted_at IS NULL", "(n.title LIKE ? ESCAPE '\\' OR n.content_markdown LIKE ? ESCAPE '\\')"]
        if excludesAIUnreadable {
            clauses.append("m.is_ai_unreadable = 0")
            clauses.append("p.is_ai_unreadable = 0")
        }
        let escaped = clean.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
        var values: [SQLiteValue] = [.text("%\(escaped)%"), .text("%\(escaped)%")]
        appendScope(scope, projectID: projectID, moduleID: moduleID, clauses: &clauses, values: &values)
        let resultRows = try rows("""
            SELECT n.id AS note_id, p.id AS project_id, m.id AS module_id,
                   p.name AS project_name, m.name AS module_name, m.is_project_root, n.title AS note_title,
                   n.content_markdown, n.kind, n.updated_at
            FROM notes n
            JOIN modules m ON m.id = n.module_id
            JOIN projects p ON p.id = m.project_id
            WHERE \(clauses.joined(separator: " AND "))
            ORDER BY CASE WHEN n.title LIKE ? THEN 0 ELSE 1 END, n.updated_at DESC
            LIMIT 80
        """, values + [.text("%\(escaped)%")])
        return searchResults(from: resultRows, query: clean, excerptColumn: nil)
    }

    private func appendScope(_ scope: SearchScope, projectID: UUID?, moduleID: UUID?, clauses: inout [String], values: inout [SQLiteValue]) {
        if scope == .project, let projectID {
            clauses.append("p.id = ?")
            values.append(.text(projectID.uuidString))
        } else if scope == .module, let moduleID {
            clauses.append("m.id = ?")
            values.append(.text(moduleID.uuidString))
        }
    }

    private func searchResults(from rows: [SQLiteRow], query: String, excerptColumn: String?) -> [NoteSearchResult] {
        rows.compactMap { row in
            guard let noteID = row.uuid("note_id"), let projectID = row.uuid("project_id"), let moduleID = row.uuid("module_id"), let updatedAt = row.date("updated_at") else { return nil }
            let excerpt: String
            if let excerptColumn {
                excerpt = row.text(excerptColumn)
            } else {
                let kind = DocumentKind(rawValue: row.text("kind")) ?? .markdown
                let content = Self.searchableText(kind: kind, content: row.text("content_markdown"))
                excerpt = Self.excerpt(from: content, matching: query)
            }
            return NoteSearchResult(
                noteID: noteID,
                projectID: projectID,
                moduleID: moduleID,
                projectName: row.text("project_name"),
                moduleName: row.text("module_name"),
                noteTitle: row.text("note_title"),
                excerpt: excerpt,
                updatedAt: updatedAt,
                isProjectRoot: row.int("is_project_root") != 0
            )
        }
    }

    /// 将 WAL 中未落盘的数据合并回主数据库文件，供备份 / 迁移存储目录使用。
    func checkpoint() throws {
        try execute("PRAGMA wal_checkpoint(FULL)")
    }

    func backup(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let databaseURL else { throw QuietPaperError.database("内存数据库无法备份") }
        try checkpoint()
        let destination = directory.appendingPathComponent("quiet-paper.sqlite")
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: databaseURL, to: destination)
    }

    private func seedIfNeeded() throws {
        guard try scalarInt("SELECT COUNT(*) FROM projects") == 0 else { return }
        let project = try createProject(name: "广告业务平台")
        _ = try createModule(projectID: project.id, name: "项目概览")
        let sync = try createModule(projectID: project.id, name: "飞书同步")
        _ = try createModule(projectID: project.id, name: "数据回流")
        _ = try createModule(projectID: project.id, name: "投放分析")
        let content = """
        通过飞书多维表格 API 按条件读取记录，支持分页获取，适用于数据同步、报表生成等场景。

        建议优先使用视图筛选条件以减少返回数据量，并合理设置分页大小。

        ## 分页读取记录

        使用分页参数 `page_size` 与 `page_token` 进行分页读取，直到返回的 `has_more` 为 false。

        ### 请求示例（cURL）

        ```bash
        curl -X GET 'https://open.feishu.cn/open-apis/bitable/v1/apps/<TABLE_ID>/tables/<TABLE_ID>/records' \\
          -H 'Authorization: Bearer <REDACTED>' \\
          -H 'Content-Type: application/json' \\
          --data-urlencode 'page_size=100' \\
          --data-urlencode 'page_token=<REDACTED>'
        ```

        ### 响应示例（JSON）

        ```json
        {
          "code": 0,
          "msg": "ok",
          "data": {
            "items": [{ "record_id": "rec<REDACTED>", "fields": { "字段A": "示例值", "字段B": 123 } }],
            "has_more": true,
            "page_token": "<REDACTED>"
          }
        }
        ```
        """
        _ = try createNote(moduleID: sync.id, title: "创建多维表格记录", content: "记录在多维表格中新建一条记录。")
        _ = try createNote(moduleID: sync.id, title: "更新多维表格记录", content: "按记录 ID 更新字段内容。")
        _ = try createNote(moduleID: sync.id, title: "飞书 API 限流说明", content: "遇到 429 时采用指数退避并尊重 Retry-After。")
        _ = try createNote(moduleID: sync.id, title: "读取多维表格记录", content: content)
    }

    private func rebuildFTS() throws {
        try execute("DELETE FROM notes_fts")
        for item in try rows("SELECT id, module_id, title, content_markdown, kind, created_at, updated_at, deleted_at FROM notes WHERE deleted_at IS NULL").compactMap(note(from:)) {
            try updateFTS(note: item)
        }
    }

    private func updateFTS(note: Note) throws {
        try execute("DELETE FROM notes_fts WHERE note_id = ?", [.text(note.id.uuidString)])
        let bodyText = Self.searchableText(kind: note.kind, content: note.contentMarkdown)
        // 模块名和项目名也纳入 FTS 索引，顶部搜索栏可按模块/项目名搜索
        let pathPrefix = moduleProjectPrefix(moduleID: note.moduleID)
        let searchableText = pathPrefix + note.title + "\n" + bodyText
        try execute("INSERT INTO notes_fts(note_id, title, plain_text) VALUES (?, ?, ?)", [.text(note.id.uuidString), .text(note.title), .text(searchableText)])
    }

    private func moduleProjectPrefix(moduleID: UUID) -> String {
        guard let row = try? rows("""
            SELECT m.name AS module_name, p.name AS project_name
            FROM modules m JOIN projects p ON p.id = m.project_id
            WHERE m.id = ?
            """, [.text(moduleID.uuidString)]).first else { return "" }
        let moduleName = row.text("module_name")
        let projectName = row.text("project_name")
        let parts = [projectName, moduleName].filter { !$0.isEmpty }
        return parts.isEmpty ? "" : parts.joined(separator: " ") + " "
    }

    private static func searchableText(kind: DocumentKind, content: String) -> String {
        switch kind {
        case .markdown: MarkdownPlainText.extract(from: content)
        case .request: HTTPRequestDraft.decode(content).searchableText
        case .websocket: WebSocketRequestDraft.decode(content).searchableText
        case .connection: DatabaseConnectionFile.decode(content).searchableText
        }
    }

    private func nextSortOrder(table: String) throws -> Int {
        try scalarInt("SELECT COALESCE(MAX(sort_order), -1) + 1 FROM \(table)")
    }

    private func removeNoteFromFoldGroups(_ noteID: UUID) throws {
        try execute("DELETE FROM note_fold_group_members WHERE note_id = ?", [.text(noteID.uuidString)])
        try removeUndersizedFoldGroups()
    }

    private func removeDeletedNoteIndexes() throws {
        try execute("DELETE FROM notes_fts WHERE note_id IN (SELECT id FROM notes WHERE deleted_at IS NOT NULL)")
        try execute("DELETE FROM note_chunks WHERE note_id IN (SELECT id FROM notes WHERE deleted_at IS NOT NULL)")
    }

    private func removeUndersizedFoldGroups() throws {
        try execute("""
            DELETE FROM note_fold_groups
            WHERE id IN (
                SELECT groups.id
                FROM note_fold_groups groups
                LEFT JOIN note_fold_group_members members ON members.group_id = groups.id
                GROUP BY groups.id
                HAVING COUNT(members.note_id) < 2
            )
        """)
    }

    private func validated(_ name: String) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw QuietPaperError.invalidName }
        return clean
    }

    private func project(from row: SQLiteRow) -> Project? {
        guard let id = row.uuid("id"), let created = row.date("created_at"), let updated = row.date("updated_at") else { return nil }
        return Project(id: id, name: row.text("name"), sortOrder: row.int("sort_order"), createdAt: created, updatedAt: updated, deletedAt: row.date("deleted_at"), isAIUnreadable: row.int("is_ai_unreadable") != 0)
    }

    private func module(from row: SQLiteRow) -> NoteModule? {
        guard let id = row.uuid("id"), let projectID = row.uuid("project_id"), let created = row.date("created_at"), let updated = row.date("updated_at") else { return nil }
        return NoteModule(id: id, projectID: projectID, name: row.text("name"), sortOrder: row.int("sort_order"), createdAt: created, updatedAt: updated, deletedAt: row.date("deleted_at"), isProjectRoot: row.int("is_project_root") != 0, isAIUnreadable: row.int("is_ai_unreadable") != 0)
    }

    private func note(from row: SQLiteRow) -> Note? {
        guard let id = row.uuid("id"), let moduleID = row.uuid("module_id"), let created = row.date("created_at"), let updated = row.date("updated_at") else { return nil }
        let kind = DocumentKind(rawValue: row.text("kind")) ?? .markdown
        return Note(id: id, moduleID: moduleID, title: row.text("title"), contentMarkdown: row.text("content_markdown"), kind: kind, createdAt: created, updatedAt: updated, deletedAt: row.date("deleted_at"))
    }

    private static func excerpt(from text: String, matching query: String) -> String {
        let normalized = text.replacingOccurrences(of: "\n", with: " ")
        guard let range = normalized.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(normalized.prefix(150))
        }
        let start = normalized.index(range.lowerBound, offsetBy: -45, limitedBy: normalized.startIndex) ?? normalized.startIndex
        let end = normalized.index(range.upperBound, offsetBy: 90, limitedBy: normalized.endIndex) ?? normalized.endIndex
        return (start > normalized.startIndex ? "…" : "") + normalized[start..<end] + (end < normalized.endIndex ? "…" : "")
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func scalarInt(_ sql: String, _ values: [SQLiteValue] = []) throws -> Int {
        try rows(sql, values).first?.int(at: 0) ?? 0
    }

    private func execute(_ sql: String, _ values: [SQLiteValue] = []) throws {
        lock.lock()
        defer { lock.unlock() }
        if values.isEmpty && sql.contains(";") {
            var message: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(handle, sql, nil, nil, &message) == SQLITE_OK else {
                let detail = message.map { String(cString: $0) } ?? "未知错误"
                sqlite3_free(message)
                throw QuietPaperError.database(detail)
            }
            return
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw error() }
    }

    private func rows(_ sql: String, _ values: [SQLiteValue] = []) throws -> [SQLiteRow] {
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        var output: [SQLiteRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var storage: [String: SQLiteValue] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let key = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER: storage[key] = .integer(Int(sqlite3_column_int64(statement, index)))
                case SQLITE_FLOAT: storage[key] = .double(sqlite3_column_double(statement, index))
                case SQLITE_TEXT: storage[key] = .text(String(cString: sqlite3_column_text(statement, index)))
                case SQLITE_BLOB:
                    if let bytes = sqlite3_column_blob(statement, index) {
                        let count = Int(sqlite3_column_bytes(statement, index))
                        storage[key] = .blob(Data(bytes: bytes, count: count))
                    } else {
                        storage[key] = .null
                    }
                default: storage[key] = .null
                }
            }
            output.append(SQLiteRow(values: storage, orderedKeys: (0..<sqlite3_column_count(statement)).map { String(cString: sqlite3_column_name(statement, $0)) }))
        }
        return output
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer?) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let string): result = sqlite3_bind_text(statement, index, string, -1, transient)
            case .integer(let integer): result = sqlite3_bind_int64(statement, index, sqlite3_int64(integer))
            case .double(let double): result = sqlite3_bind_double(statement, index, double)
            case .blob(let data): result = data.withUnsafeBytes { bytes in sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(data.count), transient) }
            case .null: result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { throw error() }
        }
    }

    // MARK: - Vector Chunks

    private func updateChunks(for note: Note) throws {
        try execute("DELETE FROM note_chunks WHERE note_id = ?", [.text(note.id.uuidString)])
        guard note.kind == .markdown, !(try isAIUnreadable(noteID: note.id)) else { return }
        let bodyText = MarkdownPlainText.extract(from: note.contentMarkdown)
        let pathPrefix = moduleProjectPrefix(moduleID: note.moduleID)
        let plainText = pathPrefix + note.title + "\n\n" + bodyText
        let paragraphs = chunkText(plainText)
        guard !paragraphs.isEmpty else { return }

        guard let service = EmbeddingService() else { return }
        let vectors = service.embedBatch(texts: paragraphs)

        for (index, paragraph) in paragraphs.enumerated() {
            guard index < vectors.count else { break }
            let embedding = vectors[index]
            let blobData = NSData(bytes: embedding, length: embedding.count * MemoryLayout<Float>.size) as Data
            try execute(
                "INSERT INTO note_chunks (id, note_id, chunk_index, content_text, embedding) VALUES (?, ?, ?, ?, ?)",
                [.text(UUID().uuidString), .text(note.id.uuidString), .integer(index), .text(paragraph), .blob(blobData)]
            )
        }
    }

    func rebuildAllChunks() throws {
        try execute("DELETE FROM note_chunks")
        let all = try rows("""
            SELECT n.id, n.module_id, n.title, n.content_markdown, n.kind, n.created_at, n.updated_at, n.deleted_at
            FROM notes n
            JOIN modules m ON m.id = n.module_id
            JOIN projects p ON p.id = m.project_id
            WHERE n.deleted_at IS NULL AND m.deleted_at IS NULL AND p.deleted_at IS NULL
              AND m.is_ai_unreadable = 0 AND p.is_ai_unreadable = 0
            """).compactMap(note(from:))
        for note in all {
            try updateChunks(for: note)
        }
    }

    func fetchAllChunks(scope: SearchScope, projectID: UUID?, moduleID: UUID?) throws -> [VectorChunk] {
        var sql = """
            SELECT nc.id, nc.note_id, nc.chunk_index, nc.content_text, nc.embedding
            FROM note_chunks nc
            JOIN notes n ON n.id = nc.note_id
            JOIN modules m ON m.id = n.module_id
            JOIN projects p ON p.id = m.project_id
            WHERE n.deleted_at IS NULL AND m.deleted_at IS NULL AND p.deleted_at IS NULL
              AND n.kind = 'markdown' AND m.is_ai_unreadable = 0 AND p.is_ai_unreadable = 0
            """
        var params: [SQLiteValue] = []
        switch scope {
        case .project:
            if let pid = projectID {
                sql += " AND p.id = ?"
                params.append(.text(pid.uuidString))
            }
        case .module:
            if let mid = moduleID {
                sql += " AND m.id = ?"
                params.append(.text(mid.uuidString))
            }
        case .all:
            break
        }

        let rs = try rows(sql, params)
        return rs.compactMap { row -> VectorChunk? in
            guard let id = row.uuid("id"),
                  let noteID = row.uuid("note_id"),
                  let blobData = row.blob("embedding") else { return nil }
            let floats: [Float] = blobData.withUnsafeBytes { ptr in
                Array(ptr.bindMemory(to: Float.self))
            }
            guard !floats.isEmpty else { return nil }
            return VectorChunk(
                id: id,
                noteID: noteID,
                chunkIndex: row.int("chunk_index"),
                contentText: row.text("content_text"),
                embedding: floats
            )
        }
    }

    func noteSearchResult(noteID: UUID, excerpt: String) throws -> NoteSearchResult? {
        let sql = """
            SELECT n.id AS note_id, n.module_id, n.title AS note_title, n.updated_at,
                   m.project_id, m.name AS module_name, m.is_project_root,
                   p.name AS project_name
            FROM notes n
            JOIN modules m ON m.id = n.module_id
            JOIN projects p ON p.id = m.project_id
            WHERE n.id = ? AND m.is_ai_unreadable = 0 AND p.is_ai_unreadable = 0
            """
        guard let row = try rows(sql, [.text(noteID.uuidString)]).first,
              let nid = row.uuid("note_id"),
              let pid = row.uuid("project_id"),
              let mid = row.uuid("module_id"),
              let updated = row.date("updated_at") else { return nil }
        return NoteSearchResult(
            noteID: nid,
            projectID: pid,
            moduleID: mid,
            projectName: row.text("project_name"),
            moduleName: row.text("module_name"),
            noteTitle: row.text("note_title"),
            excerpt: excerpt,
            updatedAt: updated,
            isProjectRoot: row.int("is_project_root") != 0
        )
    }

    private func notesWithoutChunks() throws -> [Note] {
        try rows("""
            SELECT n.id, n.module_id, n.title, n.content_markdown, n.kind, n.created_at, n.updated_at, n.deleted_at
            FROM notes n
            JOIN modules m ON m.id = n.module_id
            JOIN projects p ON p.id = m.project_id
            WHERE n.deleted_at IS NULL AND m.deleted_at IS NULL AND p.deleted_at IS NULL
              AND m.is_ai_unreadable = 0 AND p.is_ai_unreadable = 0
              AND n.id NOT IN (SELECT DISTINCT note_id FROM note_chunks)
            """).compactMap(note(from:))
    }

    func chunkCount() throws -> Int {
        try scalarInt("""
            SELECT COUNT(*) FROM note_chunks nc
            JOIN notes n ON n.id = nc.note_id
            JOIN modules m ON m.id = n.module_id
            JOIN projects p ON p.id = m.project_id
            WHERE n.deleted_at IS NULL AND m.deleted_at IS NULL AND p.deleted_at IS NULL
              AND m.is_ai_unreadable = 0 AND p.is_ai_unreadable = 0
            """)
    }

    private func chunkText(_ plainText: String) -> [String] {
        let minLength = 10
        let raw = plainText.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var result: [String] = []
        var buffer = ""
        for paragraph in raw {
            if paragraph.count < minLength {
                buffer += (buffer.isEmpty ? "" : " ") + paragraph
            } else {
                if !buffer.isEmpty {
                    result.append(buffer)
                    buffer = ""
                }
                result.append(paragraph)
            }
        }
        if !buffer.isEmpty, let last = result.popLast() {
            result.append(last + " " + buffer)
        } else if !buffer.isEmpty {
            result.append(buffer)
        }
        return result
    }

    private func error(_ prefix: String = "") -> QuietPaperError {
        let detail = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "数据库未打开"
        return .database(prefix.isEmpty ? detail : "\(prefix)：\(detail)")
    }
}

private enum SQLiteValue {
    case text(String)
    case integer(Int)
    case double(Double)
    case blob(Data)
    case null
}

private struct SQLiteRow {
    let values: [String: SQLiteValue]
    let orderedKeys: [String]

    func text(_ key: String) -> String {
        if case .text(let value) = values[key] { return value }
        return ""
    }

    func int(_ key: String) -> Int {
        if case .integer(let value) = values[key] { return value }
        return 0
    }

    func blob(_ key: String) -> Data? {
        if case .blob(let value) = values[key] { return value }
        return nil
    }

    func int(at index: Int) -> Int {
        guard orderedKeys.indices.contains(index) else { return 0 }
        return int(orderedKeys[index])
    }

    func date(_ key: String) -> Date? {
        if case .double(let value) = values[key] { return Date(timeIntervalSince1970: value) }
        if case .integer(let value) = values[key] { return Date(timeIntervalSince1970: Double(value)) }
        return nil
    }

    func uuid(_ key: String) -> UUID? { UUID(uuidString: text(key)) }
}
