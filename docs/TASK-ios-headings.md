# Task (iOS): headings you can add, rename, fold and delete (the Mac's §23)

The user approved this on 2026-11-03, as written. Today the phone only displays headings. Start it after the drag
and tapped-row work. It needs no core change: `Store.createHeading` and the existing update and delete ops cover it.
If something doesn't fit, stop and ask through the coordinator.

The source of truth is `design/INTERACTIONS-v2.md` §23. Read "What a heading is", "How a heading looks",
"Collapsing" and "Deleting a heading" for the details below.

## Add
- **"New Heading"** in a list's "…" menu adds it at the bottom of the list.
- **"New Heading Above"** in a task's long-press menu adds it above that task, which becomes the section's first task.
- It appears in place, named "New Heading" and focused for typing. Return, or a tap elsewhere, writes it: one
  `task.create` with `kind: heading`, undo name "New Heading". A tap elsewhere only ends adding, as with tasks
  (48d627e). An empty name leaves nothing: no op and no undo step.
- It's only in lists. Today and the views don't offer it.

## Rename and notes
- **Tap the heading's name** to rename it in place. (The Mac selects on a click and renames on a double-click; a
  heading has no detail sheet on the phone.) An empty name keeps the old one. Write only when the text changed, as
  in `EditSession`.
- **Notes:** "Add Notes" or "Edit Notes" in the heading's menu opens the same notes editor as a task, under the
  heading. It writes one `task.update` per session.

## Fold
- A **chevron** at the right of every heading, always shown, since there's no hover on the phone. Down means open and
  right means collapsed, rotating 200 ms ease-out. The glyph size is the Mac's, scaled. It takes the tap itself and
  never renames.
- **Collapsing** folds the notes and tasks up into the heading row as they fade, 150 ms, and the rows below close up
  on the same curve. **Expanding** plays that backwards, 220 ms ease-in. Rows never cross (§23).
- A collapsed heading shows its open-task count after its name, at 11/14 medium `ink-tertiary` with tabular figures,
  scaled.
- The folded state is saved per device, never synced, keyed by heading id, as the Mac does in `WindowState.collapsed`.
  A new heading starts open.
- "New Task in <heading>" expands it first.
- **Drag:** a task dropped right under a collapsed heading joins the end of its section and stays folded, and the
  count goes up. This is the Mac's rule in `WindowActions.reorder` 580–603. Add it to the iOS landing-spot code.
- Respect Reduce Motion.

## The heading's long-press menu
Rename · Add Notes or Edit Notes · New Task in "<heading>" · Collapse or Expand · Delete Heading (destructive).
There's no Move Up or Move Down, because dragging covers them.

## Delete
Delete removes the heading only. Its tasks stay where they are, under the heading above, or under none. A notice says
"Deleted heading “Labs”" with Undo, and the undo name is "Delete Heading". Headings don't appear in Trash.

## Rules (the user's, from 2026-11-02)
- **Tests:** run the targeted tests, then the full iPhone suite once before the install. An intelligencetasksd crash
  gets one rerun and no investigation.
- **Screenshots and iPad:** none unless asked, and no iPad runs.
- **Commits:** one commit on `ios`, under `ios/` only. A core helper needs the user's OK first.
- **Install and push:** install on the phone with this batch, keeping the data and the token, then push `ios`.
