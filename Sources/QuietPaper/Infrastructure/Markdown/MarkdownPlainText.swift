import Foundation

enum MarkdownPlainText {
    static func extract(from markdown: String) -> String {
        markdown
            .replacingOccurrences(of: #"```[A-Za-z0-9_+\-]*\n?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: #"!\[([^\]]*)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^\s{0,3}[#>*+-]+\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[*_`]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
