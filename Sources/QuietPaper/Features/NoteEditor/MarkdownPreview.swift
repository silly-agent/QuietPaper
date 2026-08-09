import AppKit
import SwiftUI

struct MarkdownPreview: View {
    let markdown: String
    let attachments: AttachmentStore
    var showsScrollIndicators = true
    var findQuery = ""
    var activeFindMatchIndex: Int? = nil

    var body: some View {
        let blocks = MarkdownParser.parse(markdown)
        let searchIndex = PreviewSearchIndex(blocks: blocks)
        let activeMatch = searchIndex.match(at: activeFindMatchIndex, query: findQuery)

        ScrollViewReader { proxy in
            ScrollView(showsIndicators: showsScrollIndicators) {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { blockIndex, block in
                        blockView(
                            block,
                            unitIDs: searchIndex.unitIDs(forBlockAt: blockIndex),
                            activeMatch: activeMatch
                        )
                    }
                }
                .frame(maxWidth: 860, alignment: .leading)
                .padding(.horizontal, 36)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .onAppear {
                scrollToActiveMatch(activeMatch, proxy: proxy, animated: false)
            }
            .onChange(of: activeMatch) { match in
                scrollToActiveMatch(match, proxy: proxy, animated: true)
            }
        }
    }

    @ViewBuilder
    private func blockView(
        _ block: MarkdownBlock,
        unitIDs: [Int],
        activeMatch: PreviewSearchMatch?
    ) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(highlightedInline(text, unitID: unitIDs[0], activeMatch: activeMatch))
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 8 : 1)
                .textSelection(.enabled)
                .id(unitIDs[0])
        case .paragraph(let text):
            Text(highlightedInline(text, unitID: unitIDs[0], activeMatch: activeMatch))
                .font(AppTypography.body)
                .bodyTracking()
                .lineSpacing(7)
                .textSelection(.enabled)
                .id(unitIDs[0])
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").font(AppTypography.body).foregroundStyle(Theme.accent.opacity(0.8))
                        Text(highlightedInline(item, unitID: unitIDs[index], activeMatch: activeMatch))
                            .font(AppTypography.body)
                            .bodyTracking()
                            .lineSpacing(7)
                            .textSelection(.enabled)
                    }
                    .id(unitIDs[index])
                }
            }
        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.accent.opacity(0.8)).frame(width: 3)
                Text(highlightedInline(text, unitID: unitIDs[0], activeMatch: activeMatch))
                    .font(AppTypography.body)
                    .bodyTracking()
                    .lineSpacing(7)
                    .foregroundStyle(.secondary)
                    .italic()
                    .textSelection(.enabled)
            }
            .padding(.vertical, 3)
            .id(unitIDs[0])
        case .code(let language, let content):
            CodeBlockView(
                language: language,
                content: content,
                findQuery: findQuery,
                searchUnitID: unitIDs[0],
                activeFindMatch: activeMatch
            )
            .id(unitIDs[0])
        case .table(let table):
            MarkdownTableView(
                table: table,
                findQuery: findQuery,
                searchUnitIDs: unitIDs,
                activeFindMatch: activeMatch
            )
        case .image(let alt, let path):
            if let image = NSImage(contentsOf: attachments.url(for: path)) {
                VStack(alignment: .leading, spacing: 5) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 480)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    if !alt.isEmpty {
                        Text(highlightedInline(alt, unitID: unitIDs[0], activeMatch: activeMatch))
                            .font(AppTypography.tertiary)
                            .foregroundStyle(.tertiary)
                            .id(unitIDs[0])
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

    private func highlightedInline(
        _ text: String,
        unitID: Int,
        activeMatch: PreviewSearchMatch?
    ) -> AttributedString {
        PreviewFindHighlighter.highlight(
            MarkdownInlineText.attributed(text),
            query: findQuery,
            unitID: unitID,
            activeMatch: activeMatch
        )
    }

    private func scrollToActiveMatch(
        _ match: PreviewSearchMatch?,
        proxy: ScrollViewProxy,
        animated: Bool
    ) {
        guard let match else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(match.unitID, anchor: .center)
            }
        } else {
            proxy.scrollTo(match.unitID, anchor: .center)
        }
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

struct MarkdownTableView: View {
    let table: MarkdownTable
    var findQuery = ""
    var searchUnitIDs: [Int] = []
    var activeFindMatch: PreviewSearchMatch? = nil

    private var columnCount: Int {
        max(table.headers.count, table.rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                row(table.headers, isHeader: true, unitOffset: 0)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { index, cells in
                    row(
                        cells,
                        isHeader: false,
                        unitOffset: table.headers.count + table.rows.prefix(index).reduce(0) { $0 + $1.count }
                    )
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

    private func row(_ cells: [String], isHeader: Bool, unitOffset: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<columnCount, id: \.self) { index in
                let unitID = searchUnitIDs[unitOffset + index]
                Text(highlightedInline(cell(at: index, in: cells), unitID: unitID))
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
                    .id(unitID)
            }
        }
        .overlay(alignment: .bottom) {
            HairlineDivider()
        }
    }

    private func cell(at index: Int, in cells: [String]) -> String {
        index < cells.count ? cells[index] : ""
    }

    private func highlightedInline(_ text: String, unitID: Int) -> AttributedString {
        PreviewFindHighlighter.highlight(
            MarkdownInlineText.attributed(text),
            query: findQuery,
            unitID: unitID,
            activeMatch: activeFindMatch
        )
    }
}

struct CodeBlockView: View {
    let language: String
    let content: String
    var findQuery = ""
    var searchUnitID: Int? = nil
    var activeFindMatch: PreviewSearchMatch? = nil
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
                Text(highlightedCode)
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

    private var highlightedCode: AttributedString {
        guard let searchUnitID else {
            return CodeSyntaxHighlighter.highlight(content, language: language)
        }
        return PreviewFindHighlighter.highlight(
            CodeSyntaxHighlighter.highlight(content, language: language),
            query: findQuery,
            unitID: searchUnitID,
            activeMatch: activeFindMatch
        )
    }
}

private enum PreviewFindHighlighter {
    static func highlight(
        _ source: AttributedString,
        query: String,
        unitID: Int,
        activeMatch: PreviewSearchMatch?
    ) -> AttributedString {
        guard !query.isEmpty else { return source }

        var output = source
        let plainText = String(output.characters)
        for range in EditorFindMatcher.ranges(in: plainText, query: query) {
            guard let stringRange = Range(range, in: plainText),
                  let lowerBound = AttributedString.Index(stringRange.lowerBound, within: output),
                  let upperBound = AttributedString.Index(stringRange.upperBound, within: output) else {
                continue
            }
            let isActive = activeMatch?.unitID == unitID && activeMatch?.range == range
            output[lowerBound..<upperBound].backgroundColor = isActive
                ? NSColor.systemOrange.withAlphaComponent(0.62)
                : NSColor.systemYellow.withAlphaComponent(0.34)
        }
        return output
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
