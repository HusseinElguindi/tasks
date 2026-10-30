# Task: rebuild the Mac app's UI to match the v2 prototype

The user tried the v2 interactions prototype in Claude Design (https://claude.ai/artifact/QetdV1H57SC6kLXtNzJRXM, source `design/prototype-v2/`). They said: "The animations here are great and so are the details ... We should make the real thing like this."

## Inputs

- **The reference implementation** is the prototype in `design/prototype-v2/`. The real app should look, move and respond like it, 1:1. When the spec and the prototype disagree, the prototype wins; flag the disagreement in your notes.
- **The build spec** is `design/INTERACTIONS-v2.md`, finalized with the user's picks.
- **The user's picks and praise** are in `docs/TASK-interaction-decisions.md`:
  - The date picker is A, add-task is C (opens in the detail pane), drag opens a gap, and checked tasks move after 1.5 s.
  - Keep exactly the animations, the hover states, the window-controls line (traffic lights on one line with the sidebar toggle, the pane titles and each pane's top-right buttons; spec §4; there is no ••• button), and the sidebar buttons after collapse.
- **What went wrong in v1** is in `design/INTERACTIONS.md` and `app/NOTES-overnight.md`. The user found v1 "clunky".
  - Known v1 failures: hover lingered, elements overlapped, and the drag-and-drop bugs.
  - Rex's measured values are in `design/REX-REFERENCE.md`.

## Rules

- **Keep the data layer.** `TasksCore`, sync, the snapshot and the performance work stay. Rebuild the views and interactions as needed; don't patch v1's views to look like v2.
- **Performance budgets** from `docs/SPEC.md` §9 still apply, including the list switch.
- **Use AppKit where SwiftUI fights you.** That means hover tracking, custom drag, and text fields that rename in place.
  - Restore what v1's List replacement lost: ⌘A, type-to-select, Home/End/PageUp/PageDown, drag autoscroll and VoiceOver basics.
- **Verify every interaction yourself**, on a scratch "Tasks Dev" instance (`-dataDirectory`) against `wrangler dev`.
  - Use screen recordings, compared side by side with the prototype running in a headless browser, for timings and positions.
  - Never touch the installed `~/Applications/Tasks.app`, its data, the live server, or Rex.
- **Commit as you go:** per path, never `git add -A`, never push. End commit messages with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. You may use subagents.

## When you're done

Leave a fresh Release build. Write `app/NOTES-v2.md` covering what's done, what differs from the prototype and why, and what to check by hand. Then report back.

## Starting in parallel

The Design agent is still committing the final `design/INTERACTIONS-v2.md`.
- Start now from `design/prototype-v2/` and `docs/TASK-interaction-decisions.md`.
- Re-read the spec whenever `git log -- design/INTERACTIONS-v2.md` shows a new commit.
- Start your own `wrangler dev` on a free port (8792), and check that it's free first. The old Mac tab's dev server on 8791 belongs to that tab.
