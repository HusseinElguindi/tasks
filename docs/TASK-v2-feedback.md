# Feedback on the installed v2 build

The user is trying v2 now. Fix each item, verify it on your scratch instance, commit, rebuild Release, and report back. More items may be appended to this file.

## 1. "New Task" shows twice

The user's words: "when you make a new task then hover over empty area, there are some states that show new task twice. i don't like that"

Screenshot: `docs/feedback/v2-double-new-task.png`.
- In the list "Hi there", ⌘N or + created the draft. The detail pane is open, with the caret in "New Task".
- The list shows two "New Task" rows: the draft, which is selected, and a second one under it. The second one appears to be the empty-area hover ghost, the add affordance.

While a draft exists, there must only ever be one "New Task" row.
- Suppress the empty-area ghost while a draft is open, or make hovering the empty area point at the existing draft.
- Check every state that leads here: ⌘N, the + button, clicking empty space, Today, an empty list, and a draft that was abandoned.
- Check the prototype has the same bug. If it does, note it, and fix the prototype too if that's cheap.

## 2. Clicking empty space creates a task, and that's annoying

The user's words: "pressing in an empty area to make a new task is getting a little annoying"

The coordinator's call, which the user can overrule:
- **A single click on empty list space no longer creates a task.** It does what it does in Rex and Finder: it clears the selection. While a draft is open, it ends the draft by the existing rules (save if it has a title, drop if it's empty). It never starts a new one.
- **Remove the hover "New Task" ghost row entirely.** With nothing created on a click, it has no reason to exist.
- **Double-click on empty list space creates a task**, exactly as ⌘N would.
- **⌘N and the + button are unchanged.**

Update `design/INTERACTIONS-v2.md` (§6 and anywhere else that mentions the empty-space click or the ghost row) and the prototype source to match. Commit, rebuild Release and report back.

## 3. Show the active-pane colour only when there are two or more panes

The user's words: "i want the active pane color to only appear when there is more than 1 pane."

- **With one pane** (the detail pane closed): the list pane shows no focused or active treatment. Use the plain neutral surface and edge, the same in every key-focus state.
- **With two panes:** the focused pane keeps its current colour, and the other one dims as now.
- **The change between the two** follows the detail pane's open and close transition rather than snapping at the end.

Do not open or drive Rex to check this; the user's rule wins. Update the spec and the prototype source.

## 4. Panes can be resized by dragging (after the compact)

The user's words: "i want these panes to be draggable in size"

- **What to resize:** drag the gap between the list pane and the detail pane, and between the sidebar and the list pane, to resize them.
- **Behaviour:** use Rex's divider behaviour as described in `design/REX-REFERENCE.md`. If it doesn't cover dividers, do the simplest thing that feels native:
  - a resize cursor over the gap, with no visible handle;
  - sensible minimum widths;
  - double-click the gap to reset to the default width;
  - widths remembered across launches, and the detail pane reopening at its last width.
- **The detail pane's open and close transition must keep working at any width.**
- Update the spec and the prototype source.

## 5. A brief flicker when renaming and when a reorder settles

The user's words: "there's a flicker that happens very quickly near when double clicking and renaming and also right after reordering (when it's settling)"

- **Double-click to rename.** The flicker appears around the moment the in-place field takes over. Check:
  - a sidebar list;
  - a task title, if double-click renames there;
  - committing the rename (Return, or a click away), as well as entering it.
  - Likely causes:
    - the label and the field both drawing for a frame, or neither;
    - a layer re-render or implicit `CALayer` animation;
    - the row being rebuilt when the store publishes the rename.
- **A reorder settling.** The flicker comes just after you drop, as the row settles into place. That covers task rows and sidebar lists, within a list and dropped onto another list.
  - Likely causes:
    - the drag snapshot being removed a frame before (or after) the real row reappears;
    - the list reloading from the store's op after the settle animation, and replacing or re-laying out rows;
    - the 35% source-row opacity snapping back.
- **Find it frame by frame.** Record at 60 fps (or capture each frame from a CADisplayLink callback inside the scratch app) and step through the frames. Don't guess. Fix the cause so every frame in the hand-off is continuous, check the frames again after the fix, then commit, rebuild Release and report back.

## 6. The detail pane's fields start at the left edge and fill the width

The user's words: "I would like for the list, when, deadline, notes, etc to also be left aligned and take up the whole width, just like the checkbox and title row". Screenshot: `docs/feedback/v2-detail-indent.png`.

At the moment, the List, When and Deadline rows, the divider and Notes are all indented to where the title's text starts, past the checkbox.

- Start everything below the title at the same left edge as the checkbox, so the icons sit in the checkbox's column.
- Give them the same right inset as the title row, so the divider and Notes span the full content width.
- Keep the vertical rhythm. Re-check the label column width and the "today" relative label so nothing crowds.
- Cover the multi-select and "no task" states, and the new-task draft.
- Update the spec and the prototype source, then commit, rebuild Release and report back.

## 7. A flicker while dragging a task across sidebar lists

The user's words: "drag a task and hold it over one list, then another list, there is flicker there. can you try doing that and fixing it"

**Reproduce:** drag a task row into the sidebar, hold it over list A, then move it onto list B without dropping. Something flickers as the target changes.

**Likely suspects:**
- list A's drop highlight clearing a frame before list B's appears, or both drawing at once;
- the "Move to <list>" badge on the dragged copy being torn down and rebuilt, or its width snapping;
- the copy's chips or opacity resetting;
- the gap in the task list (the rows parting) collapsing and reopening as the pointer leaves the task list;
- the sidebar's hover state fighting the drop highlight.

**Find it frame by frame,** as in item 5: record at 60–120 fps on the scratch instance and step through the frames.
- Also test moving quickly over several lists, moving back into the task list, and hovering Today or the archive group (where a drop isn't allowed).
- The transition from one target to the next should be continuous: either a crossfade or an instant swap, whichever the prototype does. Fix the prototype too if it has the same problem.

When it's fixed: commit, rebuild Release and report back.
