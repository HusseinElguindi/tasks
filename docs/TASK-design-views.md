# Task: design the Completed, Upcoming, Undated and Trash views

The user's words: "i want a completed, upcoming, undated, and trash page. let's make designs for these first though. they should probably be similar and build on what we have slightly."

**This is design only.** Nothing goes into `app/` until the user approves.

## Build on what exists

- **The v2 prototype is the base.** It's in `design/prototype-v2/`, published at https://claude.ai/artifact/QetdV1H57SC6kLXtNzJRXM. The user loves its animations and details.
- **The v2 build spec:** `design/INTERACTIONS-v2.md`.
- **The user's later feedback,** all of it now in the app: `docs/TASK-v2-feedback.md`.
  - A single click on empty space clears the selection, and a double-click adds a task.
  - The active-pane colour shows only with two panes.
  - Panes can be resized.
  - The detail fields are aligned with the checkbox.
  - There's an "Edit tasks" setting.
  - The sidebar has a brand header: the mark plus "Tasks" above Today.
- **Read for the model:** `docs/SPEC.md` §1–4. It gives the fields (when, deadline, completed, deleted, list, order) and how Today works.
  - Hard deletes are deferred. Trash holds soft-deleted tasks, and the design must not offer "delete forever" unless the spec allows it. If you think Trash needs it, raise it as an open question.
  - Only add model fields if a view truly needs one, and say so.
- **Rex is the source of truth for the look:** `design/REX-REFERENCE.md`, with Pane as the vocabulary. Don't drive Rex.

## Design

The four views should feel like siblings of Today: the same row, the same detail pane, the same header. Decide:
- **Where they live in the sidebar.** For example, a group under Today, or a quieter group at the bottom; what each one's icon is; and whether they show counts.
- **What each view shows and how it's grouped:**
  - **Completed:** all completed tasks across lists, perhaps grouped by the day they were completed; uncompleting; how far back it goes.
  - **Upcoming:** tasks whose when or deadline is after today, grouped by day, then week or month further out. What happens when a task has both dates? Can you drag a task onto a day to reschedule it?
  - **Undated:** open tasks with neither date, grouped by list.
  - **Trash:** deleted tasks, restoring them, how deleting works from each view, and the empty state.
- **What changes in each view:** which operations work (add, drag, reorder, move to a list), what a new task defaults to (adding in Upcoming under a day sets its when), and the empty states. Also keyboard navigation.

Where there's a real choice, show two or three variants side by side for the user to pick; don't make a menu out of obvious answers.

## Output

1. **The prototype:**
   - Extend `design/prototype-v2/` with these four views. Keep the same code, the same animations, and the user's picks.
   - Publish it as a canvas (a new artifact is fine), with boards for each view in dark and light and the variant comparisons.
   - It must stay clickable.
2. **The spec:** add a section to `design/INTERACTIONS-v2.md` with the views' rules, layout tokens and interactions, citing the prototype's lines the same way the rest of the spec does.
3. **Commit** per path, never `git add -A`, never push. End commit messages with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
4. **Report** the canvas link, the choices for the user and your recommendations to the coordinator, then stop.

You may use subagents.
