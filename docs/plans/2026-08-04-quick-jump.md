# Quick Jump Implementation Plan

**Goal:** Add three persistent global quick-jump slots bound to `Command + 1`, `Command + 2`, and `Command + 3`.

**Architecture:** Store target note UUIDs in UserDefaults. Keep the complete active-note catalog in AppModel, add a database fetch for all live notes, and centralize navigation in `AppModel.jumpToQuickPage(_:)`. Settings provides direct selection and current-page assignment. RootView receives one notification carrying the slot number; the app delegate and menu commands use the same notification.

### Task 1: Page catalog and navigation

- Add `WorkspaceDatabase.fetchAllNotes()` and keep `AppModel.allNotes` refreshed with note reloads.
- Add path display and navigation for module files and project-root files.
- Update the cached all-note entry after saves.

### Task 2: Settings configuration

- Add a “快捷跳转” settings Tab.
- Add three rows for `⌘1`, `⌘2`, and `⌘3` with page menus, current-page assignment, clear state, and missing-page feedback.
- Persist each target through `@AppStorage`.

### Task 3: Global shortcuts and verification

- Add menu commands and local keyboard handling for the three slots.
- Route all triggers through a shared notification and verify navigation in an in-memory preview.
- Run `./scripts/run-tests.sh` and package with `./scripts/build-app.sh`.
