import Foundation

enum WebSocketClientError: LocalizedError, Equatable, Sendable {
    case missingURL
    case invalidURL
    case unsupportedScheme
    case notConnected

    var errorDescription: String? {
        switch self {
        case .missingURL: "请输入 WebSocket URL"
        case .invalidURL: "WebSocket URL 格式不正确"
        case .unsupportedScheme: "仅支持 ws 和 wss 地址"
        case .notConnected: "WebSocket 尚未连接"
        }
    }
}

enum WebSocketPayload: Sendable {
    case text(String)
    case binary(Data)

    var displayText: String {
        switch self {
        case .text(let text): text
        case .binary(let data): "二进制消息 · \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
        }
    }
}

actor WebSocketClient {
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?

    func connect(_ draft: WebSocketRequestDraft) throws {
        disconnect()
        let request = try Self.makeRequest(draft)
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        self.session = session
        self.task = task
        task.resume()
    }

    func receive() async throws -> WebSocketPayload {
        guard let task else { throw WebSocketClientError.notConnected }
        switch try await task.receive() {
        case .string(let text): return .text(text)
        case .data(let data): return .binary(data)
        @unknown default: return .text("收到未知类型消息")
        }
    }

    func send(text: String) async throws {
        guard let task else { throw WebSocketClientError.notConnected }
        try await task.send(.string(text))
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        task = nil
        session = nil
    }

    static func makeRequest(_ draft: WebSocketRequestDraft) throws -> URLRequest {
        let source = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw WebSocketClientError.missingURL }
        guard let components = URLComponents(string: source),
              components.host != nil,
              let scheme = components.scheme?.lowercased(),
              let url = components.url else {
            throw WebSocketClientError.invalidURL
        }
        guard scheme == "ws" || scheme == "wss" else { throw WebSocketClientError.unsupportedScheme }

        var request = URLRequest(url: url, timeoutInterval: 30)
        for header in draft.headers where header.isEnabled {
            let key = header.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            request.setValue(header.value, forHTTPHeaderField: key)
        }
        return request
    }
}
