# Task (iOS): drag to reorder, and show the tapped task

The user approved both on 2026-11-03. The design is settled; build it as written. If something doesn't fit, stop and
ask through the coordinator. Don't improvise.

## 1. Drag to reorder, from the Mac's §14 and §23

**Gesture:** long-press, then drag, which is the iPhone's own drag. Holding still still opens the row's context menu,
and moving lifts the row. There's no grip; the whole row is the handle. The other rows part to open a gap, with no
insertion line. There's a light haptic on lift and on drop.

The lifted copy matches the Mac (§14): `fill-lift`, the row radius, `shadow-lift`, and the checkbox, title and chips.
Near the top or bottom edge, the list scrolls. Dropping where the row started writes nothing.

**What moves, and where it can land:**
- **A list's open tasks.** Headings are ordinary rows in the drag, so a task can cross into another section (§23,
  INTERACTIONS-v2:1497). Dropped right after an expanded heading, it goes to the top of that section. Right under a
  collapsed heading, it goes to the end of that section and stays folded. This is one op: `list` and `order`
  together, through `Store.reorder`.
- **A heading moves its whole section** (§23). Its notes and tasks fold into the lifted copy, which shows the
  heading's row with an `accent` badge counting its open tasks. It lands only before another heading or at the end,
  never inside a section or above the tasks that have no heading. The drop goes through `Store.moveSection`, which
  writes the heading and every task in its section, completed ones included.
- **Today and Undated:** a task moves only within its own list's group (§14: the copy stops at the group's edges).
  That reorders it within that list.
- **Lists on Home** (the stand-in for the sidebar) go through `Store.reorderLists`. Today and the views can't be
  dragged.

**Not moving:**
- done tasks;
- Completed and Trash;
- Upcoming's drag to reschedule onto a day, which is a separate §22 feature, later;
- dragging onto another list;
- multi-select drag;
- a heading to another list.

**Reuse:** the writes are only the core's `reorder`, `moveSection` and `reorderLists`, with `Ordering.Anchor` from
the drop slot. Don't add any ordering logic in `ios/`. If the anchor for a slot isn't obvious, read the Mac's
`TaskLayout` and drag code, and propose a core helper if one is needed.

## 2. Show the tapped task (option B)

- **The press:** on touch-down, the row shows its `press` fill, which `RowStyle` already has, so you can see it. At
  the moment, the list's touch delay means a quick tap never shows it. Make the press visible right away without
  breaking scrolling or swipe actions.
- **While the sheet is open:** the tapped row keeps the Mac's selected fill, `fill-row-selected` at the row radius.
- **When the sheet closes:** that fill fades out, about 300 ms ease-out, as in Mail and Settings, so you can see
  which row you came from.
- No accent edge: the Mac's selection has none.

## Rules (the user's, from 2026-11-02)

- **Tests:** run only the tests for what changed, and the full iPhone suite once before the phone install.
  intelligencetasksd crashes get one rerun and no investigation.
- **Screenshots:** none unless asked. If any are taken, after-shots only.
- **iPad:** no runs.
- **Commits:** one commit per feature on `ios`, under `ios/` only. A core helper needs the user's OK first, through
  the coordinator.
- **Phone:** install after both features are done, keeping the data and the token. Then push `ios`.
