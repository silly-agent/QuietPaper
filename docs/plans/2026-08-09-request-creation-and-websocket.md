# Request Creation and WebSocket Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task.

**Goal:** Add a polished three-option request creation sheet, cURL-to-HTTP import, and a local-first WebSocket request workspace without changing database connection creation.

**Architecture:** Keep existing HTTP request files unchanged, introduce a dedicated `websocket` document kind with a versioned draft, and route it to a system `URLSessionWebSocketTask` editor. Parse cURL locally into the existing `HTTPRequestDraft` model and create a file only after successful parsing.

**Tech Stack:** Swift 6, SwiftUI, Foundation `URLSession`, SQLite-backed existing note persistence, in-memory verification database.

---

### Task 1: Request models and local parsing

**Files:**
- Create: `Sources/QuietPaper/Infrastructure/HTTP/CURLRequestImporter.swift`
- Create: `Sources/QuietPaper/Infrastructure/WebSocket/WebSocketModels.swift`
- Modify: `Sources/QuietPaper/Domain/Models.swift`
- Modify: `Tests/QuietPaperChecks.swift`

**Steps:**

1. Add failing checks for cURL imports with quoted headers, JSON data, explicit methods, GET data, missing URL, and unclosed quotes.
2. Add a failing round-trip check for `WebSocketRequestDraft` and persistence of `DocumentKind.websocket` in `WorkspaceDatabase(inMemory: true)`.
3. Run `./scripts/run-tests.sh` and confirm the new symbols are missing.
4. Implement a shell-style tokenizer, explicit cURL option parser, typed import errors, and WebSocket draft encoding/search text.
5. Run `./scripts/run-tests.sh` and confirm the model checks pass.

### Task 2: Request creation sheet

**Files:**
- Create: `Sources/QuietPaper/Features/RequestCreation/RequestCreationSheet.swift`
- Modify: `Sources/QuietPaper/Features/NoteList/NoteListView.swift`
- Modify: `Sources/QuietPaper/App/AppModel.swift`

**Steps:**

1. Add `AppModel` creation methods that accept an imported HTTP draft and create a WebSocket request in the selected module.
2. Build a 720-point sheet with three request type cards, hover/selection feedback, a local-only privacy note, and a cURL paste state.
3. Keep “新建连接” wired directly to the existing database connection creation method.
4. Replace only the “新建请求” menu action with presentation of the new sheet.
5. Build with `swift build` to catch SwiftUI binding and availability errors.

### Task 3: WebSocket runtime and workspace

**Files:**
- Create: `Sources/QuietPaper/Infrastructure/WebSocket/WebSocketClient.swift`
- Create: `Sources/QuietPaper/Features/RequestEditor/WebSocketRequestEditorView.swift`

**Steps:**

1. Implement URL validation for `ws`/`wss`, header application, connection cancellation, text sending, and a continuous receive loop using `URLSessionWebSocketTask`.
2. Build a workspace with editable title, URL, headers, connection state, message timeline, empty state, and bottom text composer.
3. Persist only draft configuration through `AppModel.setDraftContent`; keep messages in view state.
4. Disconnect when the selected note changes or the editor disappears.
5. Run `swift build` and fix actor/concurrency diagnostics.

### Task 4: Routing, presentation, search, and export

**Files:**
- Modify: `Sources/QuietPaper/Features/RootView.swift`
- Modify: `Sources/QuietPaper/Features/NoteList/NoteListView.swift`
- Modify: `Sources/QuietPaper/Features/ProjectNavigation/ProjectSidebar.swift`
- Modify: `Sources/QuietPaper/Data/WorkspaceDatabase.swift`
- Modify: `Sources/QuietPaper/Infrastructure/Export/ModuleMarkdownExporter.swift`

**Steps:**

1. Route `DocumentKind.websocket` to the new editor.
2. Add a blue bidirectional-message icon to module and note lists.
3. Index the WebSocket URL and enabled headers in local full-text search.
4. Export WebSocket files as labeled JSON alongside other non-Markdown files.
5. Run `./scripts/run-tests.sh` and `swift build`; expect both to exit successfully.

### Task 5: Visual smoke test

**Files:** No production database files; do not package with `scripts/build-app.sh` because packaging changes the app version.

**Steps:**

1. Launch with `swift run QuietPaper`.
2. Verify “新建连接” still opens database connection creation.
3. Verify all three request options, cURL success/error states, and generated HTTP values.
4. Verify WebSocket connect/disconnect, server message display, client message display, and send-error feedback against a disposable test endpoint if one is available.
5. Confirm no files under `dist/` and no production database were changed.
