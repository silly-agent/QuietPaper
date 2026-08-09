import Foundation

struct WebSocketRequestDraft: Codable, Equatable, Sendable {
    var version: Int
    var url: String
    var headers: [HTTPKeyValue]

    init(version: Int = 1, url: String = "", headers: [HTTPKeyValue] = []) {
        self.version = version
        self.url = url
        self.headers = headers
    }

    static func decode(_ source: String) -> WebSocketRequestDraft {
        guard let data = source.data(using: .utf8),
              let draft = try? JSONDecoder().decode(Self.self, from: data) else {
            return WebSocketRequestDraft()
        }
        return draft
    }

    func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    var searchableText: String {
        let headerText = headers.filter(\.isEnabled).flatMap { [$0.key, $0.value] }
        return ([url] + headerText).joined(separator: "\n")
    }
}
