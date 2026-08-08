# Request Response Persistence Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Persist one explicitly saved response per request, add POST JSON defaults, guarantee formatted JSON responses, and show a pointing-hand cursor on clickable UI.

**Architecture:** Upgrade the versioned request draft with an optional Codable saved response while keeping live responses session-only. Centralize POST defaults and response formatting in HTTP model helpers, then apply a shared AppKit-backed cursor modifier to explicit SwiftUI interaction targets.

**Tech Stack:** Swift 6, SwiftUI, AppKit NSCursor, Foundation JSON/URLSession, SQLite-backed existing document persistence.

---

### Task 1: Persist a single saved response

**Files:**
- Modify: `Sources/QuietPaper/Infrastructure/HTTP/HTTPRequestModels.swift`
- Modify: `Sources/QuietPaper/Infrastructure/HTTP/HTTPRequestClient.swift`
- Modify: `Tests/QuietPaperChecks.swift`

**Steps:**
1. Add failing checks for decoding version-1 drafts and round-tripping a saved response.
2. Add `HTTPSavedResponse`, custom backward-compatible request decoding, and snapshot conversion.
3. Confirm saved response content is excluded from `searchableText`.
4. Run `./scripts/run-tests.sh` and confirm the checks pass.

### Task 2: Add POST JSON defaults and stable response formatting

**Files:**
- Modify: `Sources/QuietPaper/Infrastructure/HTTP/HTTPRequestModels.swift`
- Modify: `Sources/QuietPaper/Infrastructure/HTTP/HTTPRequestClient.swift`
- Modify: `Tests/QuietPaperChecks.swift`

**Steps:**
1. Add failing checks for automatic enabled JSON Content-Type, case-insensitive de-duplication, and JSON object/array/scalar formatting.
2. Implement a method-change helper that adds the default only when POST is selected and no matching Header exists.
3. Keep builder fallback behavior so programmatically constructed JSON drafts are also correct.
4. Run the core checks and confirm they pass.

### Task 3: Add save/remove response controls

**Files:**
- Modify: `Sources/QuietPaper/Features/RequestEditor/HTTPRequestEditorView.swift`

**Steps:**
1. Load an optional saved response when opening a request.
2. Add “保存响应”, saved-state metadata, and “移除已保存响应” actions.
3. Persist only on explicit save/remove and retain live response behavior for ordinary sends.
4. Build the app and resolve SwiftUI/Swift 6 diagnostics.

### Task 4: Apply pointing-hand cursors

**Files:**
- Modify: `Sources/QuietPaper/Features/Shared/DesignSystem.swift`
- Modify: interaction views under `Sources/QuietPaper/Features`

**Steps:**
1. Add a balanced AppKit-backed cursor modifier compatible with macOS 13.
2. Apply it to explicit buttons, menus, tabs, sidebar/list rows, and response actions.
3. Keep text-entry surfaces unchanged.
4. Build and inspect the main Markdown and request windows.

### Task 5: Verify and relaunch

**Files:**
- Modify: `README.md`

**Steps:**
1. Document explicit response persistence and POST defaults.
2. Run `./scripts/run-tests.sh`, `swift build`, and scoped `git diff --check`.
3. Run `./scripts/build-app.sh`, launch `dist/QuietPaper.app`, and verify a visible foreground window.
