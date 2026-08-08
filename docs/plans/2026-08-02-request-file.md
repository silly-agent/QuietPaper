# Request File Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a polished Postman-like request file that supports method, URL, query parameters, headers, JSON/text body, request execution, and response inspection.

**Architecture:** Extend the existing note-backed document model with a persisted kind discriminator, storing a versioned Codable request draft in the existing content column. Route request documents to a dedicated SwiftUI editor and execute them through a small URLSession-based client while keeping responses session-only.

**Tech Stack:** Swift 6, SwiftUI, Foundation URLSession, SQLite/FTS5, existing shell-based test harness.

---

### Task 1: Define and persist request documents

**Files:**
- Modify: `Sources/QuietPaper/Domain/Models.swift`
- Modify: `Sources/QuietPaper/Data/WorkspaceDatabase.swift`
- Modify: `Tests/QuietPaperChecks.swift`

**Steps:**
1. Add a failing persistence check that creates both Markdown and request documents and verifies their kinds after a reload.
2. Run `./scripts/run-tests.sh` and confirm the new kind symbols or API are missing.
3. Add `DocumentKind`, add `kind` to `Note`, migrate `notes` with a default `markdown` column, and update all note SELECT/INSERT/mapping paths.
4. Make FTS extraction switch between Markdown text and decoded request searchable text.
5. Run `./scripts/run-tests.sh` and confirm persistence and legacy note checks pass.

### Task 2: Model, encode, and build HTTP requests

**Files:**
- Create: `Sources/QuietPaper/Infrastructure/HTTP/HTTPRequestModels.swift`
- Create: `Sources/QuietPaper/Infrastructure/HTTP/HTTPRequestClient.swift`
- Modify: `Tests/QuietPaperChecks.swift`

**Steps:**
1. Add failing checks for default draft decoding, round-trip encoding, disabled row filtering, percent-encoded query merging, headers, JSON validation, and response formatting.
2. Run `./scripts/run-tests.sh` and confirm the HTTP types are missing.
3. Implement versioned `Codable` draft models with lossless defaults for malformed or empty stored content.
4. Implement pure URLRequest construction separately from execution so behavior remains deterministic and testable.
5. Implement the async client with URLSession, elapsed-time measurement, normalized response headers, byte count, and prettified JSON response text.
6. Run `./scripts/run-tests.sh` and confirm the HTTP model and builder checks pass.

### Task 3: Integrate request creation and document routing

**Files:**
- Modify: `Sources/QuietPaper/App/AppModel.swift`
- Modify: `Sources/QuietPaper/App/QuietPaperApp.swift`
- Modify: `Sources/QuietPaper/Features/RootView.swift`
- Modify: `Sources/QuietPaper/Features/ProjectNavigation/ProjectSidebar.swift`
- Modify: `Sources/QuietPaper/Features/NoteList/NoteListView.swift`
- Modify: `Tests/AutosaveInputCheck.swift`

**Steps:**
1. Add failing model checks for creating a request at project root and inside the selected module.
2. Add `createRequest` and `createProjectRequest` methods that persist `kind = .request`, select the new item, and retain existing autosave behavior.
3. Add “新建请求” beside existing creation actions and use a distinct `bolt.horizontal.circle` icon for request rows.
4. Route selected request documents to the request editor while preserving the Markdown editor for existing documents.
5. Run `./scripts/run-tests.sh` and confirm creation, selection, and legacy flows pass.

### Task 4: Build the polished request editor

**Files:**
- Create: `Sources/QuietPaper/Features/RequestEditor/HTTPRequestEditorView.swift`
- Create: `Sources/QuietPaper/Features/RequestEditor/HTTPKeyValueEditor.swift`
- Modify: `Sources/QuietPaper/Features/Shared/DesignSystem.swift`

**Steps:**
1. Build the title breadcrumb and compact method/URL/send bar using existing typography and semantic colors.
2. Add segmented configuration tabs for 参数, Headers, and Body.
3. Implement keyboard-friendly key/value rows with enable toggles, row deletion, and a trailing blank-row affordance.
4. Add JSON/text/none body modes with a monospaced editor and JSON validation feedback.
5. Add a response pane with status, elapsed time, size, body/header tabs, empty/loading/error states, and copy actions.
6. Bind every request draft mutation through `AppModel.setDraftContent` for debounced persistence.
7. Build with `swift build` and fix all Swift 6 concurrency and macOS 13 compatibility issues.

### Task 5: Validate the completed feature

**Files:**
- Modify: `README.md`
- Modify: `Tests/QuietPaperChecks.swift` only if coverage gaps are found

**Steps:**
1. Document the request-file capability and its local persistence/network boundary in README.
2. Run `./scripts/run-tests.sh`; expect all database, editor, input, autosave, and HTTP checks to pass.
3. Run `swift build`; expect a clean debug build.
4. Run `swift run QuietPaper` for a smoke test and verify project/module creation menus, request editing, response states, and normal Markdown editing.
5. Review `git diff --check` and `git status --short` to ensure no generated `dist/` content or unrelated files changed.
