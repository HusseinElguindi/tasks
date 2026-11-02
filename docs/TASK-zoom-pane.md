# Task: zoom a pane, Rex-style

**The user (2026-11-01):** "i would like a feature to zoom into a task. Rex has it like this … let's focus on zoom for
now. basically just make it the main tab."

The reference is `docs/feedback/rex-zoom-pane.png`: Rex's pane header has split, split, stack, **zoom** (a diagonal
two-arrow expand glyph) and ×, and the zoom button's tooltip reads "Zoom Pane ⇧⌘↩". **Only zoom is in scope.**
Splits and moving panes are for later.

## Behaviour
- **Zoom** makes the detail pane (the task, or a deleted list shown there) fill the window's content area. The
  sidebar and the list pane hide; the window itself doesn't change. Zoom again (the same button, ⇧⌘↩, or Esc)
  returns to the previous layout, with the same widths, focus and scroll.
- **The button:** in the detail pane's header, beside × and in the same style (the existing header buttons; match
  Rex's glyph). When zoomed, it shows the collapse glyph, in the matching inward-arrows shape. Its tooltip is
  "Zoom Pane ⇧⌘↩", or "Unzoom Pane" when zoomed. Mirror Rex's wording if `design/REX-REFERENCE.md` has it.
- **⇧⌘↩** toggles zoom on the focused pane. The menu item goes where §17's menus put pane commands (View menu).
  Check that ⇧⌘↩ doesn't clash with anything in §17.
- **Decide and say what you chose:**
  - Should the list pane zoom too, when it's focused? Rex zooms any pane. Recommend yes if it's cheap, since it hides
    the sidebar and the detail pane.
  - What does ↑/↓ do while zoomed? Probably still move the task selection, so the zoomed task changes.
  - What happens when the zoomed task is deleted or completed?
  - Does the detail pane open zoomed next time? Probably not: zoom is a moment, not a mode.
- **The transition:** use the layout animation the pane open and close already uses (`dur-layout`, `ease-layout`).
  Respect Reduce Motion.
- With the active-pane setting (a parallel task, `docs/TASK-active-pane-setting.md`), a zoomed pane is the only
  pane. Follow whatever that setting says for one pane. If that work hasn't landed when you get there, coordinate
  through git: don't edit files it has uncommitted.

## Rules
- Add a §29 Zoom section to `design/INTERACTIONS-v2.md`, plus a §17 row. A small prototype change is fine if it's
  cheap. Cite "the user, 2026-11-01".
- Build Release into `app/.build/DerivedData` and run all tests.
- Take in-app snapshots only (never `screencapture` of the whole screen): unzoomed with the button, zoomed, and
  the tooltip if you can capture it.
- Per-path commits only (`git commit -m … -- <paths>`), ending with `Co-Authored-By: Claude Opus 5.5
  <noreply@anthropic.com>`. Never `git add -A`. Never push.
- Don't touch the installed app, its data, the live servers, or Rex. The coordinator installs.

## Report
In a few lines, with the choices you made, the commit hashes and the snapshot paths.

## Update from the user (2026-11-01): keep the sidebar
"zoom pane should still respect the sidebar. the user can collapse it if they want afterwards."

Zoom hides only the other content pane, which is the list pane when the detail pane zooms. **The sidebar stays as
it is.** If it's open, it stays open. If it's collapsed, it stays collapsed. Its own toggle still works while
zoomed. Unzooming leaves the sidebar's state alone.
