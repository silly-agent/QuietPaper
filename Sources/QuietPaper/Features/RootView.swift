import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var showAI = false
    @State private var expandedProjects: Set<UUID> = []
    @State private var writingFocus = WritingFocusBlurState()
    @AppStorage(WritingFocusBlurPreference.defaultsKey)
    private var isWritingFocusBlurEnabled = WritingFocusBlurPreference.defaultValue

    var body: some View {
        workspace
        .tint(Theme.accent)
        .toolbarBackground(Theme.background, for: .windowToolbar)
        .searchable(text: $model.searchQuery, placement: .toolbar, prompt: "搜索笔记或输入命令…")
        .onChange(of: model.searchQuery) { _ in model.updateSearch() }
        .onReceive(NotificationCenter.default.publisher(for: .toggleQuietPaperSidebar)) { _ in
            toggleSidebar()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleQuietPaperFocusMode)) { _ in
            toggleFocusMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: .jumpToQuietPaperQuickPage)) { notification in
            guard let slot = notification.userInfo?["slot"] as? Int else { return }
            model.jumpToQuickPage(slot)
        }
        .toolbar {
            if !model.isFocusMode {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAI = true } label: {
                        Label("询问笔记", systemImage: "sparkles")
                    }
                    .help("根据现有笔记回答问题")
                    .pointingHandCursor()
                }
            }
        }
        .toolbar(model.isFocusMode ? .hidden : .automatic, for: .windowToolbar)
        .sheet(isPresented: $showAI) {
            AIQueryView()
                .environmentObject(model)
        }
        .alert("Quiet Paper", isPresented: Binding(
            get: { model.startupError != nil },
            set: { if !$0 { model.startupError = nil } }
        )) {
            Button("好") { model.startupError = nil }
        } message: {
            Text(model.startupError ?? "")
        }
    }

    @ViewBuilder
    private var workspace: some View {
        if model.isFocusMode {
            noteEditor
        } else if model.showsNoteList {
            NavigationSplitView(columnVisibility: $sidebarVisibility) {
                projectSidebar
            } content: {
                NoteListView()
                    .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 390)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        setNavigationHover(hovering, region: .noteList)
                    }
                    .onDisappear {
                        setNavigationHover(false, region: .noteList)
                    }
                    .writingFocusBlur(isActive: shouldBlurNavigation)
            } detail: {
                noteEditor
            }
        } else {
            NavigationSplitView(columnVisibility: $sidebarVisibility) {
                projectSidebar
            } detail: {
                noteEditor
            }
        }
    }

    private var projectSidebar: some View {
        ProjectSidebar(expanded: $expandedProjects)
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 310)
            .contentShape(Rectangle())
            .onHover { hovering in
                setNavigationHover(hovering, region: .projectSidebar)
            }
            .onDisappear {
                setNavigationHover(false, region: .projectSidebar)
            }
            .writingFocusBlur(isActive: shouldBlurNavigation)
    }

    private var noteEditor: some View {
        Group {
            if model.selectedNote?.kind == .request {
                HTTPRequestEditorView()
            } else if model.selectedNote?.kind == .connection {
                DatabaseConnectionEditorView()
            } else {
                NoteEditorView(
                    isFocusMode: model.isFocusMode,
                    isHeaderBlurred: shouldBlurEditorHeader,
                    onHeaderHoverChange: setEditorHeaderHover,
                    onFocusChange: setEditorFocus
                )
            }
        }
    }

    private func setEditorFocus(_ target: WritingEditorFocusTarget, _ focused: Bool) {
        var updated = writingFocus
        updated.setEditorFocus(focused, target: target)
        writingFocus = updated
    }

    private var shouldBlurNavigation: Bool {
        writingFocus.shouldBlurNavigation(isEnabled: isWritingFocusBlurEnabled)
    }

    private var shouldBlurEditorHeader: Bool {
        writingFocus.shouldBlurEditorHeader(isEnabled: isWritingFocusBlurEnabled)
    }

    private func setEditorHeaderHover(_ hovering: Bool) {
        var updated = writingFocus
        updated.setEditorHeaderHover(hovering)
        writingFocus = updated
    }

    private func setNavigationHover(_ hovering: Bool, region: WritingNavigationRegion) {
        var updated = writingFocus
        updated.setNavigationHover(hovering, region: region)
        writingFocus = updated
    }

    private func toggleSidebar() {
        withAnimation {
            if model.isFocusMode {
                model.isFocusMode = false
                sidebarVisibility = .all
                return
            }

            if sidebarVisibility == .all {
                sidebarVisibility = model.showsNoteList ? .doubleColumn : .detailOnly
            } else {
                sidebarVisibility = .all
            }
        }
    }

    private func toggleFocusMode() {
        withAnimation {
            model.isFocusMode.toggle()
            if !model.isFocusMode {
                sidebarVisibility = .all
            }
        }
    }
}
