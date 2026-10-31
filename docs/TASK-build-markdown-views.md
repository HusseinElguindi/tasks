# Task: build Markdown notes, then the four views

The user approved both designs. Build them in this order, one after the other, each with its own Release build and report.

## 1. Markdown notes

- **The spec:** `design/MARKDOWN.md` (final, commit 7ccfb08).
- **The reference implementation:** the prototype in `design/prototype-markdown/`, canvas https://claude.ai/artifact/CmypwyraQx28AYcHSfb5c5. The prototype wins over the spec, as before.
- **The user's picks:**
  - live editing: only the marks near the caret show, faintly;
  - square checklist boxes that toggle `[ ]`/`[x]` in the text;
  - a row hint right after the title: the notes glyph, or a checklist count like "2/5";
  - links open on a plain click;
  - no Add Link shortcut, so ⌘K completes everywhere.
- **Merge the spec:** it replaces `INTERACTIONS-v2.md` §7 Notes and the notes display line in `docs/SPEC.md` §2, and covers §11's "Block Markdown rendering". Update those docs.
- **The approach in the spec:** one NSTextView (TextKit 1) whose storage is the Markdown, restyled one line at a time, with the row summary computed when notes change.
  - Meet the `docs/SPEC.md` §9 budgets, and add a benchmark if one is missing.
  - Handle VoiceOver, so it reads the rendered text rather than the hidden marks (spec §11).

## 2. Completed, Upcoming, Undated and Trash

- **The spec:** `design/INTERACTIONS-v2.md` §22 (final, commit 4a4159c), plus the §12 sidebar and §17 keys.
- **The reference:** the prototype in `design/prototype-v2/`, canvas https://claude.ai/artifact/EnWEe86TBSG8voqqwbf7uf.
- **The user's picks:**
  - the sidebar is split: Upcoming and Undated under Today, Completed and Trash after the lists, no counts;
  - Upcoming always shows the next seven days, then months;
  - a task with both dates shows once, on the earlier date;
  - drag-to-reschedule and per-day adding in Upcoming;
  - Undated is grouped by list;
  - Completed is a logbook;
  - Trash is read-only with Put Back, and there is no delete-forever;
  - dropping on Completed or Trash in the sidebar completes or deletes;
  - ⌘1–9 open the first nine sidebar rows;
  - no new model fields.
- **Fix** the out-of-date prototype line references in `app/README.md` and `app/NOTES-v2.md`.

## Rules (as before)

- Scratch "Tasks Dev" plus `wrangler dev` only.
- Never touch the installed app, its data, the live server or Rex.
- Verify frame by frame where motion matters. If the screen is locked, use in-app renders.
- Commit per path with the co-author line, never `git add -A`, never push.
- Unrelated parts can go to worktree subagents.
- The SDK agent recently changed `TasksCore` (Op.actor/batch, Store.attribution, Persistence.readEntries, a public LoadedState.init, and a TasksCLI target). Check `git log` before you touch `TasksCore`.
- Builds are signed with the "Tasks Local Signing" identity.
