# Investigation: can the Mac lose an in-progress edit?

**The user (2026-11-02):** the iOS agent found that "in-progress title/notes edits in the detail view are only saved
when editing ends or the view closes, risking data loss if the app is killed while backgrounded." Its fix was to
also commit the edit on `.inactive`. "i was wondering if something similar to this happens on mac."

**This is an investigation first. Don't change app code until the user decides.**

## Find out
For every place the Mac app holds text that isn't yet an op in the store, find when it becomes an op. Then say
which events lose it. The places to check:
- task titles: in the list (inline rename and new task) and in the detail pane;
- notes in the detail pane (`app/Tasks/Detail/NotesView.swift` and its neighbours);
- list renames in the sidebar and their title in the list pane;
- headings, and any quick-entry or overlay field (`app/Tasks/Overlay`);
- anything else you find that's debounced or "commit on end editing".

The events to check:
- Quit with ⌘Q while editing, including when the app asks to terminate (`applicationShouldTerminate` and
  `willTerminate`).
- Closing the window while editing.
- Switching to another app, without quitting.
- The Mac sleeping or logging out. Restarting the Mac.
- A crash, or a `kill -9`. Nothing can save here, but say how much is lost: everything since editing began, or
  only the last debounce window?
- Sync arriving mid-edit and changing the same task. Does the field keep the user's text, or overwrite it, and is
  anything lost?
- Also check that a committed op actually reaches the disk before exit. Read `TasksCore` `Persistence` and
  `Store`: is the write async, and is it flushed on terminate?

## How
- Read the code first, and cite file:line for each finding.
- Then confirm the risky cases with a Debug build into `app/.build/DerivedData`. Use its **own data directory**, so
  the installed app's data is never touched. Script the edits with the existing debug automation in
  `app/Tasks/Support/DebugAutomation.swift` and `DebugScript.swift` if it helps. To test a kill, `kill -9` only the
  Debug process you launched, never the installed Tasks.
- Take in-app snapshots only (never `screencapture` of the whole screen).

## Report
Give a table with one row per field and event: lost, safe, or partly lost, with the evidence. Recommend the
smallest fix for each real gap, and say whether it touches only `app/Tasks` or also TasksCore. Keep it to a few
paragraphs. Write the findings to `docs/MAC-EDIT-DURABILITY.md` and commit that file by path.

## Rules
- Per-path commits only (`git commit -m … -- <paths>`), ending with `Co-Authored-By: Claude Opus 5.5
  <noreply@anthropic.com>`. Never `git add -A`. Never push.
- Don't touch the installed app, its data, the live servers, or Rex.
- An `ios` branch is being built on another Mac and will add files under TasksCore later. Don't edit TasksCore.
