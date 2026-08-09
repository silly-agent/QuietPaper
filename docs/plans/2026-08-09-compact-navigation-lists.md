# Compact Navigation Lists Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refine the project tree and note list into compact, minimal macOS navigation surfaces without changing behavior.

**Architecture:** Keep the existing SwiftUI view hierarchy and model bindings. Apply targeted typography, spacing, icon, toolbar, hover, and selection-background changes inside the two navigation feature files; verify through compilation and the repository's in-memory test flow.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Package Manager

---

### Task 1: Compact project navigation

**Files:**
- Modify: `Sources/QuietPaper/Features/ProjectNavigation/ProjectSidebar.swift`

1. Reduce header and row padding while preserving the existing hit regions.
2. Give project rows medium weight and child rows regular weight.
3. Reduce icon size and opacity so the hierarchy is title-led.
4. Replace the broad selected pill with a subtle rounded fill plus a 2pt leading accent marker.
5. Run `swift build` and expect a successful build.

### Task 2: Compact note list

**Files:**
- Modify: `Sources/QuietPaper/Features/NoteList/NoteListView.swift`

1. Reduce title-bar padding and convert the sorting label to an icon-only trigger with full accessibility text.
2. Tighten `List` row insets and internal padding.
3. Use 13pt medium note titles, 11pt timestamps, subdued icons, and monospaced digits.
4. Apply the same subtle fill and leading accent marker to selection; retain a weaker range-selection state.
5. Bring folded rows to the same density and feedback language.
6. Run `swift build` and expect a successful build.

### Task 3: Regression verification

**Files:**
- Test: `Tests/QuietPaperChecks.swift`

1. Run `./scripts/run-tests.sh`; expect all checks to pass using `WorkspaceDatabase(inMemory: true)`.
2. Launch only with `swift run QuietPaper --in-memory-preview`; confirm startup succeeds without the production database.
3. Review `git diff` and confirm only the two navigation views and these plan documents changed for this task.
