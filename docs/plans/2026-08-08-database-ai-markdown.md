# Database AI Markdown Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Render database assistant replies and reasoning as compact Markdown while preserving plain-text user and system messages.

**Architecture:** Reuse `MarkdownParser` for block parsing and extract one shared inline Markdown formatter. A compact SwiftUI renderer composes the existing code-block and table views inside database conversation rows without changing persisted message data.

**Tech Stack:** Swift 6, SwiftUI, Foundation `AttributedString`, existing Markdown parser and executable checks.

---

### Task 1: Test shared Markdown formatting

**Files:**
- Create: `Sources/QuietPaper/Infrastructure/Markdown/MarkdownInlineText.swift`
- Modify: `Tests/QuietPaperChecks.swift`
- Modify: `scripts/run-tests.sh`

**Steps:**

1. Add a failing check that parses an assistant reply containing bold, inline code, a list, and a fenced SQL block.
2. Add a shared inline formatter and verify formatting removes Markdown marker characters from rendered text.
3. Run `./scripts/run-tests.sh` and confirm the new check passes.

### Task 2: Build a compact Markdown renderer

**Files:**
- Create: `Sources/QuietPaper/Features/Shared/CompactMarkdownView.swift`
- Modify: `Sources/QuietPaper/Features/NoteEditor/MarkdownPreview.swift`

**Steps:**

1. Render every existing `MarkdownBlock` case with compact message spacing.
2. Reuse the existing code-block and table views by making them module-visible.
3. Use a secondary visual style for reasoning and the normal body style for assistant replies.
4. Run `swift build` to verify exhaustive block rendering and SwiftUI integration.

### Task 3: Integrate database conversation rows

**Files:**
- Modify: `Sources/QuietPaper/Features/DatabaseConnection/DatabaseConnectionEditorView.swift`

**Steps:**

1. Replace assistant response `Text` with `CompactMarkdownView`.
2. Replace expanded reasoning `Text` with the secondary Markdown style.
3. Keep user and system rows as plain `Text`.
4. Run all checks and inspect a local in-memory preview with representative Markdown.

### Task 4: Final verification

**Files:**
- Verify: all modified source, test, script, and plan files

**Steps:**

1. Run `./scripts/run-tests.sh` and `swift build`.
2. Run `git diff --check` and confirm no database-destructive behavior was introduced.
3. Report results; package only when requested because packaging increments the application version.
