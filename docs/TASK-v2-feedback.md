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

Check this against Rex: does a lone pane in a Rex tab show the focus colour? Note what you find; the user's rule wins either way. Update the spec and the prototype source.
