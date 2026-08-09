import SwiftUI

struct CompactMarkdownView: View {
    enum Style {
        case message
        case reasoning

        var bodyFont: Font {
            switch self {
            case .message: AppTypography.body
            case .reasoning: AppTypography.secondary
            }
        }

        var foregroundColor: Color {
            switch self {
            case .message: .primary
            case .reasoning: .secondary
            }
        }

        var blockSpacing: CGFloat {
            switch self {
            case .message: 9
            case .reasoning: 7
            }
        }
    }

    let markdown: String
    var style: Style = .message

    var body: some View {
        LazyVStack(alignment: .leading, spacing: style.blockSpacing) {
            ForEach(Array(MarkdownParser.parse(markdown).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownInlineText.attributed(text))
                .font(headingFont(level))
                .foregroundStyle(style.foregroundColor)
                .padding(.top, level <= 2 ? 3 : 0)
                .textSelection(.enabled)
        case .paragraph(let text):
            inlineText(text)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: style == .message ? 6 : 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(style.bodyFont)
                            .foregroundStyle(Theme.accent.opacity(0.8))
                        inlineText(item)
                    }
                }
            }
        case .quote(let text):
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.accent.opacity(0.72))
                    .frame(width: 3)
                inlineText(text)
                    .italic()
            }
            .padding(.vertical, 2)
        case .code(let language, let content):
            CodeBlockView(language: language, content: content)
        case .table(let table):
            MarkdownTableView(table: table)
        case .image(let alt, let path):
            Label {
                Text(alt.isEmpty ? path : alt)
                    .font(style.bodyFont)
                    .foregroundStyle(style.foregroundColor)
            } icon: {
                Image(systemName: "photo")
                    .foregroundStyle(Theme.accent)
            }
            .help(path)
        case .divider:
            HairlineDivider()
                .padding(.vertical, 2)
        }
    }

    private func inlineText(_ text: String) -> some View {
        Text(MarkdownInlineText.attributed(text))
            .font(style.bodyFont)
            .tracking(style == .message ? 1.6 : 0)
            .lineSpacing(style == .message ? 4 : 3)
            .foregroundStyle(style.foregroundColor)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func headingFont(_ level: Int) -> Font {
        switch (style, level) {
        case (.message, 1): .system(size: 19, weight: .semibold)
        case (.message, 2): .system(size: 17, weight: .semibold)
        case (.message, _): .system(size: 15, weight: .semibold)
        case (.reasoning, 1...2): AppTypography.secondary.weight(.semibold)
        case (.reasoning, _): AppTypography.tertiary.weight(.semibold)
        }
    }
}
