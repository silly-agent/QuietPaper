import SwiftUI

struct WebSocketRequestEditorView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let note = model.selectedNote {
            WebSocketRequestWorkspace(note: note) { content in
                model.setDraftContent(content)
            }
            .id(note.id)
        } else {
            EmptyStateView(title: "没有选择请求", systemImage: "arrow.left.arrow.right.circle", description: "选择或新建一个 WebSocket 请求。")
        }
    }
}

private struct WebSocketRequestWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var session = WebSocketSessionModel()
    @State private var draft: WebSocketRequestDraft
    @State private var outgoingMessage = ""
    @State private var configurationExpanded = true
    @FocusState private var messageFocused: Bool
    let onSave: (String) -> Void

    init(note: Note, onSave: @escaping (String) -> Void) {
        _draft = State(initialValue: WebSocketRequestDraft.decode(note.contentMarkdown))
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HairlineDivider()
            VStack(spacing: 0) {
                headersPanel
                HairlineDivider()
                messagePanel
            }
            statusBar
        }
        .background(Theme.background)
        .onDisappear { session.disconnect(showMessage: false) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                Text(model.selectedProject?.name ?? "")
                breadcrumbChevron
                if model.selectedModule?.isProjectRoot != true {
                    Text(model.selectedModule?.name ?? "")
                    breadcrumbChevron
                }
                Label("WebSocket", systemImage: "arrow.left.arrow.right.circle.fill")
                    .foregroundStyle(Color.blue)
                Spacer()
                Text("消息仅保留在当前会话")
                    .font(AppTypography.tertiary)
                    .foregroundStyle(.tertiary)
            }
            .font(AppTypography.secondary)
            .foregroundStyle(.secondary)

            TextField("请求名称", text: Binding(
                get: { model.draftTitle },
                set: { model.setDraftTitle($0) }
            ))
            .textFieldStyle(.plain)
            .font(AppTypography.largeTitle)

            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(session.status.color)
                        .frame(width: 7, height: 7)
                    Text(session.status.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(session.status.color)
                }
                .frame(width: 92)

                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 0.5, height: 28)

                TextField("wss://example.com/events", text: draftBinding(\.url))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 12)
                    .disabled(session.status.isBusy)
                    .onSubmit(toggleConnection)

                Button(action: toggleConnection) {
                    HStack(spacing: 6) {
                        if session.status == .connecting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: session.status == .connected ? "xmark" : "link")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        Text(session.status == .connected ? "断开" : (session.status == .connecting ? "连接中" : "连接"))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(minWidth: 76)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(session.status == .connected ? Color.secondary : Color.blue)
                .disabled(session.status == .connecting)
                .padding(5)
                .pointingHandCursor()
            }
            .frame(height: 44)
            .background(Theme.editor, in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(session.errorMessage == nil ? Color.primary.opacity(0.09) : Color.red.opacity(0.45), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.035), radius: 6, y: 2)

            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(AppTypography.secondary)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    private var headersPanel: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { configurationExpanded.toggle() }
            } label: {
                HStack {
                    Label("连接 Headers", systemImage: "list.bullet.rectangle")
                        .font(AppTypography.rowTitleStrong)
                    Text("\(draft.headers.filter { $0.isEnabled && !$0.key.isEmpty }.count) 项启用")
                        .font(AppTypography.tertiary)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Image(systemName: configurationExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .frame(height: 42)
            .pointingHandCursor()

            if configurationExpanded {
                HairlineDivider()
                HTTPKeyValueEditor(
                    items: draftBinding(\.headers),
                    keyPlaceholder: "Header",
                    valuePlaceholder: "值",
                    addLabel: "添加 Header"
                )
                .frame(minHeight: 118, idealHeight: 150, maxHeight: 180)
                .disabled(session.status.isBusy)
            }
        }
        .background(Theme.control.opacity(0.42))
    }

    private var messagePanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("消息")
                    .font(AppTypography.rowTitleStrong)
                if !session.messages.isEmpty {
                    Text("\(session.messages.count)")
                        .font(AppTypography.tertiary)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if !session.messages.isEmpty {
                    Button("清空") { session.clearMessages() }
                        .buttonStyle(.borderless)
                        .font(AppTypography.secondary)
                        .pointingHandCursor()
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 42)

            HairlineDivider()

            messages
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HairlineDivider()
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messages: some View {
        Group {
            if session.messages.isEmpty {
                EmptyStateView(
                    title: session.status == .connected ? "等待消息" : "尚未连接",
                    systemImage: session.status == .connected ? "dot.radiowaves.left.and.right" : "link.badge.plus",
                    description: session.status == .connected ? "服务端推送的消息会实时显示在这里。" : "填写 ws 或 wss 地址并连接，即可收发文本消息。"
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(session.messages) { message in
                                WebSocketMessageRow(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(18)
                    }
                    .background(Theme.editor.opacity(0.62))
                    .onChange(of: session.messages.count) { _ in
                        guard let last = session.messages.last else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("输入要发送的文本消息…", text: $outgoingMessage)
                .textFieldStyle(.plain)
                .font(AppTypography.monospacedCode)
                .focused($messageFocused)
                .onSubmit(sendMessage)

            Button(action: sendMessage) {
                Label("发送", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.blue)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(session.status != .connected || outgoingMessage.isEmpty)
            .pointingHandCursor()
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Theme.control)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle().fill(session.status.color.opacity(0.8)).frame(width: 5, height: 5)
            Text(session.status.label)
            Spacer()
            Text("配置自动保存在本地 · 消息不写入数据库")
        }
        .font(AppTypography.status)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(Theme.background)
    }

    private var breadcrumbChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.tertiary)
    }

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<WebSocketRequestDraft, Value>) -> Binding<Value> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { value in
                draft[keyPath: keyPath] = value
                persistDraft()
            }
        )
    }

    private func persistDraft() {
        do {
            onSave(try draft.encoded())
            session.errorMessage = nil
        } catch {
            session.errorMessage = "保存请求配置失败：\(error.localizedDescription)"
        }
    }

    private func toggleConnection() {
        if session.status == .connected {
            session.disconnect(showMessage: true)
        } else {
            persistDraft()
            model.forceSave()
            session.connect(draft)
        }
    }

    private func sendMessage() {
        let text = outgoingMessage
        guard !text.isEmpty else { return }
        outgoingMessage = ""
        session.send(text)
        messageFocused = true
    }
}

@MainActor
private final class WebSocketSessionModel: ObservableObject {
    @Published var status: WebSocketConnectionStatus = .disconnected
    @Published var messages: [WebSocketDisplayMessage] = []
    @Published var errorMessage: String?

    private let client = WebSocketClient()
    private var connectionTask: Task<Void, Never>?

    func connect(_ draft: WebSocketRequestDraft) {
        connectionTask?.cancel()
        status = .connecting
        errorMessage = nil
        connectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await client.connect(draft)
                guard !Task.isCancelled else { return }
                status = .connected
                append(.system("已连接到 \(draft.url)"))
                try await receiveMessages()
            } catch {
                guard !Task.isCancelled else { return }
                status = .disconnected
                errorMessage = error.localizedDescription
                append(.system("连接已结束"))
                await client.disconnect()
            }
        }
    }

    func disconnect(showMessage: Bool) {
        connectionTask?.cancel()
        connectionTask = nil
        let wasActive = status != .disconnected
        status = .disconnected
        errorMessage = nil
        if showMessage, wasActive { append(.system("已断开连接")) }
        Task { await client.disconnect() }
    }

    func send(_ text: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await client.send(text: text)
                append(.outgoing(text))
            } catch {
                errorMessage = "发送失败：\(error.localizedDescription)"
            }
        }
    }

    func clearMessages() { messages.removeAll() }

    private func receiveMessages() async throws {
        while !Task.isCancelled {
            let payload = try await client.receive()
            guard !Task.isCancelled else { return }
            append(.incoming(payload.displayText))
        }
    }

    private func append(_ message: WebSocketDisplayMessage) {
        messages.append(message)
    }
}

private enum WebSocketConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected

    var label: String {
        switch self {
        case .disconnected: "未连接"
        case .connecting: "连接中"
        case .connected: "已连接"
        }
    }

    var color: Color {
        switch self {
        case .disconnected: .secondary
        case .connecting: .orange
        case .connected: .green
        }
    }

    var isBusy: Bool { self != .disconnected }
}

private struct WebSocketDisplayMessage: Identifiable {
    enum Direction { case incoming, outgoing, system }

    let id = UUID()
    let direction: Direction
    let text: String
    let createdAt = Date()

    static func incoming(_ text: String) -> Self { .init(direction: .incoming, text: text) }
    static func outgoing(_ text: String) -> Self { .init(direction: .outgoing, text: text) }
    static func system(_ text: String) -> Self { .init(direction: .system, text: text) }
}

private struct WebSocketMessageRow: View {
    let message: WebSocketDisplayMessage

    var body: some View {
        if message.direction == .system {
            HStack(spacing: 7) {
                Capsule().fill(Color.secondary.opacity(0.18)).frame(width: 24, height: 1)
                Text(message.text)
                Text(message.createdAt, style: .time)
                Capsule().fill(Color.secondary.opacity(0.18)).frame(width: 24, height: 1)
            }
            .font(AppTypography.tertiary)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                if message.direction == .outgoing { Spacer(minLength: 70) }
                VStack(alignment: message.direction == .outgoing ? .trailing : .leading, spacing: 4) {
                    Text(message.direction == .outgoing ? "客户端" : "服务端")
                        .font(AppTypography.tertiary)
                        .foregroundStyle(.tertiary)
                    Text(message.text)
                        .font(AppTypography.monospacedCode)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .foregroundStyle(message.direction == .outgoing ? Color.white : Color.primary)
                        .background(
                            message.direction == .outgoing ? Color.blue : Theme.control,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                }
                if message.direction == .incoming { Spacer(minLength: 70) }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
