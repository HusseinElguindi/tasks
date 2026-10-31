# Check and merge: no open-task counts on list rows

The user decided that sidebar **list** rows show no open-task count. **Today keeps its count.** Upcoming, Undated,
Completed and Trash already had none. While ⌘ is held, the ⌘1–⌘9 hints still show in the count's slot on every row,
lists included.

Another session already made the change, but left it uncommitted. It's in the working tree on `main`:
`git diff -- app/Tasks/Sidebar/SidebarModel.swift`. Your job is to check it, finish it, and commit it.

## Check
1. Review the diff for correctness:
   - Today's count is unchanged.
   - Hints still appear on list rows while ⌘ is held.
   - Archived rows are still empty.
   - Look for anything left dangling, such as an unused `openTaskCount`, a `countText` caller, or count-only layout
     like the title's fade width before the count, or the drop-target count colour. Remove dead code where it's
     clearly only for this.
2. Build the Release app into `app/.build/DerivedData`, the usual way. Run the TasksCore tests, and any app tests
   that exist. Fix anything that fails.

## Finish
3. Update `design/INTERACTIONS-v2.md` so the spec matches. Look around lines 21, 182, 785–794, 885, 1138 and 1193.
   "Today and the lists keep theirs" becomes Today only, and the list-row states lose their count. The rule's
   source is "the user, 2026-10-31".
4. Check whether `design/prototype-v2/` shows list counts. If it does, a small matching change there is fine. If the
   change isn't small, note it in your report instead.

## Commit
5. Make per-path commits only: `git commit -m "…" -- <paths>`.
   - Never `git add -A` or `-a`. Never push.
   - End each message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
   - Match the style of recent messages, such as "app: …" or "design: …".

## Don't
- Don't touch the installed app in ~/Applications, its data, the live server, or Rex. The coordinator installs.

## Report
Report in a few lines: what you changed beyond the diff, the build and test results, and the commit hashes.
