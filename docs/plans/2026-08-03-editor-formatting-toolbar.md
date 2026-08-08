# Editor Formatting Toolbar Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the ambiguous Markdown editor icon row with a compact, grouped toolbar whose heading, list, quote, code, and image actions are clear and reversible.

**Architecture:** Keep the toolbar in `NoteEditorView` and continue routing text mutations through `MarkdownEditorController`. Extend `MarkdownEditorCommand` with explicit heading levels and make line/block formatting commands toggle or replace existing Markdown syntax instead of stacking duplicate prefixes.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSTextView`, existing shell-based editor checks.

---

### Task 1: Define reversible Markdown formatting behavior

**Files:**
- Modify: `Sources/QuietPaper/Features/NoteEditor/MarkdownEditor.swift`
- Test: `Tests/EditorInputCheck.swift`

**Step 1: Write failing editor checks**

Add checks that H1/H2/H3 replace one another, “正文” removes a heading prefix, list and quote commands toggle off on the second use, and the code-block command unwraps an already fenced selection.

**Step 2: Run the editor checks and confirm failure**

Run: `./scripts/run-tests.sh`

Expected: the editor check executable fails because explicit heading-level commands and reversible formatting do not exist yet.

**Step 3: Implement the minimal command transformations**

Change the command enum to carry an optional heading level. Replace existing heading markers before applying the chosen level. Add reusable line-prefix toggling for lists and quotes, and detect an already fenced code block before wrapping.

**Step 4: Run the editor checks**

Run: `./scripts/run-tests.sh`

Expected: all editor and data checks pass.

### Task 2: Replace the toolbar presentation

**Files:**
- Modify: `Sources/QuietPaper/Features/NoteEditor/NoteEditorView.swift`
- Reference: `Sources/QuietPaper/Features/Shared/DesignSystem.swift`

**Step 1: Add the compact heading menu**

Replace the localized `textformat.size` icon with a visible “H 标题” control offering 正文、H1、H2、H3.

**Step 2: Add grouped formatting buttons**

Render list, quote, code block, and image actions as equal-size buttons inside one subtle rounded container. Give every action a tooltip and accessibility label, and reuse `Theme.accent` for hover/pressed feedback.

**Step 3: Build and visually inspect**

Run: `swift build`

Expected: the package builds without warnings. Launch the app, open a Markdown note, and confirm the toolbar is readable in the active theme without consuming excessive width.

### Task 3: Final regression and packaged app

**Files:**
- Verify: `Sources/QuietPaper/Features/NoteEditor/NoteEditorView.swift`
- Verify: `Sources/QuietPaper/Features/NoteEditor/MarkdownEditor.swift`
- Verify: `Tests/EditorInputCheck.swift`

**Step 1: Run all checks**

Run: `./scripts/run-tests.sh`

Expected: all checks pass using in-memory test databases.

**Step 2: Build the app bundle once**

Run: `./scripts/build-app.sh`

Expected: the bundle builds successfully and the script increments the patch version exactly once.

**Step 3: Launch and smoke test**

Open `dist/QuietPaper.app`, verify H1/H2/H3/正文 replacement, toggle list and quote twice, and confirm code/image controls retain their existing behavior.
