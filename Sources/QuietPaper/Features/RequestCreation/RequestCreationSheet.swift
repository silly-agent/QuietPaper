import SwiftUI

struct RequestCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreateHTTP: (HTTPRequestDraft) -> Void
    let onCreateWebSocket: () -> Void

    @State private var selectedOption: RequestCreationOption?
    @State private var curlSource = ""
    @State private var importError: String?
    @FocusState private var curlFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            HairlineDivider()
            Group {
                if selectedOption == .curl {
                    curlImporter
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    optionPicker
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
        }
        .frame(width: 720, height: 500)
        .background(Theme.background)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedOption == .curl ? "从 cURL 导入" : "新建请求")
                    .font(.system(size: 18, weight: .semibold))
                Text(selectedOption == .curl ? "粘贴命令，预览无误后生成 HTTP 请求" : "选择协议或从已有命令快速开始")
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
    }

    private var optionPicker: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                ForEach(RequestCreationOption.allCases) { option in
                    RequestCreationCard(option: option) {
                        choose(option)
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                Text("请求配置只保存在本地；只有主动发送或连接时才会访问目标服务。")
            }
            .font(AppTypography.secondary)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(22)
    }

    private var curlImporter: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("cURL 命令", systemImage: "terminal")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("支持 Method · URL · Headers · Body")
                        .font(AppTypography.tertiary)
                        .foregroundStyle(.tertiary)
                }

                TextEditor(text: $curlSource)
                    .font(AppTypography.monospacedCode)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .focused($curlFocused)
                    .background(Theme.editor, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(importError == nil ? Color.primary.opacity(0.10) : Color.red.opacity(0.50), lineWidth: 0.75)
                    )
                    .frame(minHeight: 215)
                    .onChange(of: curlSource) { _ in importError = nil }

                if let importError {
                    Label(importError, systemImage: "exclamationmark.circle.fill")
                        .font(AppTypography.secondary)
                        .foregroundStyle(.red)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Text("命令和其中的凭据只在本机解析并保存。暂不导入本地文件正文。")
                        .font(AppTypography.secondary)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(22)

            Spacer(minLength: 0)
            HairlineDivider()
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        selectedOption = nil
                        importError = nil
                    }
                } label: {
                    Label("返回选择", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .font(AppTypography.secondary)
                .foregroundStyle(.secondary)
                .pointingHandCursor()

                Spacer()

                Button(action: importCURL) {
                    Label("生成 HTTP 请求", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.orange)
                .keyboardShortcut(.defaultAction)
                .disabled(curlSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .pointingHandCursor()
            }
            .padding(16)
            .background(Theme.background)
        }
        .onAppear { curlFocused = true }
    }

    private func choose(_ option: RequestCreationOption) {
        switch option {
        case .http:
            onCreateHTTP(HTTPRequestDraft())
            dismiss()
        case .websocket:
            onCreateWebSocket()
            dismiss()
        case .curl:
            withAnimation(.easeInOut(duration: 0.26)) { selectedOption = .curl }
        }
    }

    private func importCURL() {
        do {
            let draft = try CURLRequestImporter.parse(curlSource)
            onCreateHTTP(draft)
            dismiss()
        } catch {
            withAnimation(.easeOut(duration: 0.18)) {
                importError = error.localizedDescription
            }
        }
    }
}

private enum RequestCreationOption: String, CaseIterable, Identifiable {
    case http
    case websocket
    case curl

    var id: Self { self }

    var title: String {
        switch self {
        case .http: "HTTP 请求"
        case .websocket: "WebSocket 请求"
        case .curl: "从 cURL 导入"
        }
    }

    var subtitle: String {
        switch self {
        case .http: "REST API 与常规接口调试"
        case .websocket: "实时连接与双向消息通信"
        case .curl: "粘贴命令生成完整 HTTP 请求"
        }
    }

    var detail: String {
        switch self {
        case .http: "GET · POST · Headers · Body"
        case .websocket: "服务端推送 · 文本消息发送"
        case .curl: "自动识别方法、参数与正文"
        }
    }

    var systemImage: String {
        switch self {
        case .http: "globe"
        case .websocket: "arrow.left.arrow.right"
        case .curl: "terminal"
        }
    }

    var color: Color {
        switch self {
        case .http: .orange
        case .websocket: .blue
        case .curl: .purple
        }
    }
}

private struct RequestCreationCard: View {
    let option: RequestCreationOption
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13)
                            .fill(option.color.opacity(0.13))
                        Image(systemName: option.systemImage)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(option.color)
                    }
                    .frame(width: 54, height: 54)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(option.color.opacity(hovering ? 0.95 : 0.62))
                }

                Spacer(minLength: 18)
                Text(option.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(option.subtitle)
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
                Text(option.detail)
                    .font(AppTypography.tertiary)
                    .foregroundStyle(option.color.opacity(0.86))
                    .padding(.top, 13)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 245, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [Theme.control, option.color.opacity(hovering ? 0.075 : 0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(option.color.opacity(hovering ? 0.40 : 0.13), lineWidth: hovering ? 1 : 0.75)
            )
            .shadow(color: option.color.opacity(hovering ? 0.14 : 0.06), radius: hovering ? 16 : 8, y: 6)
            .scaleEffect(hovering ? 1.018 : 1)
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(.easeOut(duration: 0.18)) { hovering = value }
        }
        .pointingHandCursor()
    }
}
