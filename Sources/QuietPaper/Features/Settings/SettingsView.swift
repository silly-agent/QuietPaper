import AppKit
import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance
    case shortcuts
    case ai
    case storage
    case trash
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: "外观"
        case .shortcuts: "快捷跳转"
        case .ai: "AI"
        case .storage: "存储"
        case .trash: "最近删除"
        case .about: "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: "paintpalette"
        case .shortcuts: "command"
        case .ai: "sparkles"
        case .storage: "externaldrive"
        case .trash: "trash"
        case .about: "info.circle"
        }
    }
}

/// 左侧 Tab 导航的设置面板。每个设置类别拥有独立页面，不再纵向堆叠在同一个滚动区中。
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .appearance

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("设置", systemImage: "gearshape")
                    .font(AppTypography.sheetTitle)
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.small)
                    .pointingHandCursor()
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(Theme.background)

            HairlineDivider()

            HStack(spacing: 0) {
                settingsSidebar
                HairlineDivider(axis: .vertical)
                settingsPages
            }
        }
        .background(model.theme.palette.background)
        .frame(width: 760, height: 540)
    }

    private var settingsSidebar: some View {
        VStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 17)
                        Text(tab.title)
                            .font(AppTypography.rowTitleStrong)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selectedTab == tab ? Theme.accent : Color.primary.opacity(0.78))
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(
                        selectedTab == tab ? Theme.accent.opacity(0.11) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityValue(selectedTab == tab ? "已选择" : "")
                .pointingHandCursor()
            }

            Spacer()

            Text("Quiet Paper \(AppVersion.current)")
                .font(AppTypography.status)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
        }
        .padding(10)
        .frame(width: 168)
        .background(Theme.control)
    }

    /// 页面保持同时挂载，使 API Key 等尚未保存的输入在切换 Tab 后仍然保留。
    private var settingsPages: some View {
        ZStack(alignment: .topLeading) {
            page(for: .appearance) {
                ThemeSection()
            }
            page(for: .shortcuts) {
                QuickJumpSection()
            }
            page(for: .ai) {
                AISettingsSection()
            }
            page(for: .storage) {
                StorageLocationSection()
            }
            page(for: .trash) {
                TrashSection()
            }
            page(for: .about) {
                AboutSection()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.editor)
    }

    private func page<Content: View>(
        for tab: SettingsTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        SettingsPage(
            title: tab.title,
            summary: summary(for: tab),
            content: content
        )
        .opacity(selectedTab == tab ? 1 : 0)
        .allowsHitTesting(selectedTab == tab)
        .accessibilityHidden(selectedTab != tab)
    }

    private func summary(for tab: SettingsTab) -> String {
        switch tab {
        case .appearance: "选择一套克制的界面主题；主题色只用于强调和状态，阅读表面保持清爽。"
        case .shortcuts: "为常用文件配置最多三个全局快捷键，从任意页面快速跳转。"
        case .ai: "配置在线模型，并管理完全在本机生成和检索的笔记索引。"
        case .storage: "查看或更改笔记、附件与搜索索引的本地存储目录。"
        case .trash: "删除的内容默认保留 30 天，可在这里恢复或永久删除。"
        case .about: "查看版本信息，以及 Quiet Paper 的数据与隐私原则。"
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let summary: String
    let content: Content

    init(
        title: String,
        summary: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.summary = summary
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(AppTypography.largeTitle)
                    Text(summary)
                        .font(AppTypography.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct QuickJumpSection: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("QuietPaper.quickJump.1") private var slot1 = ""
    @AppStorage("QuietPaper.quickJump.2") private var slot2 = ""
    @AppStorage("QuietPaper.quickJump.3") private var slot3 = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("页面指笔记、请求或连接文件。可以直接从下方选择，也可以先打开目标页面，再点击“使用当前页面”。")
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(Theme.accent)
            }

            quickJumpRow(slot: 1, targetID: $slot1)
            quickJumpRow(slot: 2, targetID: $slot2)
            quickJumpRow(slot: 3, targetID: $slot3)
        }
    }

    private func quickJumpRow(slot: Int, targetID: Binding<String>) -> some View {
        QuickJumpSlotRow(
            slot: slot,
            targetID: targetID,
            pages: model.allNotes,
            currentNoteID: model.selectedNoteID,
            pathForPage: { model.quickJumpPath(for: $0) }
        )
    }
}

private struct QuickJumpSlotRow: View {
    let slot: Int
    @Binding var targetID: String
    let pages: [Note]
    let currentNoteID: UUID?
    let pathForPage: (Note) -> String

    private var selectedPage: Note? {
        guard let id = UUID(uuidString: targetID) else { return nil }
        return pages.first(where: { $0.id == id })
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("⌘\(slot)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accent)
                .frame(width: 42, height: 34)
                .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text("快捷页面 \(slot)")
                    .font(AppTypography.rowTitleStrong)
                Text(selectedPage.map(pathForPage) ?? (targetID.isEmpty ? "尚未设置" : "原页面已不存在"))
                    .font(AppTypography.tertiary)
                    .foregroundStyle(targetID.isEmpty ? Color.secondary.opacity(0.65) : (selectedPage == nil ? Color.red : Color.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Menu {
                Button("取消设置") { targetID = "" }
                    .disabled(targetID.isEmpty)
                Divider()
                ForEach(pages) { page in
                    Button {
                        targetID = page.id.uuidString
                    } label: {
                        HStack {
                            Text(pathForPage(page))
                            Spacer()
                            if page.id.uuidString == targetID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text("选择页面")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .help("选择要跳转的页面")
            .pointingHandCursor()

            Button("使用当前页面") {
                if let currentNoteID {
                    targetID = currentNoteID.uuidString
                }
            }
            .controlSize(.small)
            .disabled(currentNoteID == nil)
            .help("把当前打开的页面设为快捷页面")
            .pointingHandCursor()
        }
        .padding(12)
        .background(Theme.control, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}

/// 存储位置区块：选择 SQLite 数据库与附件的存放目录。
private struct StorageLocationSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var errorMessage: String?
    @State private var directoryToConfirm: URL?

    private var currentDirectory: URL? {
        model.database.databaseURL?.deletingLastPathComponent()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前存储目录")
                        .font(AppTypography.rowTitleStrong)
                    Text(currentDirectory?.path ?? "内存数据库（未保存到磁盘）")
                        .font(AppTypography.tertiary)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer()
            }
            .padding(12)
            .background(Theme.control, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))

            HStack(spacing: 10) {
                Button("选择目录…") { chooseDirectory() }
                    .controlSize(.small)
                    .pointingHandCursor()
                if currentDirectory?.resolvingSymlinksInPath() != WorkspaceDatabase.defaultStorageDirectory().resolvingSymlinksInPath() {
                    Button("恢复默认位置") { resetToDefault() }
                        .controlSize(.small)
                        .pointingHandCursor()
                }
            }

            Label {
                Text("切换目录会把现有笔记、附件与搜索索引自动迁移到新位置，并作为下次启动使用的存储目录。")
            } icon: {
                Image(systemName: "info.circle")
            }
                .font(AppTypography.tertiary)
                .foregroundStyle(.tertiary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(AppTypography.secondary)
                    .foregroundColor(.red)
            }
        }
        .alert("该目录已包含 Quiet Paper 数据？", isPresented: Binding(
            get: { directoryToConfirm != nil },
            set: { if !$0 { directoryToConfirm = nil } }
        ), presenting: directoryToConfirm) { directory in
            Button("取消", role: .cancel) {}
            Button("替换") { performMigration(to: directory) }
        } message: { directory in
            Text("所选目录中已存在 quiet-paper.sqlite。切换后会把当前数据迁移到该目录，原有文件会保留为备份。")
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择用于存储笔记数据的新目录。现有数据会自动迁移到该目录。"
        panel.directoryURL = currentDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        requestMigration(to: url)
    }

    private func resetToDefault() {
        requestMigration(to: WorkspaceDatabase.defaultStorageDirectory())
    }

    private func requestMigration(to directory: URL) {
        let destination = directory.appendingPathComponent("quiet-paper.sqlite")
        if FileManager.default.fileExists(atPath: destination.path) {
            directoryToConfirm = directory
        } else {
            performMigration(to: directory)
        }
    }

    private func performMigration(to directory: URL) {
        do {
            try model.setStorageDirectory(directory)
            errorMessage = nil
        } catch {
            errorMessage = "存储位置切换失败：\(error.localizedDescription)"
        }
    }
}

/// 关于页面：集中展示版本与本地优先原则。
private struct AboutSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "note.text")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 52, height: 52)
                    .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Quiet Paper")
                        .font(AppTypography.sheetTitle)
                    Text("版本 \(AppVersion.current)")
                        .font(AppTypography.secondary)
                        .foregroundStyle(.secondary)
                }
            }

            HairlineDivider()

            aboutRow(
                icon: "lock.shield",
                title: "本地优先",
                detail: "笔记、附件、搜索和向量索引默认保存在你的 Mac 上。"
            )
            aboutRow(
                icon: "network.slash",
                title: "由你决定何时联网",
                detail: "只有主动使用在线 AI 或发送 HTTP 请求时，应用才会访问网络。"
            )
            aboutRow(
                icon: "externaldrive",
                title: "数据位置透明",
                detail: "你可以在“存储”页面查看和更改数据目录，并自行进行完整备份。"
            )
        }
    }

    private func aboutRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTypography.rowTitleStrong)
                Text(detail)
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
