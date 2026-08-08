# Note List Quick Fold Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add persistent Shift-range selection and quick folding to the middle note list.

**Architecture:** Store fold groups in normalized SQLite tables and expose them through `WorkspaceDatabase` and `AppModel`. Build the visible list as a projection of sorted notes plus persisted fold groups; keep transient range selection inside `NoteListView` and leave search results unchanged.

**Tech Stack:** Swift 6, SwiftUI, AppKit modifier flags, SQLite, in-memory test databases.

---

### Task 1: Persist fold groups safely

**Files:**
- Modify: `Sources/QuietPaper/Domain/Models.swift`
- Modify: `Sources/QuietPaper/Data/WorkspaceDatabase.swift`
- Modify: `Tests/QuietPaperChecks.swift`

**Step 1:** Add a failing in-memory check covering group creation, ordered membership, expansion, move cleanup, note soft-delete cleanup, and module soft-delete restoration.

**Step 2:** Run `./scripts/run-tests.sh` and confirm the new database API is missing.

**Step 3:** Add `NoteFoldGroup`, the two normalized tables, fetch/create/delete APIs, and cleanup for moved or individually soft-deleted notes.

**Step 4:** Run `./scripts/run-tests.sh` and confirm all database checks pass without opening `applicationDatabaseURL()`.

### Task 2: Synchronize fold state through AppModel

**Files:**
- Modify: `Sources/QuietPaper/App/AppModel.swift`
- Modify: `Tests/AutosaveInputCheck.swift`

**Step 1:** Add an in-memory AppModel check that creates and expands a fold group and observes the published state.

**Step 2:** Add `noteFoldGroups`, load it with the selected module, and expose create/expand actions with error reporting.

**Step 3:** Run `./scripts/run-tests.sh` and confirm the AppModel checks pass.

### Task 3: Implement range selection and animated list projection

**Files:**
- Modify: `Sources/QuietPaper/Features/NoteList/NoteListView.swift`

**Step 1:** Add transient selected IDs and an anchor, interpreting Shift from `NSEvent.modifierFlags` while preserving normal single-click selection.

**Step 2:** Project sorted notes into note rows and one row per fold group at the first currently sorted member.

**Step 3:** Add “快速折叠（N 个文件）” to selected note context menus and a shared-styled “折叠 N 个文件” row that expands on click.

**Step 4:** Animate projection changes, reset invalid selection when the module or note set changes, and keep the search list untouched.

**Step 5:** Run `swift build` and `./scripts/run-tests.sh`.

**Step 6:** Launch `swift run QuietPaper --in-memory-preview`, inspect the feature without touching the production database, and capture the final UI state when practical.
