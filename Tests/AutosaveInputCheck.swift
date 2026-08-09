import Foundation

@main
@MainActor
struct AutosaveInputCheck {
    static func main() async throws {
        let database = try WorkspaceDatabase(inMemory: true, seedIfEmpty: true)
        let model = AppModel(database: database, autosaveInterval: .milliseconds(200))
        guard let noteID = model.selectedNoteID else {
            fatalError("自动保存测试缺少选中的笔记")
        }

        model.setDraftContent("第一段输入")
        try await Task.sleep(for: .milliseconds(120))
        let contentBeforeInterval = try database.note(id: noteID)?.contentMarkdown
        precondition(contentBeforeInterval != "第一段输入", "一分钟到期前不能频繁写入数据库")
        precondition(model.saveState == .pending, "编辑后应显示等待自动保存，而不是持续转圈")
        model.setDraftContent("第一段输入，继续输入且不能消失")
        try await Task.sleep(for: .milliseconds(180))

        let expected = "第一段输入，继续输入且不能消失"
        precondition(model.draftContent == expected, "自动保存不能覆盖编辑中的文字")
        let savedContent = try database.note(id: noteID)?.contentMarkdown
        precondition(savedContent == expected, "最新文字必须完整写入数据库")

        guard let project = model.createProject(named: "直属文件测试项目"),
              let file = model.createProjectFile(projectID: project.id, named: "直属文件") else {
            fatalError("无法创建项目直属文件")
        }
        let projectID = project.id
        precondition(model.projectFiles(in: projectID).contains(where: { $0.id == file.id }), "直属文件必须显示在项目树")
        precondition(model.selectedNoteID == file.id, "创建直属文件后必须自动选中")
        precondition(model.selectedModule?.isProjectRoot == true, "直属文件不能创建可见二级模块")
        precondition(!model.showsNoteList, "直属文件必须直接展示编辑区")
        guard let rootRequest = model.createProjectRequest(projectID: projectID, named: "直属请求") else {
            fatalError("无法创建项目直属请求")
        }
        precondition(rootRequest.kind == .request, "项目请求必须使用请求文件类型")
        precondition(model.selectedNoteID == rootRequest.id, "创建项目请求后必须自动选中")
        precondition(model.selectedModule?.isProjectRoot == true, "项目请求必须位于项目根目录")
        model.setDraftContent("快速点击期间保留的正文")
        model.selectProject(projectID)
        model.selectProject(projectID)
        precondition(model.draftContent == "快速点击期间保留的正文", "重复点击当前项目不能重新加载并覆盖草稿")
        precondition(model.saveState == .pending, "重复点击当前项目不能触发同步保存和刷新")
        model.forceSave()

        guard let module = model.createModule(projectID: projectID, named: "可选模块") else {
            fatalError("无法创建可选模块")
        }
        precondition(model.visibleModules(in: projectID).map(\.id) == [module.id], "项目树只显示用户创建的模块")
        precondition(model.showsNoteList, "选中模块时必须显示二级文件列表")
        guard let moduleRequest = model.createRequest(named: "模块请求") else {
            fatalError("无法创建模块请求")
        }
        precondition(moduleRequest.kind == .request, "模块请求必须使用请求文件类型")
        precondition(moduleRequest.moduleID == module.id, "模块请求必须创建在当前模块")
        precondition(model.selectedNoteID == moduleRequest.id, "创建模块请求后必须自动选中")
        let importedDraft = HTTPRequestDraft(method: .put, url: "https://import.example.test/items")
        guard let importedRequest = model.createRequest(named: "导入请求", draft: importedDraft) else {
            fatalError("无法创建导入请求")
        }
        precondition(HTTPRequestDraft.decode(importedRequest.contentMarkdown).method == .put, "导入请求必须保留解析后的配置")
        guard let socketRequest = model.createWebSocketRequest(named: "实时消息") else {
            fatalError("无法创建 WebSocket 请求")
        }
        precondition(socketRequest.kind == .websocket, "WebSocket 请求必须使用独立文件类型")
        precondition(socketRequest.moduleID == module.id, "WebSocket 请求必须创建在当前模块")
        precondition(model.selectedNoteID == socketRequest.id, "创建 WebSocket 请求后必须自动选中")
        guard let foldedNote = model.createNote(named: "待折叠笔记") else {
            fatalError("无法创建待折叠笔记")
        }
        model.quickFoldNotes([moduleRequest.id, foldedNote.id])
        guard let foldGroup = model.noteFoldGroups.first else {
            fatalError("AppModel 创建折叠组后必须立即刷新发布状态")
        }
        precondition(foldGroup.noteIDs == [moduleRequest.id, foldedNote.id], "AppModel 应保留折叠成员顺序")
        model.expandNoteFoldGroup(foldGroup.id)
        precondition(model.noteFoldGroups.isEmpty, "AppModel 展开折叠组后必须立即刷新发布状态")
        let storedFoldGroups = try database.fetchNoteFoldGroups(moduleID: module.id)
        precondition(storedFoldGroups.isEmpty, "展开状态必须同步到数据库")

        guard let firstDeleted = model.createNote(named: "批量删除一"),
              let secondDeleted = model.createNote(named: "批量删除二") else {
            fatalError("无法创建批量删除内存测试文件")
        }
        precondition(model.deleteNotes([firstDeleted.id, secondDeleted.id]), "AppModel 批量删除应返回成功")
        precondition(!model.notes.contains(where: { $0.id == firstDeleted.id || $0.id == secondDeleted.id }), "AppModel 批量删除后必须立即刷新文件列表")
        let deletedIDs = Set(model.deletedItems().filter { $0.kind == .note }.map(\.id))
        precondition(deletedIDs.isSuperset(of: [firstDeleted.id, secondDeleted.id]), "AppModel 批量删除必须把全部文件移到最近删除")

        guard let navigationTarget = model.createModule(projectID: projectID, named: "即时导航目标") else {
            fatalError("无法创建即时导航测试模块")
        }
        model.selectModule(module.id)
        model.selectNote(moduleRequest.id)
        let navigationDraft = "切换菜单时必须后台保存的草稿"
        model.setDraftContent(navigationDraft)
        model.selectModule(navigationTarget.id)
        precondition(model.selectedModuleID == navigationTarget.id, "有待保存草稿时，菜单选中状态也必须立即切换")
        precondition(model.selectedNoteID == nil, "切换到空模块后不应残留旧文件选中态")
        model.forceSave()
        let savedNavigationDraft = try database.note(id: moduleRequest.id)?.contentMarkdown
        precondition(savedNavigationDraft == navigationDraft, "后台导航保存必须写回切换前的文件")
        model.selectModule(module.id)
        model.selectNote(moduleRequest.id)
        precondition(model.draftContent == navigationDraft, "快速切回旧文件时不能显示保存前的过期正文")

        model.setAIUnreadable(kind: .module, id: module.id, value: true)
        precondition(model.createConnection(moduleID: module.id) == nil, "AI 不可读模块不能新建数据库连接")
        precondition(
            model.startupError == AIReadProtection.featureUnavailableMessage,
            "阻止新建连接时必须给出明确提示"
        )
        model.startupError = nil
        model.setAIUnreadable(kind: .module, id: module.id, value: false)
        precondition(model.createConnection(moduleID: module.id) != nil, "取消模块标记后应恢复新建连接功能")

        model.setAIUnreadable(kind: .project, id: projectID, value: true)
        precondition(model.createProjectConnection(projectID: projectID) == nil, "AI 不可读项目不能新建根目录连接")
        print("Quiet Paper autosave and project file checks passed: 34/34")
    }
}
