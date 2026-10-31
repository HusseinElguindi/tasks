# Feedback on the installed v2 build

The user is trying v2 now. Fix each item, verify it on your scratch instance, commit, rebuild Release, and report back. More items may be appended to this file.

## 1. "New Task" shows twice

The user's words: "when you make a new task then hover over empty area, there are some states that show new task twice. i don't like that"

Screenshot: `docs/feedback/v2-double-new-task.png`.
- In the list "Hi there", ⌘N or + created the draft. The detail pane is open, with the caret in "New Task".
- The list shows two "New Task" rows: the draft, which is selected, and a second one under it. The second one appears to be the empty-area hover ghost, the add affordance.

While a draft exists, there must only ever be one "New Task" row.
- Suppress the empty-area ghost while a draft is open, or make hovering the empty area point at the existing draft.
- Check every state that leads here: ⌘N, the + button, clicking empty space, Today, an empty list, and a draft that was abandoned.
- Check the prototype has the same bug. If it does, note it, and fix the prototype too if that's cheap.

## 2. Clicking empty space creates a task, and that's annoying

The user's words: "pressing in an empty area to make a new task is getting a little annoying"

The coordinator's call, which the user can overrule:
- **A single click on empty list space no longer creates a task.** It does what it does in Rex and Finder: it clears the selection. While a draft is open, it ends the draft by the existing rules (save if it has a title, drop if it's empty). It never starts a new one.
- **Remove the hover "New Task" ghost row entirely.** With nothing created on a click, it has no reason to exist.
- **Double-click on empty list space creates a task**, exactly as ⌘N would.
- **⌘N and the + button are unchanged.**

Update `design/INTERACTIONS-v2.md` (§6 and anywhere else that mentions the empty-space click or the ghost row) and the prototype source to match. Commit, rebuild Release and report back.

## 3. Show the active-pane colour only when there are two or more panes

The user's words: "i want the active pane color to only appear when there is more than 1 pane."

- **With one pane** (the detail pane closed): the list pane shows no focused or active treatment. Use the plain neutral surface and edge, the same in every key-focus state.
- **With two panes:** the focused pane keeps its current colour, and the other one dims as now.
- **The change between the two** follows the detail pane's open and close transition rather than snapping at the end.

Do not open or drive Rex to check this; the user's rule wins. Update the spec and the prototype source.

## 4. Panes can be resized by dragging (after the compact)

The user's words: "i want these panes to be draggable in size"

- **What to resize:** drag the gap between the list pane and the detail pane, and between the sidebar and the list pane, to resize them.
- **Behaviour:** use Rex's divider behaviour as described in `design/REX-REFERENCE.md`. If it doesn't cover dividers, do the simplest thing that feels native:
  - a resize cursor over the gap, with no visible handle;
  - sensible minimum widths;
  - double-click the gap to reset to the default width;
  - widths remembered across launches, and the detail pane reopening at its last width.
- **The detail pane's open and close transition must keep working at any width.**
- Update the spec and the prototype source.

## 5. A brief flicker when renaming and when a reorder settles

The user's words: "there's a flicker that happens very quickly near when double clicking and renaming and also right after reordering (when it's settling)"

- **Double-click to rename.** The flicker appears around the moment the in-place field takes over. Check:
  - a sidebar list;
  - a task title, if double-click renames there;
  - committing the rename (Return, or a click away), as well as entering it.
  - Likely causes:
    - the label and the field both drawing for a frame, or neither;
    - a layer re-render or implicit `CALayer` animation;
    - the row being rebuilt when the store publishes the rename.
- **A reorder settling.** The flicker comes just after you drop, as the row settles into place. That covers task rows and sidebar lists, within a list and dropped onto another list.
  - Likely causes:
    - the drag snapshot being removed a frame before (or after) the real row reappears;
    - the list reloading from the store's op after the settle animation, and replacing or re-laying out rows;
    - the 35% source-row opacity snapping back.
- **Find it frame by frame.** Record at 60 fps (or capture each frame from a CADisplayLink callback inside the scratch app) and step through the frames. Don't guess. Fix the cause so every frame in the hand-off is continuous, check the frames again after the fix, then commit, rebuild Release and report back.

## 6. The detail pane's fields start at the left edge and fill the width

The user's words: "I would like for the list, when, deadline, notes, etc to also be left aligned and take up the whole width, just like the checkbox and title row". Screenshot: `docs/feedback/v2-detail-indent.png`.

At the moment, the List, When and Deadline rows, the divider and Notes are all indented to where the title's text starts, past the checkbox.

- Start everything below the title at the same left edge as the checkbox, so the icons sit in the checkbox's column.
- Give them the same right inset as the title row, so the divider and Notes span the full content width.
- Keep the vertical rhythm. Re-check the label column width and the "today" relative label so nothing crowds.
- Cover the multi-select and "no task" states, and the new-task draft.
- Update the spec and the prototype source, then commit, rebuild Release and report back.

## 7. A flicker while dragging a task across sidebar lists

The user's words: "drag a task and hold it over one list, then another list, there is flicker there. can you try doing that and fixing it"

**Reproduce:** drag a task row into the sidebar, hold it over list A, then move it onto list B without dropping. Something flickers as the target changes.

**Likely suspects:**
- list A's drop highlight clearing a frame before list B's appears, or both drawing at once;
- the "Move to <list>" badge on the dragged copy being torn down and rebuilt, or its width snapping;
- the copy's chips or opacity resetting;
- the gap in the task list (the rows parting) collapsing and reopening as the pointer leaves the task list;
- the sidebar's hover state fighting the drop highlight.

**Find it frame by frame,** as in item 5: record at 60–120 fps on the scratch instance and step through the frames.
- Also test moving quickly over several lists, moving back into the task list, and hovering Today or the archive group (where a drop isn't allowed).
- The transition from one target to the next should be continuous: either a crossfade or an instant swap, whichever the prototype does. Fix the prototype too if it has the same problem.

When it's fixed: commit, rebuild Release and report back.

## 8. A setting for how editing a task works (after item 7)

The user's words: "I want a setting that makes it so i can control how task editing works. one is to always open a task in detail view. I think one option should be the one. and then the other is to rename tasks titles inline as they are now."

Add a setting in Settings (⌘,) with two options:
- **"Open in detail pane"**, the default.
  - Double-clicking a task, or pressing Return on a selected one, opens it in the detail pane with the caret in the title. Nothing edits inline in the list.
  - If the detail pane is already open on that task, it focuses the title.
- **"Rename in the list"** is today's behaviour: double-click or Return renames the title in place in the row.

**Notes:**
- The detail pane is still reachable with the › button and its shortcut in both modes, and adding a task (⌘N, double-click on empty space) is unchanged.
- Lists in the sidebar keep renaming in place either way. The setting is only about tasks.
- Store the setting with the other settings (UserDefaults), not in the sync log.
- Put the control where Rex would; use the simplest native look (a radio group or a pop-up) under a short label such as "Edit tasks".
- Update the spec with the setting and both behaviours, and the prototype too if that's cheap. Then commit, rebuild Release and report back.

The default was the coordinator's reading of "I think one option should be the one"; the user can flip it.

## 9. Switching appearance breaks things, including the window controls

The user's words: "i think there's a problem when switching between dark and light modes and system. the close and minimize and expand controls get all messed up too. check it out."

**Reproduce:**
- Switch the app's appearance setting between Light, Dark and System, in every order, while the window is open.
- Do it with one pane and with two, with the sidebar collapsed, and in full screen.
- Find everything that doesn't update, or updates wrongly: layers with baked-in `CGColor`s, cached row renders, the traffic lights (position, appearance, hover glyphs), the popover, tooltips and notices.

The window controls get "all messed up". Find out how: whether they lose their custom position, are drawn twice, show the wrong appearance, or lose their hover state. Fix it at the cause.

**Don't change the system-wide appearance setting**, because it affects the user's screen. Simulate "System" following in the scratch app. If a real system flip is truly needed, ask the coordinator.

## 10. The glass setting makes no visible difference

The user's words: "I also dont see a difference with and without glass. investigate these"

- Find out what the glass setting is meant to do, and what it actually changes in code.
- Compare captures with it on and off, in both appearances, over a busy desktop or wallpaper behind the window.
- If it's wired to nothing, or the effect is hidden under an opaque surface, either make it show the intended translucency or report that it should be removed, and why. Then check how it looks.

For both items: if item 10 is independent of item 9, hand it to a worktree subagent. Commit, make one Release build and report back.

## 11. Stop the Keychain prompt on every new build

The user keeps getting "Tasks wants to use your confidential information stored in 'Tasks sync token' in your keychain" after every install.

**Cause:** builds are signed ad hoc, so each build has a new code signature. The Keychain ACL, including "Always Allow", is tied to that signature.

**Fix:** sign every build with a stable local identity.
1. Add `app/Scripts/make-signing-identity.sh`. It creates a self-signed code-signing certificate named "Tasks Local Signing" with openssl (codeSigning extended key usage, long validity), then imports the key and certificate into the login keychain with `security import ... -T /usr/bin/codesign`.
   - It must be idempotent: do nothing if the identity already exists.
   - Avoid anything that needs the user's password. If marking the certificate as trusted turns out to be required, make that a separate, optional step and say so.
   - Never export the private key anywhere else, and never commit it.
2. In `app/project.yml`, sign with "Tasks Local Signing" when it exists, otherwise fall back to ad hoc. A build setting or an xcconfig chosen by the script is fine; keep it simple.
3. Run the script on this Mac. Build Release, then check:
   - `codesign -dr - Tasks.app` shows a designated requirement tied to the certificate, not a cdhash;
   - two consecutive builds have the same designated requirement.
4. **Don't touch the "Tasks sync token" Keychain item.** The user will click Always Allow once on the next build; after that it should stick.

Document it in `app/README.md`. Commit, build Release and report back.

## 12. Branding: the app mark and "Tasks" above Today in the sidebar

The user's words: "we need some branding. like the small app logo and Tasks before the 'Today' in the sidebar, like in the claude design for the logo"

**Reference:** the "Sidebar header" board in the logo canvas (https://claude.ai/artifact/ScTE29QmxCwxJxfRdnrNPd), with its source at `design/logo/Sheet.dc.html` around line 168.
- The sidebar gets a 34pt header row under the traffic-light row, above Today: the bare 04 · Log mark at 18pt, an 8pt gap, then "Tasks" in 13pt semibold ink, inset 10pt like the rows.
- Today follows 6pt below it.

**The mark:** use the final mark from `design/logo/final/svg/`. Use `mark-dark-small.svg` for the small cut at 18pt if it reads better than `mark-dark.svg`; compare them on a render.
- Draw it as a vector or a template-free image so it stays crisp at 1× and 2×.
- Check it in the Light theme as well. The app icon is dark only, but this mark sits on the light sidebar, so use a light-appearance variant if the canvas has one, or make sure the dark mark reads well there.

**Behaviour:**
- It isn't a button. No hover state; it's purely a label.
- When the sidebar collapses, it goes with the sidebar and doesn't move into the title bar.
- The window-controls line (spec §4) and the alignment rules stay intact.

Update the spec and the prototype source, then commit, rebuild Release and report back.

## 13. ⌘Z doesn't work inside the notes

The user's words: "why does cmd+z not work inside the notes?" They're running the four-views build (6580d4d) with Markdown notes.

- **Expected:** while the caret is in the notes editor, ⌘Z and ⇧⌘Z undo and redo text edits, one typing run at a time, just like any NSTextView. That includes the Markdown edits (list continuation, ⌘B and ⌘I, paste, and checkbox toggles made while editing). When the editor commits ("Edit Notes" on Esc or ⌘Return, or a click away), the app's undo stack gets one step for the whole session, as the spec says.
- **Likely causes to check:**
  - the app's Edit ▸ Undo menu item or a key handler sending ⌘Z to the Store's UndoManager instead of the first responder's;
  - `allowsUndo` being off;
  - the editor's `undoManager` returning the window's or the Store's manager;
  - the Markdown restyling clearing or breaking the text view's undo groups;
  - SwiftUI's `.onKeyPress` or a commands override swallowing ⌘Z.
- **Check the other text fields too:** the task title in the detail pane, renaming a row in place, renaming a list in place, and the date field. ⌘Z there was never checked. All of them should undo text first; outside a text field, ⌘Z keeps undoing app actions.
- **Verify** with real key events on the scratch instance if the screen is unlocked. Otherwise use the debug steps, and say which.

Commit, rebuild Release and report back.

## 14. The CLI nudges the app to sync at once (after the headings build)

The user approved this. Today the app sees a CLI change only at its next sync: up to 30 s later, or when the app becomes active.

- **The CLI:** after any command that pushed ops to the server (including `tasks run` and `tasks mcp` writes), it posts a Darwin notification with `notify_post("com.elguindi.Tasks.changed")`. It posts after the push succeeds, not before.
- **The app:**
  - It registers for that name (`notify_register_dispatch` on the main queue) and triggers its normal sync when the notification arrives.
  - The trigger is debounced, so a burst of CLI commands means one sync, not ten, and it's ignored if a sync is already in flight. A follow-up sync runs after the in-flight one finishes.
  - Nothing is shown on screen. The notification carries no data; the changes still arrive through `/v1/sync`.
- **Debug and Release:** a scratch Debug app and a Debug CLI shouldn't nudge the real app. Use a different name for Debug builds, or include the data directory or server URL in it, so test runs never poke the installed app.
- **Spec and docs:** add the trigger to `docs/SPEC.md` §5 "Realtime" and to `docs/AGENTS.md`.
- **Verify:** with the scratch app open against `wrangler dev`, a CLI write appears in the app within about 1 s, not 30 s. A burst of 20 writes causes one or two syncs.

Commit, rebuild Release and report back. Install the CLI only when the coordinator says so.

## 15. Today's Completed group can be collapsed

The user's words: "allow me to collapse today's completed."

- Today's "Completed" group, the tasks completed today at the bottom, gets the same chevron collapse as a list's Completed section and the headings: the same hover reveal, a 12pt chevron, Space, the same animation, and a count when collapsed.
- Collapse state is local only, like headings, and survives a relaunch.
- Check the other views for a Completed group that should behave the same, and keep them consistent.

## 16. Long list names overlap the row at narrow widths

The user's words: "with very long list names and short widths, things start overlapping." Screenshot: `docs/feedback/v2-long-list-name-overlap.png`.

In Today's Completed group, the trailing list name ("SE 463 — Software Project Management, Requirements, and Analysis") is laid out at its full width. It runs left over the checkbox, the title and the notes hint, and past the row's leading edge.

- **The rule:** the row's leading content (checkbox, title, hint) keeps its place, and the trailing label gets whatever room is left. It truncates with the same end fade as titles, never overlapping or extending beyond the row. The title also has to give way, so decide the priority: the title gets a minimum width, then the label truncates, then the title.
- **Audit every trailing element for the same bug:** list names in Today, Completed, Upcoming and Trash; date chips; the relative date; counts in the sidebar; the header band title; long heading names; long list titles in the large title and the sidebar; and the "Put Back in ▸" menu.
- **Test** with very long names, in a window and panes at their minimum widths.

Commit, rebuild Release and report back. These two items can run in parallel in worktree subagents.

## 17. One set of semantic colour tokens (themes tabled)

The user's words: "Let's table themes. Though I think it might be good to think of the tokens/theming params (even if we have 1 theme) for consistency reasons."

Themes themselves are tabled: no picker, no theme files and no sample themes. Do the groundwork from `design/THEMES.md` (§1, §2.1–2.4 and §6) so the app has **one consistent token system with one theme, Rex**.

- **One palette.** Merge `PaneColors` and `TK.Palette` (`TasksApp.swift:34–37`) into a single palette built from the semantic tokens in THEMES.md §1, with Rex's measured values pinned, as the Default theme does.
  - Every drawing site reads a named token.
  - Use the THEMES.md names, so a later theme only has to supply base colours.
- **Remove the hard-coded colours** that THEMES.md §1.3 lists: the brand mark in `SidebarHeader.swift:59–66`, the literal hover and shadow colours in the Pane components, and anything else you find. Each becomes a named token.
- **Palette equality is about values, not light/dark** (`TK.swift:36`). A future theme switch, and today's appearance switch, must redraw rows correctly. Build the palette once per appearance change and cache it, with no per-frame cost.
- **The derivation rules (§2.4):** implement them only if cheap. Pinned values are fine for now, but structure the code so derived tokens have one obvious place to live.
- **No visual change.** The app has to render pixel-identical before and after, in Light, Dark, Classic and Glass. Check it with in-app render diffs of the main screens (Today, a list with headings, the detail pane with notes, the date popover, Upcoming, Trash) and the §9 benchmarks.
- **Mark THEMES.md** with "tabled: tokens adopted in the app; picker, files and samples deferred".

Commit, rebuild Release and report back.

**Status (Mac agent, Oct 31, stopped for a shutdown):** in progress on branch `wip/tokens` (962b9ca, not merged). One `TK.Palette` built from `TK.Theme` (Rex pinned) with the THEMES.md names, PaneColors and the unused v1 Pane components removed, brand mark and rings on tokens, value equality. The six screens render pixel-identical in all four modes; Settings is 1 level off in 3 tokens. Left: build and run the newest debug checks (`palette:derived`, `-debugThemeCheck`), the redraw-on-switch check, the §9 benchmarks, the THEMES.md "tabled" mark, notes, merge, Release build.
