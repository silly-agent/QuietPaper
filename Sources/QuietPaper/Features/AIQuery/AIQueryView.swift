import SwiftUI

struct AIQueryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var answer: GroundedAnswer?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("询问笔记", systemImage: "sparkles")
                    .font(AppTypography.sheetTitle)
                Spacer()
                Button("完成") { dismiss() }
                    .controlSize(.small)
                    .pointingHandCursor()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            HairlineDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(privacyNotice)
                        .font(AppTypography.secondary)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)

                    HStack {
                        TextField("例如：飞书分页读取记录的接口是什么？", text: $question)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .onSubmit(ask)
                        Button(action: ask) {
                            if isLoading { ProgressView().controlSize(.small) } else { Text("提问") }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                        .pointingHandCursor()
                    }

                    if let answer {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("回答").font(AppTypography.sectionTitle)
                            Text(answer.text)
                                .font(AppTypography.body)
                                .bodyTracking()
                                .lineSpacing(4)
                                .textSelection(.enabled)
                        }
                        .padding(14)
                        .background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))

                        if !answer.sources.isEmpty {
                            Text("来源").font(AppTypography.sectionTitle)
                            ForEach(answer.sources) { source in
                                Button {
                                    model.openSearchResult(source)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 11))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(source.noteTitle).font(AppTypography.rowTitleStrong)
                                            Text(source.path)
                                                .font(AppTypography.tertiary)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Theme.control, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .pointingHandCursor()
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 680, minHeight: 520)
        .onAppear { model.ensureVectorIndex() }
    }

    private var privacyNotice: String {
        if model.activeAIProviderRequiresNetwork {
            return "当前使用 \(model.activeAIProviderName)。提问内容和检索到的笔记片段会发送至 api.deepseek.com 进行处理。请勿在提问中包含敏感信息。DeepSeek 的隐私政策适用于相关数据传输。"
        } else {
            return "回答只使用本地搜索命中的笔记片段，并附上可打开的来源。当前提供方不会发送数据到网络。"
        }
    }

    private func ask() {
        let value = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isLoading = true
        Task {
            answer = await model.ask(value)
            isLoading = false
        }
    }
}
