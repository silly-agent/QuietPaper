import AppKit
import SwiftUI

struct HTTPRequestEditorView: View {
    private enum ConfigurationTab: String, CaseIterable, Identifiable {
        case parameters = "参数"
        case headers = "Headers"
        case body = "Body"
        var id: Self { self }
    }

    private enum ResponseTab: String, CaseIterable, Identifiable {
        case body = "Body"
        case headers = "Headers"
        var id: Self { self }
    }

    @EnvironmentObject private var model: AppModel
    @State private var draft = HTTPRequestDraft()
    @State private var configurationTab: ConfigurationTab = .parameters
    @State private var responseTab: ResponseTab = .body
    @State private var response: HTTPResponseSnapshot?
    @State private var isDisplayingSavedResponse = false
    @State private var errorMessage: String?
    @State private var isSending = false
    @State private var loadedNoteID: UUID?
    @State private var requestTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            HairlineDivider()
            VSplitView {
                configurationPanel
                    .frame(minHeight: 220, idealHeight: 330)
                responsePanel
                    .frame(minHeight: 190, idealHeight: 300)
            }
            HairlineDivider()
            statusBar
        }
        .background(Theme.background)
        .onAppear(perform: loadDraft)
        .onChange(of: model.selectedNoteID) { _ in
            cancelRequest(showMessage: false)
            loadDraft()
        }
        .onDisappear { requestTask?.cancel() }
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
                Label("请求", systemImage: "bolt.horizontal.circle.fill")
                    .foregroundStyle(Color.orange)
                Spacer()
                Text("⌘↩ 发送")
                    .font(AppTypography.tertiary)
                    .foregroundStyle(.tertiary)
            }
            .font(AppTypography.secondary)
            .foregroundStyle(.secondary)

            TextField("请求名称", text: Binding(
                get: { model.draftTitle },
                set: { value in model.setDraftTitle(value) }
            ))
            .textFieldStyle(.plain)
            .font(AppTypography.largeTitle)

            HStack(spacing: 0) {
                Picker("方法", selection: methodBinding) {
                    ForEach(HTTPMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.large)
                .frame(width: 104)
                .tint(methodColor)
                .pointingHandCursor()

                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 0.5, height: 28)

                TextField("https://api.example.com/resource", text: fieldBinding(\.url))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 12)
                    .onSubmit(send)

                if isSending {
                    Button("取消") { cancelRequest(showMessage: true) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .pointingHandCursor()
                }

                Button(action: send) {
                    HStack(spacing: 6) {
                        if isSending {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 10.5))
                        }
                        Text(isSending ? "发送中" : "发送")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(minWidth: 74)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.orange)
                .disabled(isSending)
                .keyboardShortcut(.return, modifiers: [.command])
                .padding(5)
                .pointingHandCursor()
            }
            .frame(height: 44)
            .background(Theme.editor, in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(errorMessage == nil ? Color.primary.opacity(0.09) : Color.red.opacity(0.45), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.035), radius: 6, y: 2)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(AppTypography.secondary)
                    .foregroundStyle(.red)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    private var breadcrumbChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.tertiary)
    }

    private var configurationPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                ForEach(ConfigurationTab.allCases) { tab in
                    if tab == .parameters {
                        parameterTabButton(selected: configurationTab == tab) {
                            configurationTab = tab
                        }
                    } else {
                        tabButton(tab.rawValue, selected: configurationTab == tab) {
                            configurationTab = tab
                        }
                    }
                }
                Spacer()
                switch configurationTab {
                case .parameters:
                    countLabel(draft.queryItems.filter { $0.isEnabled && !$0.key.isEmpty }.count)
                case .headers:
                    countLabel(draft.headers.filter { $0.isEnabled && !$0.key.isEmpty }.count)
                case .body:
                    Text(draft.bodyMode.label)
                        .font(AppTypography.tertiary)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 42)

            HairlineDivider()

            Group {
                switch configurationTab {
                case .parameters:
                    HTTPKeyValueEditor(
                        items: fieldBinding(\.queryItems),
                        keyPlaceholder: "参数名",
                        valuePlaceholder: "值",
                        addLabel: "添加参数"
                    )
                case .headers:
                    HTTPKeyValueEditor(
                        items: fieldBinding(\.headers),
                        keyPlaceholder: "Header",
                        valuePlaceholder: "值",
                        addLabel: "添加 Header"
                    )
                case .body:
                    bodyEditor
                }
            }
        }
        .background(Theme.control.opacity(0.42))
    }

    private var bodyEditor: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("正文类型", selection: fieldBinding(\.bodyMode)) {
                    ForEach(HTTPBodyMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 210)
                .pointingHandCursor()
                Spacer()
                if draft.bodyMode == .json && !draft.body.isEmpty {
                    Button("格式化") { formatRequestJSON() }
                        .buttonStyle(.borderless)
                        .font(AppTypography.secondary)
                        .pointingHandCursor()
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 42)

            HairlineDivider()

            if draft.bodyMode == .none {
                EmptyStateView(title: "此请求没有正文", systemImage: "text.page.slash", description: "选择 JSON 或文本即可添加请求正文。")
            } else {
                TextEditor(text: fieldBinding(\.body))
                    .font(AppTypography.monospacedCode)
                    .scrollContentBackground(.hidden)
                    .padding(14)
                    .background(Theme.editor.opacity(0.72))
            }
        }
    }

    private var responsePanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                ForEach(ResponseTab.allCases) { tab in
                    tabButton(tab.rawValue, selected: responseTab == tab) {
                        responseTab = tab
                    }
                }
                Spacer()
                if let response {
                    if isDisplayingSavedResponse, let saved = draft.savedResponse {
                        Label("已保存", systemImage: "checkmark.circle.fill")
                            .font(AppTypography.tertiary)
                            .foregroundStyle(.green)
                            .help("保存于 \(saved.savedAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                    responseMetric("\(response.statusCode)", color: statusColor(response.statusCode))
                    responseMetric(durationLabel(response.duration), color: .secondary)
                    responseMetric(ByteCountFormatter.string(fromByteCount: Int64(response.size), countStyle: .file), color: .secondary)
                    Button {
                        saveResponse(response)
                    } label: {
                        Label(isDisplayingSavedResponse ? "已保存" : (draft.savedResponse == nil ? "保存响应" : "覆盖保存"), systemImage: isDisplayingSavedResponse ? "checkmark" : "square.and.arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .font(AppTypography.secondary)
                    .disabled(isDisplayingSavedResponse)
                    .pointingHandCursor()
                    Button { copyResponse() } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("复制响应")
                    .pointingHandCursor()
                    if draft.savedResponse != nil {
                        Menu {
                            Button("移除已保存响应", role: .destructive, action: removeSavedResponse)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .help("响应操作")
                        .pointingHandCursor()
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 42)

            HairlineDivider()

            if isSending && response == nil {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在等待服务器响应…")
                        .font(AppTypography.secondary)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let response {
                responseContent(response)
            } else {
                EmptyStateView(title: "准备就绪", systemImage: "arrow.up.right", description: "填写 URL 后发送请求，响应会显示在这里。")
            }
        }
        .background(Theme.background)
    }

    @ViewBuilder
    private func responseContent(_ response: HTTPResponseSnapshot) -> some View {
        switch responseTab {
        case .body:
            if response.body.isEmpty {
                EmptyStateView(title: "空响应", systemImage: "tray", description: "服务器已响应，但没有返回正文。")
            } else {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        Text(response.body)
                            .font(AppTypography.monospacedCode)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: true)
                            .frame(
                                minWidth: max(0, geometry.size.width - 36),
                                alignment: .topLeading
                            )
                            .padding(18)
                    }
                }
                .background(Theme.editor.opacity(0.65))
            }
        case .headers:
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(response.headers) { header in
                        HStack(alignment: .top, spacing: 18) {
                            Text(header.name)
                                .font(AppTypography.monospacedLabel)
                                .foregroundStyle(.secondary)
                                .frame(width: 180, alignment: .leading)
                            Text(header.value)
                                .font(AppTypography.monospacedLabel)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 7)
                        HairlineDivider()
                    }
                }
            }
        }
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
                Circle().fill(Color.orange.opacity(0.72)).frame(width: 4, height: 4)
            }
            Text(model.saveState.label)
            if case .failed = model.saveState {
                Button("重试") { model.retrySave() }
                    .buttonStyle(.link)
                    .pointingHandCursor()
            }
            Spacer()
            Text("请求配置保存在本地 · 响应不保存")
        }
        .font(AppTypography.status)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 30)
    }

    private func tabButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(selected ? AppTypography.rowTitleStrong : AppTypography.rowTitle)
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(selected ? Color.orange : Color.clear)
                        .frame(height: 2)
                        .offset(y: 9)
                }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func parameterTabButton(selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .frame(width: 18, height: 18)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(selected ? Color.orange : Color.clear)
                        .frame(height: 2)
                        .offset(y: 9)
                }
        }
        .buttonStyle(.plain)
        .help("参数")
        .accessibilityLabel("参数")
        .accessibilityValue(selected ? "已选择" : "")
        .pointingHandCursor()
    }

    private func countLabel(_ count: Int) -> some View {
        Text("\(count) 项启用")
            .font(AppTypography.tertiary)
            .foregroundStyle(.tertiary)
    }

    private func responseMetric(_ value: String, color: Color) -> some View {
        Text(value)
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.09), in: Capsule())
    }

    private var methodColor: Color {
        switch draft.method {
        case .get, .head: .green
        case .post: .orange
        case .put, .patch: .blue
        case .delete: .red
        case .options: .purple
        }
    }

    private func statusColor(_ status: Int) -> Color {
        switch status {
        case 200..<300: .green
        case 300..<400: .orange
        default: .red
        }
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        if duration < 1 { return "\(Int(duration * 1_000)) ms" }
        return String(format: "%.2f s", duration)
    }

    private func fieldBinding<Value>(_ keyPath: WritableKeyPath<HTTPRequestDraft, Value>) -> Binding<Value> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { value in
                draft[keyPath: keyPath] = value
                persistDraft()
            }
        )
    }

    private var methodBinding: Binding<HTTPMethod> {
        Binding(
            get: { draft.method },
            set: { value in
                draft.setMethod(value)
                persistDraft()
            }
        )
    }

    private func loadDraft() {
        guard loadedNoteID != model.selectedNoteID else { return }
        loadedNoteID = model.selectedNoteID
        draft = HTTPRequestDraft.decode(model.draftContent)
        response = draft.savedResponse?.snapshot
        isDisplayingSavedResponse = response != nil
        errorMessage = nil
        configurationTab = .parameters
        responseTab = .body
    }

    private func persistDraft() {
        do {
            model.setDraftContent(try draft.encoded())
        } catch {
            errorMessage = "保存请求配置失败：\(error.localizedDescription)"
        }
    }

    private func formatRequestJSON() {
        guard let formatted = JSONPrettyPrinter.format(draft.body) else {
            errorMessage = HTTPRequestError.invalidJSON.localizedDescription
            return
        }
        draft.body = formatted
        persistDraft()
        errorMessage = nil
    }

    private func send() {
        do {
            let request = try HTTPRequestBuilder.build(draft)
            persistDraft()
            model.forceSave()
            errorMessage = nil
            response = nil
            isDisplayingSavedResponse = false
            isSending = true
            requestTask?.cancel()
            requestTask = Task { @MainActor in
                do {
                    let result = try await HTTPRequestClient().send(request)
                    guard !Task.isCancelled else { return }
                    response = result
                    isDisplayingSavedResponse = false
                    isSending = false
                } catch is CancellationError {
                    isSending = false
                } catch let error as URLError where error.code == .cancelled {
                    isSending = false
                } catch {
                    guard !Task.isCancelled else { return }
                    errorMessage = readableNetworkError(error)
                    isSending = false
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelRequest(showMessage: Bool) {
        requestTask?.cancel()
        requestTask = nil
        isSending = false
        if showMessage { errorMessage = "请求已取消" }
    }

    private func readableNetworkError(_ error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .timedOut: return "请求超时，请检查网络或服务器状态"
            case .cannotFindHost: return "找不到服务器，请检查 URL"
            case .cannotConnectToHost: return "无法连接服务器"
            case .notConnectedToInternet: return "当前没有网络连接"
            case .dataLengthExceedsMaximum: return "响应数据过大，请缩小查询范围或使用分页后重试"
            default: return "请求失败：\(error.localizedDescription)"
            }
        }
        return "请求失败：\(error.localizedDescription)"
    }

    private func copyResponse() {
        guard let response else { return }
        let content: String
        switch responseTab {
        case .body:
            content = response.body
        case .headers:
            content = response.headers.map { "\($0.name): \($0.value)" }.joined(separator: "\n")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    private func saveResponse(_ response: HTTPResponseSnapshot) {
        draft.savedResponse = response.saved()
        persistDraft()
        model.forceSave()
        isDisplayingSavedResponse = true
        errorMessage = nil
    }

    private func removeSavedResponse() {
        draft.savedResponse = nil
        persistDraft()
        model.forceSave()
        if isDisplayingSavedResponse {
            response = nil
            isDisplayingSavedResponse = false
        }
    }
}
