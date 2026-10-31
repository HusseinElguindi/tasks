# Task: build headings, list text and the large list title

The user approved the design. The spec is `design/INTERACTIONS-v2.md` §23 (final, commit a62afa0). The reference is `design/prototype-v2/`, canvas https://claude.ai/artifact/9dQ4fC46yZLLhf61gLiELx. As always, the prototype wins over the spec.

## The user's picks

- A large 20pt list title with the list's description under it. The header band's small title fades in once the list scrolls.
- Bold 13pt headings with a hairline under them.
- A description on the list, plus an optional description under any heading. Both are Markdown, rendered with the notes editor.
- Headings never show in Today or the other views.
- Everything else in §23 is approved:
  - ⌥⌘N adds a heading, and headings always rename in place;
  - collapse with the hover + and chevron, and Space; collapse state is local only;
  - dragging a heading carries its section;
  - deleting a heading keeps its tasks;
  - where new tasks land.
- **Collapse and expand:** the user saw a bug in the prototype; §23 explains the failure and the rule. In the app, rows revealed by an expand must start at the heading and move in the same animation as everything else, never fade in where they end up. Verify it frame by frame.

## The model, in this order

1. **The server only loosens:** `kind` on `task.create`, and `notes` on `list.create` and `list.update`.
   - Add tests and a fixture, and test against `wrangler dev`.
   - **Don't deploy.** The coordinator asks the user first, and the server must be deployed before any app or CLI build that writes these fields reaches real data.
2. **TasksCore:** a heading is a task with `kind: "heading"` (the reducer is unchanged), and lists gain `notes`. Keep the §9 budgets, and run the benchmarks before and after.
3. **The app and the CLI ship together.**
   - The CLI needs the §23 CLI/SDK list: `tasks heading add`, `tasks list notes` and so on.
   - Regenerate the golden `tasks.d.ts`, and update `docs/AGENTS.md`.
   - Headings must not appear in the CLI's Today and other views either.

## Rules (as before)

- Use a scratch "Tasks Dev" and `wrangler dev` only. Never touch the installed app, its data, the live server or Rex. If the screen is locked, use in-app renders.
- Commit per path with the co-author line, never `git add -A`, never push. Worktree subagents are fine for independent parts.
- **Before reporting:** fix the out-of-date prototype line references in `app/README.md` and `app/NOTES-v2.md`. Make a Release build and report, including what you couldn't verify.
- **Don't install** the CLI to `~/.local/bin` until the server is deployed. The coordinator will do it.
