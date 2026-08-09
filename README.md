<div align="center">
  <img src="Resources/QuietPaperLogo-flat.svg" width="96" alt="Quiet Paper 图标">
  <h1>Quiet Paper</h1>
  <p>一个把笔记、接口请求和数据库工作台放在本机的 macOS 应用。</p>
</div>

![Quiet Paper Markdown 阅读预览](docs/images/releases/1.0.31/01-markdown-preview.jpeg)

Quiet Paper 适合按“项目 / 模块 / 文件”整理长期资料。它不是云笔记服务，没有账号体系，日常编辑、搜索、附件和备份都直接落在自己的 Mac 上。

本页界面截图来自 `1.0.31` 的内存演示工作区，不包含真实笔记、账号或连接凭据。

## 下载

[前往 Releases 下载最新版](https://github.com/silly-agent/QuietPaper/releases/latest)

每个版本提供两份应用包：

- Apple Silicon：适用于芯片名称为 M1、M2、M3、M4 或后续 M 系列的 Mac。
- Intel：适用于“关于本机”中处理器显示为 Intel 的 Mac。

下载对应的 ZIP，解压后把 `QuietPaper.app` 拖入“应用程序”即可。当前公开包使用 ad-hoc 签名；第一次打开时如果 macOS 提示无法验证开发者，请在 Finder 中右键应用并选择“打开”。正式的 Developer ID 签名与 Apple 公证配置完成后，这一步会自动消失。

[查看所有历史版本](https://github.com/silly-agent/QuietPaper/releases)。压缩包旁的 `.sha256` 文件可用于核对下载内容是否完整。

## 1.0.36 更新

- 数据库查询结果只有一列或内容较短时，表格会自然铺满结果卡片，不再缩在中间。
- 编辑数据库连接时，端口会按原始数字显示，例如 `3307`，不会再显示成 `3,307`。
- 在笔记标题和“查找当前笔记”输入框中使用 `Command-V`，内容会粘贴到当前输入框，不会误跑到正文。
- 新建但尚未配置的数据库连接不再自动弹出设置窗口，可以从连接页点击“选择数据库”后再配置。

这些调整只涉及界面显示与输入焦点，不会迁移、清空或重置已有数据库。

## 能做什么

- 用 Markdown 写笔记，在编辑和阅读预览之间切换，并用 `Command-F` 查找当前笔记。
- 按项目、模块和文件组织内容，支持排序、快速跳转、范围多选、可恢复的批量删除和专注模式。
- 搜索标题、正文和路径；普通笔记可使用系统 NLP 能力建立本地向量索引。
- 保存并运行 HTTP 请求，支持从 cURL 导入 Method、URL、Headers 与 Body；也可通过 WebSocket 实时收发文本消息。
- 管理 MySQL、PostgreSQL、Redis 和 SQLite 连接，用自然语言生成 SQL，并在应用内查看结构化结果。
- 把单篇笔记导出为 Markdown，或按项目 / 模块合并导出、打包为 ZIP。
- 备份完整数据库和附件，也可以在设置中迁移存储目录。

## 界面

### Markdown 编辑与预览

编辑器提供标题、列表、引用、代码块、表格和图片工具。阅读模式会排版 Markdown、代码块和表格，并保留一键复制按钮。

在编辑或预览状态按 `Command-F`，可以查找当前笔记。Enter 跳到下一处，Shift-Enter 返回上一处，走到末尾后会从头继续。

![编辑器查找与格式工具栏](docs/images/releases/1.0.31/02-editor-find-and-toolbar.jpeg)

需要只看正文时，可以打开专注模式。普通编辑状态还支持“写作聚焦雾化”：输入标题或正文时，左侧导航会柔和淡出；鼠标移回左侧便会恢复清晰。

![Markdown 专注模式](docs/images/releases/1.0.31/03-focus-mode.jpeg)

### HTTP、cURL 与 WebSocket

点击“新建请求”后，可以选择普通 HTTP、WebSocket，或直接粘贴 cURL。配置先保存在本机，只有主动发送或连接时才会访问目标地址。

![HTTP、WebSocket 与 cURL 创建入口](docs/images/releases/1.0.31/04-request-creation.jpeg)

cURL 导入会识别常用的 Method、URL、Headers 和 Body，生成后仍可逐项修改。HTTP 响应只保留在当前会话，不会自动写进笔记数据库。

![从 cURL 生成的 HTTP 请求](docs/images/releases/1.0.31/05-http-curl-import.jpeg)

WebSocket 工作台可以保存连接地址与 Headers，连接后实时查看服务端消息并发送文本；断开或关闭文件后，消息不会写入数据库。

![WebSocket 工作台](docs/images/releases/1.0.31/06-websocket-workbench.jpeg)

### 外观与本地 AI

应用内置跟随系统、暖纸、森林、深海、樱花和午夜六种外观。“写作聚焦雾化”也可以在外观设置中随时关闭。

![主题与当前版本](docs/images/releases/1.0.31/07-settings-theme-and-version.jpeg)

普通笔记可以使用系统内置 NLP 能力在本机建立向量索引。向量化与检索完全离线；HTTP 请求、数据库连接以及标记为“AI 不可读”的项目或模块不会进入索引。

![本地 AI 索引设置](docs/images/releases/1.0.31/08-ai-local-index.jpeg)

### 数据库连接与 AI 助手

数据库连接和笔记一样保存在项目目录中，支持 MySQL、PostgreSQL、Redis 和 SQLite。连接凭据只交给本地连接器，AI 不会收到密码或完整连接串。

![MySQL、PostgreSQL、Redis 与 SQLite 连接入口](docs/images/releases/1.0.31/09-database-connections.jpeg)

连接成功后，可以直接描述想查什么；Quiet Paper 会展示生成的 SQL、执行耗时和表格结果。AI 回复支持标题、列表、行内代码、代码块和表格，写入或修改类命令仍会在真正执行前再次确认。

仓库里附了一套不含真实业务数据的 PostgreSQL 演示环境。Docker 启动后会创建虚构的客户和订单数据：

```bash
docker compose -f docker-compose.demo.yml up -d
```

在应用中新建 PostgreSQL 连接，填写 `127.0.0.1:55432`，用户名和数据库名均为 `quietpaper_demo`，演示密码是 `quietpaper_demo_only`。随后可以直接问：

> 统计每个客户的订单数和有效消费金额，排除退款，按消费额从高到低取前 5 名。

这套账号只服务于绑定在本机回环地址的演示容器，不要把同样的密码用在其他环境。停止演示环境可运行：

```bash
docker compose -f docker-compose.demo.yml down
```

## 运行

需要 macOS 13 或更高版本、Swift 6，以及系统自带的 SQLite 3（包含 FTS5）。

```bash
git clone https://github.com/silly-agent/QuietPaper.git
cd QuietPaper
swift run QuietPaper
```

第一次启动时，应用会自动创建目录、SQLite 数据库和一组脱敏示例笔记，不需要手工准备数据库。默认位置是：

```text
~/Library/Application Support/QuietPaper/
```

构建可直接打开的应用包：

```bash
./scripts/build-app.sh
open dist/QuietPaper.app
```

Intel Mac 可以使用：

```bash
./scripts/build-app-intel.sh
open dist/QuietPaper-Intel.app
```

构建脚本会自动递增补丁版本号。

## 测试

```bash
./scripts/run-tests.sh
```

测试使用 `WorkspaceDatabase(inMemory: true)`，不会读取、清空或修改正式数据库。

## 数据边界

- 笔记数据库、WAL 文件、附件、备份、构建目录和本地配置都已加入 `.gitignore`。
- 搜索、Markdown 处理、导出和向量化在本机完成。
- 项目或模块可标记为“AI 不可读”；标记范围内的文件不会进入 AI 向量索引或笔记问答检索，数据库 AI 助手也不可使用。普通编辑、搜索与导出不受影响。
- HTTP 请求和数据库连接只在用户主动操作时访问目标地址。
- DeepSeek 是可选功能。配置 API Key 后，笔记问答会发送提问及相关笔记片段；数据库助手只发送问题和经过裁剪的表结构，不发送连接密码或完整连接串。
- 请求文件和数据库连接可能包含凭证。公开导出文件或提交代码前，请自行检查其中的敏感信息。

## 目录

```text
Sources/QuietPaper/App             应用入口与状态
Sources/QuietPaper/Domain          模型和协议
Sources/QuietPaper/Data            SQLite 持久化与搜索
Sources/QuietPaper/Infrastructure  Markdown、附件、HTTP、数据库与 AI
Sources/QuietPaper/Features        SwiftUI 界面
Tests                              本地检查程序
scripts                            测试与打包脚本
```

## 参与开发

提交改动前请先运行 `./scripts/run-tests.sh`。涉及数据库的测试必须使用内存数据库，不要让开发或测试脚本指向用户的正式数据目录。

版本标签推送后，GitHub Actions 会在原生 Apple Silicon 与 Intel runner 上分别构建应用并创建 Release。维护步骤和 Apple 公证所需配置见 [发布说明](docs/RELEASING.md)。

## License

[MIT](LICENSE)
