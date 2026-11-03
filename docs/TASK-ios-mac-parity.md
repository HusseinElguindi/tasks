# Investigation: what the iPhone app is missing, or does differently, compared with the Mac

**The user (2026-11-03):** "i want you to compare the missing/different features between mac and ios."

This is read-only analysis. Don't change app code.

## Sources
- **The Mac:** the spec is `design/INTERACTIONS-v2.md` (all sections), with `design/MARKDOWN.md`, `design/COLOR.md`
  and `design/THEMES.md`. The code is `app/Tasks/`. Where the spec and the code disagree, the code is what ships;
  note it.
- **iOS:** `ios/` (merged into main at 520c4af), and `docs/SPEC.md` §8 "iOS client", which lists the deliberate
  differences.
- **Shared:** `app/TasksCore` and `TasksTheme`. Anything the core does is the same on both, so say so rather than
  listing it.

## Already decided or in progress (list these, but don't re-propose them)
- **Built on the Ex-Mac now:** drag to reorder (`docs/TASK-ios-reorder-and-selection.md`), showing the tapped task,
  and headings: add, rename, notes, fold and delete (`docs/TASK-ios-headings.md`).
- **Deliberate differences:**
  - a tap elsewhere while adding only ends adding;
  - iOS saves typed text when the app goes to the background;
  - new tasks go at the top of a list on iOS;
  - notes are rendered at rest and edit as plain text;
  - titles keep 156 pt, list names hide below 42 pt (scaled);
  - no search on either app.
- **iPad:** out of scope for now. Compare the iPhone only, and mention the iPad only when it's the sole place
  something exists.

## Method
Go feature by feature through the Mac spec's sections:
- selection;
- adding;
- editing and the detail pane;
- completing;
- dates (When, Deadline, the date phrase parser, and the popover versus the picker);
- moving between lists;
- delete, Trash, Put Back and Delete List;
- Today, Upcoming, Undated, Completed, Trash;
- headings;
- notes and Markdown (checkboxes, lists, typing a box);
- the sidebar and lists (create, rename, reorder, delete, tiles);
- undo and redo;
- notices;
- sync status and errors, and Settings;
- menus and context menus;
- keyboard (most won't apply: say which have a touch equivalent);
- zoom, panes and highlight (Mac-only, say so);
- Moments and colour;
- empty states;
- motion and Reduce Motion;
- accessibility.

For each feature, find the iOS code that does it, or confirm it's absent. Cite file:line on both sides.

## Output
Write `docs/IOS-MAC-PARITY.md` and commit only that file, by path.
1. **A summary:** the five to ten gaps that matter most for daily use on the phone, ranked, with a recommendation for
   each: build, adapt for touch, or leave out. Give a rough size: S, M or L.
2. **A table:** feature | Mac | iPhone | status (same / different on purpose / different by accident / missing /
   Mac-only by nature) | notes and citations.
3. **"Different by accident":** a short list of places where the iPhone diverges without a decision. These are likely
   bugs.

Keep it scannable. Report in a few lines with the commit hash and the top five gaps.

## Rules
- Per-path commits only (`git commit -m … -- <paths>`), ending with `Co-Authored-By: Claude Opus 5.5
  <noreply@anthropic.com>`. Never `git add -A`. Never push.
- Don't touch the installed app, its data, the live servers or Rex.
- Building and running is optional. If you do run the iOS app, use a simulator with demo data only. No screenshots
  of the whole screen.
