# Editor Header Controls Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the editor header's visually inconsistent icon row with a refined hybrid control group.

**Architecture:** Keep all behavior and state inside `NoteEditorView`. Introduce small private SwiftUI views and styles for the segmented mode picker, standalone icon buttons, custom focus glyph, hover feedback, and press feedback.

**Tech Stack:** Swift 6, SwiftUI, AppKit, SF Symbols, existing shell-based in-memory checks.

---

### Task 1: Build the refined controls

**Files:**
- Modify: `Sources/QuietPaper/Features/NoteEditor/NoteEditorView.swift`

**Step 1:** Replace the current three-button tray with a two-item mode segment plus standalone focus and overflow controls.

**Step 2:** Add private label, button-style, and focus-glyph views that share sizing, hover, selection, border, and press behavior.

**Step 3:** Preserve tooltips, accessibility values, the focus-mode notification, and all menu actions.

### Task 2: Verify the change

**Files:**
- Verify: `Sources/QuietPaper/Features/NoteEditor/NoteEditorView.swift`

**Step 1:** Run `swift build` and expect a clean compile.

**Step 2:** Run `./scripts/run-tests.sh` and expect all checks to pass with `WorkspaceDatabase(inMemory: true)`.

**Step 3:** Review the final diff to confirm no production database, packaged app, or version file was changed by this task.
