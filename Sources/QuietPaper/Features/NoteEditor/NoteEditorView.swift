import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NoteEditorView: View {
    @EnvironmentObject private var model: AppModel
    let isFocusMode: Bool
    @State private var editing = true
    @State private var isShowingTablePopover = false
    @State private var tableColumns = 3
    @State private var tableDataRows = 3
    @StateObject private var editorController = MarkdownEditorController()

    init(isFocusMode: Bool = false) {
        self.isFocusMode = isFocusMode
    }

    var body: some View {
        Group {
            if model.selectedNoteID == nil {
                EmptyStateView(title: "选择一篇笔记", systemImage: "note.text", description: "从左侧选择模块和笔记，或按 ⌘N 新建。")
            } else {
                editorSurface
            }
        }
        .background(Theme.background)
    }

    private var editorSurface: some View {
        VStack(spacing: 0) {
            if !isFocusMode {
                editorHeader
                HairlineDivider()
            }
            if editing {
                MarkdownEditor(
                    text: Binding(get: { model.draftContent }, set: { value in model.setDraftContent(value) }),
                    onPasteImage: { image in model.importImageMarkdown(image) },
                    resolveImage: { path in NSImage(contentsOf: model.attachments.url(for: path)) },
                    documentID: model.selectedNoteID,
                    controller: editorController,
                    showsScrollIndicators: !isFocusMode
                )
            } else {
                MarkdownPreview(
                    markdown: model.draftContent,
                    attachments: model.attachments,
                    showsScrollIndicators: !isFocusMode
                )
            }
            if !isFocusMode {
                HairlineDivider()
                statusBar
            }
        }
        .frame(maxWidth: isFocusMode ? 760 : .infinity, maxHeight: .infinity, alignment: .top)
        .background(isFocusMode ? Theme.editor : Theme.background)
        .overlay {
            if isFocusMode {
                Rectangle()
                    .stroke(Color.primary.opacity(0.045), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
    }

    private var editorHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Text(model.selectedProject?.name ?? "")
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                if model.selectedModule?.isProjectRoot != true {
                    Text(model.selectedModule?.name ?? "")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(model.draftTitle)
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 2) {
                    modeButton(isEditing: true, icon: "pencil", label: "编辑")
                    modeButton(isEditing: false, icon: "eye", label: "预览")
                    focusModeButton
                }
                .padding(2)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
                Menu {
                    Button("格式化 JSON") { formatJSON() }
                    Divider()
                    Button("导出 Markdown…", action: exportMarkdown)
                    Button("完整数据备份…", action: backup)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .pointingHandCursor()
            }
            .font(AppTypography.secondary)
            .foregroundStyle(.secondary)

            TextField("笔记标题", text: Binding(get: { model.draftTitle }, set: { value in model.setDraftTitle(value) }))
                .textFieldStyle(.plain)
                .font(AppTypography.largeTitle)

            if editing {
                HStack(spacing: 0) {
                    formattingToolbar
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            switch model.saveState {
            case .saving:
                ProgressView().controlSize(.small)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            default:
                Circle().fill(Color.secondary.opacity(0.5)).frame(width: 4, height: 4)
            }
            Text(model.saveState.label)
            if case .failed = model.saveState {
                Button("重试") { model.retrySave() }
                    .buttonStyle(.link)
                    .pointingHandCursor()
            }
            Text("·")
            Text("\(model.draftContent.count) 字")
            Spacer()
            Text(editing ? "Markdown 编辑" : "阅读预览")
        }
        .font(AppTypography.status)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 30)
    }


    private var formattingToolbar: some View {
        HStack(spacing: 2) {
            headingMenu
            toolbarDivider
            EditorToolbarButton(title: "切换列表", icon: "list.bullet") {
                editorController.apply(.bullet)
            }
            EditorToolbarButton(title: "切换引用", icon: "text.quote") {
                editorController.apply(.quote)
            }
            EditorToolbarButton(title: "切换代码块", icon: "chevron.left.forwardslash.chevron.right") {
                editorController.apply(.code)
            }
            EditorToolbarButton(title: "插入表格", icon: "tablecells") {
                isShowingTablePopover = true
            }
            .popover(isPresented: $isShowingTablePopover, arrowEdge: .bottom) {
                TableInsertionPopover(
                    columns: $tableColumns,
                    dataRows: $tableDataRows,
                    onCancel: { isShowingTablePopover = false },
                    onInsert: {
                        insertTable()
                        isShowingTablePopover = false
                    }
                )
            }
            toolbarDivider
            EditorToolbarButton(title: "插入图片", icon: "photo", action: chooseImage)
        }
        .padding(3)
        .background(Theme.control.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var headingMenu: some View {
        Menu {
            Button("正文") { editorController.apply(.heading(level: nil)) }
            Divider()
            Button("一级标题  H1") { editorController.apply(.heading(level: 1)) }
            Button("二级标题  H2") { editorController.apply(.heading(level: 2)) }
            Button("三级标题  H3") { editorController.apply(.heading(level: 3)) }
        } label: {
            HStack(spacing: 5) {
                Text("H")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text("标题")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .frame(width: 62, height: 28)
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .tint(Color.secondary)
        .frame(width: 72)
        .help("设置标题级别")
        .accessibilityLabel("设置标题级别")
        .pointingHandCursor()
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 0.5, height: 16)
            .padding(.horizontal, 2)
            .accessibilityHidden(true)
    }

    private func modeButton(isEditing: Bool, icon: String, label: String) -> some View {
        let isSelected = editing == isEditing
        return Button {
            editing = isEditing
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? Theme.accent.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(isSelected ? "已选择" : "")
        .pointingHandCursor()
    }

    private var focusModeButton: some View {
        Button {
            NotificationCenter.default.post(name: .toggleQuietPaperFocusMode, object: nil)
        } label: {
            Image(systemName: model.isFocusMode
                ? "arrow.down.right.and.arrow.up.left"
                : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(model.isFocusMode ? Theme.accent : Color.secondary)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            model.isFocusMode ? Theme.accent.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
        .help(model.isFocusMode ? "退出专注模式（⌘E）" : "专注模式（⌘E）")
        .accessibilityLabel("专注模式")
        .accessibilityValue(model.isFocusMode ? "已开启" : "已关闭")
        .pointingHandCursor()
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        guard let markdown = model.importImageMarkdown(image) else { return }
        if !editorController.insertImage(image, markdown: markdown) {
            let separator = model.draftContent.hasSuffix("\n") || model.draftContent.isEmpty ? "" : "\n"
            model.setDraftContent(model.draftContent + separator + markdown + "\n")
        }
    }

    private func insertTable() {
        if editorController.insertTable(columns: tableColumns, dataRows: tableDataRows) {
            return
        }
        let markdown = MarkdownTableTemplate.make(columns: tableColumns, dataRows: tableDataRows)
        let separator = model.draftContent.hasSuffix("\n") || model.draftContent.isEmpty ? "" : "\n\n"
        model.setDraftContent(model.draftContent + separator + markdown + "\n")
    }

    private func formatJSON() {
        if editing {
            if !editorController.apply(.formatJSON) {
                model.startupError = "请选择有效的 JSON，或确保整篇笔记是 JSON 文档"
            }
        } else {
            model.formatJSON()
        }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        if let markdownType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [markdownType]
        }
        panel.nameFieldStringValue = model.draftTitle.isEmpty ? "未命名笔记.md" : "\(model.draftTitle).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.exportCurrentNote(to: url) } catch { model.startupError = error.localizedDescription }
    }

    private func backup() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "备份到这里"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let timestamp = Int(Date().timeIntervalSince1970)
        let folder = url.appendingPathComponent("QuietPaper-Backup-\(timestamp)", isDirectory: true)
        do { try model.backup(to: folder) } catch { model.startupError = error.localizedDescription }
    }
}

private struct TableInsertionPopover: View {
    @Binding var columns: Int
    @Binding var dataRows: Int
    let onCancel: () -> Void
    let onInsert: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("插入表格", systemImage: "tablecells")
                    .font(AppTypography.sectionTitle)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                stepperRow(title: "列数", value: $columns, range: 2...12)
                stepperRow(title: "数据行", value: $dataRows, range: 1...30)
            }

            Text("将插入 1 行表头和 \(dataRows) 行数据。")
                .font(AppTypography.tertiary)
                .foregroundStyle(.secondary)

            tablePreview

            HStack {
                Button("取消", action: onCancel)
                    .pointingHandCursor()
                Spacer()
                Button("插入", action: onInsert)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .pointingHandCursor()
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(Theme.background)
    }

    private func stepperRow(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title)
                .font(AppTypography.secondary)
                .foregroundStyle(.secondary)
            Spacer()
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(width: 28)
            }
            .pointingHandCursor()
        }
    }

    private var tablePreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<min(dataRows + 1, 4), id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<min(columns, 4), id: \.self) { column in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(row == 0 ? Theme.accent.opacity(0.26) : Color.primary.opacity(0.06))
                            .frame(width: 34, height: 18)
                            .overlay {
                                if row == 0 {
                                    Text("\(column + 1)")
                                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(1.5)
                    }
                }
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.editor.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }
}

private struct EditorToolbarButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovering ? Theme.accent : Color.secondary)
        .background(
            isHovering ? Theme.accent.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .onHover { isHovering = $0 }
        .help(title)
        .accessibilityLabel(title)
        .pointingHandCursor()
    }
}
