import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var modules: [NoteModule] = []
    @Published private(set) var projectFilesByProjectID: [UUID: [Note]] = [:]
    @Published private(set) var notes: [Note] = []
    @Published private(set) var noteFoldGroups: [NoteFoldGroup] = []
    @Published private(set) var allNotes: [Note] = []
    @Published var selectedProjectID: UUID?
    @Published var selectedModuleID: UUID?
    @Published var selectedNoteID: UUID?
    @Published var draftTitle = ""
    @Published var draftContent = ""
    @Published var saveState: SaveState = .idle
    @Published var searchQuery = ""
    @Published var searchScope: SearchScope = .all
    @Published private(set) var searchResults: [NoteSearchResult] = []
    @Published var startupError: String?
    /// 当前会话的专注模式；不持久化，重新启动时始终显示完整工作区。
    @Published var isFocusMode = false
    @Published var theme: Theme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Theme.defaultsKey)
        }
    }

    private(set) var database: WorkspaceDatabase
    private(set) var attachments: AttachmentStore
    private var aiProvider: any AIProvider
    private var autosaveTask: Task<Void, Never>?
    private let autosaveInterval: Duration
    private let saveQueue = DispatchQueue(label: "QuietPaper.NoteSave", qos: .utility)
    private var nextSaveSequence: UInt64 = 0
    private var latestAppliedSaveSequence: UInt64 = 0
    private var isLoadingDraft = false

    init(
        database: WorkspaceDatabase? = nil,
        aiProvider: (any AIProvider)? = nil,
        autosaveInterval: Duration = .seconds(60)
    ) {
        let usesInMemoryPreview = ProcessInfo.processInfo.arguments.contains("--in-memory-preview")
        self.autosaveInterval = autosaveInterval
        self.theme = Theme.stored
        if let database {
            self.database = database
        } else if usesInMemoryPreview {
            // 界面验收专用：使用带示例数据的内存库，绝不读取或写入用户数据库。
            self.database = try! WorkspaceDatabase(inMemory: true, seedIfEmpty: true)
        } else {
            do {
                self.database = try WorkspaceDatabase(url: WorkspaceDatabase.applicationDatabaseURL())
            } catch {
                self.database = try! WorkspaceDatabase(inMemory: true, seedIfEmpty: true)
                startupError = error.localizedDescription
            }
        }
        self.attachments = AttachmentStore(databaseURL: self.database.databaseURL)
        if let aiProvider {
            self.aiProvider = aiProvider
        } else if usesInMemoryPreview {
            self.aiProvider = LocalGroundedAIProvider()
        } else {
            self.aiProvider = Self.createDefaultAIProvider()
        }
        reloadWorkspace(selectFirst: true)
    }

    deinit { autosaveTask?.cancel() }

    private static func createDefaultAIProvider() -> any AIProvider {
        let keychain = KeychainStore()
        if let envKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !envKey.isEmpty {
            let model = resolvedDeepSeekModel()
            return DeepSeekAIProvider(apiKey: envKey, model: model)
        }
        if let keychainKey = keychain.get(), !keychainKey.isEmpty {
            let model = resolvedDeepSeekModel()
            return DeepSeekAIProvider(apiKey: keychainKey, model: model)
        }
        return LocalGroundedAIProvider()
    }

    private static func resolvedDeepSeekModel() -> String {
        let stored = UserDefaults.standard.string(forKey: "deepseek_model") ?? "deepseek-v4-flash"
        if stored == "deepseek-chat" || stored == "deepseek-reasoner" {
            UserDefaults.standard.set("deepseek-v4-flash", forKey: "deepseek_model")
            return "deepseek-v4-flash"
        }
        return ["deepseek-v4-flash", "deepseek-v4-pro"].contains(stored) ? stored : "deepseek-v4-flash"
    }

    func refreshAIProvider() {
        aiProvider = Self.createDefaultAIProvider()
    }

    var activeAIProviderName: String { aiProvider.name }
    var activeAIProviderRequiresNetwork: Bool { aiProvider.requiresNetwork }

    @Published var isRebuildingIndex = false
    var vectorChunkCount: Int { (try? database.chunkCount()) ?? 0 }

    func rebuildVectorIndex() {
        guard !isRebuildingIndex else { return }
        isRebuildingIndex = true
        Task {
            do {
                try database.rebuildAllChunks()
            } catch {
                startupError = "重建向量索引失败：\(error.localizedDescription)"
            }
            isRebuildingIndex = false
        }
    }

    /// 首次打开 AI 面板时自动建索引，不阻塞 UI。
    func ensureVectorIndex() {
        guard (try? database.chunkCount()) == 0 else { return }
        Task {
            try? database.rebuildAllChunks()
        }
    }

    var selectedProject: Project? { projects.first { $0.id == selectedProjectID } }
    var selectedModule: NoteModule? { modules.first { $0.id == selectedModuleID } }
    var selectedNote: Note? { notes.first { $0.id == selectedNoteID } }
    var showsNoteList: Bool { selectedModule?.isProjectRoot == false }

    func modules(in projectID: UUID) -> [NoteModule] {
        modules.filter { $0.projectID == projectID }
    }

    func visibleModules(in projectID: UUID) -> [NoteModule] {
        modules(in: projectID).filter { !$0.isProjectRoot }
    }

    func projectFiles(in projectID: UUID) -> [Note] {
        projectFilesByProjectID[projectID] ?? []
    }

    func selectProject(_ id: UUID) {
        let firstModule = modules(in: id).first
        if selectedProjectID == id, selectedModuleID == firstModule?.id { return }
        forceSave()
        selectedProjectID = id
        selectedModuleID = firstModule?.id
        reloadNotes(selectFirst: true)
    }

    func selectModule(_ id: UUID) {
        guard id != selectedModuleID else { return }
        forceSave()
        selectedModuleID = id
        selectedProjectID = modules.first(where: { $0.id == id })?.projectID
        reloadNotes(selectFirst: true)
    }

    func selectNote(_ id: UUID) {
        guard id != selectedNoteID else { return }
        forceSave()
        selectedNoteID = id
        loadDraft()
    }

    func selectProjectFile(_ noteID: UUID, projectID: UUID) {
        guard let root = modules.first(where: { $0.projectID == projectID && $0.isProjectRoot }) else { return }
        if selectedProjectID == projectID, selectedModuleID == root.id, selectedNoteID == noteID { return }
        forceSave()
        selectedProjectID = projectID
        selectedModuleID = root.id
        reloadNotes(selectFirst: false)
        guard notes.contains(where: { $0.id == noteID }) else { return }
        selectedNoteID = noteID
        loadDraft()
    }

    func jumpToQuickPage(_ slot: Int) {
        guard (1...3).contains(slot),
              let rawValue = UserDefaults.standard.string(forKey: "QuietPaper.quickJump.\(slot)"),
              let noteID = UUID(uuidString: rawValue),
              let target = allNotes.first(where: { $0.id == noteID }),
              let module = modules.first(where: { $0.id == target.moduleID }) else { return }

        forceSave()
        if module.isProjectRoot {
            selectProjectFile(target.id, projectID: module.projectID)
        } else {
            selectModule(module.id)
            selectNote(target.id)
        }
    }

    func quickJumpPath(for note: Note) -> String {
        guard let module = modules.first(where: { $0.id == note.moduleID }),
              let project = projects.first(where: { $0.id == module.projectID }) else {
            return note.title.isEmpty ? "未命名页面" : note.title
        }
        let title = note.title.isEmpty ? "未命名页面" : note.title
        return module.isProjectRoot
            ? "\(project.name) / \(title)"
            : "\(project.name) / \(module.name) / \(title)"
    }

    func setDraftTitle(_ value: String) {
        draftTitle = value
        scheduleSave()
    }

    func setDraftContent(_ value: String) {
        draftContent = selectedNote?.kind == .markdown ? MarkdownImageSyntax.normalized(value) : value
        scheduleSave()
    }

    func scheduleSave() {
        guard !isLoadingDraft, selectedNoteID != nil else { return }
        saveState = .pending
        guard autosaveTask == nil else { return }
        let interval = autosaveInterval
        autosaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.autosaveTask = nil
            await self.saveDraftInBackground()
        }
    }

    func forceSave() {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard selectedNoteID != nil, saveState == .pending || saveState == .saving || draftDiffersFromStored else { return }
        saveDraft()
    }

    func retrySave() { saveDraft() }

    @discardableResult
    func createProject(named name: String = "新项目") -> Project? {
        do {
            forceSave()
            let project = try database.createProject(name: name)
            _ = try database.projectRootModule(projectID: project.id)
            reloadWorkspace(selectFirst: false)
            selectProject(project.id)
            return project
        } catch { report(error) }
        return nil
    }

    @discardableResult
    func createModule(projectID: UUID? = nil, named name: String = "新模块") -> NoteModule? {
        guard let projectID = projectID ?? selectedProjectID else { return nil }
        do {
            forceSave()
            let item = try database.createModule(projectID: projectID, name: name)
            reloadWorkspace(selectFirst: false)
            selectModule(item.id)
            return item
        } catch { report(error) }
        return nil
    }

    @discardableResult
    func createNote(named title: String = "未命名笔记") -> Note? {
        guard let selectedModuleID else { return nil }
        do {
            forceSave()
            let item = try database.createNote(moduleID: selectedModuleID, title: title)
            reloadNotes(selectFirst: false)
            selectNote(item.id)
            return item
        } catch { report(error) }
        return nil
    }

    @discardableResult
    func createRequest(named title: String = "新请求") -> Note? {
        guard let selectedModuleID else { return nil }
        do {
            forceSave()
            let content = try HTTPRequestDraft().encoded()
            let item = try database.createNote(moduleID: selectedModuleID, title: title, content: content, kind: .request)
            reloadNotes(selectFirst: false)
            selectNote(item.id)
            return item
        } catch { report(error) }
        return nil
    }

    @discardableResult
    func createConnection(named title: String = "新连接") -> Note? {
        guard let selectedModuleID else { return nil }
        do {
            forceSave()
            let content = try DatabaseConnectionFile().encoded()
            let item = try database.createNote(moduleID: selectedModuleID, title: title, content: content, kind: .connection)
            reloadNotes(selectFirst: false)
            selectNote(item.id)
            return item
        } catch { report(error) }
        return nil
    }

    @discardableResult
    func createProjectFile(projectID: UUID? = nil, named title: String = "未命名文件") -> Note? {
        guard let projectID = projectID ?? selectedProjectID else { return nil }
        do {
            forceSave()
            let root = try database.projectRootModule(projectID: projectID)
            let item = try database.createNote(moduleID: root.id, title: title)
            reloadWorkspace(selectFirst: false)
            selectProjectFile(item.id, projectID: projectID)
            return item
        } catch { report(error) }
        return nil
    }

    @discardableResult
    func createProjectRequest(projectID: UUID? = nil, named title: String = "新请求") -> Note? {
        guard let projectID = projectID ?? selectedProjectID else { return nil }
        do {
            forceSave()
            let root = try database.projectRootModule(projectID: projectID)
            let content = try HTTPRequestDraft().encoded()
            let item = try database.createNote(moduleID: root.id, title: title, content: content, kind: .request)
            reloadWorkspace(selectFirst: false)
            selectProjectFile(item.id, projectID: projectID)
            return item
        } catch { report(error) }
        return nil
    }

    @discardableResult
    func createProjectConnection(projectID: UUID? = nil, named title: String = "新连接") -> Note? {
        guard let projectID = projectID ?? selectedProjectID else { return nil }
        do {
            forceSave()
            let root = try database.projectRootModule(projectID: projectID)
            let content = try DatabaseConnectionFile().encoded()
            let item = try database.createNote(moduleID: root.id, title: title, content: content, kind: .connection)
            reloadWorkspace(selectFirst: false)
            selectProjectFile(item.id, projectID: projectID)
            return item
        } catch { report(error) }
        return nil
    }

    func rename(kind: DeletedItemKind, id: UUID, to name: String) {
        do {
            try database.rename(kind: kind, id: id, name: name)
            reloadWorkspace(selectFirst: false)
            reloadNotes(selectFirst: false)
            if kind == .note, id == selectedNoteID { loadDraft() }
        } catch { report(error) }
    }

    func moveProject(_ id: UUID, offset: Int) {
        do {
            try database.moveProject(id: id, offset: offset)
            reloadWorkspace(selectFirst: false)
        } catch { report(error) }
    }

    func moveModule(_ id: UUID, offset: Int) {
        do {
            try database.moveModule(id: id, offset: offset)
            reloadWorkspace(selectFirst: false)
        } catch { report(error) }
    }

    func moveNote(_ id: UUID, to moduleID: UUID) {
        do {
            forceSave()
            try database.move(noteID: id, to: moduleID)
            reloadWorkspace(selectFirst: false)
        } catch { report(error) }
    }

    @discardableResult
    func quickFoldNotes(_ noteIDs: [UUID]) -> Bool {
        guard let moduleID = selectedModuleID else { return false }
        do {
            _ = try database.createNoteFoldGroup(moduleID: moduleID, noteIDs: noteIDs)
            noteFoldGroups = try database.fetchNoteFoldGroups(moduleID: moduleID)
            return true
        } catch {
            report(error)
            return false
        }
    }

    func expandNoteFoldGroup(_ id: UUID) {
        do {
            try database.deleteNoteFoldGroup(id: id)
            noteFoldGroups = try selectedModuleID.map(database.fetchNoteFoldGroups(moduleID:)) ?? []
        } catch { report(error) }
    }

    func delete(kind: DeletedItemKind, id: UUID) {
        do {
            forceSave()
            try database.softDelete(kind: kind, id: id)
            reloadWorkspace(selectFirst: true)
        } catch { report(error) }
    }

    func deletedItems() -> [DeletedItem] {
        (try? database.deletedItems()) ?? []
    }

    func restore(_ item: DeletedItem) {
        do {
            try database.restore(kind: item.kind, id: item.id)
            reloadWorkspace(selectFirst: true)
        } catch { report(error) }
    }

    func permanentlyDelete(_ item: DeletedItem) {
        do {
            for noteID in try database.descendantNoteIDs(kind: item.kind, id: item.id) {
                try attachments.removeAttachments(noteID: noteID)
            }
            try database.permanentlyDelete(kind: item.kind, id: item.id)
            reloadWorkspace(selectFirst: true)
        } catch { report(error) }
    }

    func updateSearch() {
        do {
            searchResults = try database.search(query: searchQuery, scope: searchScope, projectID: selectedProjectID, moduleID: selectedModuleID)
        } catch {
            searchResults = []
            report(error)
        }
    }

    func openSearchResult(_ result: NoteSearchResult) {
        forceSave()
        selectedProjectID = result.projectID
        selectedModuleID = result.moduleID
        reloadNotes(selectFirst: false)
        selectNote(result.noteID)
    }

    func ask(_ question: String) async -> GroundedAnswer {
        do {
            var combined: [UUID: (score: Float, result: NoteSearchResult)] = [:]

            // 1. FTS5 关键词检索（权重 0.4）
            let terms = RetrievalQueryTerms.make(from: question)
            for term in terms {
                for result in try database.search(query: term, scope: searchScope, projectID: selectedProjectID, moduleID: selectedModuleID) {
                    let previous = combined[result.noteID]?.score ?? 0
                    combined[result.noteID] = (previous + 1, result)
                }
            }
            let ftsMax = combined.values.map(\.score).max() ?? 1
            for (id, entry) in combined {
                combined[id] = (0.4 * entry.score / ftsMax, entry.result)
            }

            // 2. 向量语义检索（权重 0.6）
            if let embedding = EmbeddingService() {
                let chunks = try database.fetchAllChunks(scope: searchScope, projectID: selectedProjectID, moduleID: selectedModuleID)
                if !chunks.isEmpty {
                    let svc = VectorSearchService(embedding: embedding)
                    let scored = svc.search(query: question, chunks: chunks, topK: 16)
                    for sc in scored {
                        guard let result = try database.noteSearchResult(noteID: sc.chunk.noteID, excerpt: sc.chunk.contentText) else { continue }
                        let vecScore = 0.6 * max(0, sc.score)
                        if let existing = combined[result.noteID] {
                            combined[result.noteID] = (max(existing.score, vecScore), existing.result)
                        } else {
                            combined[result.noteID] = (vecScore, result)
                        }
                    }
                }
            }

            let context = combined.values
                .sorted { $0.score == $1.score ? $0.result.updatedAt > $1.result.updatedAt : $0.score > $1.score }
                .prefix(8)
                .map { NoteExcerpt(result: $0.result) }
            return try await aiProvider.answer(question: question, context: context)
        } catch {
            return GroundedAnswer(text: "查询失败：\(error.localizedDescription)", sources: [])
        }
    }

    func importImageMarkdown(_ image: NSImage) -> String? {
        guard let noteID = selectedNoteID else { return nil }
        do {
            let result = try attachments.importImage(image, noteID: noteID)
            try database.registerAttachment(noteID: noteID, relativePath: result.relativePath, mimeType: "image/png", size: result.size)
            return "![图片](\(result.relativePath))"
        } catch {
            report(error)
            return nil
        }
    }

    func insertImage(_ image: NSImage) {
        if let markdown = importImageMarkdown(image) {
            let separator = draftContent.hasSuffix("\n") || draftContent.isEmpty ? "" : "\n"
            setDraftContent(draftContent + separator + markdown + "\n")
        }
    }

    func formatJSON() {
        guard let pretty = MarkdownJSONFormatter.format(draftContent) else {
            startupError = "当前笔记不是有效的 JSON 文档"
            return
        }
        setDraftContent(pretty)
    }

    func exportCurrentNote(to url: URL) throws {
        guard selectedNoteID != nil else { throw QuietPaperError.noSelection }
        forceSave()
        try draftContent.write(to: url, atomically: true, encoding: .utf8)
    }

    func exportModuleAsMergedMarkdown(_ module: NoteModule, to url: URL) throws {
        forceSave()
        let notes = try database.fetchNotes(moduleID: module.id)
        try ModuleMarkdownExporter.writeMerged(moduleName: module.name, notes: notes, to: url)
    }

    func exportModuleAsArchive(_ module: NoteModule, to url: URL) throws {
        forceSave()
        let notes = try database.fetchNotes(moduleID: module.id)
        try ModuleMarkdownExporter.writeArchive(moduleName: module.name, notes: notes, to: url)
    }

    func exportProjectAsMergedMarkdown(_ project: Project, to url: URL) throws {
        forceSave()
        let contents = try projectExportContents(projectID: project.id)
        try ModuleMarkdownExporter.writeMergedProject(
            projectName: project.name,
            rootNotes: contents.rootNotes,
            modules: contents.modules,
            to: url
        )
    }

    func exportProjectAsArchive(_ project: Project, to url: URL) throws {
        forceSave()
        let contents = try projectExportContents(projectID: project.id)
        try ModuleMarkdownExporter.writeProjectArchive(
            projectName: project.name,
            rootNotes: contents.rootNotes,
            modules: contents.modules,
            to: url
        )
    }

    func backup(to directory: URL) throws {
        forceSave()
        try database.backup(to: directory)
        let sourceAttachments = attachments.rootURL.appendingPathComponent("attachments", isDirectory: true)
        let destination = directory.appendingPathComponent("attachments", isDirectory: true)
        if FileManager.default.fileExists(atPath: sourceAttachments.path) {
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: sourceAttachments, to: destination)
        }
    }

    /// 当前存储目录（数据库所在目录）；启动时回退到内存数据库时为 nil。
    var storageDirectoryURL: URL? {
        database.databaseURL?.deletingLastPathComponent()
    }

    /// 切换存储目录：把数据库与附件迁移到新目录，并保存为下次启动使用的目录。
    func setStorageDirectory(_ directory: URL) throws {
        if let current = storageDirectoryURL,
           current.resolvingSymlinksInPath() == directory.resolvingSymlinksInPath() {
            UserDefaults.standard.set(directory.path, forKey: WorkspaceDatabase.storageDirectoryDefaultsKey)
            return
        }

        autosaveTask?.cancel()
        autosaveTask = nil
        if saveState == .pending || saveState == .saving || draftDiffersFromStored { saveDraft() }

        let newDatabase = try migrateDatabase(to: directory)
        database = newDatabase
        attachments = AttachmentStore(databaseURL: newDatabase.databaseURL)
        UserDefaults.standard.set(directory.path, forKey: WorkspaceDatabase.storageDirectoryDefaultsKey)
        reloadWorkspace(selectFirst: false)
    }

    private func migrateDatabase(to directory: URL) throws -> WorkspaceDatabase {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("quiet-paper.sqlite")

        guard let oldURL = database.databaseURL else {
            // 启动时回退到内存数据库的情况：直接在新目录建立全新存储。
            return try WorkspaceDatabase(url: destination, seedIfEmpty: true)
        }

        try database.checkpoint()
        if fm.fileExists(atPath: destination.path) {
            let backup = directory.appendingPathComponent("quiet-paper.sqlite.backup-\(Int(Date().timeIntervalSince1970))")
            try fm.moveItem(at: destination, to: backup)
        }
        try fm.copyItem(at: oldURL, to: destination)

        let oldAttachments = attachments.rootURL.appendingPathComponent("attachments", isDirectory: true)
        let newAttachments = directory.appendingPathComponent("attachments", isDirectory: true)
        if fm.fileExists(atPath: oldAttachments.path) {
            if fm.fileExists(atPath: newAttachments.path) {
                let backup = directory.appendingPathComponent("attachments.backup-\(Int(Date().timeIntervalSince1970))")
                try fm.moveItem(at: newAttachments, to: backup)
            }
            try fm.copyItem(at: oldAttachments, to: newAttachments)
        }

        return try WorkspaceDatabase(url: destination, seedIfEmpty: false)
    }

    private func projectExportContents(
        projectID: UUID
    ) throws -> (rootNotes: [Note], modules: [ModuleExportSection]) {
        let projectModules = try database.fetchModules(projectID: projectID)
        let rootNotes = try projectModules
            .first(where: \NoteModule.isProjectRoot)
            .map { try database.fetchNotes(moduleID: $0.id) } ?? []
        let moduleSections = try projectModules
            .filter { !$0.isProjectRoot }
            .map { module in
                ModuleExportSection(
                    name: module.name,
                    notes: try database.fetchNotes(moduleID: module.id)
                )
            }
        return (rootNotes, moduleSections)
    }

    private var draftDiffersFromStored: Bool {
        guard let selectedNote else { return false }
        return selectedNote.title != draftTitle || selectedNote.contentMarkdown != draftContent
    }

    private enum SaveOutcome: Sendable {
        case success(Note)
        case failure(String)
    }

    private func draftSnapshot() -> (note: Note, sequence: UInt64)? {
        guard var item = selectedNote else { return nil }
        item.title = draftTitle.trimmingCharacters(in: .newlines)
        item.contentMarkdown = draftContent
        nextSaveSequence &+= 1
        return (item, nextSaveSequence)
    }

    private func saveDraft() {
        guard let snapshot = draftSnapshot() else { return }
        saveState = .saving
        let database = database
        let outcome = saveQueue.sync { persist(snapshot.note, database: database) }
        apply(outcome, snapshot: snapshot)
    }

    private func saveDraftInBackground() async {
        guard let snapshot = draftSnapshot() else { return }
        saveState = .saving
        let database = database
        let queue = saveQueue
        let outcome = await withCheckedContinuation { continuation in
            queue.async {
                do {
                    try database.save(note: snapshot.note)
                    continuation.resume(returning: SaveOutcome.success((try database.note(id: snapshot.note.id)) ?? snapshot.note))
                } catch {
                    continuation.resume(returning: SaveOutcome.failure(error.localizedDescription))
                }
            }
        }
        apply(outcome, snapshot: snapshot)
    }

    private func persist(_ item: Note, database: WorkspaceDatabase) -> SaveOutcome {
        do {
            try database.save(note: item)
            return .success((try database.note(id: item.id)) ?? item)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func apply(_ outcome: SaveOutcome, snapshot: (note: Note, sequence: UInt64)) {
        guard snapshot.sequence >= latestAppliedSaveSequence else { return }
        latestAppliedSaveSequence = snapshot.sequence

        switch outcome {
        case .success(let saved):
            if let index = notes.firstIndex(where: { $0.id == saved.id }) {
                notes[index] = saved
            }
            if let index = allNotes.firstIndex(where: { $0.id == saved.id }) {
                allNotes[index] = saved
            }
            if let module = modules.first(where: { $0.id == saved.moduleID }), module.isProjectRoot,
               var projectFiles = projectFilesByProjectID[module.projectID],
               let index = projectFiles.firstIndex(where: { $0.id == saved.id }) {
                projectFiles[index] = saved
                projectFilesByProjectID[module.projectID] = projectFiles
            }
            if !searchQuery.isEmpty { updateSearch() }
            guard selectedNoteID == saved.id else { return }
            if draftTitle.trimmingCharacters(in: .newlines) == snapshot.note.title,
               draftContent == snapshot.note.contentMarkdown {
                saveState = .saved(saved.updatedAt)
            } else {
                scheduleSave()
            }
        case .failure(let message):
            if selectedNoteID == snapshot.note.id {
                saveState = .failed(message)
            }
        }
    }

    private func reloadWorkspace(selectFirst: Bool) {
        do {
            projects = try database.fetchProjects()
            modules = try database.fetchAllModules()
            var projectFiles: [UUID: [Note]] = [:]
            for root in modules where root.isProjectRoot {
                projectFiles[root.projectID] = try database.fetchNotes(moduleID: root.id)
            }
            projectFilesByProjectID = projectFiles
            if selectFirst || selectedProjectID == nil || !projects.contains(where: { $0.id == selectedProjectID }) {
                selectedProjectID = projects.first?.id
            }
            if selectFirst || selectedModuleID == nil || !modules.contains(where: { $0.id == selectedModuleID }) {
                selectedModuleID = selectedProjectID.flatMap { initialModuleID(projectID: $0) }
            }
            reloadNotes(selectFirst: selectFirst)
        } catch { report(error) }
    }

    private func reloadNotes(selectFirst: Bool) {
        do {
            allNotes = try database.fetchAllNotes()
            notes = try selectedModuleID.map(database.fetchNotes(moduleID:)) ?? []
            noteFoldGroups = try selectedModuleID.map(database.fetchNoteFoldGroups(moduleID:)) ?? []
            if selectFirst || selectedNoteID == nil || !notes.contains(where: { $0.id == selectedNoteID }) {
                selectedNoteID = notes.first?.id
            }
            loadDraft()
            updateSearch()
        } catch { report(error) }
    }

    private func loadDraft() {
        isLoadingDraft = true
        defer { isLoadingDraft = false }
        if let item = selectedNote {
            draftTitle = item.title
            draftContent = item.kind == .markdown ? MarkdownImageSyntax.normalized(item.contentMarkdown) : item.contentMarkdown
            saveState = .saved(item.updatedAt)
        } else {
            draftTitle = ""
            draftContent = ""
            saveState = .idle
        }
    }

    private func report(_ error: Error) {
        startupError = error.localizedDescription
    }

    private func initialModuleID(projectID: UUID) -> UUID? {
        let candidates = modules(in: projectID)
        let roots = candidates.filter(\.isProjectRoot)
        let populated = candidates.first(where: { module in
            guard let notes = try? database.fetchNotes(moduleID: module.id) else { return false }
            return !notes.isEmpty
        })
        return roots.first(where: { module in
            guard let notes = try? database.fetchNotes(moduleID: module.id) else { return false }
            return !notes.isEmpty
        })?.id ?? populated?.id ?? roots.first?.id ?? candidates.first?.id
    }
}
