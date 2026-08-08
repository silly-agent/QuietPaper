import Foundation

enum DatabaseKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case mysql
    case postgresql
    case redis
    case sqlite

    var id: Self { self }

    var title: String {
        switch self {
        case .mysql: "MySQL"
        case .postgresql: "PostgreSQL"
        case .redis: "Redis"
        case .sqlite: "SQLite"
        }
    }

    var subtitle: String {
        switch self {
        case .mysql: "关系型数据库"
        case .postgresql: "高级开源数据库"
        case .redis: "内存键值数据库"
        case .sqlite: "本地数据库文件"
        }
    }

    var systemImage: String {
        switch self {
        case .mysql: "cylinder.fill"
        case .postgresql: "cylinder.split.1x2"
        case .redis: "square.stack.3d.up.fill"
        case .sqlite: "externaldrive.fill"
        }
    }

    var defaultPort: Int {
        switch self {
        case .mysql: 3306
        case .postgresql: 5432
        case .redis: 6379
        case .sqlite: 0
        }
    }
}

struct DatabaseConnectionSettings: Codable, Equatable, Sendable {
    var host = "127.0.0.1"
    var port = 0
    var username = ""
    var password = ""
    var database = ""
    var sqlitePath = ""
    var redisDatabase = 0
    var useTLS = false

    mutating func applyDefaults(for kind: DatabaseKind) {
        if port == 0 { port = kind.defaultPort }
        if kind == .postgresql, database.isEmpty { database = "postgres" }
        if kind == .sqlite { sqlitePath = Self.normalizedSQLitePath(sqlitePath) }
    }

    static func normalizedSQLitePath(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let unescapedSpaces = trimmed.replacingOccurrences(of: "\\ ", with: " ")
        let expanded = (unescapedSpaces as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    var redactedSummary: String {
        if !sqlitePath.isEmpty { return URL(fileURLWithPath: sqlitePath).lastPathComponent }
        let databaseSuffix = database.isEmpty ? "" : "/\(database)"
        return "\(host):\(port)\(databaseSuffix)"
    }
}

enum DatabaseMessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

struct DatabaseQueryResult: Codable, Equatable, Sendable {
    var columns: [String]
    var rows: [[String?]]
    var affectedRows: Int?
    var duration: TimeInterval
    var message: String

    static func message(_ text: String, duration: TimeInterval = 0, affectedRows: Int? = nil) -> Self {
        .init(columns: [], rows: [], affectedRows: affectedRows, duration: duration, message: text)
    }

    var compactToolDescription: String {
        if !rows.isEmpty {
            let previewRows = rows.prefix(20).map { row in
                Dictionary(uniqueKeysWithValues: zip(columns, row.map { $0 ?? "NULL" }))
            }
            if let data = try? JSONSerialization.data(withJSONObject: Array(previewRows), options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                return "查询成功，返回 \(rows.count) 行，耗时 \(duration.formattedMilliseconds)。结果：\(json)"
            }
        }
        if !columns.isEmpty || message.hasPrefix("查询完成") {
            return "查询成功，返回 0 行，耗时 \(duration.formattedMilliseconds)。没有符合条件的数据。"
        }
        if let affectedRows { return "执行成功，影响 \(affectedRows) 行，耗时 \(duration.formattedMilliseconds)。\(message)" }
        return "执行成功，耗时 \(duration.formattedMilliseconds)。\(message)"
    }

    var persisted: Self {
        var copy = self
        if copy.rows.count > 50 {
            copy.rows = Array(copy.rows.prefix(50))
            copy.message += "（文件中仅保留前 50 行预览）"
        }
        return copy
    }
}

struct DatabaseConversationMessage: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var role: DatabaseMessageRole
    var text: String
    var reasoning: String?
    var command: String?
    var result: DatabaseQueryResult?
    var createdAt = Date()
}

struct DatabaseConnectionFile: Codable, Equatable, Sendable {
    var version = 1
    var kind: DatabaseKind?
    var settings = DatabaseConnectionSettings()
    var messages: [DatabaseConversationMessage] = []

    static func decode(_ source: String) -> Self {
        guard let data = source.data(using: .utf8) else { return Self() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var value = try? decoder.decode(Self.self, from: data) else {
            return Self()
        }
        if let kind = value.kind { value.settings.applyDefaults(for: kind) }
        return value
    }

    func encoded() throws -> String {
        var copy = self
        copy.messages = copy.messages.suffix(100).map { message in
            var message = message
            message.result = message.result?.persisted
            return message
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(copy)
        return String(decoding: data, as: UTF8.self)
    }

    var searchableText: String {
        let messageText = messages.map { [$0.text, $0.command ?? ""] }.flatMap { $0 }
        return ([kind?.title ?? "数据库连接", settings.host, settings.username, settings.database, settings.sqlitePath] + messageText)
            .joined(separator: "\n")
    }
}

enum DatabaseConnectionStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var label: String {
        switch self {
        case .disconnected: "已断开"
        case .connecting: "正在连接"
        case .connected: "已连接"
        case .failed: "连接失败"
        }
    }
}

enum DatabaseCommandDecision: Equatable, Sendable {
    case execute(String)
    case confirm(String, reason: String)
    case reject(String)
}

struct PendingDatabaseCommand: Identifiable, Equatable, Sendable {
    let id = UUID()
    let command: String
    let explanation: String
    let userQuestion: String
    let reasoning: String?
    let agentContext: DatabaseAgentContext?
}

struct DatabaseAgentContext: Equatable, Sendable {
    let messagesJSON: Data
    let toolCallID: String
}

enum DatabaseConnectionError: LocalizedError, Equatable, Sendable {
    case incompleteConfiguration(String)
    case notConnected
    case invalidCommand(String)
    case multipleStatements
    case missingAPIKey
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .incompleteConfiguration(let field): "请先填写\(field)"
        case .notConnected: "连接已断开，请重新连接后再试"
        case .invalidCommand(let reason): reason
        case .multipleStatements: "为保证安全，一次只能执行一条命令"
        case .missingAPIKey: "请先在 AI 设置中保存 DeepSeek API Key"
        case .unexpectedResponse: "AI 返回了无法识别的响应，请重试"
        }
    }
}

extension TimeInterval {
    var formattedMilliseconds: String {
        if self < 1 { return "\(Int(self * 1_000)) ms" }
        return String(format: "%.2f s", self)
    }
}
