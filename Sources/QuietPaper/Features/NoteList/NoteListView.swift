import AppKit
import SwiftUI

private enum NoteListSortMode: String, CaseIterable, Identifiable {
    case fileName
    case createdAt
    case updatedAt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fileName: "文件名"
        case .createdAt: "创建时间"
        case .updatedAt: "修改时间"
        }
    }

    var menuTitle: String { "按\(title)排序" }
}

private enum NoteListSortDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ascending: "正序"
        case .descending: "倒序"
        }
    }

    var symbolName: String {
        switch self {
        case .ascending: "arrow.up"
        case .descending: "arrow.down"
        }
    }
}

private enum NoteListItem: Identifiable {
    case note(Note)
    case foldGroup(NoteFoldGroup)

    var id: String {
        switch self {
        case .note(let note): "note-\(note.id.uuidString)"
        case .foldGroup(let group): "fold-\(group.id.uuidString)"
        }
    }
}

private struct NoteDeletionRequest: Identifiable {
    let id = UUID()
    let notes: [Note]

    var count: Int { notes.count }
    var alertTitle: String { count == 1 ? "删除笔记？" : "删除 \(count) 个文件？" }
    var actionTitle: String { count == 1 ? "删除" : "删除 \(count) 个文件" }
}

struct NoteListView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("QuietPaper.noteListSortMode") private var sortModeRawValue = NoteListSortMode.fileName.rawValue
    @AppStorage("QuietPaper.noteListSortDirection") private var sortDirectionRawValue = NoteListSortDirection.ascending.rawValue
    @State private var deletionRequest: NoteDeletionRequest?
    @State private var noteToRename: Note?
    @State private var rangeSelection = NoteRangeSelection()
    @State private var showRequestCreation = false

    private var sortMode: NoteListSortMode {
        NoteListSortMode(rawValue: sortModeRawValue) ?? .fileName
    }

    private var sortDirection: NoteListSortDirection {
        NoteListSortDirection(rawValue: sortDirectionRawValue) ?? .ascending
    }

    private var sortedNotes: [Note] {
        model.notes.sorted(by: areNotesOrdered)
    }

    private var listItems: [NoteListItem] {
        let visibleNoteIDs = Set(sortedNotes.map(\.id))
        let groups = model.noteFoldGroups.compactMap { group -> NoteFoldGroup? in
            let validNoteIDs = group.noteIDs.filter(visibleNoteIDs.contains)
            guard validNoteIDs.count >= 2 else { return nil }
            return NoteFoldGroup(id: group.id, moduleID: group.moduleID, noteIDs: validNoteIDs, createdAt: group.createdAt)
        }
        var groupByNoteID: [UUID: NoteFoldGroup] = [:]
        for group in groups {
            for noteID in group.noteIDs { groupByNoteID[noteID] = group }
        }

        var emittedGroupIDs = Set<UUID>()
        var items: [NoteListItem] = []
        for note in sortedNotes {
            if let group = groupByNoteID[note.id] {
                if emittedGroupIDs.insert(group.id).inserted {
                    items.append(.foldGroup(group))
                }
            } else {
                items.append(.note(note))
            }
        }
        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.selectedModule?.isProjectRoot == true ? model.selectedProject?.name ?? "文件" : model.selectedModule?.name ?? "笔记")
                        .font(.system(size: 13.5, weight: .semibold))
                    if !model.searchQuery.isEmpty {
                        Text("\(model.searchResults.count) 个搜索结果")
                            .font(AppTypography.tertiary)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if model.searchQuery.isEmpty {
                    sortMenu
                }
                Menu {
                    Button("新建笔记") { _ = model.createNote() }
                    Button("新建请求") { showRequestCreation = true }
                    Button("新建连接") { _ = model.createConnection() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .help("新建文件")
                .disabled(model.selectedModuleID == nil)
                .pointingHandCursor()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if !model.searchQuery.isEmpty {
                Picker("范围", selection: $model.searchScope) {
                    ForEach(SearchScope.allCases) { scope in Text(scope.label).tag(scope) }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .onChange(of: model.searchScope) { _ in model.updateSearch() }
                .pointingHandCursor()
            }

            HairlineDivider()

            if model.searchQuery.isEmpty {
                notesList
            } else {
                searchList
            }
        }
        .background(Theme.control)
        .sheet(item: $noteToRename) { note in
            RenameNoteSheet(note: note)
                .environmentObject(model)
        }
        .sheet(isPresented: $showRequestCreation) {
            RequestCreationSheet(
                onCreateHTTP: { draft in _ = model.createRequest(draft: draft) },
                onCreateWebSocket: { _ = model.createWebSocketRequest() }
            )
        }
        .alert(deletionRequest?.alertTitle ?? "删除笔记？", isPresented: Binding(
            get: { deletionRequest != nil },
            set: { if !$0 { deletionRequest = nil } }
        ), presenting: deletionRequest) { request in
            Button("取消", role: .cancel) {}
            Button(request.actionTitle, role: .destructive) { confirmDeletion(request) }
        } message: { request in
            if let note = request.notes.first, request.count == 1 {
                Text("“\(note.title)”将移到最近删除。")
            } else {
                Text("选中的 \(request.count) 个文件将移到最近删除，可在设置中恢复。")
            }
        }
        .onChange(of: model.selectedModuleID) { _ in resetRangeSelection() }
        .onChange(of: model.searchQuery) { _ in resetRangeSelection() }
        .onChange(of: model.notes.map(\.id)) { noteIDs in
            rangeSelection.retainValidIDs(Set(noteIDs))
        }
    }

    private var notesList: some View {
        Group {
            if model.notes.isEmpty {
                EmptyStateView(title: "还没有笔记", systemImage: "doc.badge.plus", description: "创建一篇笔记，直接开始记录。")
            } else {
                List {
                    ForEach(listItems) { item in
                        switch item {
                        case .note(let note):
                            NoteRow(
                                note: note,
                                isSelected: note.id == model.selectedNoteID,
                                isRangeSelected: rangeSelection.selectedIDs.contains(note.id)
                            )
                                .contentShape(Rectangle())
                                .onTapGesture { select(note) }
                                .pointingHandCursor()
                                .listRowInsets(EdgeInsets(top: 1.5, leading: 6, bottom: 1.5, trailing: 6))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .contextMenu {
                                    if rangeSelection.selectedIDs.contains(note.id), rangeSelection.selectedIDs.count >= 2 {
                                        Button {
                                            quickFoldSelection()
                                        } label: {
                                            Label("快速折叠（\(rangeSelection.selectedIDs.count) 个文件）", systemImage: "rectangle.compress.vertical")
                                        }
                                        Divider()
                                    }
                                    Button("重命名") { noteToRename = note }
                                    Menu("移动到") {
                                        ForEach(model.modules) { module in
                                            Button(module.isProjectRoot ? "项目根目录" : module.name) { model.moveNote(note.id, to: module.id) }
                                                .disabled(module.id == note.moduleID)
                                        }
                                    }
                                    Button(role: .destructive) {
                                        requestDeletion(for: note)
                                    } label: {
                                        Label(deletionMenuTitle(for: note), systemImage: "trash")
                                    }
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        case .foldGroup(let group):
                            FoldGroupRow(
                                count: group.noteIDs.count,
                                isSelected: model.selectedNoteID.map(group.noteIDs.contains) ?? false
                            )
                                .contentShape(Rectangle())
                                .onTapGesture { expand(group) }
                                .pointingHandCursor()
                                .listRowInsets(EdgeInsets(top: 1.5, leading: 6, bottom: 1.5, trailing: 6))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .contextMenu {
                                    Button {
                                        expand(group)
                                    } label: {
                                        Label("展开全部文件", systemImage: "rectangle.expand.vertical")
                                    }
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 24)
                .animation(.easeInOut(duration: 0.24), value: model.noteFoldGroups)
                .onExitCommand { resetRangeSelection() }
            }
        }
    }

    private var searchList: some View {
        Group {
            if model.searchResults.isEmpty {
                EmptyStateView(title: "没有搜索结果", systemImage: "magnifyingglass", description: "没有找到“\(model.searchQuery)”；可以换一个关键词或搜索范围。")
            } else {
                List(model.searchResults) { result in
                    Button { model.openSearchResult(result) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.noteTitle)
                                .font(AppTypography.rowTitleStrong)
                                .foregroundStyle(.primary)
                            Text(result.excerpt)
                                .font(AppTypography.secondary)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(result.path)
                                .font(AppTypography.tertiary)
                                .foregroundStyle(Theme.accent)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .listRowSeparator(.hidden)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Section("排序字段") {
                ForEach(NoteListSortMode.allCases) { mode in
                    Button {
                        sortModeRawValue = mode.rawValue
                    } label: {
                        HStack {
                            Text(mode.title)
                            Spacer()
                            if mode == sortMode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Section("排序方向") {
                ForEach(NoteListSortDirection.allCases) { direction in
                    Button {
                        sortDirectionRawValue = direction.rawValue
                    } label: {
                        HStack {
                            Label(direction.title, systemImage: direction.symbolName)
                            Spacer()
                            if direction == sortDirection {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .help("选择排序字段和方向")
        .accessibilityLabel("文件排序")
        .accessibilityValue("\(sortMode.title)，\(sortDirection.title)")
        .pointingHandCursor()
    }

    private func areNotesOrdered(_ lhs: Note, _ rhs: Note) -> Bool {
        let primaryOrder: ComparisonResult
        switch sortMode {
        case .fileName:
            primaryOrder = displayName(for: lhs).localizedStandardCompare(displayName(for: rhs))
        case .createdAt:
            primaryOrder = lhs.createdAt == rhs.createdAt
                ? .orderedSame
                : (lhs.createdAt < rhs.createdAt ? .orderedAscending : .orderedDescending)
        case .updatedAt:
            primaryOrder = lhs.updatedAt == rhs.updatedAt
                ? .orderedSame
                : (lhs.updatedAt < rhs.updatedAt ? .orderedAscending : .orderedDescending)
        }

        let tieBreakOrder = primaryOrder == .orderedSame
            ? displayName(for: lhs).localizedStandardCompare(displayName(for: rhs))
            : primaryOrder
        let resolvedOrder = tieBreakOrder == .orderedSame
            ? lhs.id.uuidString.localizedStandardCompare(rhs.id.uuidString)
            : tieBreakOrder
        return sortDirection == .ascending
            ? resolvedOrder == .orderedAscending
            : resolvedOrder == .orderedDescending
    }

    private func displayName(for note: Note) -> String {
        note.title.isEmpty ? "未命名笔记" : note.title
    }

    private func select(_ note: Note) {
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        rangeSelection.select(
            note.id,
            orderedIDs: sortedNotes.map(\.id),
            extendingRange: modifiers.contains(.shift),
            fallbackAnchorID: model.selectedNoteID
        )
        model.selectNote(note.id)
    }

    private func quickFoldSelection() {
        let orderedNoteIDs = sortedNotes.map(\.id).filter(rangeSelection.selectedIDs.contains)
        guard orderedNoteIDs.count >= 2 else { return }
        withAnimation(.easeInOut(duration: 0.24)) {
            if model.quickFoldNotes(orderedNoteIDs) {
                resetRangeSelection()
            }
        }
    }

    private func deletionMenuTitle(for note: Note) -> String {
        let count = rangeSelection.resolvedActionIDs(
            for: note.id,
            orderedIDs: sortedNotes.map(\.id)
        ).count
        return count == 1 ? "删除" : "删除 \(count) 个文件"
    }

    private func requestDeletion(for note: Note) {
        let noteByID = Dictionary(uniqueKeysWithValues: sortedNotes.map { ($0.id, $0) })
        let notes = rangeSelection.resolvedActionIDs(
            for: note.id,
            orderedIDs: sortedNotes.map(\.id)
        ).compactMap { noteByID[$0] }
        deletionRequest = NoteDeletionRequest(notes: notes.isEmpty ? [note] : notes)
    }

    private func confirmDeletion(_ request: NoteDeletionRequest) {
        if model.deleteNotes(request.notes.map(\.id)) {
            resetRangeSelection()
        }
    }

    private func expand(_ group: NoteFoldGroup) {
        let selectedMemberID = model.selectedNoteID.flatMap { group.noteIDs.contains($0) ? $0 : nil }
        withAnimation(.easeInOut(duration: 0.24)) {
            model.expandNoteFoldGroup(group.id)
            if let selectedMemberID { model.selectNote(selectedMemberID) }
            resetRangeSelection()
        }
    }

    private func resetRangeSelection() {
        rangeSelection.reset()
    }
}

private struct NoteRow: View {
    let note: Note
    let isSelected: Bool
    let isRangeSelected: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: fileIcon)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(fileColor)
            Text(note.title.isEmpty ? "未命名笔记" : note.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.90))
                .lineLimit(1)
            Spacer()
            Text(note.updatedAt, style: .time)
                .font(.system(size: 11, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(Color.secondary.opacity(0.58))
        }
        .padding(.vertical, 4.5)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            NoteListRowBackground(
                color: backgroundColor,
                showsAccent: isSelected,
                accentOpacity: 0.88
            )
        }
        .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        if isSelected { return Theme.accent.opacity(0.07) }
        if isRangeSelected { return Theme.accent.opacity(0.04) }
        if isHovering { return Color.primary.opacity(0.035) }
        return Color.clear
    }

    private var fileIcon: String {
        switch note.kind {
        case .markdown: "doc.text"
        case .request: "bolt.horizontal.circle"
        case .websocket: "arrow.left.arrow.right.circle"
        case .connection: "cylinder"
        }
    }

    private var fileColor: Color {
        switch note.kind {
        case .request: .orange
        case .websocket: .blue
        case .connection: .teal
        case .markdown: Color.secondary.opacity(0.68)
        }
    }

}

private struct FoldGroupRow: View {
    let count: Int
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "rectangle.compress.vertical")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.accent.opacity(0.82))
            Text("折叠 \(count) 个文件")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.90))
            Spacer()
            HStack(spacing: 4) {
                Text("点击展开")
                    .font(.system(size: 11, weight: .regular))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Color.secondary.opacity(0.58))
        }
        .padding(.vertical, 4.5)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            NoteListRowBackground(
                color: isSelected
                    ? Theme.accent.opacity(0.07)
                    : (isHovering ? Color.primary.opacity(0.035) : Color.primary.opacity(0.018)),
                showsAccent: isSelected,
                accentOpacity: 0.88
            )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Theme.accent.opacity(isSelected ? 0.14 : 0.08), lineWidth: 0.5)
        }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("折叠 \(count) 个文件，点击展开")
    }
}

private struct NoteListRowBackground: View {
    let color: Color
    let showsAccent: Bool
    let accentOpacity: Double

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color)
            if showsAccent {
                Capsule()
                    .fill(Theme.accent.opacity(accentOpacity))
                    .frame(width: 2, height: 14)
                    .padding(.leading, 2)
            }
        }
    }
}

private struct RenameNoteSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let note: Note
    @State private var title: String

    init(note: Note) {
        self.note = note
        _title = State(initialValue: note.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("重命名笔记").font(AppTypography.sheetTitle)
            TextField("标题", text: $title)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .pointingHandCursor()
                Button("保存") {
                    model.rename(kind: .note, id: note.id, to: title)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .pointingHandCursor()
            }
        }
        .padding(22)
        .frame(width: 380)
    }
}
