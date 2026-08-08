import Foundation

struct DatabaseAgentPlan: Sendable {
    let content: String
    let reasoning: String?
    let command: String?
    let explanation: String
    let context: DatabaseAgentContext?
}

struct DatabaseAgentReply: Sendable {
    let content: String
    let reasoning: String?
    let command: String?
    let explanation: String
    let context: DatabaseAgentContext?
}

private struct DeepSeekToolResponse: Decodable {
    let choices: [Choice]?
    let error: APIError?

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let role: String
        let content: String?
        let reasoningContent: String?
        let toolCalls: [ToolCall]?

        enum CodingKeys: String, CodingKey {
            case role, content
            case reasoningContent = "reasoning_content"
            case toolCalls = "tool_calls"
        }
    }

    struct ToolCall: Decodable {
        let id: String
        let type: String
        let function: Function

        struct Function: Decodable {
            let name: String
            let arguments: String
        }
    }

    struct APIError: Decodable { let message: String }
}

private struct DatabaseToolArguments: Decodable {
    let command: String
    let explanation: String?
}

struct DeepSeekDatabaseAgent: Sendable {
    let apiKey: String
    let model: String
    let httpClient: HTTPRequestClient

    init(apiKey: String, model: String = "deepseek-v4-flash", httpClient: HTTPRequestClient = HTTPRequestClient()) {
        self.apiKey = apiKey
        self.model = Self.currentModel(model)
        self.httpClient = httpClient
    }

    static func configured() throws -> Self {
        let environmentKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]
        guard let key = [environmentKey, KeychainStore().get()]
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else {
            throw DatabaseConnectionError.missingAPIKey
        }
        let storedModel = UserDefaults.standard.string(forKey: "deepseek_model") ?? "deepseek-v4-flash"
        return Self(apiKey: key, model: storedModel)
    }

    func plan(
        question: String,
        kind: DatabaseKind,
        connectionSummary: String,
        schema: String,
        history: [DatabaseConversationMessage]
    ) async throws -> DatabaseAgentPlan {
        var messages: [[String: Any]] = [["role": "system", "content": Self.systemPrompt(kind: kind)]]
        let recentHistory = Array(history.suffix(40))
        for (index, message) in recentHistory.enumerated() where !message.text.isEmpty {
            switch message.role {
            case .user:
                messages.append(["role": "user", "content": message.text])
            case .assistant:
                var context = message.text
                if let command = message.command, !command.isEmpty {
                    context += "\n历史执行命令：\(command)"
                }
                if index >= recentHistory.count - 8, let result = message.result {
                    context += "\n历史返回摘要：\(result.compactToolDescription)"
                }
                messages.append(["role": "assistant", "content": context])
            case .system:
                continue
            }
        }
        messages.append([
            "role": "user",
            "content": """
                当前连接：\(kind.title) · \(connectionSummary)
                数据库结构（仅为本地工具返回的脱敏信息）：
                \(schema)

                用户要求：\(question)
                """
        ])

        let response = try await request(messages: messages, includeTools: true)
        guard let message = response.choices?.first?.message else { throw DatabaseConnectionError.unexpectedResponse }
        guard let toolCall = message.toolCalls?.first else {
            return DatabaseAgentPlan(
                content: message.content?.nonEmpty ?? "我需要更多信息才能生成数据库命令。",
                reasoning: Self.cleanedReasoning(message.reasoningContent),
                command: nil,
                explanation: "",
                context: nil
            )
        }
        guard toolCall.function.name == "execute_database_command",
              let argumentData = toolCall.function.arguments.data(using: .utf8),
              let arguments = try? JSONDecoder().decode(DatabaseToolArguments.self, from: argumentData),
              !arguments.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DatabaseConnectionError.unexpectedResponse
        }

        var assistant: [String: Any] = [
            "role": message.role,
            "content": message.content ?? "",
            "tool_calls": [[
                "id": toolCall.id,
                "type": toolCall.type,
                "function": ["name": toolCall.function.name, "arguments": toolCall.function.arguments]
            ]]
        ]
        if let reasoning = message.reasoningContent { assistant["reasoning_content"] = reasoning }
        messages.append(assistant)
        let contextData = try JSONSerialization.data(withJSONObject: messages)
        return DatabaseAgentPlan(
            content: message.content ?? "",
            reasoning: Self.cleanedReasoning(message.reasoningContent),
            command: arguments.command.trimmingCharacters(in: .whitespacesAndNewlines),
            explanation: arguments.explanation?.nonEmpty ?? "执行 AI 生成的数据库命令",
            context: DatabaseAgentContext(messagesJSON: contextData, toolCallID: toolCall.id)
        )
    }

    func complete(context: DatabaseAgentContext, result: DatabaseQueryResult) async throws -> DatabaseAgentReply {
        guard var messages = try JSONSerialization.jsonObject(with: context.messagesJSON) as? [[String: Any]] else {
            throw DatabaseConnectionError.unexpectedResponse
        }
        messages.append([
            "role": "tool",
            "tool_call_id": context.toolCallID,
            "content": result.compactToolDescription
        ])
        let response = try await request(messages: messages, includeTools: true)
        guard let message = response.choices?.first?.message else { throw DatabaseConnectionError.unexpectedResponse }
        if let toolCall = message.toolCalls?.first {
            guard toolCall.function.name == "execute_database_command",
                  let argumentData = toolCall.function.arguments.data(using: .utf8),
                  let arguments = try? JSONDecoder().decode(DatabaseToolArguments.self, from: argumentData),
                  !arguments.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DatabaseConnectionError.unexpectedResponse
            }
            var assistant: [String: Any] = [
                "role": message.role,
                "content": message.content ?? "",
                "tool_calls": [[
                    "id": toolCall.id,
                    "type": toolCall.type,
                    "function": ["name": toolCall.function.name, "arguments": toolCall.function.arguments]
                ]]
            ]
            if let reasoning = message.reasoningContent { assistant["reasoning_content"] = reasoning }
            messages.append(assistant)
            let contextData = try JSONSerialization.data(withJSONObject: messages)
            return DatabaseAgentReply(
                content: Self.cleanedUserFacingText(message.content) ?? "",
                reasoning: Self.cleanedReasoning(message.reasoningContent),
                command: arguments.command.trimmingCharacters(in: .whitespacesAndNewlines),
                explanation: arguments.explanation?.nonEmpty ?? "继续完成数据库操作",
                context: DatabaseAgentContext(messagesJSON: contextData, toolCallID: toolCall.id)
            )
        }
        return DatabaseAgentReply(
            content: Self.cleanedUserFacingText(message.content) ?? result.compactToolDescription,
            reasoning: Self.cleanedReasoning(message.reasoningContent),
            command: nil,
            explanation: "",
            context: nil
        )
    }

    private func request(messages: [[String: Any]], includeTools: Bool) async throws -> DeepSeekToolResponse {
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "thinking": ["type": "enabled"],
            "reasoning_effort": "high",
            "max_tokens": 4_096,
            "stream": false
        ]
        if includeTools {
            body["tools"] = [Self.databaseTool]
            body["tool_choice"] = "auto"
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = data
        request.timeoutInterval = 90

        let snapshot = try await httpClient.send(request)
        guard let responseData = snapshot.body.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(DeepSeekToolResponse.self, from: responseData) else {
            throw DatabaseConnectionError.unexpectedResponse
        }
        if let apiError = decoded.error { throw DeepSeekError.apiError(snapshot.statusCode, apiError.message) }
        guard (200...299).contains(snapshot.statusCode) else { throw DeepSeekError.httpError(snapshot.statusCode) }
        return decoded
    }

    private static func currentModel(_ value: String) -> String {
        switch value {
        case "deepseek-chat", "deepseek-reasoner": "deepseek-v4-flash"
        case "deepseek-v4-flash", "deepseek-v4-pro": value
        default: "deepseek-v4-flash"
        }
    }

    private static func systemPrompt(kind: DatabaseKind) -> String {
        """
        你是 Quiet Paper 的数据库助手，当前数据库类型是 \(kind.title)。你可以解释数据库结构，也可以调用本地工具执行一条数据库命令。

        必须遵守：
        1. 用户查询某张表的数据但没有明确数量时，生成的 SQL 必须包含 LIMIT 20；应用本地执行器还会再次强制检查。
        2. 每次工具调用只能包含一条 SQL 或一条 Redis 命令，禁止把多条语句拼在一起。
        3. INSERT 与 CREATE 可直接执行。UPDATE、DELETE、TRUNCATE、DROP、ALTER、权限变更以及覆盖或删除 Redis 数据会由应用弹窗二次确认。
        4. 不要询问、复述或输出密码、连接串、令牌、个人敏感信息；连接凭据由本地连接器处理，绝不应进入工具命令。
        5. 不猜测不存在的表和字段；结构不足时先用只读命令检查结构，或向用户提问。
        6. 对执行结果只用中文给出一两句简洁说明；真实数据会由应用单独渲染为表格，不要在回复中重复输出 Markdown 表格、逐行数据或完整结果集。
        7. MySQL 新建数据库必须使用 CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci。
        8. 用户要求查询具体数据时必须完成真正的 SELECT 查询。若先调用 SHOW COLUMNS、DESCRIBE 或其他命令确认结构，拿到结构后必须继续调用工具执行 SELECT，不能把结构检查当作最终答案。
        9. 不要在 content 或 reasoning_content 中输出 DSML、tool_calls、invoke、parameter 等内部工具协议标记。
        10. 应用允许你在一次用户请求中连续调用数据库工具最多 20 次。只要仍能通过只读检查推进任务，就继续分析和查询，直到得到用户真正要求的答案；不要在中间结构检查后提前结束。
        """
    }

    private static var databaseTool: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "execute_database_command",
                "description": "在当前本地数据库连接中执行一条 SQL 或 Redis 命令。只允许一条命令。",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "command": ["type": "string", "description": "要执行的一条完整数据库命令"],
                        "explanation": ["type": "string", "description": "用中文简短解释命令目的和影响"]
                    ],
                    "required": ["command", "explanation"],
                    "additionalProperties": false
                ]
            ]
        ]
    }

    private static func cleanedUserFacingText(_ source: String?) -> String? {
        cleanedBeforeToolProtocol(source)
    }

    private static func cleanedReasoning(_ source: String?) -> String? {
        cleanedBeforeToolProtocol(source)
    }

    private static func cleanedBeforeToolProtocol(_ source: String?) -> String? {
        guard let source else { return nil }
        let markers = ["DSML", "tool_calls", "invoke name=", "parameter name="]
        let firstMarker = markers.compactMap { source.range(of: $0, options: .caseInsensitive)?.lowerBound }.min()
        let clean: String
        if let firstMarker {
            let lineStart = source[..<firstMarker].lastIndex(of: "\n").map { source.index(after: $0) } ?? source.startIndex
            clean = String(source[..<lineStart])
        } else {
            clean = source
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
