# AGENTS.md

This repository contains Quiet Paper, a local-first macOS note application built with Swift Package Manager.

## Project overview

- App entry: `swift run QuietPaper`
- Main package definition: `Package.swift`
- App source root: `Sources/QuietPaper`
- Tests/checks entry: `Tests/QuietPaperChecks.swift`
- Utility scripts:
  - `./scripts/run-tests.sh`
  - `./scripts/build-app.sh`

## Repository layout

- `Sources/QuietPaper/App`: app bootstrap and shared app state
- `Sources/QuietPaper/Domain`: core models and protocols
- `Sources/QuietPaper/Data`: persistence and database access
- `Sources/QuietPaper/Infrastructure`: attachments, markdown, and local AI helpers
- `Sources/QuietPaper/Features`: SwiftUI feature views and design primitives
- `Sources/CSQLite`: SQLite shim/module map
- `Resources`: bundled app resources
- `docs/plans`: design notes and planning docs
- `scripts`: local build/test helpers

## Working rules

- Keep the app local-first. Do not introduce network dependencies for core note, search, backup, or QA flows unless the user explicitly asks for that change.
- Prefer minimal, targeted changes that preserve the current package structure.
- When changing persistence behavior, verify impact on SQLite/FTS-related code in `Sources/QuietPaper/Data` and `Sources/CSQLite`.
- When changing UI behavior, keep styling aligned with shared primitives in `Sources/QuietPaper/Features/Shared`.
- Do not edit generated app bundle contents under `dist/` unless the task is explicitly about packaged output.
- **数据库保护**：编写代码、编译项目或运行测试时，绝对不允许清空、删除或重置用户数据库 `~/Library/Application Support/QuietPaper/quiet-paper.sqlite`。测试必须使用 `WorkspaceDatabase(inMemory: true)` 创建内存数据库。禁止执行 `DELETE FROM`、`DROP TABLE`、删除数据库文件或修改 `applicationDatabaseURL()` 指向的数据库文件等操作。仅在用户明确要求且确认后才可操作生产数据库。

## Versioning

- 应用版本号的**唯一来源**是 `Sources/QuietPaper/Infrastructure/AppVersion.swift` 中的 `AppVersion.current`，格式为 `major.minor.patch`（例如 `1.0.1`）。
- `scripts/build-app.sh` 每次打包都会自动递增补丁号并写回该文件，同时把新版本号同步到 app 包 Info.plist 的 `CFBundleShortVersionString` 与 `CFBundleVersion`。因此**每次打包都会产生一个新的版本号**。
- 设置面板左下角「设置 → 最新版本」区块直接展示 `AppVersion.current`。
- **不要手动修改** `AppVersion.current` 或 `Resources/Info.plist` 里的版本号；版本递增统一由 `scripts/build-app.sh` 负责。若需要提升大/中版本号，请在打包后手动调整 `AppVersion.current`，但不要直接改 `Resources/Info.plist`。

## Validation

- Primary verification: `./scripts/run-tests.sh`
- App launch smoke test: `swift run QuietPaper`
- Build app bundle when relevant: `./scripts/build-app.sh`

## Notes for agents

- Read `README.md` first for the expected local workflow.
- Check `docs/plans/` for design context before making structural changes.
- Favor source edits over documentation-only guesses; keep docs synchronized when behavior changes.
