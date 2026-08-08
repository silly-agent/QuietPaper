import SwiftUI

/// 设置面板中的主题区块：选择全局配色，自动适配系统的浅色 / 深色外观。
struct ThemeSection: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(WritingFocusBlurPreference.defaultsKey)
    private var isWritingFocusBlurEnabled = WritingFocusBlurPreference.defaultValue

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Theme.allCases) { theme in
                    Button {
                        model.theme = theme
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            themePreview(for: theme)

                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(theme.title)
                                        .font(AppTypography.rowTitleStrong)
                                        .foregroundStyle(.primary)
                                    Text(theme.summary)
                                        .font(AppTypography.tertiary)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: model.theme == theme ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(model.theme == theme ? theme.palette.accent : Color.secondary.opacity(0.35))
                            }
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            model.theme == theme ? theme.palette.accent.opacity(0.085) : Color.primary.opacity(0.022),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(model.theme == theme ? theme.palette.accent.opacity(0.32) : Color.primary.opacity(0.075), lineWidth: 0.75)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }

            writingFocusCard
        }
    }

    private var writingFocusCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "eye.slash")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text("写作聚焦雾化")
                    .font(AppTypography.rowTitleStrong)
                Text("编辑标题或正文时雾化左侧导航；鼠标移入左侧后临时恢复清晰。")
                    .font(AppTypography.tertiary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("写作聚焦雾化", isOn: $isWritingFocusBlurEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(13)
        .background(Theme.control, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.075), lineWidth: 0.75)
        )
    }

    /// 用缩略工作区展示侧栏、列表、编辑器与强调色之间的真实关系。
    private func themePreview(for theme: Theme) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Capsule()
                    .fill(theme.palette.accent)
                    .frame(width: 18, height: 4)
                Capsule()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: 24, height: 3)
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 20, height: 3)
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(width: 48, height: 54, alignment: .topLeading)
            .background(theme.palette.control)

            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.16))
                    .frame(width: 52, height: 5)
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(maxWidth: .infinity)
                    .frame(height: 3)
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 76, height: 3)
                Spacer(minLength: 0)
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
            .background(theme.palette.editor)
        }
        .background(theme.palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
    }
}
