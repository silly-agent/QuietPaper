import Foundation

enum RetrievalQueryTerms {
    private static let aliases: [(source: String, targets: [String])] = [
        ("谷歌", ["Google", "Gmail"]),
        ("脸书", ["Facebook", "Meta"]),
        ("脸谱", ["Facebook", "Meta"]),
        ("推特", ["Twitter"]),
        ("微软邮箱", ["Outlook", "Hotmail"]),
        ("苹果邮箱", ["iCloud"])
    ]

    static func make(from question: String) -> [String] {
        let stripped = question
            .replacingOccurrences(of: "是什么", with: "")
            .replacingOccurrences(of: "怎么", with: "")
            .replacingOccurrences(of: "如何", with: "")
            .replacingOccurrences(of: "请问", with: "")
            .replacingOccurrences(of: "我的", with: "")
            .replacingOccurrences(of: "？", with: "")
            .replacingOccurrences(of: "?", with: "")
        let words = stripped
            .split { $0.isWhitespace || $0.isPunctuation }
            .map(String.init)
            .filter { $0.count > 1 }
        var output = words
        for word in words where containsHan(word) && word.count > 2 {
            let characters = Array(word)
            for index in 0..<(characters.count - 1) {
                output.append(String(characters[index...index + 1]))
            }
        }
        for alias in aliases where question.localizedCaseInsensitiveContains(alias.source) {
            output.append(contentsOf: alias.targets)
        }
        var seen: Set<String> = []
        return output.filter { seen.insert($0.lowercased()).inserted }
    }

    private static func containsHan(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value) || (0x4E00...0x9FFF).contains(scalar.value)
        }
    }
}
