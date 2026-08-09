import Foundation

enum CURLImportError: LocalizedError, Equatable, Sendable {
    case emptyCommand
    case notCURLCommand
    case unclosedQuote
    case missingOptionValue(String)
    case missingURL
    case invalidURL
    case unsupportedScheme
    case unsupportedOption(String)
    case filePayloadUnsupported

    var errorDescription: String? {
        switch self {
        case .emptyCommand: "请粘贴一条 cURL 命令"
        case .notCURLCommand: "命令需要以 curl 开头"
        case .unclosedQuote: "cURL 命令中有未闭合的引号"
        case .missingOptionValue(let option): "参数 \(option) 缺少值"
        case .missingURL: "cURL 命令中没有请求 URL"
        case .invalidURL: "cURL 中的 URL 格式不正确"
        case .unsupportedScheme: "只能导入 HTTP 或 HTTPS cURL 请求"
        case .unsupportedOption(let option): "暂不支持 cURL 参数 \(option)"
        case .filePayloadUnsupported: "暂不支持从本地文件读取 cURL 请求正文"
        }
    }
}

enum CURLRequestImporter {
    static func parse(_ source: String) throws -> HTTPRequestDraft {
        let tokens = try tokenize(source)
        guard !tokens.isEmpty else { throw CURLImportError.emptyCommand }
        guard tokens[0].split(separator: "/").last?.lowercased() == "curl" else {
            throw CURLImportError.notCURLCommand
        }

        var explicitMethod: HTTPMethod?
        var urlSource: String?
        var headers: [HTTPKeyValue] = []
        var dataValues: [String] = []
        var useGET = false
        var index = 1

        while index < tokens.count {
            let token = tokens[index]
            let option = longOption(token)

            switch option.name {
            case "-X", "--request":
                let value = try option.value ?? nextValue(after: &index, tokens: tokens, option: option.name)
                guard let method = HTTPMethod(rawValue: value.uppercased()) else {
                    throw CURLImportError.unsupportedOption("\(option.name) \(value)")
                }
                explicitMethod = method
            case "-H", "--header":
                let value = try option.value ?? nextValue(after: &index, tokens: tokens, option: option.name)
                if let header = header(from: value) { headers.append(header) }
            case "-d", "--data", "--data-raw", "--data-binary", "--data-urlencode":
                let value = try option.value ?? nextValue(after: &index, tokens: tokens, option: option.name)
                guard !value.hasPrefix("@") else { throw CURLImportError.filePayloadUnsupported }
                dataValues.append(value)
            case "--url":
                urlSource = try option.value ?? nextValue(after: &index, tokens: tokens, option: option.name)
            case "-G", "--get":
                useGET = true
            case "-u", "--user":
                let value = try option.value ?? nextValue(after: &index, tokens: tokens, option: option.name)
                let encoded = Data(value.utf8).base64EncodedString()
                headers.append(HTTPKeyValue(key: "Authorization", value: "Basic \(encoded)"))
            case "-A", "--user-agent":
                let value = try option.value ?? nextValue(after: &index, tokens: tokens, option: option.name)
                headers.append(HTTPKeyValue(key: "User-Agent", value: value))
            case "-e", "--referer":
                let value = try option.value ?? nextValue(after: &index, tokens: tokens, option: option.name)
                headers.append(HTTPKeyValue(key: "Referer", value: value))
            case "-b", "--cookie":
                let value = try option.value ?? nextValue(after: &index, tokens: tokens, option: option.name)
                headers.append(HTTPKeyValue(key: "Cookie", value: value))
            case "-L", "--location", "--compressed", "-s", "--silent", "-S", "--show-error", "-k", "--insecure", "-i", "--include", "--http1.1", "--http2":
                break
            default:
                if token.hasPrefix("-") {
                    throw CURLImportError.unsupportedOption(option.name)
                }
                if urlSource == nil { urlSource = token }
            }
            index += 1
        }

        guard let rawURL = urlSource?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
            throw CURLImportError.missingURL
        }
        guard let components = URLComponents(string: rawURL), components.host != nil, let scheme = components.scheme?.lowercased() else {
            throw CURLImportError.invalidURL
        }
        guard scheme == "http" || scheme == "https" else { throw CURLImportError.unsupportedScheme }

        let method = explicitMethod ?? (useGET ? .get : (dataValues.isEmpty ? .get : .post))
        var draft = HTTPRequestDraft(url: rawURL, headers: headers)
        draft.method = method

        if useGET {
            draft.queryItems = dataValues.compactMap(queryItem(from:))
        } else if !dataValues.isEmpty {
            let body = dataValues.joined(separator: "&")
            draft.body = body
            draft.bodyMode = isJSON(body, headers: headers) ? .json : .text
            if draft.bodyMode == .text, !containsHeader("Content-Type", in: headers), body.contains("=") {
                draft.headers.append(HTTPKeyValue(key: "Content-Type", value: "application/x-www-form-urlencoded"))
            }
        }
        return draft
    }

    private static func tokenize(_ source: String) throws -> [String] {
        enum State { case plain, singleQuoted, doubleQuoted }
        var state = State.plain
        var tokens: [String] = []
        var token = ""
        var tokenStarted = false
        var iterator = source.makeIterator()

        while let character = iterator.next() {
            switch state {
            case .plain:
                if character == "'" {
                    state = .singleQuoted
                    tokenStarted = true
                } else if character == "\"" {
                    state = .doubleQuoted
                    tokenStarted = true
                } else if character == "\\" {
                    guard let escaped = iterator.next() else {
                        token.append(character)
                        tokenStarted = true
                        continue
                    }
                    if escaped != "\n" { token.append(escaped); tokenStarted = true }
                } else if character.isWhitespace {
                    if tokenStarted { tokens.append(token); token = ""; tokenStarted = false }
                } else {
                    token.append(character)
                    tokenStarted = true
                }
            case .singleQuoted:
                if character == "'" { state = .plain } else { token.append(character) }
            case .doubleQuoted:
                if character == "\"" {
                    state = .plain
                } else if character == "\\", let escaped = iterator.next() {
                    if escaped != "\n" { token.append(escaped) }
                } else {
                    token.append(character)
                }
            }
        }

        guard state == .plain else { throw CURLImportError.unclosedQuote }
        if tokenStarted { tokens.append(token) }
        return tokens
    }

    private static func nextValue(after index: inout Int, tokens: [String], option: String) throws -> String {
        index += 1
        guard index < tokens.count else { throw CURLImportError.missingOptionValue(option) }
        return tokens[index]
    }

    private static func longOption(_ token: String) -> (name: String, value: String?) {
        guard token.hasPrefix("--"), let separator = token.firstIndex(of: "=") else { return (token, nil) }
        return (String(token[..<separator]), String(token[token.index(after: separator)...]))
    }

    private static func header(from source: String) -> HTTPKeyValue? {
        guard let separator = source.firstIndex(of: ":") else { return nil }
        let key = source[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        let value = source[source.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return HTTPKeyValue(key: key, value: value)
    }

    private static func queryItem(from source: String) -> HTTPKeyValue? {
        let pair = source.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard let rawKey = pair.first, !rawKey.isEmpty else { return nil }
        let rawValue = pair.count > 1 ? String(pair[1]) : ""
        return HTTPKeyValue(
            key: String(rawKey).removingPercentEncoding ?? String(rawKey),
            value: rawValue.removingPercentEncoding ?? rawValue
        )
    }

    private static func isJSON(_ source: String, headers: [HTTPKeyValue]) -> Bool {
        if headers.contains(where: {
            $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame && $0.value.lowercased().contains("json")
        }) { return true }
        guard let data = source.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    private static func containsHeader(_ name: String, in headers: [HTTPKeyValue]) -> Bool {
        headers.contains { $0.key.caseInsensitiveCompare(name) == .orderedSame }
    }
}
