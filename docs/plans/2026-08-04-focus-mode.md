# Focus Mode Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a toolbar button and `Command + E` shortcut that toggle a detail-only editing layout, with a centered, responsive white canvas for Markdown files.

**Architecture:** Store the transient focus flag on `AppModel`, let `RootView` render either the editor alone or the normal `NavigationSplitView`, hide the window toolbar while focused, and route keyboard events through the existing notification-based shortcut bridge. `NoteEditorView` applies a centered, responsive canvas up to 1280pt wide with at least 32pt side padding, a seamless white background, and hidden title/header/status chrome while the Markdown editor is focused; request and connection editors remain separate RootView branches. The editor button binds to the same flag so visual state and layout state cannot diverge.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Package Manager.

---

### Task 1: Shared focus state and layout behavior

**Files:**
- Modify: `Sources/QuietPaper/App/AppModel.swift`
- Modify: `Sources/QuietPaper/Features/RootView.swift`

**Step 1:** Add a non-persisted `@Published isFocusMode` flag.

**Step 2:** Branch in `RootView`; render only the detail editor when focused and restore the normal split view when unfocused.

**Step 3:** Make the existing sidebar toggle exit focus mode before applying normal sidebar behavior.

**Step 4:** Run `swift build`; expect a successful build.

### Task 2: Editor button and shortcut

**Files:**
- Modify: `Sources/QuietPaper/Features/NoteEditor/NoteEditorView.swift`
- Modify: `Sources/QuietPaper/App/QuietPaperApp.swift`

**Step 1:** Add the focus button immediately after the eye button, including selected styling, tooltip, and accessibility value.

**Step 2:** Add a `Command + E` menu command and extend the local key monitor to consume both `Command + B` and `Command + E`.

**Step 3:** Route shortcut events through a focus-mode notification handled by `RootView`.

**Step 4:** Run `swift build`; expect a successful build.

### Task 3: Regression and visual verification

**Files:**
- Verify: `Sources/QuietPaper/App/AppModel.swift`
- Verify: `Sources/QuietPaper/Features/RootView.swift`
- Verify: `Sources/QuietPaper/Features/NoteEditor/NoteEditorView.swift`
- Verify: `Sources/QuietPaper/App/QuietPaperApp.swift`

**Step 1:** Run `./scripts/run-tests.sh`; expect all in-memory checks to pass.

**Step 2:** Launch with `--in-memory-preview`, click the focus button, and verify only the detail column remains.

**Step 2a:** Verify a Markdown note uses a centered responsive white canvas with equal side margins and no editor chrome, while request and connection editors retain their existing layout.

**Step 3:** Trigger `Command + E` and verify all columns return, then repeat for a project-root file layout.

**Step 4:** Build the distributable app with `./scripts/build-app.sh` after verification.

### Task 4: Refine the focused reading canvas

**Files:**
- Modify: `Sources/QuietPaper/Features/NoteEditor/NoteEditorView.swift`
- Modify: `Sources/QuietPaper/Features/RootView.swift`

**Step 1:** Increase the focused Markdown canvas maximum width to 1280pt and preserve 32pt minimum horizontal safety padding.

**Step 2:** Remove the paper edge and theme-colored side gutters; use one seamless white surface across the focused window.

**Step 3:** Use the light appearance while the focused Markdown canvas is visible so text remains readable on white.

**Step 4:** Build, run the complete in-memory test suite, and visually verify equal left/right margins at multiple window widths.
