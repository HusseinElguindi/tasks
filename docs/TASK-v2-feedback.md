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
