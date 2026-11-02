# Task: build Delete List, direction A (INTERACTIONS-v2 §28)

**The user picked direction A (2026-11-01).** The spec is `design/INTERACTIONS-v2.md` §28, currently marked
proposed: mark it final and fold it into the sections it replaces, which §28 lists. The prototype is `Del.dc.html`
and `del.css` in `design/prototype-v2/`. The canvas is https://claude.ai/artifact/JEqsvymjkNwNHkfDGbqzQw. Where the
spec and the prototype disagree, the prototype wins.

**Wording:** keep the design's split. Lists say **Restore**; tasks keep **Put Back**. The user didn't pick one verb.
Keep the strings in one place each, so unifying them later is a one-line change.

## The rule (decided; don't relitigate)
- A list's existing `archivedAt` op is the deletion. There are no new ops, no cascade, and **no server change**.
- **A task in a deleted list counts as deleted** everywhere that decides what's live: Today, Upcoming, Undated,
  Completed, counts, `find`, search, Move to, drag targets and type-select.
- Restoring the list brings everything back exactly as it was. A task that was deleted on its own stays deleted,
  and shows on its own in Trash on its own day.
- A single task can be put back out of a deleted list. It goes through the "Put back in" menu, per §28.

## Where it changes (all in step)
1. **TasksCore:** the projection and queries, where "live" means not deleted and its list not deleted. Add tests,
   including the case of a task deleted before its list.
2. **The app:**
   - Trash shows a deleted list as one row on the day it was deleted. It expands like a heading, and Return opens
     it read-only with a Restore banner.
   - Remove the Archive group, the banner, Unarchive and the archived row state.
   - Sidebar ⌘⌫ becomes Delete List, with the notice "Deleted School", Undo, and the next list below opening.
   - Update the menus.
3. **The CLI:**
   - `tasks list delete` and `tasks list restore`, with `archive` and `unarchive` kept as hidden aliases.
   - `deleteList` and `restoreList` in the API, with `archiveList` and `unarchiveList` as hidden aliases.
   - `find` and every read follow the rule.
   - Regenerate the `tasks.d.ts` golden. Update `docs/AGENTS.md` and `tasks help`.
4. **`remote/`:** the TypeScript port must match.
   - Regenerate the parity goldens (`pnpm parity`) and the CLI scenarios. Add scenarios for deleting and restoring
     a list.
   - All parity checks must pass, and `remote/tasks.d.ts` must equal the new golden.
   - **Don't deploy.** Report the redeploy command; the coordinator asks the user first.
5. The spec, `docs/SPEC.md` §2 (where it says nothing is read-only), and `docs/SDK-PLAN.md` where they mention
   archive.

## Rules
- Build Release into `app/.build/DerivedData`. Run all tests: TasksCore, the CLI, TasksTests, and `remote/`'s Node
  and Worker suites.
- Drive the Debug app against a scratch data folder with sync off, and screenshot Trash with a deleted list,
  collapsed, expanded and opened. Use in-app snapshots only, never `screencapture` of the whole screen.
- Per-path commits only (`git commit -m … -- <paths>`), ending with `Co-Authored-By: Claude Opus 5.5
  <noreply@anthropic.com>`. Never `git add -A`. Never push.
- Don't touch the installed app, its data, the live servers, or Rex. The coordinator installs and deploys.
- Compact yourself between steps if context passes about 45%.

## Report
In a few lines: what was built, the test results, departures from the canvas, and the commit hashes.
