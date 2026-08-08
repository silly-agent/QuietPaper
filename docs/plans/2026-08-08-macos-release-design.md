# macOS 双架构发布设计

## 目标

让普通用户在 GitHub Releases 中按自己的 Mac 下载 Quiet Paper，解压后即可得到完整的 `.app`。每个版本永久保留 Apple Silicon 与 Intel 两份压缩包和对应的 SHA-256 校验文件，旧版本通过 Releases 页面继续可见。

## 发布方式

版本标签采用 `vX.Y.Z`。标签推送后，GitHub Actions 分别在原生 Apple Silicon runner（`macos-15`）和原生 Intel runner（`macos-15-intel`）上构建，避免把交叉编译结果当作最终分发包。工作流校验标签版本与 `AppVersion.current` 一致，再调用现有打包脚本的“固定版本”模式；日常本地打包仍保持自动递增补丁号的原行为。

每个构建任务检查二进制架构、Info.plist 版本和代码签名，使用 `ditto` 打包应用，并生成 SHA-256。发布任务只在两个构建都成功后创建 GitHub Release，上传压缩包和校验文件，同时由 GitHub 根据提交记录生成版本说明。Release 资产用于长期下载，Actions 中间产物仅用于任务间传递。

## 签名与安装

仓库当前没有 Apple Developer ID 证书，因此首个公开包使用 ad-hoc 签名。用户下载后可能需要在 Finder 中右键选择一次“打开”；这是 macOS Gatekeeper 对未公证应用的限制，不是应用安装器可以绕过的。打包脚本预留 `QUIETPAPER_CODESIGN_IDENTITY`，后续配置 Developer ID Application 证书、Apple ID 专用密码和 Team ID 后，可在相同流程中加入 hardened runtime、公证与 stapling，届时普通用户可直接双击打开。

## 验收

本地至少构建当前架构，验证 `.app` 中版本号、最低系统版本、签名和二进制架构，再解压 ZIP 做二次检查。工作流 YAML 通过静态解析，项目测试全部通过。首个标签发布后，检查 Release 页面同时存在两种架构的 ZIP 与校验文件，并下载一份资产核对摘要。
