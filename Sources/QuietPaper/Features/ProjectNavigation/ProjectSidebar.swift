import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct RenameTarget: Identifiable {
    let id: UUID
    let kind: DeletedItemKind
    let currentName: String
}

private struct DeleteTarget: Identifiable {
    let id: UUID
    let kind: DeletedItemKind
    let name: String
}

private enum BulkExportTarget: Identifiable {
    case project(Project)
    case module(NoteModule)

    var id: UUID {
        switch self {
        case .project(let project): project.id
        case .module(let module): module.id
        }
    }

    var name: String {
        switch self {
        case .project(let project): project.name
        case .module(let module): module.name
        }
    }
}

struct ProjectSidebar: View {
    @EnvironmentObject private var model: AppModel
    @Binding var expanded: Set<UUID>
    @State private var renameTarget: RenameTarget?
    @State private var deleteTarget: DeleteTarget?
    @State private var exportTarget: BulkExportTarget?
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("项目")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    if let item = model.createProject() {
                        expanded.insert(item.id)
                        renameTarget = .init(id: item.id, kind: .project, currentName: item.name)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("新建项目")
                .accessibilityLabel("新建项目")
                .pointingHandCursor()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.projects) { project in
                        SidebarProjectRow(
                            project: project,
                            isExpanded: expanded.contains(project.id),
                            isSelected: project.id == model.selectedProjectID
                                && (model.selectedModuleID == nil || (model.selectedModule?.isProjectRoot == true && model.selectedNoteID == nil)),
                            onDisclose: {
                                if expanded.contains(project.id) {
                                    expanded.remove(project.id)
                                } else {
                                    expanded.insert(project.id)
                                }
                            },
                            onSelect: {
                                model.selectProject(project.id)
                            },
                            onCreateModule: {
                                if let item = model.createModule(projectID: project.id) {
                                    renameTarget = .init(id: item.id, kind: .module, currentName: item.name)
                                }
                            },
                            onCreateFile: {
                                _ = model.createProjectFile(projectID: project.id)
                            },
                            onCreateRequest: {
                                _ = model.createProjectRequest(projectID: project.id)
                            },
                            onCreateConnection: {
                                _ = model.createProjectConnection(projectID: project.id)
                            },
                            onExport: { exportTarget = .project(project) },
                            onRename: { renameTarget = .init(id: project.id, kind: .project, currentName: project.name) },
                            onDelete: { deleteTarget = .init(id: project.id, kind: .project, name: project.name) }
                        )
                        if expanded.contains(project.id) {
                            ForEach(model.projectFiles(in: project.id)) { note in
                                SidebarProjectFileRow(
                                    note: note,
                                    isSelected: note.id == model.selectedNoteID && model.selectedModule?.isProjectRoot == true,
                                    onSelect: { model.selectProjectFile(note.id, projectID: project.id) },
                                    onRename: { renameTarget = .init(id: note.id, kind: .note, currentName: note.title) },
                                    onDelete: { deleteTarget = .init(id: note.id, kind: .note, name: note.title) }
                                )
                            }
                            ForEach(model.visibleModules(in: project.id)) { item in
                                SidebarModuleRow(
                                    module: item,
                                    isSelected: item.id == model.selectedModuleID,
                                    onExport: { exportTarget = .module(item) },
                                    onRename: { renameTarget = .init(id: item.id, kind: .module, currentName: item.name) },
                                    onDelete: { deleteTarget = .init(id: item.id, kind: .module, name: item.name) }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
            }

            HairlineDivider()
            Button {
                showSettings = true
            } label: {
                Label("设置", systemImage: "gearshape")
                    .font(AppTypography.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .pointingHandCursor()
        }
        .background(Theme.background)
        .sheet(item: $renameTarget) { target in
            RenameSheet(title: target.kind == .note ? "重命名文件" : "重命名\(target.kind.rawValue)", initialValue: target.currentName) { name in
                model.rename(kind: target.kind, id: target.id, to: name)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(model)
        }
        .alert("移到最近删除？", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        ), presenting: deleteTarget) { target in
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { model.delete(kind: target.kind, id: target.id) }
        } message: { target in
            if target.kind == .note {
                Text("“\(target.name)”将移到最近删除。")
            } else {
                Text("“\(target.name)”将移到最近删除。项目或模块中的下级内容也会一同移入。")
            }
        }
        .confirmationDialog(
            exportTarget.map { "导出“\($0.name)”" } ?? "一键导出",
            isPresented: Binding(
                get: { exportTarget != nil },
                set: { if !$0 { exportTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let target = exportTarget {
                Button("合并为一个 Markdown 文件…") { exportMergedMarkdown(target) }
                Button("分开文件并导出 ZIP…") { exportSeparateArchive(target) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("请选择将全部文件合并导出，或按项目与模块结构分别保存后打包。请求或连接配置也会导出，可能包含敏感信息。")
        }
        .onAppear {
            if let id = model.selectedProjectID { expanded.insert(id) }
        }
    }

    private func exportMergedMarkdown(_ target: BulkExportTarget) {
        let panel = NSSavePanel()
        if let markdownType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [markdownType]
        }
        panel.nameFieldStringValue = "\(ModuleMarkdownExporter.safeBaseName(target.name, fallback: "一键导出")).md"
        panel.prompt = "导出"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            switch target {
            case .project(let project): try model.exportProjectAsMergedMarkdown(project, to: url)
            case .module(let module): try model.exportModuleAsMergedMarkdown(module, to: url)
            }
        } catch {
            model.startupError = error.localizedDescription
        }
    }

    private func exportSeparateArchive(_ target: BulkExportTarget) {
        let panel = NSSavePanel()
        if let zipType = UTType(filenameExtension: "zip") {
            panel.allowedContentTypes = [zipType]
        }
        panel.nameFieldStringValue = "\(ModuleMarkdownExporter.safeBaseName(target.name, fallback: "一键导出")).zip"
        panel.prompt = "导出"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            switch target {
            case .project(let project): try model.exportProjectAsArchive(project, to: url)
            case .module(let module): try model.exportModuleAsArchive(module, to: url)
            }
        } catch {
            model.startupError = error.localizedDescription
        }
    }
}

private struct SidebarProjectRow: View {
    @EnvironmentObject private var model: AppModel
    let project: Project
    let isExpanded: Bool
    let isSelected: Bool
    let onDisclose: () -> Void
    let onSelect: () -> Void
    let onCreateModule: () -> Void
    let onCreateFile: () -> Void
    let onCreateRequest: () -> Void
    let onCreateConnection: () -> Void
    let onExport: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            Button(action: onDisclose) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8.5, weight: .semibold))
                    .frame(width: 10)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            HStack(spacing: 5) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Theme.accent : .secondary)
                Text(project.name)
                    .font(AppTypography.rowTitle)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onDisclose)
            .onTapGesture(count: 1, perform: onSelect)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4.5)
        .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .pointingHandCursor()
        .contextMenu {
            Button("新建文件", action: onCreateFile)
            Button("新建请求", action: onCreateRequest)
            Button("新建连接", action: onCreateConnection)
            Button("新建模块", action: onCreateModule)
            Divider()
            Button("一键导出…", action: onExport)
            Divider()
            Button("重命名", action: onRename)
            Button("上移") { model.moveProject(project.id, offset: -1) }
            Button("下移") { model.moveProject(project.id, offset: 1) }
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
    }

    private var backgroundStyle: Color {
        if isSelected { return Theme.accent.opacity(0.10) }
        if isHovering { return Color.primary.opacity(0.05) }
        return Color.clear
    }
}

private struct SidebarProjectFileRow: View {
    let note: Note
    let isSelected: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: fileIcon)
                .font(.system(size: 11))
                .foregroundStyle(fileColor)
            Text(note.title)
                .font(AppTypography.rowTitle)
                .lineLimit(1)
            Spacer()
        }
        .padding(.leading, 30)
        .padding(.trailing, 6)
        .padding(.vertical, 4.5)
        .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .pointingHandCursor()
        .contextMenu {
            Button("重命名", action: onRename)
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
    }

    private var backgroundStyle: Color {
        if isSelected { return Theme.accent.opacity(0.10) }
        if isHovering { return Color.primary.opacity(0.05) }
        return Color.clear
    }

    private var fileIcon: String {
        switch note.kind {
        case .markdown: "doc.text"
        case .request: "bolt.horizontal.circle"
        case .connection: "cylinder"
        }
    }

    private var fileColor: Color {
        switch note.kind {
        case .request: .orange
        case .connection: .teal
        case .markdown: isSelected ? Theme.accent : .secondary
        }
    }
}

private struct SidebarModuleRow: View {
    @EnvironmentObject private var model: AppModel
    let module: NoteModule
    let isSelected: Bool
    let onExport: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Theme.accent : .secondary)
            Text(module.name)
                .font(AppTypography.rowTitle)
                .lineLimit(1)
            Spacer()
        }
        .padding(.leading, 30)
        .padding(.trailing, 6)
        .padding(.vertical, 4.5)
        .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { model.selectModule(module.id) }
        .onHover { isHovering = $0 }
        .pointingHandCursor()
        .contextMenu {
            Button("新建文件") { _ = model.createNote() }
            Button("新建请求") { _ = model.createRequest() }
            Button("新建连接") { _ = model.createConnection() }
            Divider()
            Button("一键导出…", action: onExport)
            Divider()
            Button("重命名", action: onRename)
            Button("上移") { model.moveModule(module.id, offset: -1) }
            Button("下移") { model.moveModule(module.id, offset: 1) }
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
    }

    private var backgroundStyle: Color {
        if isSelected { return Theme.accent.opacity(0.10) }
        if isHovering { return Color.primary.opacity(0.05) }
        return Color.clear
    }
}

private struct RenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let initialValue: String
    let onSave: (String) -> Void
    @State private var value: String

    init(title: String, initialValue: String, onSave: @escaping (String) -> Void) {
        self.title = title
        self.initialValue = initialValue
        self.onSave = onSave
        _value = State(initialValue: initialValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(AppTypography.sheetTitle)
            TextField("名称", text: $value)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .pointingHandCursor()
                Button("保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .pointingHandCursor()
            }
        }
        .padding(22)
        .frame(width: 380)
    }

    private func save() {
        onSave(value)
        dismiss()
    }
}
