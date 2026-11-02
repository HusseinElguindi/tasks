# Task: open a deleted list in the detail pane, reusing the list view

**The user (2026-11-01):** "i actually dont like the open view. it's hard to get back. i would like for it to open the
same list view as in how normal lists open, but in the detail tab (with a restore banner of course). i dont want to
rebuild things. reuse is better."

The current behaviour (§28, commit 4852707): Return or open on a deleted list's row in Trash replaces the Trash pane
with a read-only list pane. Getting back to Trash is awkward.

## Wanted
- **Opening a deleted list** shows it in the **detail pane**, on the right, with Trash staying in the middle.
  That covers Return, double-click, and selecting the list's row if that's how the detail pane already follows
  selection.
- What it shows is **the same list view a normal list uses**: the large title with its tile, the list's notes,
  headings, and rows with their checkboxes, chips and dates. Use the existing components; don't make a second
  version of them. Put the Restore banner on top. It reuses the existing banner component, which today lives in the
  read-only pane.
- Read-only, as §28 says. Headings can still fold. Selecting a task inside it is fine if it's cheap; say what you
  chose.
- Esc, or closing the detail pane, returns focus to Trash. Nothing about the Trash pane itself changes.
- **Remove the full-pane read-only open,** and whatever code becomes dead with it. Keep the inline expand in Trash.
- If the detail pane is too narrow for the list view at its minimum width, say how it degrades. Don't build a
  narrow variant.

## Rules
- **Reuse over new code.** If the list view can't be hosted in the detail pane without a large refactor, stop and
  report the options before refactoring.
- Update `design/INTERACTIONS-v2.md` §28, and wherever the open behaviour is described, citing "the user,
  2026-11-01". Leave the prototype alone unless a small change is enough.
- Build Release into `app/.build/DerivedData` and run all tests.
- Take in-app snapshots only (never `screencapture` of the whole screen): Trash with a deleted list open in the
  detail pane, in dark and light.
- Per-path commits only (`git commit -m … -- <paths>`), ending with `Co-Authored-By: Claude Opus 5.5
  <noreply@anthropic.com>`. Never `git add -A`. Never push.
- Don't touch the installed app, its data, the live servers, or Rex. The coordinator installs.

## Report
In a few lines, with the commit hashes and the snapshot paths.
