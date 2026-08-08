import Foundation

// MARK: - DeepSeek API Response Models

private struct DeepSeekChatResponse: Decodable {
    let choices: [Choice]?
    let error: APIError?

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }

    struct APIError: Decodable {
        let message: String
    }
}

// MARK: - Provider

struct DeepSeekAIProvider: AIProvider {
    let apiKey: String
    let model: String
    let httpClient: HTTPRequestClient

    init(apiKey: String,
         model: String = "deepseek-v4-flash",
         httpClient: HTTPRequestClient = HTTPRequestClient()) {
        self.apiKey = apiKey
        self.model = model
        self.httpClient = httpClient
    }

    var name: String {
        switch model {
        case "deepseek-v4-pro": "DeepSeek V4 Pro"
        default: "DeepSeek V4 Flash"
        }
    }
    var requiresNetwork: Bool { true }

    func answer(question: String, context: [NoteExcerpt]) async throws -> GroundedAnswer {
        guard !context.isEmpty else {
            return GroundedAnswer(
                text: "没有在现有笔记中找到足够依据。可以换一个更精确的关键词，或扩大搜索范围。",
                sources: []
            )
        }

        let sources = context.map(\.result)
        let systemPrompt = Self.systemPrompt
        let userMessage = Self.buildUserMessage(question: question, excerpts: context)

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "temperature": 0.3,
            "thinking": ["type": "disabled"],
            "max_tokens": 2048,
            "stream": false
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw DeepSeekError.invalidRequestBody
        }

        var request = URLRequest(url: URL(string: "https://api.deepseek.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        request.timeoutInterval = 60

        let response = try await httpClient.send(request)

        guard (200...299).contains(response.statusCode) else {
            if let error = parseError(from: response.body) {
                throw DeepSeekError.apiError(response.statusCode, error)
            }
            throw DeepSeekError.httpError(response.statusCode)
        }

        guard let data = response.body.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(DeepSeekChatResponse.self, from: data) else {
            throw DeepSeekError.unexpectedResponse
        }

        if let apiError = decoded.error {
            throw DeepSeekError.apiError(response.statusCode, apiError.message)
        }

        guard let text = decoded.choices?.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw DeepSeekError.emptyContent
        }

        return GroundedAnswer(text: text, sources: sources)
    }

    // MARK: - Prompt Helpers

    private static let systemPrompt = """
        你是一个帮助用户基于已有笔记回答问题的助手。请仅根据下方提供的笔记片段回答问题。\
        如果笔记中没有足够信息，请如实说明，不要编造。请用中文回答。

        回答要求：
        - 引用具体笔记时，使用"根据《笔记标题》中的记录…"的格式。
        - 不要编造笔记中不存在的信息。
        - 回答末尾不需要列出引用来源，系统会自动附带来源链接。
        """

    private static func buildUserMessage(question: String, excerpts: [NoteExcerpt]) -> String {
        let contextBlocks = excerpts.enumerated().map { index, excerpt in
            let result = excerpt.result
            return "---\n\(index + 1). 《\(result.noteTitle)》（\(result.path)）\n   \(result.excerpt)"
        }.joined(separator: "\n")

        return """
            问题：\(question)

            相关笔记片段：
            \(contextBlocks)

            （共 \(excerpts.count) 个相关片段）
            """
    }

    // MARK: - Error Parsing

    private func parseError(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(DeepSeekChatResponse.self, from: data) else {
            return nil
        }
        return decoded.error?.message
    }
}

// MARK: - Error Types

enum DeepSeekError: LocalizedError {
    case invalidRequestBody
    case httpError(Int)
    case apiError(Int, String)
    case unexpectedResponse
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .invalidRequestBody:
            "无法构造 API 请求体"
        case .httpError(let code):
            "服务器返回错误（HTTP \(code)），请稍后重试"
        case .apiError(let code, let message):
            code == 401 ? "API Key 无效，请在设置中检查" : "DeepSeek API 错误：\(message)"
        case .unexpectedResponse:
            "无法解析 DeepSeek 响应，请稍后重试"
        case .emptyContent:
            "DeepSeek 返回了空的回答内容"
        }
    }
}
