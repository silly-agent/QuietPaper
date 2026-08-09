# Batch Note Delete Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add confirmed, atomic soft deletion for a Shift-selected range of notes while preserving single-note deletion.

**Architecture:** `WorkspaceDatabase` owns an atomic `softDeleteNotes(ids:)` operation and shares its implementation with the existing single-item soft delete path. `AppModel` exposes one UI-facing batch method. `NoteListView` converts the existing alert state into a request that can contain one or many notes and resets range selection only after success.

**Tech Stack:** Swift 6, SwiftUI, SQLite, custom in-memory check runner

---

### Task 1: Specify database batch deletion

**Files:**
- Modify: `Tests/QuietPaperChecks.swift`

1. Add `batchSoftDeleteNotesIsAtomicAndRecoverable()` using `WorkspaceDatabase(inMemory: true)` only.
2. Create three notes and one fold group, batch-delete two notes, then assert the unselected note remains.
3. Assert deleted notes leave search/vector results, appear in recent deletion, dissolve the undersized fold group, and restore successfully.
4. Run `./scripts/run-tests.sh` and expect compilation to fail because `softDeleteNotes(ids:)` does not exist yet.

### Task 2: Implement one-transaction soft deletion

**Files:**
- Modify: `Sources/QuietPaper/Data/WorkspaceDatabase.swift`

1. Add `softDeleteNotes(ids:)` with stable UUID de-duplication and an empty-input no-op.
2. Run all fold-membership updates, note `deleted_at` updates, FTS cleanup, and vector cleanup inside one transaction.
3. Refactor `.note` handling in `softDelete(kind:id:)` to call the shared private operation without nesting transactions.
4. Run `./scripts/run-tests.sh`; expect all database checks to pass.

### Task 3: Expose batch deletion through AppModel

**Files:**
- Modify: `Sources/QuietPaper/App/AppModel.swift`
- Modify: `Tests/AutosaveInputCheck.swift`

1. Add `deleteNotes(_:) -> Bool`, forcing pending draft save before database mutation.
2. Reload the workspace once after success and report errors without clearing selection on failure.
3. Add an AppModel check using its injected in-memory database to verify published notes refresh after deleting two IDs.
4. Run `./scripts/run-tests.sh`; expect all AppModel checks to pass.

### Task 4: Connect the multi-selection menu and confirmation

**Files:**
- Modify: `Sources/QuietPaper/Features/NoteList/NoteListView.swift`

1. Replace `noteToDelete` with an identifiable request containing an ordered note array.
2. Make the destructive context-menu label conditional: “删除” for one note, “删除 N 个文件” for a selected range.
3. Present one confirmation alert whose title/message reflect the request count.
4. On confirmation, call `model.deleteNotes`, then reset range selection only when it succeeds.
5. Run `swift build` and `./scripts/run-tests.sh`; expect both to pass.

### Task 5: Safety and diff review

**Files:**
- Review only

1. Confirm every new deletion test constructs `WorkspaceDatabase(inMemory: true)`.
2. Confirm no test references `applicationDatabaseURL()` or the production SQLite path.
3. Run `git diff --check` and review only the scoped source, test, and plan files.
