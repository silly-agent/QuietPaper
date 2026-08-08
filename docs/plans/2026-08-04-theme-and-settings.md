# Theme and Settings Tabs Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace color-washed themes with neutral semantic surfaces and reorganize Settings into five left-navigation Tab pages.

**Architecture:** Keep `Theme` as the persisted theme identifier and refine `ThemePalette` values so existing surface roles gain clear hierarchy without touching feature data flow. Rebuild `SettingsView` as a two-column shell whose local selection chooses one existing settings section per page.

**Tech Stack:** Swift 6, SwiftUI, AppKit dynamic colors, Swift Package Manager.

---

### Task 1: Neutral theme palettes

**Files:**
- Modify: `Sources/QuietPaper/Infrastructure/Theme.swift`
- Modify: `Sources/QuietPaper/Features/Settings/ThemeSection.swift`

**Step 1: Define acceptance checks**

Verify every non-system palette has three visually ordered low-chroma surfaces and one recognizable accent in both Aqua and Dark Aqua.

**Step 2: Implement the palette values**

Keep the public roles `accent`, `background`, `control`, and `editor`, but move chroma out of the large surfaces. Update theme summaries to describe the restrained behavior.

**Step 3: Improve the theme preview**

Replace the two isolated swatches with a miniature sidebar/editor composition and an accent selection mark.

**Step 4: Compile**

Run: `swift build`

Expected: build completes without Swift errors.

### Task 2: Settings navigation shell

**Files:**
- Modify: `Sources/QuietPaper/Features/Settings/SettingsView.swift`
- Modify: `Sources/QuietPaper/Features/Settings/ThemeSection.swift`
- Modify: `Sources/QuietPaper/Features/Settings/AISettingsSection.swift`
- Modify: `Sources/QuietPaper/Features/Settings/TrashSection.swift`

**Step 1: Create the Tab model**

Add a private enum for `appearance`, `ai`, `storage`, `trash`, and `about`, including title and SF Symbol metadata.

**Step 2: Build the two-column shell**

Render a fixed 168-point navigation column and one page at a time in the detail area. Preserve the existing dismiss action and environment object.

**Step 3: Convert sections into page content**

Move page headings into a shared page header. Keep existing controls and actions unchanged while giving each page independent scrolling and appropriate empty states.

**Step 4: Compile**

Run: `swift build`

Expected: build completes without Swift errors.

### Task 3: Regression and visual verification

**Files:**
- Verify: `Sources/QuietPaper/Infrastructure/Theme.swift`
- Verify: `Sources/QuietPaper/Features/Settings/*.swift`

**Step 1: Run all local checks**

Run: `./scripts/run-tests.sh`

Expected: core, editor, and autosave checks all pass using in-memory databases.

**Step 2: Launch a disposable smoke-test instance**

Run the debug executable with `--in-memory-preview`, which creates a seeded `WorkspaceDatabase(inMemory: true)` and never resolves the production database URL.

Expected: Settings opens, all five Tabs switch correctly, and theme selection updates the window immediately.

**Step 3: Inspect light and dark appearances**

Check that editor content is the clearest surface, sidebar/list hierarchy remains visible, and accent color is not used as a full-window wash.
