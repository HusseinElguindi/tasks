# Task: fix typing a checklist item in notes

The user reported two bugs:

> When i type - [ ] in the notes, the "- " turns into a bullet automatically, so i end up with "bullet [ ", which is
> weird. also, after the "- [ ]" and i type something, it ends up reverting from the checkbox to "- [ ]text". we need
> to fix both of these.

The specs are `design/MARKDOWN.md` §4 (list prefixes are never shown as text) and §5 (checklists). The scanner is in
TasksCore; the notes view lives in the app.

## Wanted behaviour
1. **Typing `- [ ] ` reads naturally.** Today, after `- ` the line becomes a bullet, and `[`, ` ` then show as text
   after the dot. Instead, while the line's text after the bullet is a prefix of a box (`[`, `[ `, `[x`, `[ ]`), keep
   it from looking broken. Pick the cleanest of these:
   - show the raw `- [` as typed, with no bullet, until the box completes;
   - or show the bullet with the partial bracket as dim marks, not as body text.

   Whichever you pick, the moment `- [ ]` or `- [x]` is complete, it becomes the box.
2. **The box doesn't fall apart when you keep typing.** Today, typing right after `- [ ]` with no space gives literal
   `- [ ]text`. Fix it so typing straight on yields a checklist item, for example by inserting the space when `]`
   completes a box, with the caret after it. That way the stored Markdown stays `- [ ] text` and other Markdown
   readers agree. A plain paste of `- [ ]text` doesn't have to become a box. This is about typing.
3. Check the same pattern for `* `, `+ `, numbered items and nested levels, if the scanner supports them. Backspace
   from the item's start must still remove the box (§6), and undo must make sense: one ⌘Z undoes the inserted space
   together with the `]`, or skips it cleanly.

Add TasksCore tests for the scanner or edit logic, and drive the real notes field with the app's debug hooks if they
can type. Update `design/MARKDOWN.md` with the rule you chose, citing "the user, 2026-11-01".

## Rules
- Build Release into `app/.build/DerivedData` and run the tests.
- Per-path commits only (`git commit -m … -- <paths>`), ending with `Co-Authored-By: Claude Opus 5.5
  <noreply@anthropic.com>`. Never `git add -A`. Never push.
- Don't touch the installed app in ~/Applications, its data, the live server, or Rex. The coordinator installs.
- Another agent is doing colour design (design files only). Commit only your own paths.

## Report
In a few lines: the behaviour you chose, the tests, and the commit hashes.
