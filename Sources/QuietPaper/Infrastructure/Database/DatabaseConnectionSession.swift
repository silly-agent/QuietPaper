import CSQLite
import Foundation
import Logging
import MySQLKit
import NIOPosix
import PostgresKit
@preconcurrency import RediStack

final class DatabaseConnectionSession: @unchecked Sendable {
    private enum Handle {
        case mysql(EventLoopGroupConnectionPool<MySQLConnectionSource>)
        case postgresql(EventLoopGroupConnectionPool<PostgresConnectionSource>)
        case redis(RedisConnection)
        case sqlite(ExternalSQLiteHandle)
    }

    private let logger = Logger(label: "com.quietpaper.database")
    private let stateLock = NSRecursiveLock()
    private var handle: Handle?
    private var idleTask: Task<Void, Never>?
    private let idleTimeout: Duration
    var onIdleDisconnect: (@Sendable () -> Void)?

    init(idleTimeout: Duration = .seconds(10 * 60)) {
        self.idleTimeout = idleTimeout
    }

    deinit {
        idleTask?.cancel()
        if case .sqlite(let sqlite) = handle { sqlite.close() }
        if case .redis(let redis) = handle { _ = redis.close() }
        if case .mysql(let pool) = handle { pool.shutdown() }
        if case .postgresql(let pool) = handle { pool.shutdown() }
    }

    func connect(kind: DatabaseKind, settings: DatabaseConnectionSettings) async throws {
        await disconnect()
        var settings = settings
        settings.applyDefaults(for: kind)
        try Self.validate(kind: kind, settings: settings)

        switch kind {
        case .mysql:
            let configuration = MySQLConfiguration(
                hostname: settings.host,
                port: settings.port,
                username: settings.username,
                password: settings.password,
                database: settings.database.isEmpty ? "information_schema" : settings.database,
                tlsConfiguration: settings.useTLS ? .makeClientConfiguration() : nil
            )
            let pool = EventLoopGroupConnectionPool(
                source: MySQLConnectionSource(configuration: configuration),
                maxConnectionsPerEventLoop: 1,
                requestTimeout: .seconds(12),
                pruneInterval: .seconds(30),
                maxIdleTimeBeforePruning: .seconds(120),
                logger: logger,
                on: NIOSingletons.posixEventLoopGroup
            )
            do {
                _ = try await pool.database(logger: logger).sql().raw("SELECT 1").all()
                setHandle(.mysql(pool))
            } catch {
                try? await pool.shutdownAsync()
                throw error
            }
        case .postgresql:
            let tls: PostgresConnection.Configuration.TLS
            if settings.useTLS {
                tls = try .require(.init(configuration: .makeClientConfiguration()))
            } else {
                tls = .disable
            }
            let configuration = SQLPostgresConfiguration(
                hostname: settings.host,
                port: settings.port,
                username: settings.username,
                password: settings.password.isEmpty ? nil : settings.password,
                database: settings.database.isEmpty ? nil : settings.database,
                tls: tls
            )
            let pool = EventLoopGroupConnectionPool(
                source: PostgresConnectionSource(sqlConfiguration: configuration),
                maxConnectionsPerEventLoop: 1,
                requestTimeout: .seconds(12),
                pruneInterval: .seconds(30),
                maxIdleTimeBeforePruning: .seconds(120),
                logger: logger,
                on: NIOSingletons.posixEventLoopGroup
            )
            do {
                _ = try await pool.database(logger: logger).sql().raw("SELECT 1").all()
                setHandle(.postgresql(pool))
            } catch {
                try? await pool.shutdownAsync()
                throw error
            }
        case .redis:
            let configuration = try RedisConnection.Configuration(
                address: .makeAddressResolvingHost(settings.host, port: settings.port),
                username: settings.username.isEmpty ? nil : settings.username,
                password: settings.password.isEmpty ? nil : settings.password,
                initialDatabase: settings.redisDatabase,
                defaultLogger: logger
            )
            let connection = try await RedisConnection.make(
                configuration: configuration,
                boundEventLoop: NIOSingletons.posixEventLoopGroup.any()
            ).get()
            do {
                _ = try await connection.send(command: "PING").get()
                setHandle(.redis(connection))
            } catch {
                try? await connection.close().get()
                throw error
            }
        case .sqlite:
            let sqlite = try ExternalSQLiteHandle(path: settings.sqlitePath)
            setHandle(.sqlite(sqlite))
        }
        scheduleIdleDisconnect()
    }

    func disconnect() async {
        idleTask?.cancel()
        idleTask = nil
        let existing = takeHandle()
        switch existing {
        case .mysql(let pool): try? await pool.shutdownAsync()
        case .postgresql(let pool): try? await pool.shutdownAsync()
        case .redis(let connection): try? await connection.close().get()
        case .sqlite(let sqlite): sqlite.close()
        case nil: break
        }
    }

    func execute(_ command: String, kind: DatabaseKind) async throws -> DatabaseQueryResult {
        let startedAt = Date()
        let current = currentHandle()
        guard current != nil else { throw DatabaseConnectionError.notConnected }

        let result: DatabaseQueryResult
        switch current {
        case .mysql(let pool):
            let rows = try await pool.database(logger: logger).sql().raw(SQLQueryString(command)).all()
            result = Self.result(from: rows, command: command, startedAt: startedAt)
        case .postgresql(let pool):
            let rows = try await pool.database(logger: logger).sql().raw(SQLQueryString(command)).all()
            result = Self.result(from: rows, command: command, startedAt: startedAt)
        case .redis(let connection):
            let arguments = try DatabaseCommandPolicy.redisArguments(from: command)
            let response = try await connection.send(
                command: arguments[0].uppercased(),
                with: arguments.dropFirst().map { RESPValue(from: $0) }
            ).get()
            result = Self.result(from: response, startedAt: startedAt)
        case .sqlite(let sqlite):
            result = try sqlite.execute(command, startedAt: startedAt)
        case nil:
            throw DatabaseConnectionError.notConnected
        }
        scheduleIdleDisconnect()
        return result
    }

    func decision(for command: String, kind: DatabaseKind) async -> DatabaseCommandDecision {
        guard kind == .redis,
              let arguments = try? DatabaseCommandPolicy.redisArguments(from: command),
              let keyword = arguments.first?.uppercased(),
              ["SET", "MSET", "HSET"].contains(keyword),
              arguments.count > 1,
              case .redis(let connection) = currentHandle() else {
            return DatabaseCommandPolicy.decision(for: command, kind: kind)
        }
        let exists = (try? await connection.exists(RedisKey(arguments[1])).get()) ?? 0
        return DatabaseCommandPolicy.decision(for: command, kind: kind, redisKeyExists: exists > 0)
    }

    func schemaOverview(kind: DatabaseKind) async throws -> String {
        let command: String
        switch kind {
        case .mysql:
            command = """
                SELECT table_schema, table_name, column_name, data_type
                FROM information_schema.columns
                WHERE table_schema = DATABASE()
                ORDER BY table_name, ordinal_position LIMIT 300
                """
        case .postgresql:
            command = """
                SELECT table_schema, table_name, column_name, data_type
                FROM information_schema.columns
                WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
                ORDER BY table_schema, table_name, ordinal_position LIMIT 300
                """
        case .sqlite:
            command = "SELECT name, type, sql FROM sqlite_master WHERE type IN ('table', 'view') ORDER BY name LIMIT 100"
        case .redis:
            command = "SCAN 0 COUNT 20"
        }
        return try await execute(command, kind: kind).compactToolDescription
    }

    func mysqlDatabases() async throws -> [String] {
        guard case .mysql = currentHandle() else { throw DatabaseConnectionError.notConnected }
        let result = try await execute("SHOW DATABASES", kind: .mysql)
        return result.rows.compactMap(\.first).compactMap { $0 }.filter { !$0.isEmpty }
    }

    func createMySQLDatabase(named name: String) async throws {
        let identifier = try DatabaseCommandPolicy.validatedIdentifier(name)
        _ = try await execute(
            "CREATE DATABASE `\(identifier)` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci",
            kind: .mysql
        )
    }

    private func scheduleIdleDisconnect() {
        idleTask?.cancel()
        idleTask = Task { [weak self, idleTimeout] in
            try? await Task.sleep(for: idleTimeout)
            guard !Task.isCancelled, let self else { return }
            await self.disconnect()
            self.onIdleDisconnect?()
        }
    }

    private func setHandle(_ value: Handle) {
        stateLock.lock(); defer { stateLock.unlock() }
        handle = value
    }

    private func takeHandle() -> Handle? {
        stateLock.lock(); defer { stateLock.unlock() }
        defer { handle = nil }
        return handle
    }

    private func currentHandle() -> Handle? {
        stateLock.lock(); defer { stateLock.unlock() }
        return handle
    }

    private static func validate(kind: DatabaseKind, settings: DatabaseConnectionSettings) throws {
        if kind == .sqlite {
            guard !settings.sqlitePath.isEmpty else { throw DatabaseConnectionError.incompleteConfiguration(" SQLite 文件") }
            return
        }
        guard !settings.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DatabaseConnectionError.incompleteConfiguration("主机地址")
        }
        guard settings.port > 0 && settings.port <= 65_535 else {
            throw DatabaseConnectionError.incompleteConfiguration("有效端口")
        }
        if kind != .redis, settings.username.isEmpty {
            throw DatabaseConnectionError.incompleteConfiguration("用户名")
        }
    }

    private static func result(from rows: [any SQLRow], command: String, startedAt: Date) -> DatabaseQueryResult {
        let columns = rows.first?.allColumns ?? []
        let values = rows.map { row in columns.map { displayValue(row: row, column: $0) } }
        let keyword = command.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace || $0 == ";" })
            .first?.uppercased() ?? ""
        let isQuery = ["SELECT", "SHOW", "DESCRIBE", "DESC", "EXPLAIN", "PRAGMA", "WITH", "VALUES"].contains(keyword)
        return DatabaseQueryResult(
            columns: columns,
            rows: values,
            affectedRows: nil,
            duration: Date().timeIntervalSince(startedAt),
            message: rows.isEmpty && isQuery ? "查询完成，没有符合条件的数据" : (rows.isEmpty ? "命令执行成功" : "返回 \(rows.count) 行")
        )
    }

    private static func displayValue(row: any SQLRow, column: String) -> String? {
        if (try? row.decodeNil(column: column)) == true { return nil }
        if let value = try? row.decode(column: column, as: String.self) { return value }
        if let value = try? row.decode(column: column, as: Int.self) { return String(value) }
        if let value = try? row.decode(column: column, as: Int64.self) { return String(value) }
        if let value = try? row.decode(column: column, as: Double.self) { return String(value) }
        if let value = try? row.decode(column: column, as: Decimal.self) { return NSDecimalNumber(decimal: value).stringValue }
        if let value = try? row.decode(column: column, as: Bool.self) { return value ? "true" : "false" }
        if let value = try? row.decode(column: column, as: Date.self) { return value.formatted(date: .abbreviated, time: .standard) }
        if let value = try? row.decode(column: column, as: Data.self) { return value.base64EncodedString() }
        return "（无法显示）"
    }

    private static func result(from value: RESPValue, startedAt: Date) -> DatabaseQueryResult {
        let duration = Date().timeIntervalSince(startedAt)
        if case .array(let values) = value {
            let rows = values.enumerated().map { [String($0.offset), $0.element.description] as [String?] }
            return .init(columns: ["序号", "值"], rows: rows, affectedRows: nil, duration: duration, message: "返回 \(rows.count) 项")
        }
        if case .integer(let count) = value {
            return .message(value.description, duration: duration, affectedRows: count)
        }
        return .message(value.description, duration: duration)
    }
}

private final class ExternalSQLiteHandle: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()

    init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            throw DatabaseConnectionError.invalidCommand("无法打开 SQLite 文件")
        }
        guard sqlite3_exec(handle, "PRAGMA foreign_keys = ON", nil, nil, nil) == SQLITE_OK else {
            throw error()
        }
    }

    deinit { close() }

    func close() {
        lock.lock(); defer { lock.unlock() }
        if let handle { sqlite3_close(handle); self.handle = nil }
    }

    func execute(_ sql: String, startedAt: Date) throws -> DatabaseQueryResult {
        lock.lock(); defer { lock.unlock() }
        guard let handle else { throw DatabaseConnectionError.notConnected }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }

        let columnCount = Int(sqlite3_column_count(statement))
        let columns = (0..<columnCount).map { String(cString: sqlite3_column_name(statement, Int32($0))) }
        var rows: [[String?]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                rows.append((0..<columnCount).map { index in
                    let index = Int32(index)
                    if sqlite3_column_type(statement, index) == SQLITE_NULL { return nil }
                    if sqlite3_column_type(statement, index) == SQLITE_BLOB,
                       let bytes = sqlite3_column_blob(statement, index) {
                        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index))).base64EncodedString()
                    }
                    return sqlite3_column_text(statement, index).map { String(cString: $0) }
                })
            } else if step == SQLITE_DONE {
                break
            } else {
                throw error()
            }
        }
        let duration = Date().timeIntervalSince(startedAt)
        let affected = columnCount == 0 ? Int(sqlite3_changes(handle)) : nil
        return .init(
            columns: columns,
            rows: rows,
            affectedRows: affected,
            duration: duration,
            message: columnCount > 0 && rows.isEmpty ? "查询完成，没有符合条件的数据" : (rows.isEmpty ? "命令执行成功" : "返回 \(rows.count) 行")
        )
    }

    private func error() -> DatabaseConnectionError {
        let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite 连接已关闭"
        return .invalidCommand(message)
    }
}
