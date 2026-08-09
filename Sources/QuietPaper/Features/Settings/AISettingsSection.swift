import SwiftUI

/// 设置面板中的 AI 配置区块：API Key、模型与本地向量索引。
struct AISettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var apiKey: String = ""
    @State private var selectedModel: String = "deepseek-v4-flash"
    @State private var isSaving = false
    @State private var saveError: String?

    private let keychain = KeychainStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("DeepSeek API Key")
                    .font(AppTypography.rowTitleStrong)
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .onChange(of: apiKey) { _ in saveError = nil }
                Text("从 DeepSeek 开放平台获取 API Key。密钥保存在本机应用中，避免每次对话重复请求钥匙串授权。")
                    .font(AppTypography.tertiary)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("模型")
                    .font(AppTypography.rowTitleStrong)
                Picker("模型", selection: $selectedModel) {
                    Text("DeepSeek V4 Flash（推荐）").tag("deepseek-v4-flash")
                    Text("DeepSeek V4 Pro").tag("deepseek-v4-pro")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .controlSize(.small)
            }

            HStack {
                if model.isRebuildingIndex {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text("正在重建索引…")
                        .font(AppTypography.secondary)
                } else {
                    Text("已索引 \(model.vectorChunkCount) 个文本片段")
                        .font(AppTypography.secondary)
                }
                Spacer()
                Button("重建索引") {
                    model.rebuildVectorIndex()
                }
                .controlSize(.small)
                .disabled(model.isRebuildingIndex)
                .pointingHandCursor()
            }
            .padding(12)
            .background(Theme.control, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))

            Text("仅使用系统内置 NLP 模型将普通笔记内容向量化；API 请求、数据库连接及标记为 AI 不可读的项目或模块不进入向量索引。向量化和检索过程完全离线，不发送数据到网络。")
                .font(AppTypography.tertiary)
                .foregroundStyle(.tertiary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if let saveError {
                Text(saveError)
                    .font(AppTypography.secondary)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button(action: save) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("保存")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                .pointingHandCursor()
            }
        }
        .onAppear {
            if !ProcessInfo.processInfo.arguments.contains("--in-memory-preview") {
                apiKey = keychain.get() ?? ""
            }
            let stored = UserDefaults.standard.string(forKey: "deepseek_model") ?? "deepseek-v4-flash"
            selectedModel = ["deepseek-v4-flash", "deepseek-v4-pro"].contains(stored) ? stored : "deepseek-v4-flash"
        }
    }

    private func save() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        isSaving = true
        saveError = nil

        do {
            try keychain.set(value: key)
            UserDefaults.standard.set(selectedModel, forKey: "deepseek_model")
            model.refreshAIProvider()
        } catch {
            saveError = "保存失败：\(error.localizedDescription)"
        }
        isSaving = false
    }
}
