import Foundation

enum JSONPrettyPrinter {
    static func format(_ source: String) -> String? {
        let candidate = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = candidate.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let output = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
              ),
              let pretty = String(data: output, encoding: .utf8) else { return nil }
        return removingSpacesBeforeColons(in: compactingEmptyContainers(in: pretty))
    }

    private static func compactingEmptyContainers(in source: String) -> String {
        let lines = source.components(separatedBy: "\n")
        var output: [String] = []
        var index = 0

        while index < lines.count {
            if index + 2 < lines.count {
                let opening = lines[index].trimmingCharacters(in: .whitespaces)
                let middle = lines[index + 1].trimmingCharacters(in: .whitespaces)
                let closing = lines[index + 2].trimmingCharacters(in: .whitespaces)
                let closingToken: String?

                if opening.hasSuffix("{") && (closing == "}" || closing == "},") {
                    closingToken = closing == "}," ? "}," : "}"
                } else if opening.hasSuffix("[") && (closing == "]" || closing == "],") {
                    closingToken = closing == "]," ? "]," : "]"
                } else {
                    closingToken = nil
                }

                if middle.isEmpty, let closingToken {
                    output.append(lines[index] + closingToken)
                    index += 3
                    continue
                }
            }

            output.append(lines[index])
            index += 1
        }

        return output.joined(separator: "\n")
    }

    private static func removingSpacesBeforeColons(in source: String) -> String {
        var output = ""
        var isInsideString = false
        var isEscaped = false

        for character in source {
            if isInsideString {
                output.append(character)
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
                output.append(character)
            } else if character == ":" {
                while output.last == " " { output.removeLast() }
                output.append(character)
            } else {
                output.append(character)
            }
        }

        return output
    }
}

enum MarkdownJSONFormatter {
    static func format(_ source: String) -> String? {
        let candidate = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let fenced = candidate.hasPrefix("```json") && candidate.hasSuffix("```")
        let raw = fenced
            ? String(candidate.dropFirst(7).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            : candidate
        guard let pretty = JSONPrettyPrinter.format(raw) else { return nil }
        return fenced ? "```json\n\(pretty)\n```" : pretty
    }
}
