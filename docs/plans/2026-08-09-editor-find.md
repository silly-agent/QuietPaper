# Editor Find Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Command-F search with cyclic Enter navigation to both Markdown editing and rendered preview modes.

**Architecture:** Keep one find session in `NoteEditorView`, backed by pure range/index helpers. Bridge edit-mode selection to `PastingTextView`; derive ordered searchable preview units and render highlighted attributed strings with `ScrollViewReader` navigation.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSTextView`, existing local check executables.

---

### Task 1: Pure find session and preview index

**Files:**
- Create: `Sources/QuietPaper/Features/NoteEditor/EditorFind.swift`
- Modify: `Tests/QuietPaperChecks.swift`
- Modify: `scripts/run-tests.sh`

**Step 1: Write the failing test**

Add checks that query `Alpha beta alpha` for `alpha`, assert two ordered UTF-16 ranges, and assert next/previous navigation wraps. Add a parsed Markdown fixture and assert its preview search units contain heading, inline-visible paragraph text, list items, code, table cells, and image alt text in display order.

**Step 2: Run test to verify it fails**

Run: `./scripts/run-tests.sh`

Expected: compilation fails because the find helpers do not exist.

**Step 3: Write minimal implementation**

Implement `EditorFindMatches` for local case-insensitive/width-insensitive range discovery and cyclic index movement. Implement `PreviewSearchUnit` plus a builder that flattens parsed `MarkdownBlock` values into stable ordered text units.

**Step 4: Run test to verify it passes**

Run: `./scripts/run-tests.sh`

Expected: all core checks pass without opening the production database.

### Task 2: Find bar and edit-mode navigation

**Files:**
- Modify: `Sources/QuietPaper/Features/NoteEditor/NoteEditorView.swift`
- Modify: `Sources/QuietPaper/Features/NoteEditor/MarkdownEditor.swift`
- Modify: `Tests/EditorInputCheck.swift`

**Step 1: Write the failing test**

Extend `EditorInputCheck` to install a find callback, synthesize `Command-F`, and assert the callback fires. Search repeated editor text, navigate twice, and assert the selected ranges advance and wrap.

**Step 2: Run test to verify it fails**

Run: `./scripts/run-tests.sh`

Expected: editor checks fail because the callback and navigation API are absent.

**Step 3: Write minimal implementation**

Add an `onFind` callback to `MarkdownEditor`/`PastingTextView`, intercept only exact `Command-F`, and expose controller methods for selecting and revealing a match. Add a compact SwiftUI find bar to `NoteEditorView` with focused query input, result count, previous/next buttons, Escape handling, and query reset on document change.

**Step 4: Run test to verify it passes**

Run: `./scripts/run-tests.sh`

Expected: AppKit editor input checks and core checks pass.

### Task 3: Preview highlighting and navigation

**Files:**
- Modify: `Sources/QuietPaper/Features/NoteEditor/MarkdownPreview.swift`
- Modify: `Sources/QuietPaper/Features/NoteEditor/NoteEditorView.swift`
- Modify: `Tests/QuietPaperChecks.swift`

**Step 1: Write the failing test**

Add checks that the active global preview match resolves to the correct unit and local range when multiple units contain repeated keywords.

**Step 2: Run test to verify it fails**

Run: `./scripts/run-tests.sh`

Expected: checks fail because preview match resolution is absent.

**Step 3: Write minimal implementation**

Pass the shared query and active match into `MarkdownPreview`. Highlight all local matches in each preview text unit, distinguish the active match, and scroll its unit into view whenever Enter or Shift-Enter changes the active global index.

**Step 4: Run test to verify it passes**

Run: `./scripts/run-tests.sh`

Expected: all checks pass.

### Task 4: Full verification

**Files:**
- Verify only; do not modify `dist/` or production database files.

**Step 1: Run the full suite**

Run: `./scripts/run-tests.sh`

Expected: every check executable reports success.

**Step 2: Inspect the diff**

Run: `git diff --check && git diff -- Sources/QuietPaper/Features/NoteEditor Tests scripts/run-tests.sh docs/plans/2026-08-09-editor-find*.md`

Expected: no whitespace errors and no unrelated edits introduced by this feature.
