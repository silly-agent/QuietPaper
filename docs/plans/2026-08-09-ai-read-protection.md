# AI Read Protection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add inherited project/module AI-read protection that blocks indexing, note retrieval, and database AI features.

**Architecture:** Persist explicit protection flags on projects and modules, then calculate effective protection at the database boundary. Keep ordinary FTS search unchanged while adding AI-only protected retrieval, and make UI checks a visible companion to database/AppModel enforcement.

**Tech Stack:** Swift 6, SwiftUI, SQLite/FTS5, Swift Package Manager, in-memory database checks.

---

### Task 1: Persist and calculate AI-read protection

**Files:**
- Modify: `Sources/QuietPaper/Domain/Models.swift`
- Modify: `Sources/QuietPaper/Data/WorkspaceDatabase.swift`
- Modify: `Tests/QuietPaperChecks.swift`

**Step 1: Write the failing in-memory database check**

Create a project with two modules and assert that module-level protection affects only that module, while project-level protection affects the project root and every child module. Assert that clearing the project flag leaves an explicit module flag intact.

**Step 2: Run the check and verify it fails**

Run: `./scripts/run-tests.sh`

Expected: compilation fails because `isAIUnreadable`, `setAIUnreadable`, or effective-protection queries do not exist.

**Step 3: Add schema fields and model properties**

Add `is_ai_unreadable INTEGER NOT NULL DEFAULT 0` to `projects` and `modules`, including additive migrations for existing databases. Decode the fields into `Project.isAIUnreadable` and `NoteModule.isAIUnreadable`.

**Step 4: Add transactional mutation and effective checks**

Implement project/module setters that update the explicit flag and timestamp. Add effective checks for project, module, and note IDs using `project.is_ai_unreadable OR module.is_ai_unreadable`.

**Step 5: Run the checks**

Run: `./scripts/run-tests.sh`

Expected: the new inheritance check passes without accessing an on-disk database.

### Task 2: Enforce protection in all note-AI data paths

**Files:**
- Modify: `Sources/QuietPaper/Data/WorkspaceDatabase.swift`
- Modify: `Sources/QuietPaper/App/AppModel.swift`
- Modify: `Tests/QuietPaperChecks.swift`

**Step 1: Write failing index and retrieval checks**

Create protected and readable Markdown notes. Assert that applying a flag removes protected chunks, saving does not recreate them, rebuilding indexes only readable notes, vector fetches exclude protected notes, and AI keyword search excludes protected notes while ordinary search still returns them.

**Step 2: Run the check and verify it fails**

Run: `./scripts/run-tests.sh`

Expected: protected notes still appear in chunks or AI keyword results.

**Step 3: Guard vector writes and reads**

Make `updateChunks(for:)` stop after deleting stale chunks when the note is effectively protected. Filter `rebuildAllChunks`, `fetchAllChunks`, `noteSearchResult`, and index count/missing-index logic by effective permission.

**Step 4: Add AI-only keyword retrieval**

Keep `search(...)` unchanged for the normal search UI. Add an AI-specific search method whose FTS and fallback SQL append the effective-readable clauses, and update `AppModel.ask` to use it.

**Step 5: Run focused and full checks**

Run: `./scripts/run-tests.sh`

Expected: all checks pass and ordinary search still finds protected content.

### Task 3: Add AppModel operations and block connection creation

**Files:**
- Modify: `Sources/QuietPaper/App/AppModel.swift`
- Modify: `Tests/QuietPaperChecks.swift`

**Step 1: Add testable AppModel/database permission state**

Expose project/module effective protection helpers and a selected-note protection property. Add toggle methods that force-save, update the database, reload workspace state, and surface failures through the existing error channel.

**Step 2: Block both connection creation paths**

Before creating a project-root or module connection, check effective protection. Return `nil` and set the user-facing message `被标记为 AI 不可读的项目或模块下不可使用此功能` when denied.

**Step 3: Verify creation behavior**

Run: `./scripts/run-tests.sh`

Expected: connection creation is rejected for protected targets and allowed elsewhere.

### Task 4: Add sidebar controls and visible state

**Files:**
- Modify: `Sources/QuietPaper/Features/ProjectNavigation/ProjectSidebar.swift`

**Step 1: Wire project and module context menus**

Add the toggle action after export and before rename. Use “标记 AI 不可读” for readable explicit targets and “取消 AI 不可读” for explicitly protected targets. For inherited module protection, show a disabled “AI 不可读（继承自项目）” item.

**Step 2: Show protection affordances**

Render a small `eye.slash` indicator for protected projects/modules with help text distinguishing explicit and inherited protection.

**Step 3: Route connection denial through the existing alert surface**

Ensure both project and module “新建连接” actions select/check the intended target and display the AppModel error instead of creating a connection.

**Step 4: Build**

Run: `swift build`

Expected: all context-menu closures and model properties compile.

### Task 5: Disable AI for existing protected database connections

**Files:**
- Modify: `Sources/QuietPaper/Features/DatabaseConnection/DatabaseConnectionEditorView.swift`
- Modify: `Sources/QuietPaper/Features/DatabaseConnection/DatabaseConnectionViewModel.swift`

**Step 1: Pass effective permission into the connection workspace**

Supply `model.isSelectedNoteAIUnreadable` to the workspace and ViewModel. Keep connection configuration editable, but disable the natural-language composer and show a protection notice.

**Step 2: Add a ViewModel send guard**

Make `send(_:)` reject before reading schema or creating a DeepSeek agent whenever protection is active. Update the guard if the selected hierarchy flag changes while the editor is open.

**Step 3: Build and run checks**

Run: `swift build && ./scripts/run-tests.sh`

Expected: build succeeds; all checks pass using only in-memory databases.

### Task 6: Final verification and documentation sync

**Files:**
- Modify: `README.md`
- Modify: `Sources/QuietPaper/Features/Settings/AISettingsSection.swift`

**Step 1: Clarify privacy behavior**

Document that protected project/module content is excluded from AI indexing and retrieval. Update index-help text to mention the exclusion.

**Step 2: Run the full suite**

Run: `./scripts/run-tests.sh`

Expected: all check executables report success.

**Step 3: Compile a release build without packaging**

Run: `swift build -c release`

Expected: successful compilation. Do not run `scripts/build-app.sh`, because packaging increments the application version.

**Step 4: Inspect the final diff**

Run: `git diff --check` and review only task-related hunks, preserving all pre-existing user changes.
