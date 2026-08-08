import Foundation

enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullets([String])
    case quote(String)
    case code(language: String, content: String)
    case table(MarkdownTable)
    case image(alt: String, path: String)
    case divider
}

struct MarkdownTable: Equatable, Sendable {
    var headers: [String]
    var rows: [[String]]
}

enum MarkdownParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = MarkdownImageSyntax.normalized(markdown).components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var code: [String] = []
        var language = ""
        var inCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        func flushBullets() {
            guard !bullets.isEmpty else { return }
            blocks.append(.bullets(bullets))
            bullets.removeAll()
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(language: language, content: code.joined(separator: "\n")))
                    code.removeAll()
                    language = ""
                    inCode = false
                } else {
                    flushParagraph()
                    flushBullets()
                    language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCode = true
                }
                index += 1
                continue
            }
            if inCode {
                code.append(line)
                index += 1
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                flushBullets()
            } else if let table = parseTable(lines, startIndex: index) {
                flushParagraph()
                flushBullets()
                blocks.append(table.block)
                index = table.nextIndex
                continue
            } else if trimmed == "---" || trimmed == "***" {
                flushParagraph()
                flushBullets()
                blocks.append(.divider)
            } else if let heading = parseHeading(trimmed) {
                flushParagraph()
                flushBullets()
                blocks.append(heading)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                bullets.append(String(trimmed.dropFirst(2)))
            } else if trimmed.hasPrefix("> ") {
                flushParagraph()
                flushBullets()
                blocks.append(.quote(String(trimmed.dropFirst(2))))
            } else if let image = parseImage(trimmed) {
                flushParagraph()
                flushBullets()
                blocks.append(image)
            } else {
                flushBullets()
                paragraph.append(trimmed)
            }
            index += 1
        }
        flushParagraph()
        flushBullets()
        if inCode { blocks.append(.code(language: language, content: code.joined(separator: "\n"))) }
        return blocks
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        let count = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(count), line.dropFirst(count).first == " " else { return nil }
        return .heading(level: count, text: String(line.dropFirst(count + 1)))
    }

    private static func parseImage(_ line: String) -> MarkdownBlock? {
        guard line.hasPrefix("!["), let closeAlt = line.firstIndex(of: "]") else { return nil }
        let afterAlt = line.index(after: closeAlt)
        guard afterAlt < line.endIndex, line[afterAlt] == "(", line.hasSuffix(")") else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<closeAlt])
        let pathStart = line.index(after: afterAlt)
        let pathEnd = line.index(before: line.endIndex)
        return .image(alt: alt, path: String(line[pathStart..<pathEnd]))
    }

    private static func parseTable(_ lines: [String], startIndex: Int) -> (block: MarkdownBlock, nextIndex: Int)? {
        guard startIndex + 1 < lines.count,
              let headers = parseTableRow(lines[startIndex]),
              isSeparatorRow(lines[startIndex + 1], expectedColumns: headers.count) else { return nil }

        var rows: [[String]] = []
        var index = startIndex + 2
        while index < lines.count, let row = parseTableRow(lines[index]), row.count == headers.count {
            rows.append(row)
            index += 1
        }
        return (.table(MarkdownTable(headers: headers, rows: rows)), index)
    }

    private static func parseTableRow(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }
        var content = trimmed
        if content.hasPrefix("|") { content.removeFirst() }
        if content.hasSuffix("|") { content.removeLast() }
        let cells = content
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard cells.count >= 2 else { return nil }
        return cells
    }

    private static func isSeparatorRow(_ line: String, expectedColumns: Int) -> Bool {
        guard let cells = parseTableRow(line), cells.count == expectedColumns else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            let withoutColons = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return withoutColons.count >= 3 && withoutColons.allSatisfy { $0 == "-" }
        }
    }
}
