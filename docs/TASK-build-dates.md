# Task: build the dates design (§24)

The user approved the dates design.
- **Spec:** `design/INTERACTIONS-v2.md` §24.
- **Prototype:** `design/prototype-v2/`.
- **Canvas:** https://claude.ai/artifact/2wUF9Dz2JEt8Xp2pBDahy2.

The Design views agent is finalizing §24 right now. Start once its "§24 final" commit lands (check `git log -- design/INTERACTIONS-v2.md`), or start now from these picks and re-read the spec when it does. As always, the prototype wins over the spec.

## The user's picks

- **Placement:** the quiet When is plain grey text after the title, in the order title, notes hint, When. Only the Deadline is a badge, at the right.
- **Wording:**
  - Deadlines read "Nd left" from 1 to 14 days, "Due today" on the day and "Nd ago" when overdue, counted in days.
  - Beyond 14 days, show the date ("Nov 15", with the year when it isn't this year).
  - The When reads "Today", "Tomorrow" and "in Nd" up to 14 days, then the date.
  - Tooltips and the detail pane use full words ("13 days left", "2 days overdue").
- **Checkbox rings:**
  - red when overdue;
  - amber when due today;
  - blue when the When is today, in lists other than Today (Today shows the deadline rings only);
  - when blue meets a deadline ring, a double ring: the deadline's ring outside, a thin blue ring inside.
  - Completed and Trash show no cues, and ticking a task clears them.
  - The detail pane's checkbox shows the same cue, and VoiceOver reads it out.
- **Everything else in §24:** the date popover changes, tooltips, the narrow-width rules (the When drops before the title goes under 120pt), and the CLI's date wording if it shares the formatter.
- **Model:** no changes.

## Rules (as before)

- Use a scratch Tasks Dev and `wrangler dev` only.
- Commit per path with the co-author line, never push. Worktree subagents are fine.
- Run the §9 benchmarks.
- Check the ring states and wording in dark and light, and at day boundaries (midnight, and tomorrow becoming today).
- Make a Release build and report back.
