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
