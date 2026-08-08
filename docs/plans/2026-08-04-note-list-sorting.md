# Note List Sorting Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add persistent filename, creation-time, and modification-time sorting with ascending/descending directions to the middle note list.

**Architecture:** Keep SQLite fetch order and persistence unchanged. Add small `NoteListSortMode` and `NoteListSortDirection` value types in the note-list feature, store their raw values with `@AppStorage`, and derive the displayed notes from `model.notes`; search results continue using their existing relevance order.

**Tech Stack:** Swift 6, SwiftUI, Foundation, UserDefaults via `@AppStorage`.

---

### Task 1: Sorting model, direction, and derived list

**Files:**
- Modify: `Sources/QuietPaper/Features/NoteList/NoteListView.swift`

**Step 1:** Add the three-case sorting enum, two-case direction enum, Chinese labels, and a stable comparison function.

**Step 2:** Add `@AppStorage` raw-value properties defaulting to filename + ascending sorting.

**Step 3:** Derive `sortedNotes` from `model.notes`, applying the selected direction to localized natural filename order or date order with deterministic tie-breakers.

**Step 4:** Render `sortedNotes` in the normal list and leave `searchResults` untouched.

### Task 2: Compact secondary sorting menu

**Files:**
- Modify: `Sources/QuietPaper/Features/NoteList/NoteListView.swift`

**Step 1:** Move the sorting control from the subtitle to the right side of the middle-list title bar.

**Step 2:** Group field and direction choices in the menu, with checkmarks, help text, and accessibility labels.

**Step 3:** Build with `swift build` and inspect the middle-column header at normal width.

### Task 3: Regression and packaging

**Files:**
- Verify: `Sources/QuietPaper/Features/NoteList/NoteListView.swift`

**Step 1:** Run `./scripts/run-tests.sh`; expect 25/25, 43/43, and 16/16.

**Step 2:** Verify the three menu choices in an in-memory Preview app and confirm search order is unchanged.

**Step 3:** Run `./scripts/build-app.sh` to produce the distributable app.
