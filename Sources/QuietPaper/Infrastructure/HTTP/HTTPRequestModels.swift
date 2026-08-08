import Foundation

enum HTTPMethod: String, CaseIterable, Codable, Identifiable, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"

    var id: Self { self }
}

enum HTTPBodyMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case json
    case text

    var id: Self { self }

    var label: String {
        switch self {
        case .none: "无"
        case .json: "JSON"
        case .text: "文本"
        }
    }
}

struct HTTPKeyValue: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var isEnabled: Bool
    var key: String
    var value: String

    init(id: UUID = UUID(), isEnabled: Bool = true, key: String = "", value: String = "") {
        self.id = id
        self.isEnabled = isEnabled
        self.key = key
        self.value = value
    }
}

struct HTTPResponseHeader: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    let name: String
    let value: String

    init(id: UUID = UUID(), name: String, value: String) {
        self.id = id
        self.name = name
        self.value = value
    }
}

struct HTTPSavedResponse: Codable, Equatable, Sendable {
    let url: URL?
    let statusCode: Int
    let headers: [HTTPResponseHeader]
    let body: String
    let duration: TimeInterval
    let size: Int
    let savedAt: Date
}

struct HTTPRequestDraft: Codable, Equatable, Sendable {
    var version: Int
    var method: HTTPMethod
    var url: String
    var queryItems: [HTTPKeyValue]
    var headers: [HTTPKeyValue]
    var bodyMode: HTTPBodyMode
    var body: String
    var savedResponse: HTTPSavedResponse?

    init(
        version: Int = 2,
        method: HTTPMethod = .get,
        url: String = "",
        queryItems: [HTTPKeyValue] = [],
        headers: [HTTPKeyValue] = [],
        bodyMode: HTTPBodyMode = .none,
        body: String = "",
        savedResponse: HTTPSavedResponse? = nil
    ) {
        self.version = version
        self.method = method
        self.url = url
        self.queryItems = queryItems
        self.headers = headers
        self.bodyMode = bodyMode
        self.body = body
        self.savedResponse = savedResponse
        addDefaultJSONHeaderIfNeeded()
    }

    static func decode(_ source: String) -> HTTPRequestDraft {
        guard let data = source.data(using: .utf8),
              let value = try? JSONDecoder().decode(HTTPRequestDraft.self, from: data) else {
            return HTTPRequestDraft()
        }
        return value
    }

    func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }

    var searchableText: String {
        let query = queryItems.filter(\.isEnabled).flatMap { [$0.key, $0.value] }
        let header = headers.filter(\.isEnabled).flatMap { [$0.key, $0.value] }
        return ([method.rawValue, url] + query + header + [body]).joined(separator: "\n")
    }

    mutating func setMethod(_ value: HTTPMethod) {
        method = value
        addDefaultJSONHeaderIfNeeded()
    }

    private mutating func addDefaultJSONHeaderIfNeeded() {
        guard method == .post, !headers.contains(where: { item in
            item.key.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("Content-Type") == .orderedSame
        }) else { return }
        headers.append(HTTPKeyValue(key: "Content-Type", value: "application/json"))
    }
}

enum HTTPRequestError: LocalizedError, Equatable, Sendable {
    case missingURL
    case invalidURL
    case unsupportedScheme
    case invalidJSON
    case nonHTTPResponse
    case responseTooLarge(maximumBytes: Int)

    var errorDescription: String? {
        switch self {
        case .missingURL: "请输入请求 URL"
        case .invalidURL: "URL 格式不正确"
        case .unsupportedScheme: "仅支持 HTTP 和 HTTPS 请求"
        case .invalidJSON: "请求正文不是有效的 JSON"
        case .nonHTTPResponse: "服务器没有返回有效的 HTTP 响应"
        case .responseTooLarge(let maximumBytes):
            "响应超过 \(ByteCountFormatter.string(fromByteCount: Int64(maximumBytes), countStyle: .file))，请缩小查询范围或使用分页"
        }
    }
}

enum HTTPRequestBuilder {
    static func build(_ draft: HTTPRequestDraft) throws -> URLRequest {
        let source = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw HTTPRequestError.missingURL }
        guard var components = URLComponents(string: source), let scheme = components.scheme?.lowercased() else {
            throw HTTPRequestError.invalidURL
        }
        guard scheme == "http" || scheme == "https" else { throw HTTPRequestError.unsupportedScheme }

        var appendedItems = draft.queryItems.compactMap { item -> URLQueryItem? in
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard item.isEnabled, !key.isEmpty else { return nil }
            return URLQueryItem(name: key, value: item.value)
        }
        let bodyQueryItems = try queryItemsFromGETJSONBody(draft)
        if let bodyQueryItems {
            let explicitKeys = Set(appendedItems.map(\.name))
            appendedItems.append(contentsOf: bodyQueryItems.filter { !explicitKeys.contains($0.name) })
        }
        if !appendedItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + appendedItems
        }
        guard let url = components.url, url.host != nil else { throw HTTPRequestError.invalidURL }

        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = draft.method.rawValue
        for header in draft.headers where header.isEnabled {
            let key = header.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            request.setValue(header.value, forHTTPHeaderField: key)
        }

        switch draft.bodyMode {
        case .none:
            break
        case .json:
            guard let data = draft.body.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else {
                throw HTTPRequestError.invalidJSON
            }
            if bodyQueryItems == nil {
                request.httpBody = data
                if !hasHeader(named: "Content-Type", in: request) {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }
        case .text:
            request.httpBody = Data(draft.body.utf8)
            if !hasHeader(named: "Content-Type", in: request) {
                request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
            }
        }
        return request
    }

    private static func hasHeader(named name: String, in request: URLRequest) -> Bool {
        request.allHTTPHeaderFields?.keys.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) == true
    }

    /// GET/HEAD 服务通常忽略请求体。将顶层 JSON 对象转换为查询参数；数组和对象值保持紧凑 JSON。
    private static func queryItemsFromGETJSONBody(_ draft: HTTPRequestDraft) throws -> [URLQueryItem]? {
        guard draft.method == .get || draft.method == .head,
              draft.bodyMode == .json,
              !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let data = draft.body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw HTTPRequestError.invalidJSON
        }
        guard let dictionary = object as? [String: Any] else { return nil }
        return try dictionary.keys.sorted().map { key in
            URLQueryItem(name: key, value: try queryValue(dictionary[key]!))
        }
    }

    private static func queryValue(_ value: Any) throws -> String {
        if let value = value as? String { return value }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
