# v2 notes (macOS app)

The Mac UI, rebuilt to match the interactions v2 prototype (`docs/TASK-mac-v2.md`, `design/INTERACTIONS-v2.md`,
`design/prototype-v2/`). Everything below was checked on a scratch "Tasks Dev" instance with its own data folder,
offline or syncing with my own `wrangler dev` on 127.0.0.1:8792 (Rex tab "mac-v2: wrangler dev :8792"). The installed
app, its data, the live server and Rex were never touched, and the Release build was built but never launched (it
would open the real data folder and Keychain item).

## Install the new build

The Release build of the last commit is `app/.build/DerivedData/Build/Products/Release/Tasks.app` (ad-hoc signed,
`com.elguindi.Tasks`, same data folder and settings as the installed app; nothing migrates).

1. Quit Tasks (⌘Q) so it writes everything down.
2. `rm -rf ~/Applications/Tasks.app && cp -R app/.build/DerivedData/Build/Products/Release/Tasks.app ~/Applications/`
3. Open it. macOS may ask whether Tasks may use the `com.elguindi.Tasks.sync` Keychain item: Always Allow.

## What's done

The data layer is unchanged (`TasksCore`, sync, the snapshot, the indexes). Two small additions: the Store's actions
take an optional undo name and report whether they did anything, and `createTask`/`createList` accept an id (a new
task keeps the id it was shown with as a draft). `TasksCore` gained `DatePhrase` and `DateLabel` (the prototype's
typed dates and chip texts; 31 tests). The views were rebuilt, not patched:

| Piece | How |
|---|---|
| Tokens (`Theme/TK.swift`) | The prototype's colors (dark and light), metrics, timers and motion, as SwiftUI animations and as Core Animation curves and springs (`.smooth`/`.snappy` converted to CA springs). |
| Task list (`TaskList/`) | AppKit. One recycled view per visible row, placed from a layout ported from the prototype's `layout()`; rows move on the `layout` spring (additive, so interrupted moves compose), enter with a 180 ms fade and leave with 150 ms (into the Completed row when just completed). One hover tracker for the list; selection on mouse-down; its own drag (rows part for the gap, autoscroll, compact tag over the sidebar, Esc cancels); rename in place; Today's labels, the Completed row, the ghost row, empty states, the archive banner; ⌘A, type-to-select, Home/End/Page Up/Down; VoiceOver rows with their checkbox and ›. |
| Sidebar (`Sidebar/`) | AppKit, the same approach: hover, current capsule, renames and new lists in place, list drag, drop targets for task drags, held-⌘ hints, the Archive group. |
| Detail pane (`Detail/`) | SwiftUI with AppKit text: the new-task draft (§6) with the dimmed rows, the title, the rows, notes that edit in place in the same font. v1's open/close transition is kept as it was. |
| Overlays (`Overlay/`) | The date popover (calendar, field, quick picks), notices, tooltips, the drag copy. |
| Menus | Native NSMenus for every context menu and ⇧⌘M; the menu bar per §17. |
| Undo | Every change is one named step ("Undo Delete", "Redo Move") that also restores the view and selection, with the "Undo …" notice. |

## How it was verified

- **Against the prototype, side by side.** The prototype runs in headless Chrome (the cached Playwright Chromium,
  driven over the DevTools protocol with no packages) at 1180×720, 2×; the app renders the same seed
  (`-demoData YES` is the prototype's seed). Pixel diffs and offset searches per element: rows, chips, checkboxes,
  labels, the Completed row, the ghost row, the archive banner, the collapsed-sidebar header and the whole sidebar
  match to the pixel except text antialiasing (Chrome vs Core Text); text baselines were tuned to land on Chrome's
  (half a point). Light theme too. The detail pane and the popover were checked the same way by the agents that built
  them (within 0.05pt and 0.5pt).
- **Live, with real input.** HID clicks, drags and keys on the scratch window (a tool that refuses anything but the
  scratch app), screenshots after each step: click/⌘/⇧ selection and ⇧↓ across a group label, Space and the 1.5 s
  settle into Completed (selection stays), drag reorder with the gap, drag to a sidebar list (drop look, compact tag,
  "Moved to …" notice), Esc cancelling a drag, autoscroll in a 2,000-task list, rename by double-click, ⌘⌫ with the
  notice and ⌘Z restoring task and selection, the native context menu and ⇧⌘M (first other list highlighted),
  tooltips, ⌘N in a list and in Today (the group label appears, When = today), typing into the draft (the row
  follows), Return to the notes, Esc back to the list, an untitled draft dropped by Esc or by pressing another row,
  the date popover from a row chip ("fri" → Fri, Nov 6, Return sets it), sidebar hover, switching, ⇧⌘N, held-⌘
  hints, ⌘⌫ archiving, the narrow window's drill-in.
- **Timing, from 60 fps screen recordings** (per-frame pixel samples): a row's › hover-in reaches ~88% on the first
  frame and is gone ~67 ms after the pointer leaves (Rex: ~86%, ~85 ms); the check fill and the 1.5 s hold before
  the row slides out; the notice enters on its 220 ms curve, holds 5.0 s and leaves in ~150 ms; the list narrows
  smoothly with the detail pane's spring (no jump, though the list is AppKit inside SwiftUI); the sidebar hides on its
  decelerating 300 ms curve.
- **Performance (SPEC §9).** `app/Scripts/switch-bench.sh` (optimized build, 2,000-task list): every list switch
  reaches its first rows in 4.4–10.5 ms (v1: 13–40 ms), so the guard now fails above one frame. In the 2,000-task
  list a selection change renders in 0.1–0.6 ms and a check in ~1–3 ms (`-debugRenderTimes`). `swift test`: 132 tests,
  0 failures (1 skipped, the live-server test). `Scripts/e2e.sh phase1` against :8792: converged.

## Where it differs from the prototype, and why

- **List colors** come from the list's id (DIRECTIONS decision 3, as the spec says), not the prototype's hand-out
  order, so tiles are colored differently from the prototype's seed.
- **Esc during a task drag**: the gap closes while the copy flies back (the spec's words). The prototype keeps the
  gap open for 200 ms and then snaps.
- **Dropping a sidebar list**: the other lists stay parted through the 160 ms flight. The prototype springs them
  back ~93% and then forward again once the order is written (a prototype bug).
- **The lifted list's tile** keeps the list's color, as the prototype draws it (§14 says `ink`).
- **Detail pane**: the relative date sits 34pt past a set chip and the untitled draft's checkbox is at 45%, as the
  prototype renders them (§21 says 26pt; §6 says 70%). Code spans use SF Mono, per the tokens (the prototype falls
  back to Menlo in Chrome).
- **Date popover**: Tab keeps the keys in the field (the browser moves focus to the quick picks); while nothing
  matches, the last matching quick pick stays tinted (the prototype does; the spec says "the pick that matches").
- **Typed dates**: "9th" in December finds January's 9th (the prototype finds nothing, a bug); "constructor" doesn't
  produce NaN. "feb 29" without a year behaves as the prototype (only this year and next).
- **Context menus** are native NSMenus, so their highlight and timing are the system's (the spec asks for this).
- **The sun in the sidebar's Today tile** sits 1pt below center, as measured in the prototype.
- **⌘Return** in the detail title is caught by a key monitor: AppKit binds no command to it, so a field never sees it.

## For the spec (prototype vs text, for the Design agent)

1. §21 "The relative date sits 26 past a set chip": the prototype has 8 + 26 = 34.
2. §6 "checkbox … `ink-quiet` at 70%" while untitled: the prototype's inert rule makes it 45% until there's text.
3. §14 lifted list "tile and name in `ink`": the prototype keeps the tile's color.
4. §11 "the pick that matches what's typed is tinted": the prototype keeps the last match tinted while nothing
   matches; flipped above its anchor, the popover's gap is 7 (it's placed with 344 but is 343 tall).
5. Prototype bugs (not copied): the sidebar list drop springs back during its flight; "9th" in December finds
   nothing; "constructor" in the date field gives NaN; in headless Chrome the expanded Completed row draws no chevron
   and its text sits 14pt right.

## What to check by hand

- The feel of hover, springs and drags with a real trackpad, including momentum scrolling under a still pointer.
- The detail pane's open and close next to v1 (the code is v1's; the list beside it is now AppKit).
- Reduce Motion (System Settings ▸ Accessibility ▸ Display): every animation should be off.
- VoiceOver on the lists, rows, checkboxes and the date popover (the tree is there; I only read it with the
  Accessibility API).
- ⌘Z inside text fields (each field has its own undo), and opening a link from the notes.
- The List pop-up in the detail pane, and the notice holding while hovered.
- Light mode in daily use.
- The dividers (feedback 4) with a real pointer: the resize cursor over the sidebar's edge and the detail gap, the
  one-way cursor at a limit, a drag's smoothness in a long list, and a double-click reset.

## Feedback fixes (docs/TASK-v2-feedback.md)

1. **"New Task" twice.** While a new task is being added, the empty-area ghost row no longer shows: the draft's row is
   the only "New Task" (pressing the empty area still does what §6 says: caret back to the title, or write it). Checked
   live after ⌘N, the header +, a press on the empty area, a titled draft, in an empty list and in Today, and after
   the draft is written, dropped with Esc, or dropped by hiding the pane (the ghost comes back on hover). The
   prototype had the same bug (`ghostShow`, dc:1924); fixed there too, in the source only (the published canvas
   wasn't republished).

2. **A click on empty space no longer adds a task.** It clears the selection, as in Rex and Finder; with a task being
   added or something renamed, the first click only ends that (a new task is written, or dropped if untitled). A
   double-click there adds a task as ⌘N does. The hover "New Task" row is gone, and an empty list says "Double-click
   anywhere here or press ⌘N to add one." Checked live in a list, an empty list and Today, with a titled and an
   untitled draft open; the spec (§5, §6, §13, §16, §18.12, §21) and the prototype source were updated to match and
   checked in Chrome.

3. **The focused look only with two panes.** A pane alone in the window (the list with the detail pane closed, or the
   narrow window's detail pane) shows no focus whatever has the keys: `surface-dim` with the `line-pane-dim` edge (the
   unfocused fill, so the lit color only ever means "this one of the two"), header icons at 100%, the title in `ink`,
   selected rows in `fill-row-selected`. With both panes open nothing changed. Opening or closing the detail pane
   changes the list's fill, edge, icons and title on the pane's own spring (sampled every ~70 ms: the fill moves from
   one color to the other while the pane slides, not at the end); selected rows switch at once, as always. Checked in
   every state (one or two panes × list, detail or sidebar focused, and the narrow window), the prototype in Chrome the
   same way; spec §4 and the token table updated. If "plain neutral" was meant as `surface-base`, it's one line
   (`PaneChromeModifier`, and `.single` in the CSS).

4. **Resizable panes.** The sidebar's edge (8 wide, centered on the list pane's edge) and the 8pt gap before the detail
   pane are dividers (`Window/PaneDivider.swift`): no handle, the column-resize cursor (one-way at a limit), live
   resizing with no animation, a double-click springs back to 230 / 420 on `natural`. Limits: sidebar 180–400, detail
   340 and up, and the list never under 220 from a divider. Both widths are kept in the app's defaults (`sidebarWidth`,
   `detailWidth`; the default removes the key) and the detail pane reopens at its last width. A window narrower than
   the widths keeps the sidebar, lets the detail pane give way to 340, then goes narrow (drill-in) as before; the
   defaults still switch at 900. The sidebar's rows now span its width (they were a fixed 209). Checked in the app with
   in-process drags: each limit, both resets (the 600 → 420 spring sampled over ~300 ms), widths kept across a relaunch
   and the detail pane reopening at 714, the window at 1000 (detail 364, list 220) and 960 (narrow), the detail pane
   closing smoothly at 544. The prototype does the same in Chrome (limits, cursors, reset, `localStorage` across a
   reload). Not checked with a real pointer: the cursor itself and the feel of a live drag (the Mac was in use).

5. **Flicker on rename and after a drop.** Found frame by frame: the window recorded with ScreenCaptureKit (works while
   it's covered, up to 120 fps), every frame diffed against its neighbours.
   - *Drop (tasks and sidebar lists, in a list, Esc too):* the copy was hidden the moment it landed while its row faded
     back in from 0, so the row was gone for ~45 ms (5 frames at 0 text pixels) and then faded up. Now the row shows at
     once, exactly under the copy (any slide toward the gap still running unseen is cut), in the same transaction as
     the copy starting to fade out over it (150 ms): the row's text stays at full strength in every frame. Other rows of
     a multi-row drag fade in as before; a drop on a sidebar list was already clean (the row leaves).
   - *Rename (tasks and sidebar lists, entering and committing by Return or a click away):* three causes. The row's
     changes went out in an explicit Core Animation transaction and the field was added after it, so one frame showed the
     ring with no title; the field is now synced and drawn inside that transaction. AppKit's field editor draws with font
     smoothing and the labels (`CATextLayer`) without, so the title went ~30% bolder while renaming; the field now has
     its own editor that doesn't smooth. And both fields sat 0.5pt off the label (task field high, sidebar field low);
     both now land on the label's pixels (same left and top edge, centroid within 0.4px).
   - Prototype: the same drop hand-off (`.landed`, `.settle`; it also built the 'done' state from the pre-flight drag,
     so its copy had no position), checked in Chrome.

6. **Detail fields from the checkbox's edge, full width.** List, When and Deadline, the separator, Notes and the
   "Created" line start at the checkbox's left edge and span the content width, as the title row does. Each row's icon
   is centered in the checkbox's 16pt column and its word sits 10 after it, in line with the title's text (label
   column 81, so the 55pt for the word and the 8 before the value are as before; the values gain 21pt). "3 tasks
   selected" stays at 26, in line with the labels. Measured on captures: icon centers on the checkbox's center (the
   flag glyph 0.5pt off, its shape), the label's first pixel on the title's, the separator from the checkbox's edge to
   the title row's right inset. Checked one task, two selected, a new task (dimmed), no task, and the pane at its 340pt
   minimum (the relative date still clears the edge). The prototype measures the same in Chrome.

7. **Dragging a task across sidebar lists.** Recorded holding a task over School, then Inbox, then over Home past
   the task's own list. Sidebar rows are 30 tall on a 32 pitch, and the 2pt between them hit no row, nor did the
   task's own list, a label, Today in Today or an archived list. On any of those the drag counted as back over the
   task list for that event: the copy jumped back to a full-width row across the sidebar, the highlight dropped, and
   the task rows parted and closed again (frames 146–147 of the recording; again for the ~30pt across the own list).
   - Now each row's hit area takes half the gap either side, so the target goes straight from one row to the next in
     one frame. Anywhere over the sidebar the copy stays a tag at the pointer and the group stays closed up
     (`Drag.sidebar`), with no highlight where nothing takes the drop. A drop there cancels: the tag flies home,
     widening back into the row.
   - A fast sweep showed a second, smaller smear: a list's count stayed blue for ~250 ms after the target left it,
     three at once. The count's text layer redrew at commit time with Core Animation's default `contents` crossfade.
     It now has no implicit actions and changes in the same frame as the fill and ring (css:117 has no transition).
     The title keeps its `hover-out` ease; it needs that redraw, and without it the title froze partway to grey.
   - Checked frame by frame: slow and fast sweeps, Today in the Today view, the archive group, back into the list
     and out again, a drop on no target, a drop on Home (moved) and Esc (back in its slot). The prototype had the
     same dead band and got the same fix, checked in Chrome. Its Esc also left the gap at the last target while the
     copy flew home, so the row snapped back when the drag ended; the gap now reopens at the row's own slot
     (`homeSlot`, dc:2166–2173), as in the app. Mid-file line numbers are unchanged.

8. **Settings ▸ Edit tasks.** A pop-up in a new "Behavior" section (Rex's settings have a behavior page whose rows are
   a title and a one-line description, as this one is): "Open in detail pane", the default, or "Rename in the list".
   It's kept in the app's defaults as `taskEditing` (`detail` or `inline`); `-taskEditing inline` on the launch line
   overrides it without saving. Double-click on a task's row, Return (list or detail pane focused) and Rename in the
   task's menu all go through `WindowActions.editTask`: by default it selects the task, shows the detail pane, focuses
   it and puts the caret at the end of the title; with the pane already on that task only the title takes the caret.
   A title focus request now names its task, so one made as the selection changes waits for that task's title instead
   of landing in the one leaving. The same in both: › and ⌘D (no caret), ⌘N, + and a double-click on empty space,
   renaming sidebar lists, and a double-click on a completed task only selecting it (as before; Return still edits
   it). Checked on the scratch instance with `-debugScript` in both modes: double-click, Return from the list and from
   the detail pane's key sink, the pane already on that task, the pane on another task (double-click and Return),
   typing into the title and committing (Return on to the notes, Esc back to the list); unchanged: a double-click on
   empty space, `-debugAdd` (⌘N's action), double-click and Return on a sidebar list, the ›, a completed row. Settings
   rendered in both modes with `-snapshotSettings`. Not checked: Rename in the context menu (a modal menu the script
   can't drive), ⌘N itself (menu key equivalents don't reach a background app), clicking the pop-up, and the
   prototype in Chrome (its runtime isn't in the repo; the script parses). The prototype's strip has the same choice,
   kept in `localStorage`.

9. **Switching appearance.** Two faults, found by switching Settings ▸ Theme in every order on the scratch instance
   and standing in for the system with the app's own appearance (`NSApp.appearance`; the system setting wasn't
   touched):
   - **The traffic lights rose to the window's top edge.** Any appearance change, the window's or the app's, makes
     AppKit lay the title bar out again. It shrinks the container back to 32pt and leaves the buttons (the same
     instances) at the origins we gave them, so they sat 18pt too high, half off the window. The old fix-up ran
     async after resize and key notifications, so it raced that layout and sometimes lost; an appearance change posts
     neither. Now the container's and the buttons' own frame changes put them back, inside AppKit's layout, so no
     frame is drawn with them out of place. Sampled before every commit (`watch:` below) through 11 switches with
     the sidebar shown and hidden: 0 of 152 run-loop turns out of place, against 15 of 150 with the old code
     (container 32, close button at y 0).
   - **System didn't follow.** Going from Dark or Light back to System kept the old palette: `ThemedRoot` read
     SwiftUI's `colorScheme`, which still had the last explicit choice, while the window had gone back to the system
     appearance. Light rows drawn over a dark window, and the reverse, left some text unreadable. Now the model
     watches the app's effective appearance (KVO), resolves System itself (`AppModel.dark`), and always gives the
     window that explicit scheme, so the window and the palette can't come apart. The Settings window gets the same
     root.
   - Checked with in-process renders of the whole window (title bar and lights included, `snap:`), since the screen
     was locked: every order of System, Dark and Light with the system dark and light; one pane and two; the detail
     pane open with its title being edited; the sidebar hidden through switches and shown again; and the date
     popover open through switches. Rows, chips, selection, the sidebar, the detail pane and the popover all switch
     with the window. Not checked:
     - full screen, since entering it takes over a Space;
     - the lights' hover glyphs and pressed states, with no real pointer;
     - context menus and tooltips, which are modal or need hover (they take the window's appearance, which now always
       matches);
     - a real system flip, since only the app's appearance was simulated;
     - a frame-by-frame screen recording, because the screen was locked.

     One capture taken before the lock showed the lights in color in an inactive window right after a switch, while
     they were out of place. It couldn't be checked again after the fix.
   - New `-debugScript` steps:
     - `theme:system|dark|light`;
     - `sys:dark|light|none`, which stands in for the system appearance;
     - `chrome:/path`, which logs the window appearance, the lights' frames and the container height;
     - `watch:MS:/path`, which checks the lights before every commit;
     - `sidebar`;
     - `picker:when|deadline`.

## Notes for whoever drives the UI next

- Scratch tools (not committed) are in the session scratchpad's `tools/`: `ui` (window-relative HID input that only
  targets the "Tasks Dev" bundle and refuses if another window is on top), `cdp.mjs` (drives the prototype in
  headless Chrome), `imgdiff`/`px` (pixel comparisons), `track` (per-frame samples from a recording). The prototype's
  runtime (`support.js`) came from the canvas artifact.
- While someone is using the Mac, don't take the screen: launch with `open -g` (never activated) and drive it with
  `-debugScript` (in-process events; `size:W,H` resizes the window), and capture with `screencapture -l<window id>`,
  which works while the window is covered. Clicks reach only views that accept the first mouse (rows don't, the list's
  empty space, the sidebar, the headers' buttons and the detail pane do), and key events don't arrive at all.
- Launch the scratch app through LaunchServices (`open -n … --args …`): run directly from a shell, it has no
  accessibility windows. Its windows are owned by "Tasks" (the display name), so find them by bundle id or PID.
- Debug flags are in `app/README.md` (`-demoData`, `-demoBulk`, `-debugRoute`, `-debugSelect`, `-debugDetail`,
  `-debugAdd`, `-debugRenderTimes`, the sidebar's `-debugSidebarScript`, the popover's `-debugPicker`).
