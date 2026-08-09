# Writing Focus Blur Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Blur the project and note navigation columns while a Markdown note title or body has keyboard focus, and reveal both columns whenever either is hovered.

**Architecture:** Keep focus/hover decisions in a small value type owned by `RootView`. Report title focus from SwiftUI and body focus from the AppKit-backed Markdown editor, then apply one reusable visual modifier to both navigation columns without disabling hit testing.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSTextViewDelegate`, existing executable checks.

---

### Task 1: Add and test the focus decision state

**Files:**
- Create: `Sources/QuietPaper/Features/Shared/WritingFocusBlur.swift`
- Modify: `Tests/QuietPaperChecks.swift`

**Steps:**

1. Add a check covering no focus, title/body focus, each hover region, and focus removal.
2. Run `./scripts/run-tests.sh` and verify the new check fails before the state type exists.
3. Implement `WritingFocusBlurState` with focused targets and hover flags.
4. Run `./scripts/run-tests.sh` and verify the state check passes.

### Task 2: Report title and Markdown body focus

**Files:**
- Modify: `Sources/QuietPaper/Features/NoteEditor/MarkdownEditor.swift`
- Modify: `Sources/QuietPaper/Features/NoteEditor/NoteEditorView.swift`

**Steps:**

1. Add an `onFocusChange` callback to `MarkdownEditor` and report `NSTextView` begin/end editing from its coordinator.
2. Add title `FocusState` tracking in `NoteEditorView` and forward title/body changes to `RootView`.
3. Clear both focus targets when the note editor disappears.
4. Build through `./scripts/run-tests.sh` to catch SwiftUI/AppKit integration errors.

### Task 3: Apply blur and hover reveal in the split view

**Files:**
- Modify: `Sources/QuietPaper/Features/RootView.swift`
- Modify: `Sources/QuietPaper/Features/Shared/WritingFocusBlur.swift`

**Steps:**

1. Store `WritingFocusBlurState` in `RootView` and pass focus updates into `NoteEditorView`.
2. Track hover across the project and note columns; either hover must reveal both.
3. Add the shared blur/opacity/saturation modifier with reduced-motion support and apply it to both columns.
4. Run `./scripts/run-tests.sh` and launch an in-memory smoke preview.

### Task 4: Final verification

**Files:**
- Verify: all modified source and plan files

**Steps:**

1. Confirm the diff contains no production database path or destructive database operation.
2. Run `./scripts/run-tests.sh` once more and record the result.
3. Report source changes and validation; package/restart only when requested because packaging increments the app version.

### Task 5: Add a persistent appearance setting

**Files:**
- Modify: `Sources/QuietPaper/Features/Shared/WritingFocusBlur.swift`
- Modify: `Sources/QuietPaper/Features/RootView.swift`
- Modify: `Sources/QuietPaper/Features/Settings/ThemeSection.swift`
- Modify: `Sources/QuietPaper/Features/Settings/SettingsView.swift`
- Modify: `Tests/QuietPaperChecks.swift`

**Steps:**

1. Define one shared `UserDefaults` key with a default value of enabled.
2. Add a switch card to the appearance settings page using `@AppStorage`.
3. Read the same setting in `RootView` and gate the blur decision without altering focus/hover behavior.
4. Extend the state check to cover the disabled preference and rerun all checks.

### Task 6: Extend focus blur to the editor header

**Files:**
- Modify: `Sources/QuietPaper/Features/Shared/WritingFocusBlur.swift`
- Modify: `Sources/QuietPaper/Features/RootView.swift`
- Modify: `Sources/QuietPaper/Features/NoteEditor/NoteEditorView.swift`
- Modify: `Tests/QuietPaperChecks.swift`

**Steps:**

1. Test that body-only focus blurs the editor header while title focus keeps it clear.
2. Track editor-header hover independently from navigation hover.
3. Apply the existing blur modifier to the breadcrumb, title, mode controls, and formatting toolbar.
4. Verify hover reveal and the persistent master switch in an in-memory preview.
