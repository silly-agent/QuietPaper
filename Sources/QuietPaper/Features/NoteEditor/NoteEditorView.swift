import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NoteEditorView: View {
    @EnvironmentObject private var model: AppModel
    let isFocusMode: Bool
    let isHeaderBlurred: Bool
    let onHeaderHoverChange: (Bool) -> Void
    @State private var editing = true
    @State private var isShowingTablePopover = false
    @State private var tableColumns = 3
    @State private var tableDataRows = 3
    @State private var isFindPresented = false
    @State private var findQuery = ""
    @State private var findSelection = EditorFindSelection()
    @ObservedObject private var editorController: MarkdownEditorController
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isFindFieldFocused: Bool
    let onFocusChange: (WritingEditorFocusTarget, Bool) -> Void

    init(
        isFocusMode: Bool = false,
        editorController: MarkdownEditorController,
        isHeaderBlurred: Bool = false,
        onHeaderHoverChange: @escaping (Bool) -> Void = { _ in },
        onFocusChange: @escaping (WritingEditorFocusTarget, Bool) -> Void = { _, _ in }
    ) {
        self.isFocusMode = isFocusMode
        self.editorController = editorController
        self.isHeaderBlurred = isHeaderBlurred
        self.onHeaderHoverChange = onHeaderHoverChange
        self.onFocusChange = onFocusChange
    }

    var body: some View {
        Group {
            if model.selectedNoteID == nil {
                EmptyStateView(title: "选择一篇笔记", systemImage: "note.text", description: "从左侧选择模块和笔记，或按 ⌘N 新建。")
            } else {
                editorSurface
            }
        }
        .background(isFocusMode ? Color.white : Theme.background)
        .onChange(of: model.selectedNoteID) { _ in
            resetFindSession()
        }
        .onChange(of: editing) { _ in
            guard isFindPresented else { return }
            DispatchQueue.main.async {
                refreshFindResults(selectFirst: true)
            }
        }
        .onChange(of: model.draftContent) { _ in
            guard isFindPresented else { return }
            DispatchQueue.main.async {
                refreshFindResults(selectFirst: false)
            }
        }
        .onDisappear {
            onHeaderHoverChange(false)
            onFocusChange(.title, false)
            onFocusChange(.body, false)
        }
    }

    private var editorSurface: some View {
        VStack(spacing: 0) {
            if !isFocusMode {
                editorHeader
                HairlineDivider()
            }
            if isFindPresented {
                findBar
                HairlineDivider()
            }
            if editing {
                MarkdownEditor(
                    text: Binding(get: { model.draftContent }, set: { value in model.setDraftContent(value) }),
                    onPasteImage: { image in model.importImageMarkdown(image) },
                    resolveImage: { path in NSImage(contentsOf: model.attachments.url(for: path)) },
                    documentID: model.selectedNoteID,
                    controller: editorController,
                    showsScrollIndicators: !isFocusMode,
                    onFind: presentFind,
                    onFocusChange: { focused in
                        onFocusChange(.body, focused)
                    }
                )
            } else {
                MarkdownPreview(
                    markdown: model.draftContent,
                    attachments: model.attachments,
                    showsScrollIndicators: !isFocusMode,
                    findQuery: isFindPresented ? findQuery : "",
                    activeFindMatchIndex: isFindPresented ? findSelection.activeIndex : nil
                )
            }
            if !isFocusMode {
                HairlineDivider()
                statusBar
            }
        }
        .frame(maxWidth: isFocusMode ? 1_280 : .infinity, maxHeight: .infinity, alignment: .top)
        .background(isFocusMode ? Color.white : Theme.background)
        .padding(.horizontal, isFocusMode ? 32 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(isFocusMode ? Color.white : Theme.background)
        .background(
            EditorFindShortcutMonitor(action: presentFind)
                .frame(width: 0, height: 0)
        )
    }

    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("查找当前笔记", text: $findQuery)
                .textFieldStyle(.plain)
                .font(AppTypography.secondary)
                .focused($isFindFieldFocused)
                .onSubmit {
                    let direction: EditorFindDirection = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
                        ? .previous
                        : .next
                    moveFind(direction)
                }
                .onChange(of: findQuery) { _ in
                    refreshFindResults(selectFirst: true)
                }

            Text(findResultLabel)
                .font(AppTypography.tertiary)
                .foregroundStyle(findSelection.matchCount == 0 && !findQuery.isEmpty ? Color.red.opacity(0.82) : Color.secondary)
                .frame(minWidth: 54, alignment: .trailing)

            findBarButton(icon: "chevron.up", label: "上一处（Shift-Enter）") {
                moveFind(.previous)
            }
            .disabled(findSelection.matchCount == 0)

            findBarButton(icon: "chevron.down", label: "下一处（Enter）") {
                moveFind(.next)
            }
            .disabled(findSelection.matchCount == 0)

            findBarButton(icon: "xmark", label: "关闭查找（Esc）", action: closeFind)
        }
        .padding(.horizontal, isFocusMode ? 24 : 16)
        .frame(height: 36)
        .background(Theme.control.opacity(0.58))
        .onExitCommand(perform: closeFind)
    }

    private var findResultLabel: String {
        guard !findQuery.isEmpty else { return "" }
        guard findSelection.matchCount > 0, let activeIndex = findSelection.activeIndex else { return "无结果" }
        return "\(activeIndex + 1) / \(findSelection.matchCount)"
    }

    private func findBarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.secondary)
        .help(label)
        .accessibilityLabel(label)
        .pointingHandCursor()
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
                HStack(spacing: 6) {
                    HStack(spacing: 0) {
                        modeButton(isEditing: true, icon: "square.and.pencil", label: "编辑")
                        modeButton(isEditing: false, icon: "doc.text", label: "预览")
                    }
                    .padding(2)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.055), lineWidth: 0.5)
                    }

                    focusModeButton
                    moreMenu
                }
            }
            .font(AppTypography.secondary)
            .foregroundStyle(.secondary)

            TextField("笔记标题", text: Binding(get: { model.draftTitle }, set: { value in model.setDraftTitle(value) }))
                .textFieldStyle(.plain)
                .font(AppTypography.largeTitle)
                .focused($isTitleFocused)
                .onChange(of: isTitleFocused) { focused in
                    onFocusChange(.title, focused)
                }

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
        .contentShape(Rectangle())
        .onHover(perform: onHeaderHoverChange)
        .onDisappear {
            onHeaderHoverChange(false)
        }
        .writingFocusBlur(isActive: isHeaderBlurred)
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
            EditorHeaderControlLabel(
                glyph: .system(icon),
                isSelected: isSelected,
                width: 30,
                height: 28
            )
        }
        .buttonStyle(EditorHeaderPressStyle())
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(isSelected ? "已选择" : "")
        .pointingHandCursor()
    }

    private var focusModeButton: some View {
        Button {
            NotificationCenter.default.post(name: .toggleQuietPaperFocusMode, object: nil)
        } label: {
            EditorHeaderControlLabel(
                glyph: .focusFrame,
                isSelected: model.isFocusMode,
                width: 32,
                height: 32
            )
        }
        .buttonStyle(EditorHeaderPressStyle())
        .help(model.isFocusMode ? "退出专注模式（⌘E）" : "专注模式（⌘E）")
        .accessibilityLabel("专注模式")
        .accessibilityValue(model.isFocusMode ? "已开启" : "已关闭")
        .pointingHandCursor()
    }

    private var moreMenu: some View {
        Menu {
            Button("格式化 JSON") { formatJSON() }
            Divider()
            Button("导出 Markdown…", action: exportMarkdown)
            Button("完整数据备份…", action: backup)
        } label: {
            EditorHeaderControlLabel(
                glyph: .system("ellipsis"),
                isSelected: false,
                width: 32,
                height: 32
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(EditorHeaderPressStyle())
        .fixedSize()
        .help("更多操作")
        .accessibilityLabel("更多操作")
        .pointingHandCursor()
    }

    private func presentFind() {
        isFindPresented = true
        refreshFindResults(selectFirst: findSelection.activeIndex == nil)
        DispatchQueue.main.async {
            isFindFieldFocused = true
        }
    }

    private func closeFind() {
        isFindPresented = false
        isFindFieldFocused = false
    }

    private func resetFindSession() {
        isFindPresented = false
        isFindFieldFocused = false
        findQuery = ""
        findSelection.reset()
    }

    private func refreshFindResults(selectFirst: Bool) {
        guard !findQuery.isEmpty else {
            findSelection.reset()
            return
        }

        let count = currentFindMatchCount()
        findSelection.refresh(matchCount: count, selectFirst: selectFirst)
        revealCurrentFindMatch()
    }

    private func moveFind(_ direction: EditorFindDirection) {
        guard !findQuery.isEmpty else { return }
        let count = currentFindMatchCount()
        findSelection.move(direction, matchCount: count)
        revealCurrentFindMatch()
        isFindFieldFocused = true
    }

    private func currentFindMatchCount() -> Int {
        if editing {
            return editorController.findRanges(for: findQuery).count
        }
        return previewSearchIndex.matches(query: findQuery).count
    }

    private func revealCurrentFindMatch() {
        guard editing,
              let activeIndex = findSelection.activeIndex else { return }
        let matches = editorController.findRanges(for: findQuery)
        guard matches.indices.contains(activeIndex) else { return }
        editorController.revealFindMatch(matches[activeIndex])
    }

    private var previewSearchIndex: PreviewSearchIndex {
        PreviewSearchIndex(blocks: MarkdownParser.parse(model.draftContent))
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

private struct EditorFindShortcutMonitor: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.installMonitor()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        var action: () -> Void
        private var monitor: Any?

        init(action: @escaping () -> Void) {
            self.action = action
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard modifiers == .command,
                      event.charactersIgnoringModifiers?.lowercased() == "f" else {
                    return event
                }
                self?.action()
                return nil
            }
        }

        func removeMonitor() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

    }
}

private enum EditorHeaderGlyph {
    case system(String)
    case focusFrame
}

private struct EditorHeaderControlLabel: View {
    let glyph: EditorHeaderGlyph
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat
    @State private var isHovering = false

    private var foregroundColor: Color {
        isSelected || isHovering ? Theme.accent : Color.secondary
    }

    private var fillColor: Color {
        if isSelected { return Theme.accent.opacity(0.13) }
        if isHovering { return Theme.accent.opacity(0.07) }
        return .clear
    }

    private var strokeColor: Color {
        if isSelected { return Theme.accent.opacity(0.22) }
        if isHovering { return Theme.accent.opacity(0.14) }
        return .clear
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(fillColor)

            RoundedRectangle(cornerRadius: 7)
                .stroke(strokeColor, lineWidth: 0.5)

            glyphView
        }
        .frame(width: width, height: height)
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .shadow(
            color: isSelected ? Theme.accent.opacity(0.07) : .clear,
            radius: 1,
            y: 0.5
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .animation(.easeOut(duration: 0.14), value: isSelected)
    }

    @ViewBuilder
    private var glyphView: some View {
        switch glyph {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(foregroundColor)
        case .focusFrame:
            FocusFrameGlyph()
                .stroke(
                    foregroundColor,
                    style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 14, height: 14)
        }
    }
}

private struct EditorHeaderPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct FocusFrameGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let inset: CGFloat = 0.75
        let arm = min(rect.width, rect.height) * 0.31
        let minX = rect.minX + inset
        let maxX = rect.maxX - inset
        let minY = rect.minY + inset
        let maxY = rect.maxY - inset

        var path = Path()
        path.move(to: CGPoint(x: minX, y: minY + arm))
        path.addLine(to: CGPoint(x: minX, y: minY))
        path.addLine(to: CGPoint(x: minX + arm, y: minY))

        path.move(to: CGPoint(x: maxX - arm, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: minY + arm))

        path.move(to: CGPoint(x: maxX, y: maxY - arm))
        path.addLine(to: CGPoint(x: maxX, y: maxY))
        path.addLine(to: CGPoint(x: maxX - arm, y: maxY))

        path.move(to: CGPoint(x: minX + arm, y: maxY))
        path.addLine(to: CGPoint(x: minX, y: maxY))
        path.addLine(to: CGPoint(x: minX, y: maxY - arm))
        return path
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
