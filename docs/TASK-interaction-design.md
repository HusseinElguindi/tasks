# Task: design the interactions from scratch

The user tried the current Mac build (`76eb966`). Their verdict: "a bit better but it's just clunky. let's go back to claude design and design the interactions from scratch. adding tasks, renaming lists, the date picker, everything."

Earlier, they called the interactions and hover states "horrendous". The only part they liked was the transition when the detail pane opens on the side.

## Goal

Design every interaction in the app from a blank page, in Claude Design. The result has to be something the user can *feel* before any Swift is written, and a written spec the Mac agent can build exactly.

The scope is everything a person does:
- **Tasks:** adding (⌘N, and clicking in empty space), editing a title inline, notes, completing and uncompleting, deleting with undo, and moving a task to another list.
- **Selection:** single and multi-select, plus keyboard navigation.
- **Dates:** the When and Deadline pickers. Cover typing a date ("tom", "fri", "3d"), the calendar, clearing a date, and how the chips read.
- **Lists:** creating, renaming (inline, double-click, context menu), reordering, archiving, and the archive view.
- **Today:** its behaviour, the empty states, and completed tasks.
- **Panes:** the detail pane opening and closing (keep what the user liked) and pane focus.
- **Throughout:** hover, press and focus states for every control, context menus, drag (reorder, cross-list, sidebar), and undo feedback.

## Constraints

- **The app:** A1 · Split stays as the layout: sidebar, list pane and detail pane. Read `design/DIRECTIONS.md`, `docs/SPEC.md` §1–4 (model and screens) and `docs/BRIEF.md`. The data model and sync are fixed.
- **Rex is the source of truth, not Pane** (`docs/TASK-source-of-truth.md`).
  - `design/REX-REFERENCE.md` holds measured Rex colours, metrics and timings. Use them.
  - **Do not drive or click Rex yourself.** If you need something measured, write the question in your notes and tell the coordinator.
- **Pane** (Claude Design: https://claude.ai/artifact/MS3VdrN9VHU7A7pTUTzpm8, `design/PaneTheme.swift`) is the token vocabulary. Don't get stuck copying it. Where Rex and Pane disagree, Rex wins; log the gap in `design/PANE-UPSTREAM.md`.
- **Read `design/INTERACTIONS.md`.** It describes what was built and what felt wrong. Don't inherit it; use it as a list of traps.
- **Simplicity.** Fewer, better interactions. No confirmation dialogs, since everything can be undone. It's a native macOS app, so respect platform conventions (⌘Z, Return or double-click to rename, Escape cancels, type-to-select) unless Rex does it differently.

## Output

1. **An interactive prototype in Claude Design**, as an artifact.
   - It should be clickable and typeable, with real hover states and real animation timings: add a task, rename a list, pick a date, drag, undo.
   - It should be good enough that the user can judge the feel in a browser.
   - Dark theme first; light as a toggle.
2. **Where there is a real choice** (for example how quick add works, or the date picker's shape), put two or three variants side by side in the prototype or on a canvas so the user can pick. Don't present a menu for things with an obvious answer.
3. **`design/INTERACTIONS-v2.md`** is the build spec for the Mac agent. For every interaction, give:
   - the trigger;
   - each state, with exact tokens and colours;
   - timing and curve;
   - keyboard behaviour;
   - the SwiftUI or AppKit approach, wherever SwiftUI's defaults would fight it.
4. **Commit as you go:** per path, never `git add -A`, never push. End commit messages with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

**Do not touch `app/`.** The Mac agent builds from your spec once the user approves it.

When the prototype is ready to try, stop and report its link and the open choices. The user reviews before the spec is final. You may use subagents.
