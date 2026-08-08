import Foundation

enum DatabaseCommandPolicy {
    private static let readOnlySQLKeywords: Set<String> = [
        "SELECT", "SHOW", "DESCRIBE", "DESC", "EXPLAIN", "PRAGMA", "VALUES"
    ]
    private static let directSQLKeywords: Set<String> = ["INSERT", "CREATE"]
    private static let confirmationSQLKeywords: Set<String> = [
        "UPDATE", "DELETE", "TRUNCATE", "DROP", "ALTER", "REPLACE", "MERGE",
        "GRANT", "REVOKE", "VACUUM", "ATTACH", "DETACH", "REINDEX"
    ]

    private static let readOnlyRedisCommands: Set<String> = [
        "GET", "MGET", "EXISTS", "TYPE", "TTL", "PTTL", "KEYS", "SCAN", "SSCAN", "HSCAN", "ZSCAN",
        "HGET", "HMGET", "HGETALL", "HEXISTS", "HLEN", "HKEYS", "HVALS",
        "LRANGE", "LLEN", "LINDEX", "SMEMBERS", "SCARD", "SISMEMBER",
        "ZRANGE", "ZREVRANGE", "ZCARD", "ZSCORE", "INFO", "DBSIZE", "PING", "ECHO", "TIME"
    ]
    private static let redisInsertCommands: Set<String> = [
        "SETNX", "MSETNX", "HSETNX", "LPUSH", "RPUSH", "SADD", "ZADD", "XADD", "PFADD"
    ]
    private static let redisAlwaysConfirmCommands: Set<String> = [
        "DEL", "UNLINK", "FLUSHDB", "FLUSHALL", "RENAME", "RENAMENX", "EXPIRE", "PEXPIRE",
        "EXPIREAT", "PEXPIREAT", "PERSIST", "MOVE", "MIGRATE", "RESTORE", "LSET", "LTRIM",
        "LPOP", "RPOP", "SREM", "ZREM", "HDEL", "XDEL", "XTRIM", "INCR", "INCRBY", "DECR", "DECRBY"
    ]

    static func decision(for command: String, kind: DatabaseKind, redisKeyExists: Bool? = nil) -> DatabaseCommandDecision {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .reject("命令不能为空") }
        guard !containsMultipleStatements(trimmed, kind: kind) else { return .reject(DatabaseConnectionError.multipleStatements.localizedDescription) }

        if kind == .redis {
            return redisDecision(for: trimmed, keyExists: redisKeyExists)
        }

        let normalized = strippingLeadingSQLComments(trimmed)
        let tokens = sqlTokens(normalized)
        guard let first = tokens.first else { return .reject("无法识别 SQL 命令") }

        let effectiveKeyword: String
        if first == "WITH" {
            effectiveKeyword = tokens.first(where: confirmationSQLKeywords.contains)
                ?? tokens.first(where: directSQLKeywords.contains)
                ?? tokens.first(where: readOnlySQLKeywords.contains)
                ?? first
        } else {
            effectiveKeyword = first
        }

        let limited = applyingDefaultLimit(to: trimmed, kind: kind)
        if readOnlySQLKeywords.contains(effectiveKeyword) { return .execute(limited) }
        if directSQLKeywords.contains(effectiveKeyword) { return .execute(trimmed) }
        if confirmationSQLKeywords.contains(effectiveKeyword) {
            return .confirm(trimmed, reason: riskReason(for: effectiveKeyword))
        }
        return .confirm(trimmed, reason: "这条命令可能修改数据库结构或数据")
    }

    static func applyingDefaultLimit(to sql: String, kind: DatabaseKind) -> String {
        guard kind != .redis else { return sql }
        let normalized = strippingLeadingSQLComments(sql)
        let upper = normalized.uppercased()
        guard upper.hasPrefix("SELECT") || upper.hasPrefix("WITH") else { return sql }
        guard !matches("\\bLIMIT\\s+\\d+", in: upper),
              !matches("\\bFETCH\\s+(FIRST|NEXT)\\s+\\d+", in: upper),
              !matches("\\b(COUNT|SUM|AVG|MIN|MAX|EXISTS)\\s*\\(", in: upper),
              !matches("\\bFOR\\s+(UPDATE|SHARE)\\b", in: upper) else { return sql }

        let withoutSemicolon = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        if withoutSemicolon.hasSuffix(";") {
            return String(withoutSemicolon.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) + " LIMIT 20;"
        }
        return withoutSemicolon + " LIMIT 20"
    }

    static func redisArguments(from command: String) throws -> [String] {
        var output: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false

        for character in command {
            if escaping {
                current.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if let activeQuote = quote {
                if character == activeQuote { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty {
                    output.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        guard quote == nil else { throw DatabaseConnectionError.invalidCommand("命令中的引号没有闭合") }
        if escaping { current.append("\\") }
        if !current.isEmpty { output.append(current) }
        guard !output.isEmpty else { throw DatabaseConnectionError.invalidCommand("命令不能为空") }
        return output
    }

    static func validatedIdentifier(_ value: String) throws -> String {
        guard !value.isEmpty,
              value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$-")).contains($0) }) else {
            throw DatabaseConnectionError.invalidCommand("数据库名称只能包含字母、数字、下划线、短横线或 $ 符号")
        }
        return value
    }

    private static func redisDecision(for command: String, keyExists: Bool?) -> DatabaseCommandDecision {
        guard let arguments = try? redisArguments(from: command), let keyword = arguments.first?.uppercased() else {
            return .reject("无法识别 Redis 命令")
        }
        if readOnlyRedisCommands.contains(keyword) { return .execute(command) }
        if redisInsertCommands.contains(keyword) { return .execute(command) }
        if keyword == "SET" || keyword == "MSET" || keyword == "HSET" {
            if keyExists == false { return .execute(command) }
            return .confirm(command, reason: "这条命令会覆盖已有键或字段")
        }
        if redisAlwaysConfirmCommands.contains(keyword) {
            return .confirm(command, reason: "这条 Redis 命令会更新或删除已有数据")
        }
        return .confirm(command, reason: "这条 Redis 命令可能改变数据库内容")
    }

    private static func riskReason(for keyword: String) -> String {
        switch keyword {
        case "UPDATE", "REPLACE", "MERGE": "这条命令会更新已有数据"
        case "DELETE", "TRUNCATE": "这条命令会删除数据，操作可能无法恢复"
        case "DROP": "这条命令会删除数据库对象，操作可能无法恢复"
        case "ALTER": "这条命令会修改数据库结构"
        case "GRANT", "REVOKE": "这条命令会修改访问权限"
        default: "这条命令可能修改数据库"
        }
    }

    private static func strippingLeadingSQLComments(_ sql: String) -> String {
        var value = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        while true {
            if value.hasPrefix("--"), let newline = value.firstIndex(of: "\n") {
                value = String(value[value.index(after: newline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if value.hasPrefix("/*"), let end = value.range(of: "*/") {
                value = String(value[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                break
            }
        }
        return value
    }

    private static func sqlTokens(_ sql: String) -> [String] {
        sql.uppercased().split { !$0.isLetter && !$0.isNumber && $0 != "_" }.map(String.init)
    }

    private static func matches(_ pattern: String, in value: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func containsMultipleStatements(_ command: String, kind: DatabaseKind) -> Bool {
        guard kind != .redis else { return command.contains("\n") && command.split(separator: "\n").count > 1 }
        var quote: Character?
        var isLineComment = false
        var isBlockComment = false
        var statementEnded = false
        let characters = Array(command)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : "\0"
            if isLineComment {
                if character == "\n" { isLineComment = false }
            } else if isBlockComment {
                if character == "*" && next == "/" { isBlockComment = false; index += 1 }
            } else if let activeQuote = quote {
                if character == activeQuote {
                    if next == activeQuote { index += 1 } else { quote = nil }
                }
            } else if character == "'" || character == "\"" || character == "`" {
                quote = character
            } else if character == "-" && next == "-" {
                isLineComment = true; index += 1
            } else if character == "/" && next == "*" {
                isBlockComment = true; index += 1
            } else if character == ";" {
                statementEnded = true
            } else if statementEnded && !character.isWhitespace {
                return true
            }
            index += 1
        }
        return false
    }
}
