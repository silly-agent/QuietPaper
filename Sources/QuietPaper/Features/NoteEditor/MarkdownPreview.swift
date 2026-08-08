import AppKit
import SwiftUI

struct MarkdownPreview: View {
    let markdown: String
    let attachments: AttachmentStore
    var showsScrollIndicators = true

    var body: some View {
        ScrollView(showsIndicators: showsScrollIndicators) {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(Array(MarkdownParser.parse(markdown).enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 8 : 1)
                .textSelection(.enabled)
        case .paragraph(let text):
            Text(inline(text))
                .font(AppTypography.body)
                .bodyTracking()
                .lineSpacing(7)
                .textSelection(.enabled)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").font(AppTypography.body).foregroundStyle(Theme.accent.opacity(0.8))
                        Text(inline(item)).font(AppTypography.body).bodyTracking().lineSpacing(7).textSelection(.enabled)
                    }
                }
            }
        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.accent.opacity(0.8)).frame(width: 3)
                Text(inline(text)).font(AppTypography.body).bodyTracking().lineSpacing(7).foregroundStyle(.secondary).italic().textSelection(.enabled)
            }
            .padding(.vertical, 3)
        case .code(let language, let content):
            CodeBlockView(language: language, content: content)
        case .table(let table):
            MarkdownTableView(table: table)
        case .image(let alt, let path):
            if let image = NSImage(contentsOf: attachments.url(for: path)) {
                VStack(alignment: .leading, spacing: 5) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 480)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    if !alt.isEmpty {
                        Text(alt).font(AppTypography.tertiary).foregroundStyle(.tertiary)
                    }
                }
            } else {
                Label("找不到图片：\(path)", systemImage: "photo.badge.exclamationmark")
                    .font(AppTypography.secondary)
                    .foregroundStyle(.secondary)
            }
        case .divider:
            HairlineDivider()
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .system(size: 22, weight: .semibold)
        case 2: .system(size: 17, weight: .semibold)
        case 3: .system(size: 15, weight: .semibold)
        default: .system(size: 13.5, weight: .semibold)
        }
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable

    private var columnCount: Int {
        max(table.headers.count, table.rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                row(table.headers, isHeader: true)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { index, cells in
                    row(cells, isHeader: false)
                        .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.018) : Color.clear)
                }
            }
            .background(Theme.editor.opacity(0.58))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func row(_ cells: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<columnCount, id: \.self) { index in
                Text(inline(cell(at: index, in: cells)))
                    .font(isHeader ? AppTypography.secondary.weight(.semibold) : AppTypography.secondary)
                    .foregroundStyle(isHeader ? Color.primary : Color.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .frame(width: 150, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(isHeader ? Theme.control.opacity(0.78) : Color.clear)
                    .overlay(alignment: .trailing) {
                        if index < columnCount - 1 {
                            HairlineDivider(axis: .vertical)
                        }
                    }
            }
        }
        .overlay(alignment: .bottom) {
            HairlineDivider()
        }
    }

    private func cell(at index: Int, in cells: [String]) -> String {
        index < cells.count ? cells[index] : ""
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

private struct CodeBlockView: View {
    let language: String
    let content: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language.lowercased())
                    .font(AppTypography.monospacedLabel)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        copied = false
                    }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(AppTypography.tertiary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            HairlineDivider()

            ScrollView(.horizontal, showsIndicators: false) {
                Text(CodeSyntaxHighlighter.highlight(content, language: language))
                    .font(AppTypography.monospacedCode)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.editor.opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private enum CodeSyntaxHighlighter {
    static func highlight(_ source: String, language: String) -> AttributedString {
        let output = NSMutableAttributedString(
            string: source,
            attributes: [.foregroundColor: NSColor.labelColor]
        )
        apply(#"\b(?:true|false|null|nil|let|var|func|struct|class|protocol|return|throw|throws|async|await|SELECT|FROM|WHERE|JOIN|INSERT|UPDATE|DELETE|CREATE|TABLE|GET|POST|PUT|PATCH|curl)\b"#, color: .systemPurple, to: output)
        apply(#"\b\d+(?:\.\d+)?\b"#, color: .systemOrange, to: output)
        apply(#"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'"#, color: .systemGreen, to: output)
        apply(#"(?m)(?://|--|#\s).*$"#, color: .tertiaryLabelColor, to: output)
        return AttributedString(output)
    }

    private static func apply(_ pattern: String, color: NSColor, to output: NSMutableAttributedString) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(location: 0, length: output.string.utf16.count)
        for match in regex.matches(in: output.string, range: range) {
            output.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}
