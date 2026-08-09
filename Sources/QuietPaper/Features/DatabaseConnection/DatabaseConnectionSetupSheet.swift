import AppKit
import SwiftUI

struct DatabaseConnectionSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onComplete: (DatabaseKind, DatabaseConnectionSettings) -> Void
    let initialKind: DatabaseKind?
    let initialSettings: DatabaseConnectionSettings
    let isEditing: Bool
    @State private var selectedKind: DatabaseKind?
    @State private var showWizard: Bool
    @State private var cardRotation = 0.0

    init(
        initialKind: DatabaseKind? = nil,
        initialSettings: DatabaseConnectionSettings = .init(),
        isEditing: Bool = false,
        onComplete: @escaping (DatabaseKind, DatabaseConnectionSettings) -> Void
    ) {
        self.initialKind = initialKind
        self.initialSettings = initialSettings
        self.isEditing = isEditing
        self.onComplete = onComplete
        _selectedKind = State(initialValue: initialKind)
        _showWizard = State(initialValue: initialKind != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(sheetTitle)
                        .font(.system(size: 18, weight: .semibold))
                    Text(showWizard ? "修改后会保存到当前连接文件，并使用新信息重新连接" : "选择一种数据库，开始配置连接")
                        .font(AppTypography.secondary)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .controlSize(.small)
                    .pointingHandCursor()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            HairlineDivider()

            if showWizard, let selectedKind {
                DatabaseTerminalWizard(
                    kind: selectedKind,
                    initialSettings: selectedKind == initialKind ? initialSettings : .init(),
                    isEditing: isEditing
                ) { settings in
                    onComplete(selectedKind, settings)
                    dismiss()
                } onBack: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showWizard = false
                        self.selectedKind = nil
                        cardRotation = 0
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(DatabaseKind.allCases) { kind in
                            DatabaseTypeCard(kind: kind, flipped: selectedKind == kind, rotation: selectedKind == kind ? cardRotation : 0)
                                .onTapGesture { select(kind) }
                                .pointingHandCursor()
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                        Text("连接凭据只由本地连接器读取；AI 不会收到密码或完整连接串。")
                    }
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(22)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .frame(width: 720, height: 560)
        .background(Theme.background)
    }

    private var sheetTitle: String {
        if showWizard, let selectedKind {
            return isEditing ? "编辑 \(selectedKind.title) 连接" : "连接 \(selectedKind.title)"
        }
        return isEditing ? "更换数据库类型" : "新建连接"
    }

    private func select(_ kind: DatabaseKind) {
        guard selectedKind == nil else { return }
        selectedKind = kind
        withAnimation(.spring(response: 0.58, dampingFraction: 0.74)) { cardRotation = 180 }
        Task {
            try? await Task.sleep(for: .milliseconds(520))
            withAnimation(.easeInOut(duration: 0.28)) { showWizard = true }
        }
    }
}

private struct DatabaseTypeCard: View {
    let kind: DatabaseKind
    let flipped: Bool
    let rotation: Double
    @State private var hovering = false

    var body: some View {
        ZStack {
            cardFront.opacity(flipped && rotation > 90 ? 0 : 1)
            cardBack
                .opacity(flipped && rotation > 90 ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        .scaleEffect(hovering && !flipped ? 1.018 : 1)
        .shadow(color: color.opacity(hovering ? 0.18 : 0.08), radius: hovering ? 15 : 8, y: 5)
        .onHover { value in
            withAnimation(.easeOut(duration: 0.18)) { hovering = value }
        }
    }

    private var cardFront: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 13).fill(color.opacity(0.13))
                Image(systemName: kind.systemImage)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 5) {
                Text(kind.title).font(.system(size: 15, weight: .semibold))
                Text(kind.subtitle).font(AppTypography.secondary).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(color.opacity(0.8))
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 124)
        .background(
            LinearGradient(colors: [Theme.control, color.opacity(0.045)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 15)
        )
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(color.opacity(hovering ? 0.35 : 0.12)))
    }

    private var cardBack: some View {
        VStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 27))
                .foregroundStyle(color)
            Text("已选择 \(kind.title)").font(.system(size: 14, weight: .semibold))
            Text("正在打开连接助手…").font(AppTypography.secondary).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 124)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(color.opacity(0.25)))
    }

    private var color: Color {
        switch kind {
        case .mysql: .blue
        case .postgresql: .indigo
        case .redis: .red
        case .sqlite: .teal
        }
    }
}

private struct DatabaseTerminalWizard: View {
    let kind: DatabaseKind
    let isEditing: Bool
    let onComplete: (DatabaseConnectionSettings) -> Void
    let onBack: () -> Void
    @State private var settings: DatabaseConnectionSettings
    @State private var step = 0
    @State private var answer = ""
    @State private var transcript: [(String, String)] = []
    @State private var validation: String?
    @FocusState private var focused: Bool

    init(
        kind: DatabaseKind,
        initialSettings: DatabaseConnectionSettings,
        isEditing: Bool,
        onComplete: @escaping (DatabaseConnectionSettings) -> Void,
        onBack: @escaping () -> Void
    ) {
        self.kind = kind
        self.isEditing = isEditing
        self.onComplete = onComplete
        self.onBack = onBack
        _settings = State(initialValue: initialSettings)
    }

    var body: some View {
        Group {
            if isEditing {
                editForm
            } else {
                terminalFlow
            }
        }
        .onAppear {
            settings.applyDefaults(for: kind)
            answer = defaultAnswer
            focused = true
        }
    }

    private var terminalFlow: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        terminalMessage("你好，我是本地连接助手。凭据会保存在连接文件中，但不会发送给 AI。")
                        ForEach(Array(transcript.enumerated()), id: \.offset) { index, item in
                            terminalMessage(item.0)
                            userMessage(item.1, masked: shouldMask(index: index))
                        }
                        terminalMessage(currentPrompt)
                            .id("current")
                    }
                    .padding(20)
                }
                .onChange(of: step) { _ in withAnimation { proxy.scrollTo("current", anchor: .bottom) } }
            }
            .background(Theme.editor)

            HairlineDivider()
            VStack(spacing: 9) {
                if kind == .sqlite {
                    sqlitePicker
                } else {
                    HStack(spacing: 9) {
                        Group {
                            if isPasswordStep {
                                SecureField(currentPlaceholder, text: $answer)
                            } else {
                                TextField(currentPlaceholder, text: $answer)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(AppTypography.monospacedCode)
                        .focused($focused)
                        .onSubmit(advance)
                        Button(step == prompts.count - 1 ? (isEditing ? "保存并连接" : "完成") : "继续", action: advance)
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .pointingHandCursor()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Theme.control, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.07)))
                }
                if let validation {
                    Text(validation).font(AppTypography.secondary).foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button(isEditing ? "更换数据库类型" : "返回选择") { onBack() }
                        .buttonStyle(.plain)
                        .font(AppTypography.secondary)
                        .foregroundStyle(.secondary)
                        .pointingHandCursor()
                    Spacer()
                    Text("第 \(min(step + 1, prompts.count)) / \(prompts.count) 步")
                        .font(AppTypography.tertiary)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .background(Theme.background)
        }
    }

    private var editForm: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("已回显当前保存的连接信息")
                                .font(.system(size: 14, weight: .semibold))
                            Text("修改后会先关闭旧连接，再保存这些信息并重新连接。")
                                .font(AppTypography.secondary)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 12))

                    if kind == .sqlite {
                        sqliteEditFields
                    } else {
                        serverEditFields
                    }

                    if let validation {
                        Text(validation)
                            .font(AppTypography.secondary)
                            .foregroundStyle(Color.red)
                    }
                }
                .padding(22)
            }

            HairlineDivider()
            HStack {
                Button("更换数据库类型") { onBack() }
                    .buttonStyle(.plain)
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
                    .pointingHandCursor()
                Spacer()
                Button("保存并重新连接", action: saveEditedSettings)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .pointingHandCursor()
            }
            .padding(16)
            .background(Theme.background)
        }
    }

    private var serverEditFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                editField("主机地址") {
                    TextField("例如 127.0.0.1", text: $settings.host)
                }
                editField("端口") {
                    TextField("端口", value: $settings.port, format: .number.grouping(.never))
                        .frame(width: 130)
                }
            }
            HStack(spacing: 14) {
                editField(kind == .redis ? "ACL 用户名（可选）" : "用户名") {
                    TextField(kind == .redis ? "可选" : "用户名", text: $settings.username)
                }
                editField("密码（仅保存在本地）") {
                    SecureField("可选", text: $settings.password)
                }
            }
            if kind == .redis {
                editField("数据库编号") {
                    TextField("0", value: $settings.redisDatabase, format: .number)
                        .frame(width: 130)
                }
            } else {
                editField(kind == .mysql ? "数据库（可选）" : "数据库") {
                    TextField(kind == .mysql ? "留空后选择或新建" : "postgres", text: $settings.database)
                }
                Toggle("使用 TLS 加密连接", isOn: $settings.useTLS)
                    .font(AppTypography.secondary)
            }
        }
    }

    private var sqliteEditFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            editField("SQLite 文件路径") {
                TextField("例如 ~/Documents/database.sqlite", text: $settings.sqlitePath)
                    .font(AppTypography.monospacedCode)
            }
            HStack {
                Button { chooseSQLite(create: false) } label: { Label("更换文件", systemImage: "folder") }
                    .pointingHandCursor()
                Button { chooseSQLite(create: true) } label: { Label("新建数据库", systemImage: "plus.square") }
                    .pointingHandCursor()
                Spacer()
                Text("也可以直接输入完整路径或 ~/ 开头的路径")
                    .font(AppTypography.tertiary)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func editField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppTypography.secondary)
                .foregroundStyle(.secondary)
            content()
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveEditedSettings() {
        validation = nil
        if kind == .sqlite {
            completeSQLitePath()
            return
        }

        settings.host = settings.host.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.username = settings.username.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.database = settings.database.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !settings.host.isEmpty else { validation = "主机地址不能为空"; return }
        guard (1...65_535).contains(settings.port) else { validation = "请输入 1 到 65535 之间的端口"; return }
        guard kind == .redis || !settings.username.isEmpty else { validation = "用户名不能为空"; return }
        guard kind != .postgresql || !settings.database.isEmpty else { validation = "数据库名不能为空"; return }
        guard kind != .redis || settings.redisDatabase >= 0 else { validation = "数据库编号不能小于 0"; return }
        onComplete(settings)
    }

    private var prompts: [(prompt: String, placeholder: String)] {
        switch kind {
        case .mysql:
            [("MySQL 主机地址是什么？", "例如 127.0.0.1"), ("端口是多少？", "3306"), ("请输入用户名。", "root"), ("请输入密码；没有密码可以直接继续。", "密码（可选）"), ("要直接连接哪个数据库？留空后，我会让你选择已有数据库或新建数据库。", "数据库名（可选）")]
        case .postgresql:
            [("PostgreSQL 主机地址是什么？", "例如 127.0.0.1"), ("端口是多少？", "5432"), ("请输入用户名。", "postgres"), ("请输入密码；没有密码可以直接继续。", "密码（可选）"), ("要连接哪个数据库？", "postgres")]
        case .redis:
            [("Redis 主机地址是什么？", "例如 127.0.0.1"), ("端口是多少？", "6379"), ("请输入 ACL 用户名；没有可以直接继续。", "用户名（可选）"), ("请输入密码；没有可以直接继续。", "密码（可选）"), ("使用哪个数据库编号？", "0")]
        case .sqlite:
            [("请选择已有的 SQLite 文件，或创建一个新的数据库文件。", "SQLite 文件")]
        }
    }

    private var currentPrompt: String { prompts[min(step, prompts.count - 1)].prompt }
    private var currentPlaceholder: String { prompts[min(step, prompts.count - 1)].placeholder }
    private var isPasswordStep: Bool { step == 3 && kind != .sqlite }
    private var defaultAnswer: String {
        switch step {
        case 0: settings.host
        case 1: String(settings.port)
        case 2: settings.username
        case 3: settings.password
        case 4 where kind == .redis: String(settings.redisDatabase)
        case 4: settings.database
        default: ""
        }
    }

    private func advance() {
        validation = nil
        let value = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if step == 0 && value.isEmpty { validation = "主机地址不能为空"; return }
        if step == 1 && (Int(value) == nil || !(1...65_535).contains(Int(value) ?? 0)) { validation = "请输入 1 到 65535 之间的端口"; return }
        if step == 2 && kind != .redis && value.isEmpty { validation = "用户名不能为空"; return }
        if step == 4 && kind == .postgresql && value.isEmpty { validation = "数据库名不能为空"; return }
        if step == 4 && kind == .redis && (Int(value) == nil || (Int(value) ?? -1) < 0) { validation = "请输入不小于 0 的数据库编号"; return }

        apply(value)
        transcript.append((currentPrompt, value.isEmpty ? "（留空）" : value))
        if step == prompts.count - 1 {
            onComplete(settings)
        } else {
            step += 1
            answer = defaultAnswer
            focused = true
        }
    }

    private func apply(_ value: String) {
        switch step {
        case 0: settings.host = value
        case 1: settings.port = Int(value) ?? kind.defaultPort
        case 2: settings.username = value
        case 3: settings.password = value
        case 4 where kind == .redis: settings.redisDatabase = Int(value) ?? 0
        case 4: settings.database = value
        default: break
        }
    }

    private func shouldMask(index: Int) -> Bool { index == 3 && kind != .sqlite }

    private func terminalMessage(_ value: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            Text(value)
                .font(AppTypography.body)
                .bodyTracking()
                .lineSpacing(3)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 10))
            Spacer(minLength: 80)
        }
    }

    private func userMessage(_ value: String, masked: Bool) -> some View {
        HStack {
            Spacer(minLength: 100)
            Text(masked && value != "（留空）" ? String(repeating: "•", count: max(8, min(value.count, 18))) : value)
                .font(AppTypography.monospacedCode)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            Image(systemName: "person.crop.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
        }
    }

    private var sqlitePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SQLite 文件路径")
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
                TextField("例如 ~/Documents/database.sqlite", text: $settings.sqlitePath)
                    .font(AppTypography.monospacedCode)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(completeSQLitePath)
            }
            HStack {
                Button { chooseSQLite(create: false) } label: { Label(isEditing ? "更换文件" : "选择已有文件", systemImage: "folder") }
                    .pointingHandCursor()
                Button { chooseSQLite(create: true) } label: { Label("新建数据库", systemImage: "plus.square") }
                    .pointingHandCursor()
                Spacer()
                Button(isEditing ? "保存并连接" : "使用此路径并连接", action: completeSQLitePath)
                    .buttonStyle(.borderedProminent)
                    .disabled(settings.sqlitePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .pointingHandCursor()
            }
        }
    }

    private func chooseSQLite(create: Bool) {
        if create {
            let panel = NSSavePanel()
            panel.title = "新建 SQLite 数据库"
            panel.nameFieldStringValue = "database.sqlite"
            panel.allowedContentTypes = [.database]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            settings.sqlitePath = url.path
        } else {
            let panel = NSOpenPanel()
            panel.title = "选择 SQLite 数据库"
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.database, .data]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            settings.sqlitePath = url.path
        }
        if !isEditing {
            completeSQLitePath()
        }
    }

    private func completeSQLitePath() {
        validation = nil
        let clean = settings.sqlitePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            validation = "请输入 SQLite 文件路径"
            return
        }
        let normalizedPath = DatabaseConnectionSettings.normalizedSQLitePath(clean)
        let url = URL(fileURLWithPath: normalizedPath)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            validation = "请输入数据库文件路径，不能选择文件夹"
            return
        }
        settings.sqlitePath = url.path
        transcript.append((currentPrompt, url.path))
        onComplete(settings)
    }
}

struct MySQLDatabaseChooser: View {
    @Environment(\.dismiss) private var dismiss
    let databases: [String]
    let onChoose: (String) -> Void
    let onCreate: (String) -> Void
    @State private var selection = ""
    @State private var newDatabase = ""
    @State private var mode = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("选择或新建数据库", systemImage: "cylinder.split.1x2")
                .font(AppTypography.sheetTitle)
            Text("MySQL 服务器连接成功，但连接文件尚未指定数据库。")
                .font(AppTypography.secondary)
                .foregroundStyle(.secondary)
            Picker("操作", selection: $mode) {
                Text("选择已有数据库").tag(0)
                Text("新建数据库").tag(1)
            }
            .pickerStyle(.segmented)
            if mode == 0 {
                Picker("数据库", selection: $selection) {
                    Text("请选择…").tag("")
                    ForEach(databases, id: \.self) { Text($0).tag($0) }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("数据库名称", text: $newDatabase).textFieldStyle(.roundedBorder)
                    Text("固定使用 utf8mb4 / utf8mb4_general_ci")
                        .font(AppTypography.tertiary).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button(mode == 0 ? "连接" : "新建并连接") {
                    if mode == 0 { onChoose(selection) } else { onCreate(newDatabase) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(mode == 0 ? selection.isEmpty : newDatabase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
                .pointingHandCursor()
            }
        }
        .padding(22)
        .frame(width: 480)
    }
}
