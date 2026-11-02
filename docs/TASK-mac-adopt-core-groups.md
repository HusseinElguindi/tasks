# Task: the Mac app uses the core's ViewGroups and MarkdownNumbers

The iOS work (merge fee39a7) moved three Mac-only rules into TasksCore, verbatim, so that both apps share one
copy:
- `app/TasksCore/Sources/TasksCore/ViewGroups.swift`: the Upcoming day (`upDay`), the Upcoming order, the Upcoming
  groups (7 days, then months with "Later in"), the Completed/Trash groups (`past`), the weekday and month names,
  and the checkbox ring's cue (`RingCue`).
- `app/TasksCore/Sources/TasksCore/MarkdownNumbers.swift`: `Markdown.Document.shownNumbers`, how ordered lists
  number themselves.

The Mac app still has its own copies. **Switch the Mac to the core's versions and delete its copies.**
- `app/Tasks/TaskList/ViewLayout.swift`: `ViewItems.upDay`, `ViewNames`, and the buckets in `buildView` (Upcoming,
  Completed and Trash). Group ids and names must come out the same.
- `app/Tasks/TaskList/RowDates.swift`: `CheckLayer.Cue.init` should come from `ViewGroups.RingCue`. Keep the Mac's
  `CheckLayer.Cue` type if the layers need it, but build it from the core value.
- `app/Tasks/Detail/NotesMarkdown.swift`: the numbering loop in `update` should use `doc.shownNumbers`.
- The Completed sort (newest first, ties broken by id, `ViewLayout.swift` near line 121) is still in the app.
  Leave it, unless the core already has an equivalent.

**One deliberate behaviour change:** `ViewGroups.past` clamps a future day to today (clock skew from another
device). The Mac's code put a future-stamped completion or deletion under a weekday. After the switch, it joins
"Today". That's the user's decision (2026-11-02). Every other output must stay identical.

## How
- **Don't edit TasksCore.** If a core API doesn't fit the Mac, stop and report. The core files are shared with
  `ios/`.
- Prove that nothing changed: before you edit, record the Mac's outputs for the views (Upcoming, Completed, Trash:
  group ids, names, subs and order) and the notes numbering, using unit tests or a DebugScript dump. Compare them
  after the switch. The only difference should be the clamp.
- Mention the switch in `design/INTERACTIONS-v2.md` where those rules are described, if it says where they live.
- Build Release into `app/.build/DerivedData`. Run all tests: xcodebuild test for the app, and `swift test` in
  `app/TasksCore`.
- Take in-app snapshots only (never `screencapture`): Upcoming, Completed and a note with an ordered list, before
  and after. They should match.

## Rules
- Per-path commits only (`git commit -m … -- <paths>`), ending with `Co-Authored-By: Claude Opus 5.5
  <noreply@anthropic.com>`. Never `git add -A`. Never push.
- Don't touch the installed app, its data, the live servers, or Rex. The coordinator installs.

## Report
In a few lines: the commit hashes, the before/after comparison, and the snapshot paths.
