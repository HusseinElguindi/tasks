# Task: design "Delete List", with a deleted list living in Trash (replacing Archive)

## The user's decision (2026-11-01)
Having both "deleted" and "archived" is two concepts for one thing. Archiving a list should take its tasks with it.
The user chose:

- **The mechanics (option 2):** a list's existing `archivedAt` op stays exactly as it is, with no new ops, no
  cascade, and no server change. Everywhere that decides what's live treats **a task in a deleted (archived) list as
  deleted**: Today, Upcoming, Undated, Completed, `find`, counts, search, Move to, and drag targets. Restoring the
  list brings everything back exactly as it was. Tasks that were deleted on their own before the list was deleted
  stay deleted.
- **What the user sees (option 3):** there is no Archive any more. The action is **Delete List** (⌘⌫ in the
  sidebar, and the menu). The deleted list, with its tasks, lives in **Trash**. Restoring it puts it back in its old
  place in Lists.

## Scope
**This is design only.** Start from `design/prototype-v2/` and `design/INTERACTIONS-v2.md`:
- §12, the Archive group, the archive view and banner, Unarchive (lines ~838–867, 943, 1010, 1182);
- §22, Trash and the views (~1213–1243);
- §14, notices and undo labels (~647, 665).

The current Trash shows deleted tasks from active lists, newest deleted first.

## Design
Make two or three directions for how Trash holds a deleted list, side by side, in dark and light. For example:
- a list row among the tasks: tile, name and "12 tasks", collapsed, opening or expanding to show its tasks;
- a "Lists" section at the top of Trash;
- something better.

Settle each of these:
- **Ordering:** a deleted list next to deleted tasks, newest deleted first, or grouped.
- **Opening a deleted list:** a read-only pane, or editable as archived lists are today (SPEC §2 says nothing is
  read-only). It needs a banner with **Restore** in place of Unarchive.
- **Restoring:** the whole list. Can a single task be restored out of a deleted list? Where does it go?
- **A task deleted on its own** whose list is later deleted: does it show under the list, or alone?
- **What leaves the sidebar:** the Archive group, its label and chevron, the archived row state, and §27 notes.
- **The sidebar ⌘⌫:** "Delete List" wording, no confirmation, and the notice "Deleted School", with Undo.
- **Menus and keys:** everything that said Archive or Unarchive.
- **The CLI and API naming,** to note for the build only: `tasks list archive` and `archiveList` become
  `list delete` and `deleteList`. Keep the old names as aliases? Recommend one.

## Output
- A canvas (Claude Design, as earlier design tasks did) with the directions.
- A proposed section in `design/INTERACTIONS-v2.md`, marked proposed, replacing the Archive parts.
- Per-path commits only (`git commit -m … -- <paths>`), ending with `Co-Authored-By: Claude Opus 5.5
  <noreply@anthropic.com>`. Never `git add -A`. Never push.

## Don't
- Don't touch app code, the installed app, its data, the live servers, or Rex.

## Report
- The canvas link.
- One line per direction.
- Your recommendation.
