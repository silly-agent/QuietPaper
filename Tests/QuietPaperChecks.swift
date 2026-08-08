import Foundation

@main
struct QuietPaperChecks {
    static func main() async throws {
        try hierarchyPersistsAndSearchFindsMarkdownBody()
        try documentKindsPersistWithoutChangingMarkdownDefaults()
        try connectionFilesRoundTripAndRemainSearchable()
        try sqliteShellEscapedPathsNormalize()
        try onlyMarkdownFilesReceiveVectorChunks()
        try chineseBrandQueryFindsEnglishEmailHeading()
        try queryPolicyAppliesDefaultLimit()
        try dangerousCommandsRequireConfirmation()
        try redisPolicyDistinguishesCreateAndOverwrite()
        try emptyQueryResultIsNotReportedAsMutationSuccess()
        try requestDraftRoundTripsAndBuildsURLRequest()
        try getJSONBodyBecomesQueryParameters()
        try requestBuilderRejectsInvalidJSON()
        try responseTextFormatsJSONAndKeepsPlainText()
        try await downloadedResponseLoadsFromTemporaryFile()
        try await oversizedDownloadedResponseHasClearError()
        try savedResponseRoundTripsAndLegacyDraftStillDecodes()
        try postMethodAddsEnabledJSONHeaderWithoutDuplicates()
        try responseFormattingIncludesArraysAndScalars()
        try projectFilesRemainOutsideVisibleModules()
        try saveKeepsMarkdownAsSourceOfTruth()
        try noteFoldGroupsPersistAndCleanUp()
        try softDeleteNoteRemovesOnlyItsVectorChunks()
        try softDeleteAndRestoreModuleCascadesToNotes()
        try moduleMarkdownExportSupportsMergedAndSeparateFiles()
        try projectMarkdownExportPreservesHierarchy()
        noteRangeSelectionIsInclusiveAndCancelable()
        parsesContinuousDocumentBlocks()
        parsesMarkdownTables()
        unclosedFencePreservesCode()
        plainTextRemovesMarkdownFurnitureButKeepsCode()
        normalizesConcatenatedAndRepeatedImages()
        formatsPlainAndFencedJSON()
        print("Quiet Paper checks passed: 33/33")
    }

    static func noteRangeSelectionIsInclusiveAndCancelable() {
        let ids = [UUID(), UUID(), UUID(), UUID(), UUID()]
        var selection = NoteRangeSelection()

        selection.select(ids[1], orderedIDs: ids, extendingRange: false)
        precondition(selection.selectedIDs.isEmpty, "普通单击只设置锚点，不应留下多选高亮")
        precondition(selection.anchorID == ids[1], "普通单击应更新 Shift 选择锚点")

        selection.select(ids[3], orderedIDs: ids, extendingRange: true)
        precondition(selection.selectedIDs == Set(ids[1...3]), "正向 Shift 选择必须包含锚点和目标")

        selection.select(ids[0], orderedIDs: ids, extendingRange: false)
        precondition(selection.selectedIDs.isEmpty, "多选后普通单击必须立即取消范围")
        selection.select(ids[3], orderedIDs: ids, extendingRange: false)
        selection.select(ids[1], orderedIDs: ids, extendingRange: true)
        precondition(selection.selectedIDs == Set(ids[1...3]), "反向 Shift 选择必须与正向范围一致")

        selection.reset()
        precondition(selection.selectedIDs.isEmpty && selection.anchorID == nil, "Esc 重置必须清空范围与锚点")
        selection.select(ids[2], orderedIDs: ids, extendingRange: true, fallbackAnchorID: ids[0])
        precondition(selection.selectedIDs == Set(ids[0...2]), "首次 Shift 点击应使用当前文件作为后备锚点")
    }

    static func noteFoldGroupsPersistAndCleanUp() throws {
        let database = try WorkspaceDatabase(inMemory: true)
        let project = try database.createProject(name: "折叠测试")
        let source = try database.createModule(projectID: project.id, name: "来源")
        let destination = try database.createModule(projectID: project.id, name: "目标")
        let first = try database.createNote(moduleID: source.id, title: "1")
        let second = try database.createNote(moduleID: source.id, title: "2")
        let third = try database.createNote(moduleID: source.id, title: "3")
        let fourth = try database.createNote(moduleID: source.id, title: "4")
        let fifth = try database.createNote(moduleID: source.id, title: "5")

        let expandedGroup = try database.createNoteFoldGroup(
            moduleID: source.id,
            noteIDs: [first.id, second.id, third.id]
        )
        let fetchedExpandedGroup = try database.fetchNoteFoldGroups(moduleID: source.id).first
        try expect(fetchedExpandedGroup?.id == expandedGroup.id, "折叠组应保存到数据库")
        try expect(fetchedExpandedGroup?.noteIDs == expandedGroup.noteIDs, "折叠组成员顺序应保存到数据库")
        try database.deleteNoteFoldGroup(id: expandedGroup.id)
        try expect(try database.fetchNoteFoldGroups(moduleID: source.id).isEmpty, "展开后应删除折叠组")

        _ = try database.createNoteFoldGroup(moduleID: source.id, noteIDs: [first.id, second.id, third.id])
        try database.move(noteID: third.id, to: destination.id)
        try expect(
            try database.fetchNoteFoldGroups(moduleID: source.id).first?.noteIDs == [first.id, second.id],
            "移动文件后应从原折叠组移除，两个成员的组继续保留"
        )
        try database.move(noteID: second.id, to: destination.id)
        try expect(try database.fetchNoteFoldGroups(moduleID: source.id).isEmpty, "折叠组不足两个成员时应自动解散")

        _ = try database.createNoteFoldGroup(moduleID: source.id, noteIDs: [fourth.id, fifth.id])
        try database.softDelete(kind: .note, id: fourth.id)
        try expect(try database.fetchNoteFoldGroups(moduleID: source.id).isEmpty, "单个文件移入最近删除后应退出并解散折叠组")

        let sixth = try database.createNote(moduleID: source.id, title: "6")
        let seventh = try database.createNote(moduleID: source.id, title: "7")
        let restoredGroup = try database.createNoteFoldGroup(moduleID: source.id, noteIDs: [sixth.id, seventh.id])
        try database.softDelete(kind: .module, id: source.id)
        try database.restore(kind: .module, id: source.id)
        let fetchedRestoredGroup = try database.fetchNoteFoldGroups(moduleID: source.id).first
        try expect(fetchedRestoredGroup?.id == restoredGroup.id, "模块恢复后应保留原折叠组")
        try expect(fetchedRestoredGroup?.noteIDs == restoredGroup.noteIDs, "模块恢复后应保留原折叠成员")
    }

    static func moduleMarkdownExportSupportsMergedAndSeparateFiles() throws {
        let database = try WorkspaceDatabase(inMemory: true)
        let project = try database.createProject(name: "导出项目")
        let module = try database.createModule(projectID: project.id, name: "接口/文档")
        let markdown = try database.createNote(moduleID: module.id, title: "说明.md", content: "正文内容")
        let request = try database.createNote(
            moduleID: module.id,
            title: "说明:请求",
            content: try HTTPRequestDraft(url: "https://example.test").encoded(),
            kind: .request
        )
        let notes = [markdown, request]

        let merged = ModuleMarkdownExporter.mergedMarkdown(moduleName: module.name, notes: notes)
        try expect(merged.hasPrefix("# 接口/文档\n"), "合并导出应使用模块名作为标题")
        try expect(merged.contains("## 说明.md\n\n正文内容"), "合并导出应保留 Markdown 原文")
        try expect(merged.contains("> 文件类型：HTTP 请求\n\n```json"), "请求文件应转换成可读 Markdown 代码块")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuietPaper-Export-Check-\(UUID().uuidString)", isDirectory: true)
        let files = root.appendingPathComponent("files", isDirectory: true)
        let archive = root.appendingPathComponent("接口文档.zip")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try ModuleMarkdownExporter.writeSeparateFiles(notes: notes, to: files)
        let names = try FileManager.default.contentsOfDirectory(atPath: files.path)
        try expect(Set(names) == ["说明.md", "说明-请求.md"], "分开导出应清理文件名并避免重复扩展名")

        try ModuleMarkdownExporter.writeArchive(moduleName: module.name, notes: notes, to: archive)
        let attributes = try FileManager.default.attributesOfItem(atPath: archive.path)
        try expect((attributes[.size] as? NSNumber)?.intValue ?? 0 > 0, "模块分开导出应生成非空 ZIP")
        try ModuleMarkdownExporter.writeArchive(moduleName: module.name, notes: notes, to: archive)
        try expect(FileManager.default.fileExists(atPath: archive.path), "确认覆盖后应能替换已有 ZIP")
    }

    static func projectMarkdownExportPreservesHierarchy() throws {
        let database = try WorkspaceDatabase(inMemory: true)
        let project = try database.createProject(name: "完整项目")
        let rootModule = try database.projectRootModule(projectID: project.id)
        let rootNote = try database.createNote(moduleID: rootModule.id, title: "项目说明", content: "根目录正文")
        let apiModule = try database.createModule(projectID: project.id, name: "接口/模块")
        let apiNote = try database.createNote(moduleID: apiModule.id, title: "获取用户", content: "接口正文")
        let emptyModule = try database.createModule(projectID: project.id, name: "空模块")
        let sections = [
            ModuleExportSection(name: apiModule.name, notes: [apiNote]),
            ModuleExportSection(name: emptyModule.name, notes: [])
        ]

        let merged = ModuleMarkdownExporter.mergedProjectMarkdown(
            projectName: project.name,
            rootNotes: [rootNote],
            modules: sections
        )
        try expect(merged.hasPrefix("# 完整项目\n\n## 项目说明\n\n根目录正文"), "项目合并导出应先包含根目录文件")
        try expect(merged.contains("## 接口/模块\n\n### 获取用户\n\n接口正文"), "项目合并导出应保留模块与文件层级")
        try expect(merged.contains("## 空模块"), "项目合并导出应保留空模块")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuietPaper-Project-Export-Check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try ModuleMarkdownExporter.writeProjectFiles(rootNotes: [rootNote], modules: sections, to: root)
        try expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("项目说明.md").path), "项目 ZIP 顶层应包含根目录文件")
        try expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("接口-模块/获取用户.md").path), "项目 ZIP 应按模块建立文件夹")
        var isDirectory: ObjCBool = false
        try expect(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("空模块").path, isDirectory: &isDirectory) && isDirectory.boolValue,
            "项目 ZIP 应保留空模块文件夹"
        )
    }

    static func connectionFilesRoundTripAndRemainSearchable() throws {
        let database = try WorkspaceDatabase(inMemory: true)
        let project = try database.createProject(name: "数据库项目")
        let module = try database.createModule(projectID: project.id, name: "测试连接")
        var file = DatabaseConnectionFile()
        file.kind = .postgresql
        file.settings = DatabaseConnectionSettings(host: "127.0.0.1", port: 5432, username: "tester", password: "local-password", database: "sandbox")
        file.messages = [.init(role: .user, text: "查看用户表", createdAt: Date(timeIntervalSince1970: 1_700_000_000))]
        let encoded = try file.encoded()
        let decoded = DatabaseConnectionFile.decode(encoded)
        try expect(decoded == file, "连接文件配置与对话往返编码")
        let note = try database.createNote(moduleID: module.id, title: "本地 PG", content: encoded, kind: .connection)
        try expect(try database.fetchNotes(moduleID: module.id).first?.kind == .connection, "连接文件类型持久化")
        try expect(try database.search(query: "sandbox", scope: .all, projectID: nil, moduleID: nil).first?.noteID == note.id, "连接数据库名可搜索")
    }

    static func sqliteShellEscapedPathsNormalize() throws {
        let escaped = "/Users/test/Library/Application\\ Support/QuietPaper/quiet-paper.sqlite"
        let normalized = DatabaseConnectionSettings.normalizedSQLitePath(escaped)
        try expect(
            normalized == "/Users/test/Library/Application Support/QuietPaper/quiet-paper.sqlite",
            "SQLite 手动路径应兼容终端转义空格"
        )
    }

    static func onlyMarkdownFilesReceiveVectorChunks() throws {
        let database = try WorkspaceDatabase(inMemory: true)
        let project = try database.createProject(name: "向量范围")
        let module = try database.createModule(projectID: project.id, name: "测试")
        let markdown = try database.createNote(moduleID: module.id, title: "普通笔记", content: "只有普通笔记需要生成本地向量分块", kind: .markdown)
        _ = try database.createNote(moduleID: module.id, title: "接口请求", content: try HTTPRequestDraft(url: "https://example.test").encoded(), kind: .request)
        var connection = DatabaseConnectionFile()
        connection.kind = .sqlite
        connection.settings.sqlitePath = "/tmp/example.sqlite"
        _ = try database.createNote(moduleID: module.id, title: "数据库连接", content: try connection.encoded(), kind: .connection)

        let chunks = try database.fetchAllChunks(scope: .all, projectID: nil, moduleID: nil)
        try expect(!chunks.isEmpty, "Markdown 文件应生成向量分块")
        try expect(Set(chunks.map(\.noteID)) == [markdown.id], "请求与连接文件不能生成向量分块")
    }

    static func chineseBrandQueryFindsEnglishEmailHeading() throws {
        let database = try WorkspaceDatabase(inMemory: true)
        let project = try database.createProject(name: "账号")
        let module = try database.createModule(projectID: project.id, name: "邮箱")
        let note = try database.createNote(
            moduleID: module.id,
            title: "外网账号",
            content: "## Facebook\n\n892774306@qq.com\n\n## Google\n\nwenjie056053@gmail.com",
            kind: .markdown
        )

        let terms = RetrievalQueryTerms.make(from: "我的谷歌邮箱")
        try expect(terms.contains("Google") && terms.contains("Gmail"), "中文品牌名应展开为英文检索词")
        let matches = try terms.flatMap {
            try database.search(query: $0, scope: .all, projectID: nil, moduleID: nil)
        }
        try expect(matches.contains(where: { $0.noteID == note.id }), "谷歌邮箱问题应召回包含 Google/Gmail 的笔记")
    }

    static func queryPolicyAppliesDefaultLimit() throws {
        try expect(
            DatabaseCommandPolicy.decision(for: "SELECT * FROM users", kind: .postgresql) == .execute("SELECT * FROM users LIMIT 20"),
            "未指定数量的查询默认 LIMIT 20"
        )
        try expect(
            DatabaseCommandPolicy.decision(for: "SELECT * FROM users LIMIT 5", kind: .mysql) == .execute("SELECT * FROM users LIMIT 5"),
            "保留用户明确指定的 LIMIT"
        )
        try expect(
            DatabaseCommandPolicy.decision(for: "SELECT COUNT(*) FROM users", kind: .sqlite) == .execute("SELECT COUNT(*) FROM users"),
            "聚合查询不追加 LIMIT"
        )
    }

    static func dangerousCommandsRequireConfirmation() throws {
        try expect(DatabaseCommandPolicy.decision(for: "INSERT INTO users(name) VALUES ('A')", kind: .mysql) == .execute("INSERT INTO users(name) VALUES ('A')"), "INSERT 无需确认")
        try expect(DatabaseCommandPolicy.decision(for: "CREATE TABLE demo(id INT)", kind: .postgresql) == .execute("CREATE TABLE demo(id INT)"), "CREATE 无需确认")
        if case .confirm = DatabaseCommandPolicy.decision(for: "UPDATE users SET active = 0", kind: .mysql) {} else { throw CheckError.failed("UPDATE 必须确认") }
        if case .confirm = DatabaseCommandPolicy.decision(for: "DELETE FROM users", kind: .sqlite) {} else { throw CheckError.failed("DELETE 必须确认") }
        if case .confirm = DatabaseCommandPolicy.decision(for: "TRUNCATE users", kind: .postgresql) {} else { throw CheckError.failed("TRUNCATE 必须确认") }
        if case .confirm = DatabaseCommandPolicy.decision(for: "WITH selected AS (SELECT id FROM users) UPDATE users SET active = 0", kind: .postgresql) {} else { throw CheckError.failed("CTE 中的 UPDATE 必须确认") }
        if case .reject = DatabaseCommandPolicy.decision(for: "SELECT 1; DELETE FROM users", kind: .mysql) {} else { throw CheckError.failed("多语句必须拒绝") }
    }

    static func redisPolicyDistinguishesCreateAndOverwrite() throws {
        try expect(DatabaseCommandPolicy.decision(for: "SET new_key value", kind: .redis, redisKeyExists: false) == .execute("SET new_key value"), "Redis 新建键无需确认")
        if case .confirm = DatabaseCommandPolicy.decision(for: "SET old_key value", kind: .redis, redisKeyExists: true) {} else { throw CheckError.failed("Redis 覆盖已有键必须确认") }
        if case .confirm = DatabaseCommandPolicy.decision(for: "DEL old_key", kind: .redis) {} else { throw CheckError.failed("Redis 删除键必须确认") }
    }

    static func emptyQueryResultIsNotReportedAsMutationSuccess() throws {
        let result = DatabaseQueryResult(
            columns: ["name"],
            rows: [],
            affectedRows: nil,
            duration: 0.01,
            message: "查询完成，没有符合条件的数据"
        )
        try expect(result.compactToolDescription.contains("返回 0 行"), "空查询必须明确返回 0 行")
        try expect(!result.compactToolDescription.contains("执行成功"), "空查询不能伪装成修改命令执行成功")
    }

    static func requestDraftRoundTripsAndBuildsURLRequest() throws {
        let draft = HTTPRequestDraft(
            method: .post,
            url: "https://example.test/users?existing=yes",
            queryItems: [
                HTTPKeyValue(key: "关键词", value: "安静 笔记"),
                HTTPKeyValue(isEnabled: false, key: "ignored", value: "value"),
                HTTPKeyValue(key: "", value: "empty")
            ],
            headers: [
                HTTPKeyValue(key: "X-Client", value: "QuietPaper"),
                HTTPKeyValue(isEnabled: false, key: "X-Ignored", value: "no")
            ],
            bodyMode: .json,
            body: #"{"name":"测试"}"#
        )
        let encoded = try draft.encoded()
        let decoded = HTTPRequestDraft.decode(encoded)
        try expect(decoded == draft, "请求草稿往返编码")

        let request = try HTTPRequestBuilder.build(decoded)
        try expect(request.httpMethod == "POST", "请求方法")
        try expect(request.url?.absoluteString.contains("existing=yes") == true, "保留 URL 原有参数")
        try expect(request.url?.absoluteString.contains("%E5%85%B3%E9%94%AE%E8%AF%8D") == true, "Query 参数编码")
        try expect(request.url?.absoluteString.contains("ignored") == false, "忽略禁用参数")
        try expect(request.value(forHTTPHeaderField: "X-Client") == "QuietPaper", "请求 Header")
        try expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json", "JSON 自动内容类型")
        try expect(String(data: request.httpBody ?? Data(), encoding: .utf8) == draft.body, "JSON 正文编码")
    }

    static func requestBuilderRejectsInvalidJSON() throws {
        let draft = HTTPRequestDraft(method: .post, url: "https://example.test", bodyMode: .json, body: "{invalid")
        do {
            _ = try HTTPRequestBuilder.build(draft)
            throw CheckError.failed("无效 JSON 必须阻止发送")
        } catch let error as HTTPRequestError {
            try expect(error == .invalidJSON, "无效 JSON 错误类型")
        }
    }

    static func getJSONBodyBecomesQueryParameters() throws {
        let draft = HTTPRequestDraft(
            method: .get,
            url: "https://business-api.example/report",
            queryItems: [HTTPKeyValue(key: "page", value: "2")],
            bodyMode: .json,
            body: #"{"advertiser_ids":["7656713748595228690"],"dimensions":["adgroup_id","stat_time_hour"],"page":1,"page_size":1}"#
        )

        let request = try HTTPRequestBuilder.build(draft)
        let requestURL = try require(request.url, "GET 请求 URL")
        let items = try require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems, "GET 查询参数")
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        try expect(request.httpBody == nil, "GET 顶层 JSON 对象不应作为请求体发送")
        try expect(values["advertiser_ids"] == #"["7656713748595228690"]"#, "GET 数组参数应编码为紧凑 JSON")
        try expect(values["dimensions"] == #"["adgroup_id","stat_time_hour"]"#, "GET dimensions 应进入查询参数")
        try expect(values["page"] == "2", "参数面板中的显式值应优先于同名 JSON Body 字段")
        try expect(values["page_size"] == "1", "GET 数字参数应进入查询参数")
    }

    static func responseTextFormatsJSONAndKeepsPlainText() throws {
        let formatted = HTTPResponseSnapshot.displayText(for: Data(#"{"ok":true,"count":2}"#.utf8))
        try expect(formatted.contains("\n") && formatted.contains("\"ok\": true"), "JSON 响应自动格式化")
        try expect(HTTPResponseSnapshot.displayText(for: Data("plain response".utf8)) == "plain response", "纯文本响应保持原样")
        try expect(HTTPResponseSnapshot.displayText(for: Data()).isEmpty, "空响应保持为空")
    }

    static func downloadedResponseLoadsFromTemporaryFile() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("quiet-paper-http-\(UUID().uuidString).json")
        try Data(#"{"ok":true,"rows":[1,2,3]}"#.utf8).write(to: fileURL, options: .atomic)
        let response = try require(
            HTTPURLResponse(
                url: URL(string: "https://example.test/report")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ),
            "下载响应"
        )
        let client = HTTPRequestClient(maximumResponseBytes: 1_024) { _ in (fileURL, response) }

        let snapshot = try await client.send(URLRequest(url: response.url!))

        try expect(snapshot.statusCode == 200, "流式下载应保留 HTTP 状态码")
        try expect(snapshot.body.contains("\"ok\": true"), "流式下载的 JSON 响应应正常格式化")
        try expect(snapshot.size > 0, "流式下载应报告响应大小")
    }

    static func oversizedDownloadedResponseHasClearError() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("quiet-paper-http-large-\(UUID().uuidString).txt")
        try Data(repeating: 65, count: 32).write(to: fileURL, options: .atomic)
        let response = try require(
            HTTPURLResponse(
                url: URL(string: "https://example.test/large")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            ),
            "超大响应"
        )
        let client = HTTPRequestClient(maximumResponseBytes: 16) { _ in (fileURL, response) }

        do {
            _ = try await client.send(URLRequest(url: response.url!))
            throw CheckError.failed("超过展示上限的响应必须被拦截")
        } catch let error as HTTPRequestError {
            try expect(error == .responseTooLarge(maximumBytes: 16), "超大响应应返回明确的应用错误")
            try expect(
                error.localizedDescription.contains("缩小查询范围") || error.localizedDescription.contains("分页"),
                "超大响应错误应给出处理建议"
            )
        }
    }

    static func savedResponseRoundTripsAndLegacyDraftStillDecodes() throws {
        let legacy = #"{"version":1,"method":"GET","url":"https://legacy.test","queryItems":[],"headers":[],"bodyMode":"none","body":""}"#
        let legacyDraft = HTTPRequestDraft.decode(legacy)
        try expect(legacyDraft.url == "https://legacy.test", "版本 1 请求保持兼容")
        try expect(legacyDraft.savedResponse == nil, "旧请求默认没有保存响应")

        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = HTTPResponseSnapshot(
            url: URL(string: "https://example.test/final"),
            statusCode: 201,
            headers: [HTTPResponseHeader(name: "Content-Type", value: "application/json")],
            body: "{\n  \"secret-response\" : true\n}",
            duration: 0.25,
            size: 27
        )
        let saved = snapshot.saved(at: savedAt)
        let draft = HTTPRequestDraft(url: "https://example.test", savedResponse: saved)
        let decoded = HTTPRequestDraft.decode(try draft.encoded())
        try expect(decoded.savedResponse == saved, "保存响应随请求往返持久化")
        try expect(decoded.savedResponse?.snapshot.statusCode == 201, "保存响应可恢复为展示快照")
        try expect(
            decoded.savedResponse?.snapshot.body.contains("\"secret-response\": true") == true,
            "旧格式保存的 JSON 响应在展示时应统一漂亮排版"
        )
        try expect(!decoded.searchableText.contains("secret-response"), "保存响应不进入请求全文搜索")
    }

    static func postMethodAddsEnabledJSONHeaderWithoutDuplicates() throws {
        let post = HTTPRequestDraft(method: .post)
        let automatic = post.headers.filter { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }
        try expect(automatic.count == 1, "POST 默认添加 Content-Type")
        try expect(automatic.first?.isEnabled == true && automatic.first?.value == "application/json", "POST 默认启用 JSON Header")

        var changed = HTTPRequestDraft()
        changed.setMethod(.post)
        try expect(changed.headers.count == 1, "切换 POST 时添加默认 Header")
        changed.setMethod(.post)
        try expect(changed.headers.count == 1, "重复选择 POST 不重复添加 Header")

        let existing = HTTPRequestDraft(
            method: .post,
            headers: [HTTPKeyValue(isEnabled: false, key: "content-type", value: "custom/type")]
        )
        try expect(existing.headers.count == 1 && existing.headers.first?.value == "custom/type", "已有 Header 不覆盖且不重复")
    }

    static func responseFormattingIncludesArraysAndScalars() throws {
        let array = HTTPResponseSnapshot.displayText(for: Data(#"[{"b":1,"a":2}]"#.utf8))
        try expect(array.contains("\n") && array.contains("\"a\": 2"), "JSON 数组响应默认格式化")
        try expect(HTTPResponseSnapshot.displayText(for: Data("true".utf8)) == "true", "JSON 标量响应默认格式化")
    }

    static func documentKindsPersistWithoutChangingMarkdownDefaults() throws {
        let database = try WorkspaceDatabase(inMemory: true)
        let project = try database.createProject(name: "请求集合")
        let module = try database.createModule(projectID: project.id, name: "用户接口")
        let note = try database.createNote(moduleID: module.id, title: "接口说明")
        let requestContent = try HTTPRequestDraft(url: "https://example.test/users").encoded()
        let request = try database.createNote(
            moduleID: module.id,
            title: "获取用户",
            content: requestContent,
            kind: .request
        )

        let loaded = try database.fetchNotes(moduleID: module.id)
        try expect(loaded.first(where: { $0.id == note.id })?.kind == .markdown, "旧文件默认保持 Markdown 类型")
        try expect(loaded.first(where: { $0.id == request.id })?.kind == .request, "请求文件类型持久化")
        try expect(try database.search(query: "example.test", scope: .all, projectID: nil, moduleID: nil).first?.noteID == request.id, "请求 URL 可搜索")
    }

    static func hierarchyPersistsAndSearchFindsMarkdownBody() throws {
        let database = try WorkspaceDatabase(inMemory: true)
        let project = try database.createProject(name: "接口平台")
        let module = try database.createModule(projectID: project.id, name: "飞书同步")
        let note = try database.createNote(
            moduleID: module.id,
            title: "分页读取记录",
            content: "## 请求\n\n```bash\ncurl https://example.test/records?page_size=100\n```"
        )

        try expect(database.fetchProjects().map(\.name) == ["接口平台"], "项目持久化")
        try expect(database.fetchModules(projectID: project.id).map(\.name) == ["飞书同步"], "模块持久化")
        try expect(database.fetchNotes(moduleID: module.id).map(\.id) == [note.id], "笔记持久化")

        let results = try database.search(query: "page_size", scope: .all, projectID: nil, moduleID: nil)
        try expect(results.first?.noteID == note.id, "正文搜索")
        try expect(results.first?.path == "接口平台 / 飞书同步 / 分页读取记录", "搜索路径")
    }

    static func saveKeepsMarkdownAsSourceOfTruth() throws {
        let database = try WorkspaceDatabase(inMemory: true)
        let project = try database.createProject(name: "项目")
        let module = try database.createModule(projectID: project.id, name: "模块")
        var note = try database.createNote(moduleID: module.id)
        note.title = "JSON 示例"
        note.contentMarkdown = "```json\n{\"字段\": true}\n```"
        try database.save(note: note)

        let loaded = try require(database.note(id: note.id), "读取保存后的笔记")
        try expect(loaded.title == note.title, "标题保存")
        try expect(loaded.contentMarkdown == note.contentMarkdown, "Markdown 原文保存")
        try expect(database.search(query: "字段", scope: .module, projectID: project.id, moduleID: module.id).count == 1, "中文搜索")
    }

    static func projectFilesRemainOutsideVisibleModules() throws {
        let database = try WorkspaceDatabase(inMemory: true)
        let project = try database.createProject(name: "项目")
        let root = try database.projectRootModule(projectID: project.id)
        let note = try database.createNote(moduleID: root.id, title: "根目录文件", content: "无需模块")

        try expect(root.isProjectRoot, "项目根目录标记")
        try expect(try database.fetchModules(projectID: project.id).filter { !$0.isProjectRoot }.isEmpty, "项目文件不显示为模块")
        try expect(try database.fetchNotes(moduleID: root.id).map(\.id) == [note.id], "项目根目录文件持久化")
        try expect(try database.search(query: "无需模块", scope: .all, projectID: nil, moduleID: nil).first?.path == "项目 / 根目录文件", "项目文件搜索路径")
    }

    static func softDeleteAndRestoreModuleCascadesToNotes() throws {
        let database = try WorkspaceDatabase(inMemory: true)
        let project = try database.createProject(name: "项目")
        let module = try database.createModule(projectID: project.id, name: "模块")
        _ = try database.createNote(moduleID: module.id, title: "笔记", content: "可恢复内容")
        try expect(try database.chunkCount() > 0, "模块中的 Markdown 文件应生成向量数据")

        try database.softDelete(kind: .module, id: module.id)
        try expect(database.fetchModules(projectID: project.id).isEmpty, "模块软删除")
        try expect(database.search(query: "可恢复", scope: .all, projectID: nil, moduleID: nil).isEmpty, "删除内容不参与搜索")
        try expect(try database.chunkCount() == 0, "删除模块必须同步删除其下全部向量数据")

        try database.restore(kind: .module, id: module.id)
        try expect(database.fetchModules(projectID: project.id).count == 1, "模块恢复")
        try expect(database.fetchNotes(moduleID: module.id).count == 1, "下级笔记恢复")
        try expect(database.search(query: "可恢复", scope: .all, projectID: nil, moduleID: nil).count == 1, "恢复后重建索引")
        try expect(try database.chunkCount() > 0, "恢复模块后应重新生成 Markdown 向量数据")
    }

    static func softDeleteNoteRemovesOnlyItsVectorChunks() throws {
        let database = try WorkspaceDatabase(inMemory: true)
        let project = try database.createProject(name: "向量清理")
        let module = try database.createModule(projectID: project.id, name: "文件")
        let deletedNote = try database.createNote(
            moduleID: module.id,
            title: "待删除文件",
            content: "这是需要随文件删除的向量化正文内容"
        )
        let deletedNoteChunkCount = try database.chunkCount()
        try expect(deletedNoteChunkCount > 0, "待删除文件应先生成向量数据")

        let keptNote = try database.createNote(
            moduleID: module.id,
            title: "保留文件",
            content: "这是不能被其他文件删除操作影响的正文内容"
        )
        let totalChunkCount = try database.chunkCount()
        let keptNoteChunkCount = totalChunkCount - deletedNoteChunkCount
        try expect(keptNoteChunkCount > 0, "保留文件应生成独立向量数据")

        try database.softDelete(kind: .note, id: deletedNote.id)

        try expect(try database.chunkCount() == keptNoteChunkCount, "删除文件必须只清理该文件的向量数据")
        let remainingNoteIDs = Set(try database.fetchAllChunks(scope: .all, projectID: nil, moduleID: nil).map(\.noteID))
        try expect(remainingNoteIDs == [keptNote.id], "删除文件不能误删同模块其他文件的向量数据")
    }

    static func parsesContinuousDocumentBlocks() {
        let markdown = "# 标题\n\n一段说明。\n\n- 第一项\n- 第二项\n\n```json\n{\"ok\": true}\n```"
        precondition(MarkdownParser.parse(markdown) == [
            .heading(level: 1, text: "标题"),
            .paragraph("一段说明。"),
            .bullets(["第一项", "第二项"]),
            .code(language: "json", content: "{\"ok\": true}")
        ], "Markdown 连续文档解析失败")
    }

    static func parsesMarkdownTables() {
        let markdown = "前文\n\n| 姓名 | 状态 |\n| --- | --- |\n| 张三 | 完成 |\n| 李四 | 进行中 |\n\n后文"
        precondition(MarkdownParser.parse(markdown) == [
            .paragraph("前文"),
            .table(MarkdownTable(headers: ["姓名", "状态"], rows: [
                ["张三", "完成"],
                ["李四", "进行中"]
            ])),
            .paragraph("后文")
        ], "Markdown 表格必须解析为表格块")
    }

    static func unclosedFencePreservesCode() {
        precondition(
            MarkdownParser.parse("```sql\nSELECT * FROM notes;") == [.code(language: "sql", content: "SELECT * FROM notes;")],
            "未闭合代码围栏应保留原文"
        )
    }

    static func plainTextRemovesMarkdownFurnitureButKeepsCode() {
        let output = MarkdownPlainText.extract(from: "## 请求\n\n```bash\ncurl example.test\n```")
        precondition(output.contains("请求") && output.contains("curl example.test") && !output.contains("```"), "Markdown 纯文本提取失败")
    }

    static func normalizesConcatenatedAndRepeatedImages() {
        let first = "![图片](attachments/first.png)"
        let second = "![图片](attachments/second.png)"
        let damaged = first + first + first + second + "\n"
        let normalized = MarkdownImageSyntax.normalized(damaged)
        precondition(normalized == first + "\n" + second + "\n", "粘连图片标记应分行并去除连续重复项")
        precondition(
            MarkdownParser.parse(damaged) == [
                .image(alt: "图片", path: "attachments/first.png"),
                .image(alt: "图片", path: "attachments/second.png")
            ],
            "损坏的多图 Markdown 仍应正确预览"
        )
    }

    static func formatsPlainAndFencedJSON() {
        precondition(
            MarkdownJSONFormatter.format(#"{"b":1,"a":2}"#) == "{\n  \"a\": 2,\n  \"b\": 1\n}",
            "普通 JSON 应格式化并按键排序"
        )
        precondition(
            MarkdownJSONFormatter.format("```json\n{\"ok\":true}\n```") == "```json\n{\n  \"ok\": true\n}\n```",
            "JSON 代码块格式化后必须保留围栏"
        )
        precondition(
            MarkdownJSONFormatter.format(#"{"text":"冒号 : 保留","nested":{"value":1}}"#)
                == "{\n  \"nested\": {\n    \"value\": 1\n  },\n  \"text\": \"冒号 : 保留\"\n}",
            "JSON 键的冒号前不应留空格，字符串内部内容必须保持不变"
        )
        precondition(
            JSONPrettyPrinter.format(#"{"args":{},"files":[],"nested":{"empty":{}}}"#)
                == "{\n  \"args\": {},\n  \"files\": [],\n  \"nested\": {\n    \"empty\": {}\n  }\n}",
            "空对象和空数组必须保持紧凑，不能产生空白行"
        )
    }

    static func expect(_ condition: @autoclosure () throws -> Bool, _ label: String) throws {
        guard try condition() else { throw CheckError.failed(label) }
    }

    static func require<T>(_ value: T?, _ label: String) throws -> T {
        guard let value else { throw CheckError.failed(label) }
        return value
    }
}

enum CheckError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self { case .failed(let label): "检查失败：\(label)" }
    }
}
