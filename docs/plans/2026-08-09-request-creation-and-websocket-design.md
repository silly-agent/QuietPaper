# Quiet Paper 新建请求与 WebSocket 设计

## 产品范围

“新建请求”和“新建连接”继续作为两个独立入口。“新建连接”保持现有数据库连接流程不变；点击“新建请求”后展示一个与数据库连接选择器一致的精致弹框，提供 HTTP 请求、WebSocket 请求、从 cURL 导入三个选项。HTTP 请求立即创建现有请求文件；从 cURL 导入先展示多行粘贴区，解析成功后生成普通 HTTP 请求；WebSocket 请求创建独立文件并进入专用工作台。

选择器采用三张横向卡片，使用 HTTP、双向通信和终端导入的独立图标与色彩，并保留清晰的标题、说明、悬浮反馈和本地优先提示。cURL 区域在原弹框内完成，不再叠加第二层弹框；解析失败时保留用户输入，在输入区附近展示具体错误，只有成功解析后才创建文件。

## 数据与架构

新增 `DocumentKind.websocket`，与现有 `request` 和 `connection` 并列。WebSocket 文件使用版本化 `WebSocketRequestDraft` JSON 保存 URL 与 Headers；当前连接状态和收发消息仅存在编辑器会话中，不写入数据库。现有 HTTP 请求格式不迁移，cURL 导入结果直接转成 `HTTPRequestDraft`，因此旧请求保持完全兼容。

`CURLRequestImporter` 负责 shell 风格分词并解析常用 cURL 参数，包括 URL、`-X/--request`、`-H/--header`、`-d/--data` 系列、`-G/--get` 与 `--url`。无法安全还原的参数不猜测；缺少 URL、协议不受支持或引号未闭合时返回可读错误。

WebSocket 运行时基于系统 `URLSessionWebSocketTask`，只接受 `ws` 与 `wss`。编辑器负责连接、断开、持续接收服务端推送、发送文本消息以及显示时间和方向。用户切换文件或关闭视图时主动取消任务，避免后台残留连接。

## 验证

内存数据库检查覆盖 WebSocket 文件类型持久化和搜索；纯模型检查覆盖 WebSocket 草稿往返编码与 cURL 的 Method、URL、Headers、Body、GET 数据解析。构建检查覆盖所有 `DocumentKind` 分支。最后运行 `./scripts/run-tests.sh` 和 `swift build`，并启动应用检查选择器、cURL 错误态、WebSocket 空状态及窄窗口布局。所有测试继续使用 `WorkspaceDatabase(inMemory: true)`，不读取或修改正式数据库。
