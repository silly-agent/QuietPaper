import Foundation

enum MarkdownImageSyntax {
    private static let repeatedImageRegex = try! NSRegularExpression(
        pattern: #"(!\[[^\]\n]*\]\([^)\n]+\))(?:(?:[ \t\r\n]*)\1)+"#
    )
    private static let adjacentImageRegex = try! NSRegularExpression(
        pattern: #"\)(?=!\[)"#
    )

    static func normalized(_ markdown: String) -> String {
        let fullRange = NSRange(location: 0, length: markdown.utf16.count)
        let deduplicated = repeatedImageRegex.stringByReplacingMatches(
            in: markdown,
            range: fullRange,
            withTemplate: "$1"
        )
        let deduplicatedRange = NSRange(location: 0, length: deduplicated.utf16.count)
        return adjacentImageRegex.stringByReplacingMatches(
            in: deduplicated,
            range: deduplicatedRange,
            withTemplate: ")\n"
        )
    }
}
