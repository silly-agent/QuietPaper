import AppKit
import SwiftUI

struct DatabaseConnectionEditorView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let note = model.selectedNote {
            DatabaseConnectionWorkspace(note: note, isAIUnreadable: model.isSelectedNoteAIUnreadable) { content in
                model.setDraftContent(content)
            }
            .id(note.id)
        } else {
            EmptyStateView(title: "没有选择连接", systemImage: "cylinder", description: "选择或新建一个数据库连接文件。")
        }
    }
}

private struct DatabaseConnectionWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var viewModel: DatabaseConnectionViewModel
    let isAIUnreadable: Bool
    @State private var input = ""
    @State private var showSetup: Bool
    @State private var aiTask: Task<Void, Never>?
    @FocusState private var inputFocused: Bool

    init(note: Note, isAIUnreadable: Bool, onSave: @escaping (String) -> Void) {
        self.isAIUnreadable = isAIUnreadable
        _viewModel = StateObject(wrappedValue: DatabaseConnectionViewModel(
            noteID: note.id,
            content: note.contentMarkdown,
            isAIUnreadable: isAIUnreadable,
            onSave: onSave
        ))
        _showSetup = State(initialValue: DatabaseConnectionFile.decode(note.contentMarkdown).kind == nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HairlineDivider()
            conversation
            HairlineDivider()
            composer
        }
        .background(Theme.editor)
        .sheet(isPresented: $showSetup) {
            DatabaseConnectionSetupSheet(
                initialKind: viewModel.file.kind,
                initialSettings: viewModel.file.settings,
                isEditing: viewModel.file.kind != nil
            ) { kind, settings in
                Task { await viewModel.configure(kind: kind, settings: settings) }
            }
        }
        .sheet(isPresented: $viewModel.needsMySQLDatabase) {
            MySQLDatabaseChooser(
                databases: viewModel.availableMySQLDatabases,
                onChoose: { name in Task { await viewModel.chooseMySQLDatabase(name, create: false) } },
                onCreate: { name in Task { await viewModel.chooseMySQLDatabase(name, create: true) } }
            )
        }
        .sheet(item: $viewModel.pendingCommand) { pending in
            DatabaseCommandConfirmationSheet(
                pending: pending,
                onCancel: viewModel.cancelPendingCommand,
                onConfirm: { Task { await viewModel.confirmPendingCommand() } }
            )
        }
        .alert("数据库连接", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("修改连接信息") {
                viewModel.errorMessage = nil
                showSetup = true
            }
            Button("好") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onChange(of: isAIUnreadable) { value in
            if value {
                aiTask?.cancel()
                aiTask = nil
            }
            viewModel.setAIUnreadable(value)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(kindColor.opacity(0.12))
                Image(systemName: viewModel.file.kind?.systemImage ?? "cylinder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(kindColor)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                TextField("连接名称", text: Binding(
                    get: { model.draftTitle },
                    set: { value in model.setDraftTitle(value) }
                ))
                .textFieldStyle(.plain)
                .font(AppTypography.sheetTitle)
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(viewModel.status.label)
                    if let kind = viewModel.file.kind {
                        Text("· \(kind.title) · \(viewModel.file.settings.redactedSummary)")
                    }
                }
                .font(AppTypography.tertiary)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.file.kind != nil {
                Button {
                    showSetup = true
                } label: {
                    Label("编辑连接", systemImage: "slider.horizontal.3")
                }
                .controlSize(.small)
                .pointingHandCursor()
            }
            if viewModel.status == .connected {
                Button("断开") { Task { await viewModel.disconnect() } }
                    .controlSize(.small)
                    .pointingHandCursor()
            } else if viewModel.file.kind != nil {
                Button {
                    Task { await viewModel.connect(showMySQLChooser: viewModel.file.kind == .mysql && viewModel.file.settings.database.isEmpty) }
                } label: {
                    Label("重新连接", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.status == .connecting)
                .pointingHandCursor()
            } else {
                Button {
                    showSetup = true
                } label: {
                    Label("选择数据库", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .pointingHandCursor()
            }
            Menu {
                if viewModel.file.kind != nil {
                    Button("编辑连接信息") { showSetup = true }
                    Divider()
                }
                Button("清空对话", role: .destructive) { viewModel.clearHistory() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .pointingHandCursor()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(Theme.background)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if viewModel.file.messages.isEmpty {
                        databaseWelcome
                    }
                    ForEach(viewModel.file.messages) { message in
                        DatabaseMessageView(message: message)
                            .id(message.id)
                    }
                    if viewModel.isThinking {
                        DatabaseThinkingView(stage: viewModel.loadingStage)
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .frame(maxWidth: 1_040, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .onChange(of: viewModel.file.messages.count) { _ in
                if let id = viewModel.file.messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
            .onChange(of: viewModel.isThinking) { active in
                if active { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
        }
    }

    private var databaseWelcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("数据库助手", systemImage: "sparkles")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(Theme.accent)
            Text("连接成功后，可以直接用自然语言查询结构、读取数据或修改数据库。我会把命令和返回结果清楚地展示出来。")
                .font(AppTypography.body)
                .bodyTracking()
                .foregroundStyle(.secondary)
                .lineSpacing(3)
            Text("例如：列出所有表 · 看一下 users 表最近的数据 · 创建一张测试表")
                .font(AppTypography.secondary)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var composer: some View {
        if viewModel.isAIUnreadable {
            HStack(spacing: 8) {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                Text("当前项目或模块已标记为 AI 不可读，数据库 AI 助手不可使用。")
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Theme.background)
        } else {
            HStack(alignment: .bottom, spacing: 10) {
            TextField("用自然语言操作数据库…", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(AppTypography.body)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.control, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07)))
                .focused($inputFocused)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .clipShape(Circle())
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isThinking)
            .keyboardShortcut(.return, modifiers: .command)
            .pointingHandCursor()
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Theme.background)
        }
    }

    private var kindColor: Color {
        switch viewModel.file.kind {
        case .mysql: .blue
        case .postgresql: .indigo
        case .redis: .red
        case .sqlite: .teal
        case nil: Theme.accent
        }
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .connected: .green
        case .connecting: .orange
        case .disconnected, .failed: .red
        }
    }

    private func send() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !viewModel.isAIUnreadable else { return }
        input = ""
        aiTask?.cancel()
        aiTask = Task { await viewModel.send(value) }
    }
}

private struct DatabaseMessageView: View {
    let message: DatabaseConversationMessage
    @State private var reasoningExpanded = false

    var body: some View {
        Group {
            switch message.role {
            case .user:
                userRow
            case .assistant:
                assistantRow
            case .system:
                systemRow
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var userRow: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 110)
            VStack(alignment: .trailing, spacing: 7) {
                HStack(alignment: .bottom, spacing: 9) {
                    Text(message.text)
                        .font(AppTypography.body)
                        .bodyTracking()
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Theme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.08)))
                    avatar(systemImage: "person.fill", color: Theme.accent, background: Theme.accent.opacity(0.11))
                }
                timestamp.padding(.trailing, 39)
            }
            .layoutPriority(1)
        }
    }

    private var assistantRow: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar(systemImage: "sparkles", color: Theme.accent, background: Theme.accent.opacity(0.09))
            VStack(alignment: .leading, spacing: 10) {
                if let reasoning = displayedReasoning {
                    DisclosureGroup(isExpanded: $reasoningExpanded) {
                        CompactMarkdownView(markdown: reasoning, style: .reasoning)
                            .padding(.top, 7)
                    } label: {
                        Label("思考过程", systemImage: "brain.head.profile")
                            .font(AppTypography.secondary)
                            .foregroundStyle(.secondary)
                    }
                }
                if !displayedText.isEmpty {
                    CompactMarkdownView(markdown: displayedText)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .background(Theme.control, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.045)))
                }
                if let command = message.command {
                    DatabaseCommandBlock(command: command)
                }
                if let result = message.result {
                    DatabaseResultView(result: result)
                }
                timestamp
            }
            .layoutPriority(1)
            Spacer(minLength: 72)
        }
    }

    private var systemRow: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar(systemImage: "info.circle.fill", color: .secondary, background: Color.secondary.opacity(0.08))
            VStack(alignment: .leading, spacing: 5) {
                Text(message.text)
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                timestamp
            }
            .padding(.top, 3)
            Spacer(minLength: 72)
        }
        .padding(.vertical, 2)
    }

    private var timestamp: some View {
        Text(message.createdAt, style: .time)
            .font(AppTypography.tertiary)
            .foregroundStyle(.tertiary)
    }

    private func avatar(systemImage: String, color: Color, background: Color) -> some View {
        ZStack {
            Circle().fill(background)
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: 30, height: 30)
    }

    private var displayedText: String {
        if let result = message.result,
           result.rows.isEmpty,
           (!result.columns.isEmpty || result.message.hasPrefix("查询完成")) {
            return "查询完成，没有找到符合条件的数据。"
        }
        guard message.result != nil else { return message.text }
        var output: [String] = []
        var lastWasBlank = false
        for line in message.text.components(separatedBy: .newlines) {
            let clean = line.trimmingCharacters(in: .whitespaces)
            if clean.hasPrefix("|") { continue }
            let isBlank = clean.isEmpty
            if isBlank && lastWasBlank { continue }
            output.append(line)
            lastWasBlank = isBlank
        }
        return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedReasoning: String? {
        guard let reasoning = message.reasoning else { return nil }
        let markers = ["DSML", "tool_calls", "invoke name=", "parameter name="]
        let firstMarker = markers.compactMap {
            reasoning.range(of: $0, options: .caseInsensitive)?.lowerBound
        }.min()
        let clean: String
        if let firstMarker {
            let lineStart = reasoning[..<firstMarker].lastIndex(of: "\n").map {
                reasoning.index(after: $0)
            } ?? reasoning.startIndex
            clean = String(reasoning[..<lineStart])
        } else {
            clean = reasoning
        }
        let trimmed = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct DatabaseCommandBlock: View {
    let command: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(commandType)
                    .font(AppTypography.monospacedLabel)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .font(AppTypography.tertiary)
                .pointingHandCursor()
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.035))
            ScrollView(.horizontal, showsIndicators: false) {
                Text(command)
                    .font(AppTypography.monospacedCode)
                    .textSelection(.enabled)
                    .padding(11)
            }
        }
        .background(Theme.editor, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.07)))
    }

    private var commandType: String {
        command.split(whereSeparator: \.isWhitespace).first?.uppercased() ?? "COMMAND"
    }
}

private struct DatabaseResultView: View {
    let result: DatabaseQueryResult

    private let rowHeight: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .font(AppTypography.secondary)
                    .foregroundStyle(Color.green)
                Text("· \(result.duration.formattedMilliseconds)")
                    .font(AppTypography.tertiary)
                    .foregroundStyle(.tertiary)
                Spacer()
                if !result.rows.isEmpty {
                    Menu("导出") {
                        Button("复制为 JSON") { copyJSON() }
                        Button("复制为 CSV") { copyCSV() }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .font(AppTypography.tertiary)
                    .pointingHandCursor()
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)

            if !result.rows.isEmpty {
                HairlineDivider()
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 0) {
                        resultRow(result.columns, isHeader: true, index: -1)
                        ForEach(Array(normalizedRows.enumerated()), id: \.offset) { index, row in
                            resultRow(row, isHeader: false, index: index)
                        }
                    }
                }
                .frame(width: viewportWidth, height: tableHeight, alignment: .topLeading)
                .clipped()
            } else if !result.columns.isEmpty {
                Text("没有符合条件的数据")
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 11)
                    .padding(.bottom, 10)
            } else if !result.message.isEmpty {
                Text(result.message)
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 11)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: viewportWidth, alignment: .leading)
        .background(Theme.editor, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private var summary: String {
        if !result.rows.isEmpty { return "返回 \(result.rows.count) 行" }
        if !result.columns.isEmpty { return "返回 0 行" }
        if let affected = result.affectedRows { return "影响 \(affected) 行" }
        return "执行成功"
    }

    private func resultRow(_ values: [String], isHeader: Bool, index: Int) -> some View {
        let background: Color = isHeader
            ? Color.primary.opacity(0.045)
            : (index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.018))
        return HStack(spacing: 0) {
            ForEach(result.columns.indices, id: \.self) { valueIndex in
                DatabaseResultCell(
                    value: values.indices.contains(valueIndex) ? values[valueIndex] : "NULL",
                    isHeader: isHeader,
                    width: columnWidths[valueIndex],
                    height: rowHeight
                )
            }
        }
        .background(background)
        .overlay(alignment: .bottom) { HairlineDivider() }
    }

    private func copyJSON() {
        var objects: [[String: String]] = []
        for row in result.rows {
            var object: [String: String] = [:]
            for (index, column) in result.columns.enumerated() {
                object[column] = row.indices.contains(index) ? (row[index] ?? "NULL") : "NULL"
            }
            objects.append(object)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys]),
              let value = String(data: data, encoding: .utf8) else { return }
        copy(value)
    }

    private func copyCSV() {
        var output = result.columns.map(csvEscaped).joined(separator: ",")
        for row in result.rows {
            output += "\n"
            var values: [String] = []
            for value in row { values.append(csvEscaped(value ?? "")) }
            output += values.joined(separator: ",")
        }
        copy(output)
    }

    private var normalizedRows: [[String]] {
        result.rows.map { row in
            result.columns.indices.map { index in
                row.indices.contains(index) ? (row[index] ?? "NULL") : "NULL"
            }
        }
    }

    private var measuredColumnWidths: [CGFloat] {
        result.columns.indices.map { index in
            let values = [result.columns[index]] + normalizedRows.map { $0[index] }
            let longest = values.map(visualCharacterCount).max() ?? 12
            return min(max(CGFloat(longest) * 7.4 + 26, 132), 320)
        }
    }

    private var columnWidths: [CGFloat] {
        DatabaseResultColumnLayout.expandedWidths(measuredColumnWidths, minimumTotalWidth: 380)
    }

    private var viewportWidth: CGFloat {
        guard !result.columns.isEmpty else { return 380 }
        return min(max(columnWidths.reduce(0, +), 380), 860)
    }

    private var tableHeight: CGFloat {
        min(CGFloat(result.rows.count + 1) * rowHeight, 380)
    }

    private func visualCharacterCount(_ value: String) -> Int {
        value.unicodeScalars.reduce(0) { count, scalar in
            count + (scalar.isASCII ? 1 : 2)
        }
    }

    private func csvEscaped(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct DatabaseResultCell: View {
    let value: String
    let isHeader: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Text(value)
            .foregroundStyle(foregroundColor)
            .help(value)
            .font(isHeader ? AppTypography.rowTitleStrong : AppTypography.secondary)
            .lineLimit(1)
            .textSelection(.enabled)
            .padding(.horizontal, 10)
            .frame(width: width, height: height, alignment: .leading)
            .overlay(alignment: .trailing) { HairlineDivider(axis: .vertical) }
    }

    private var foregroundColor: Color {
        if isHeader { return .primary }
        return value == "NULL" ? .secondary.opacity(0.6) : .secondary
    }
}

private struct DatabaseThinkingView: View {
    let stage: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.10)).frame(width: 28, height: 28)
                ProgressView().controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(stage.isEmpty ? "AI 正在思考…" : stage)
                    .font(AppTypography.secondary)
                TimelineView(.animation(minimumInterval: 0.45)) { context in
                    let count = Int(context.date.timeIntervalSinceReferenceDate * 2).quotientAndRemainder(dividingBy: 4).remainder
                    Text(String(repeating: "●", count: count + 1))
                        .font(.system(size: 7))
                        .foregroundStyle(Theme.accent.opacity(0.55))
                }
            }
        }
        .padding(12)
        .background(Theme.control, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 420, alignment: .leading)
    }
}

private struct DatabaseCommandConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pending: PendingDatabaseCommand
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("确认执行高风险操作？").font(AppTypography.sheetTitle)
                    Text("执行后可能无法恢复，请仔细核对命令。")
                        .font(AppTypography.secondary).foregroundStyle(.secondary)
                }
            }
            Text(pending.explanation)
                .font(AppTypography.secondary)
                .foregroundStyle(.secondary)
            ScrollView([.horizontal, .vertical]) {
                Text(pending.command)
                    .font(AppTypography.monospacedCode)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 100, maxHeight: 220)
            .background(Theme.editor, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.red.opacity(0.25)))
            HStack {
                Spacer()
                Button("取消") { onCancel(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .pointingHandCursor()
                Button("确认执行", role: .destructive) { onConfirm(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .pointingHandCursor()
            }
        }
        .padding(22)
        .frame(width: 580)
    }
}
