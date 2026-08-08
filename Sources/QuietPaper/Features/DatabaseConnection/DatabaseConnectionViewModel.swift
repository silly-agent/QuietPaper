import Foundation

@MainActor
final class DatabaseConnectionViewModel: ObservableObject {
    @Published var file: DatabaseConnectionFile
    @Published private(set) var status: DatabaseConnectionStatus = .disconnected
    @Published private(set) var isThinking = false
    @Published private(set) var loadingStage = ""
    @Published var pendingCommand: PendingDatabaseCommand?
    @Published var availableMySQLDatabases: [String] = []
    @Published var needsMySQLDatabase = false
    @Published var errorMessage: String?

    let noteID: UUID
    private let session: DatabaseConnectionSession
    private let onSave: (String) -> Void

    init(noteID: UUID, content: String, onSave: @escaping (String) -> Void) {
        self.noteID = noteID
        self.file = DatabaseConnectionFile.decode(content)
        self.onSave = onSave
        self.session = DatabaseConnectionSession()
        self.session.onIdleDisconnect = { [weak self] in
            Task { @MainActor in
                self?.status = .disconnected
                self?.file.messages.append(.init(role: .system, text: "连接因长时间未使用已自动断开，可以点击“重新连接”。"))
                self?.persist()
            }
        }
    }

    deinit {
        let session = session
        Task { await session.disconnect() }
    }

    func configure(kind: DatabaseKind, settings: DatabaseConnectionSettings) async {
        var settings = settings
        settings.applyDefaults(for: kind)
        await session.disconnect()
        status = .disconnected
        needsMySQLDatabase = false
        availableMySQLDatabases = []
        errorMessage = nil
        file.kind = kind
        file.settings = settings
        persist()
        await connect(showMySQLChooser: kind == .mysql && settings.database.isEmpty)
    }

    func connect(showMySQLChooser: Bool = false) async {
        guard let kind = file.kind else { return }
        status = .connecting
        errorMessage = nil
        do {
            try await session.connect(kind: kind, settings: file.settings)
            status = .connected
            let connectionMessage = "已连接到 \(kind.title) · \(file.settings.redactedSummary)"
            let latestConnectionMessage = file.messages.last(where: {
                $0.role == .system && $0.text.hasPrefix("已连接到 ")
            })?.text
            if latestConnectionMessage != connectionMessage {
                file.messages.append(.init(role: .system, text: connectionMessage))
                persist()
            }
            if showMySQLChooser {
                availableMySQLDatabases = try await session.mysqlDatabases()
                needsMySQLDatabase = true
            }
        } catch {
            status = .failed(error.localizedDescription)
            errorMessage = readableConnectionError(error)
        }
    }

    func disconnect() async {
        await session.disconnect()
        status = .disconnected
    }

    func chooseMySQLDatabase(_ name: String, create: Bool) async {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        do {
            if create { try await session.createMySQLDatabase(named: clean) }
            file.settings.database = clean
            persist()
            needsMySQLDatabase = false
            await connect()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func send(_ input: String) async {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, let kind = file.kind else { return }
        file.messages.append(.init(role: .user, text: question))
        persist()
        guard status == .connected else {
            file.messages.append(.init(role: .assistant, text: "连接当前已断开。请先点击“重新连接”，我不会自动重试数据库操作。"))
            persist()
            return
        }

        isThinking = true
        loadingStage = "正在读取数据库结构…"
        errorMessage = nil
        do {
            let schema = try await session.schemaOverview(kind: kind)
            loadingStage = "DeepSeek V4 Flash 正在思考…"
            let agent = try DeepSeekDatabaseAgent.configured()
            let plan = try await agent.plan(
                question: question,
                kind: kind,
                connectionSummary: file.settings.redactedSummary,
                schema: schema,
                history: Array(file.messages.dropLast())
            )
            guard let command = plan.command else {
                file.messages.append(.init(role: .assistant, text: plan.content, reasoning: plan.reasoning))
                persist()
                isThinking = false
                loadingStage = ""
                return
            }

            switch await session.decision(for: command, kind: kind) {
            case .execute(let normalizedCommand):
                loadingStage = "正在执行数据库命令…"
                await executeAndComplete(
                    command: normalizedCommand,
                    explanation: plan.explanation,
                    question: question,
                    reasoning: plan.reasoning,
                    context: plan.context,
                    agent: agent
                )
            case .confirm(let command, let reason):
                pendingCommand = PendingDatabaseCommand(
                    command: command,
                    explanation: "\(plan.explanation)\n\(reason)",
                    userQuestion: question,
                    reasoning: plan.reasoning,
                    agentContext: plan.context
                )
                isThinking = false
                loadingStage = ""
            case .reject(let reason):
                file.messages.append(.init(role: .assistant, text: "为保证安全，这条命令没有执行：\(reason)", reasoning: plan.reasoning, command: command))
                persist()
                isThinking = false
                loadingStage = ""
            }
        } catch {
            file.messages.append(.init(role: .assistant, text: "处理失败：\(error.localizedDescription)"))
            persist()
            errorMessage = error.localizedDescription
            isThinking = false
            loadingStage = ""
        }
    }

    func confirmPendingCommand() async {
        guard let pending = pendingCommand else { return }
        pendingCommand = nil
        isThinking = true
        loadingStage = "已确认，正在执行数据库命令…"
        let agent = try? DeepSeekDatabaseAgent.configured()
        await executeAndComplete(
            command: pending.command,
            explanation: pending.explanation,
            question: pending.userQuestion,
            reasoning: pending.reasoning,
            context: pending.agentContext,
            agent: agent
        )
    }

    func cancelPendingCommand() {
        guard let pending = pendingCommand else { return }
        pendingCommand = nil
        file.messages.append(.init(
            role: .assistant,
            text: "已取消执行。数据库没有发生更改。",
            reasoning: pending.reasoning,
            command: pending.command
        ))
        persist()
    }

    func clearHistory() {
        file.messages.removeAll()
        persist()
    }

    private func executeAndComplete(
        command: String,
        explanation: String,
        question: String,
        reasoning: String?,
        context: DatabaseAgentContext?,
        agent: DeepSeekDatabaseAgent?,
        remainingToolSteps: Int = 20
    ) async {
        guard let kind = file.kind else { return }
        do {
            let result = try await session.execute(command, kind: kind)
            loadingStage = "正在整理返回结果…"
            var finalText = explanation
            var finalReasoning = reasoning
            if let agent, let context {
                if let reply = try? await agent.complete(context: context, result: result) {
                    finalText = reply.content
                    finalReasoning = [reasoning, reply.reasoning].compactMap { $0 }.joined(separator: "\n\n").nonEmpty
                    if let nextCommand = reply.command, let nextContext = reply.context {
                        guard remainingToolSteps > 1 else {
                            file.messages.append(.init(
                                role: .assistant,
                                text: "已经连续执行 20 个数据库分析步骤，但仍未得到可靠答案。请补充更明确的表名、字段或筛选条件后继续。",
                                reasoning: finalReasoning,
                                command: command,
                                result: result
                            ))
                            persist()
                            isThinking = false
                            loadingStage = ""
                            return
                        }

                        switch await session.decision(for: nextCommand, kind: kind) {
                        case .execute(let normalizedCommand):
                            let nextStep = 22 - remainingToolSteps
                            loadingStage = "AI 正在连续分析（第 \(nextStep) / 20 步）…"
                            await executeAndComplete(
                                command: normalizedCommand,
                                explanation: reply.explanation,
                                question: question,
                                reasoning: finalReasoning,
                                context: nextContext,
                                agent: agent,
                                remainingToolSteps: remainingToolSteps - 1
                            )
                        case .confirm(let command, let reason):
                            pendingCommand = PendingDatabaseCommand(
                                command: command,
                                explanation: "\(reply.explanation)\n\(reason)",
                                userQuestion: question,
                                reasoning: finalReasoning,
                                agentContext: nextContext
                            )
                            isThinking = false
                            loadingStage = ""
                        case .reject(let reason):
                            file.messages.append(.init(
                                role: .assistant,
                                text: "为保证安全，后续命令没有执行：\(reason)",
                                reasoning: finalReasoning,
                                command: nextCommand
                            ))
                            persist()
                            isThinking = false
                            loadingStage = ""
                        }
                        return
                    }
                }
            }
            file.messages.append(.init(
                role: .assistant,
                text: finalText,
                reasoning: finalReasoning,
                command: command,
                result: result
            ))
            persist()
        } catch {
            file.messages.append(.init(
                role: .assistant,
                text: "命令执行失败：\(error.localizedDescription)",
                reasoning: reasoning,
                command: command
            ))
            persist()
            errorMessage = error.localizedDescription
        }
        isThinking = false
        loadingStage = ""
    }

    private func persist() {
        guard let content = try? file.encoded() else { return }
        onSave(content)
    }

    private func readableConnectionError(_ error: Error) -> String {
        let detail = error.localizedDescription
        if detail.localizedCaseInsensitiveContains("connection refused") {
            return "无法连接到数据库服务，请检查主机、端口以及服务是否已启动。"
        }
        if detail.localizedCaseInsensitiveContains("password") || detail.localizedCaseInsensitiveContains("authentication") {
            return "身份验证失败，请检查用户名和密码。"
        }
        return detail
    }
}

private extension String {
    var nonEmpty: String? {
        let clean = trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}
