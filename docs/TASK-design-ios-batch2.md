# Design: iOS parity batch 2, five features that need a touch design

**The user (2026-11-03):** the ones that need design are designed here, on the main Mac, for their OK. Then the Ex-Mac
builds them.

**This is design only.** Don't change app code. Design matters a great deal to the user. Rex is the source of truth
for the look, the Pane design system is the vocabulary, and the Mac's `design/INTERACTIONS-v2.md` sets the rules.
Each proposal must be the Mac's rule adapted for touch, not a new idea. Where touch forces a change, say why.

## Read first
- `docs/IOS-MAC-PARITY.md`: gaps 2, 4, 6, 7 and 10, with file:line on both sides.
- `design/INTERACTIONS-v2.md` for each feature's Mac rules. `design/COLOR.md` §4 for Moments. `docs/SPEC.md` §8 for
  the iOS notes and the deliberate differences.
- The iOS code, `ios/Tasks/`: what exists today (the date sheet, notices, the long-press menus, the floating +, the
  sheet).
- What's being built now on the Ex-Mac, so you don't clash with it: `docs/TASK-ios-reorder-and-selection.md`,
  `docs/TASK-ios-headings.md` and `docs/TASK-ios-parity-batch1.md`.

## The five
1. **Undo and redo on touch** (gap 2): shake, three-finger undo and redo, a hardware keyboard's ⌘Z and ⇧⌘Z, wired to
   the Store's undo steps. Each one is confirmed with a notice, as the Mac does (`WindowActions.swift:82`). Should
   there also be a visible Undo affordance, and where?
2. **Typed dates** (gap 4): a field in the date sheet that takes "fri", "3d" or "nov 9" through the core's
   `DatePhrase.match`. It moves the highlighted day as you type, and Return sets it. Decide:
   - where it sits;
   - the keyboard type;
   - how a no-match looks;
   - the hints;
   - how it fits with the quick picks.
3. **Multi-select** (gap 6): Select in the list's menu gives an edit mode with two-finger swipe selection and a bottom
   bar for Complete, When, Move and Delete. Decide:
   - how you enter and leave it;
   - the selected look (the Mac's joined blocks);
   - whether swipe and drag work in it;
   - what each action does with a mixed selection (the Mac's rules).
4. **Trash** (gap 7):
   - "Put back in ▸" in a task's menu and its sheet;
   - opening a deleted list as a pushed, read-only list screen with a Restore banner, following the Mac's §28
     detail-pane version.
5. **Moments and Reduce Motion** (gap 10): the completion spark and warm flash, and the lit sun or sunrise when Today
   is all done (COLOR.md §4), at the phone's scale. Add haptics where they fit. Every animation is gated on Reduce
   Motion: say exactly what each one becomes.

## Output
Write `design/IOS-BATCH2.md`. For each feature:
- what it does;
- the options, if there are real ones, with your recommendation first;
- the exact rules, numbers and wording, so that a builder can work from it without guessing;
- what it reuses from the core and the Mac;
- a rough size.

Keep it tight. The user reads it and picks. Commit it by path. Report in a few lines: each feature's recommendation,
and any question only the user can answer.

**Optional:** if a picture would settle a choice, make an HTML mock-up in your scratchpad, at phone size, light and
dark, with the Rex tokens from TasksTheme. Give the coordinator its paths. Don't publish anything.

## Rules
- Per-path commits only (`git commit -m … -- <paths>`), ending with `Co-Authored-By: Claude Opus 5.5
  <noreply@anthropic.com>`. Never `git add -A`. Never push.
- Don't touch the installed app, its data, the live servers or Rex. Don't edit `ios/` or `app/`.
