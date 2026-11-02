# Task: a setting for the active-pane colour

**The user (2026-11-01):** "can you make it so that the active tab is that highlighted color even if there is just
one tab. i asked to remove it before. maybe make it a setting. show active tab or something with a few options."

"Tab" here means **pane**. Earlier, v2 feedback item 3 (`docs/TASK-v2-feedback.md` §3) made the active-pane colour
appear only when two or more panes are open: the list pane showed the neutral surface when the detail pane was
closed. The user now wants that colour available with one pane too, as a setting.

## Build
- **A setting in Settings:** a "Highlight active pane" row (pick a better name if Rex or Pane vocabulary has one),
  with three options, the first being the default:
  1. **Always:** the focused pane shows its active colour even when it's the only pane. This is the user's wish now.
  2. **With two panes:** today's behaviour (item 3).
  3. **Never:** neutral everywhere. The focus still has to be readable some other way. If nothing else shows focus,
     say so in your report.
- Store it in UserDefaults, local to the Mac like the other appearance settings, never synced. It takes effect
  live, with no restart.
- Keep item 3's transition: the change follows the detail pane's open and close animation. With **Always**, no
  change is needed when the detail pane opens or closes, apart from the inactive pane dimming as now.
- Match the existing Settings rows exactly. If there's a segmented control or popup convention, use it.

## Rules
- Update `design/INTERACTIONS-v2.md`, where item 3's rule lives and in Settings, citing "the user, 2026-11-01".
- Build Release into `app/.build/DerivedData` and run all tests.
- Take in-app snapshots only (never `screencapture` of the whole screen): one pane with Always, in dark and light,
  and the Settings row.
- Per-path commits only (`git commit -m … -- <paths>`), ending with `Co-Authored-By: Claude Opus 5.5
  <noreply@anthropic.com>`. Never `git add -A`. Never push.
- Don't touch the installed app, its data, the live servers, or Rex. The coordinator installs.

## Report
In a few lines, with the commit hashes and the snapshot paths.
