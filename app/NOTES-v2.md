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
   prototype had the same bug (`ghostShow`, dc:2743); fixed there too, in the source only (the published canvas
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
     (`homeSlot`, dc:2998–3004), as in the app. Mid-file line numbers are unchanged.

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

10. **Glass made no difference, because it was wired to nothing.** The setting reached the environment
    (`paneInterfaceStyle`), and only Pane's `PaneChrome` read it, as a `glassEffect` behind each pane. v1 used
    `PaneChrome`, but even there the glass sat on an opaque window ground with nothing behind it to show. The v2
    foundation (7031b6e) gave the panes their own `paneChrome` modifier with opaque `base` / `dim` fills, so nothing
    read the setting anymore. Classic and Glass rendered the same pixels, and the window had no material view at all.
    The intent (Settings: "Glass is translucent"; DIRECTIONS: Pane's interface style, fills at 84–90% to keep
    `ink-secondary` legible) is now drawn (spec §4 Glass):
    - The ground under the sidebar, gutters and top band is the sidebar material blending behind the window (`.active`,
      in the theme's appearance), with the theme's ground over it at 60% (`GlassGround`).
    - The panes' fills are at 88%.
    - Hiding the sidebar also fades it out, or the panes would show it through.
    - Classic is untouched. `WindowConfigurator` is unchanged: the window stays opaque, and the material blends
      behind it as a sidebar's does.

    The screen was locked, so `screencapture` and ScreenCaptureKit returned nothing, and this was checked inside the
    app. A new `glasssnap:` script step renders the window with its materials hidden and no window background, so
    the alpha shows how much covers the glass. It also writes the window's opacity and every material view. Results:
    - Before: Classic and Glass were identical (except the lists' random tile colors), opaque everywhere, with no
      material.
    - Now, Classic: identical to before in all six cases (dark and light; one pane, two panes, sidebar hidden).
    - Now, Glass: one behind-window `.sidebar` material over the whole window, unhidden. The ground is covered at
      0.60, so 40% of the material shows. The panes are covered at 0.95, and rows, chips and the sidebar's current
      capsule at 1.0. With the sidebar hidden, nothing of it shows through the list pane.
    - A composite of those renders over a blurred test pattern (a simulation, not the material) is in the scratchpad.

    Not checked with the lock on:
    - the real material over a real desktop, and tuning the 60% / 88%;
    - contrast over bright and dark wallpapers;
    - the window's corners and shadow;
    - switching the style while the window is open (only the code was read; a script step would have written the shared
      defaults);
    - full screen.

    Settings keeps its opaque ground.

11. **The Keychain prompt after every install.** Ad-hoc builds have a new signature each time, and the sync token's
    "Always Allow" is tied to it. Builds now sign with a local identity when this Mac has one
    (`Scripts/make-signing-identity.sh`, README "Signing"), so the designated requirement stays the same.
    - Checked: two Release builds with different code (`-Onone`, then the normal build) both have
      `identifier "com.elguindi.Tasks" and certificate leaf = H"cf1bb96c…"`, with different cdhashes. Both pass
      `codesign --verify --strict`. Debug signs the same way.
    - The ad-hoc fallback still builds without the identity. A second run of the script changes nothing.
    - The certificate is untrusted (self-signed); codesign doesn't need trust for this.
    - A pending Keychain prompt anywhere in the login keychain (here, the installed app asking for the token on a
      locked screen) holds up every codesign that uses this key until someone answers it, so builds hang meanwhile.
      A codesign killed mid-sign leaves `Contents/MacOS/Tasks.cstemp`, which the next signature seals in; delete the
      product and build again.
    - Not checked: that "Always Allow" on the next install holds for the build after it. That needs the real app and
      its token item.

12. **The brand header.** The sidebar's content now starts with the 04 · Log mark and "Tasks" (34 tall), and Today is 6
    below it. Every row's y comes from `SidebarModel`, so hit-testing, drops, scrolling and list drags follow the
    shift. `SidebarHeaderLayer` draws the mark as `CAShapeLayer`s from `gen.py`'s shapes (`BrandMark`), so it stays
    crisp at any scale. On the light sidebar it uses the mark's designed light colours.
    - The cut: the small and full cuts rendered at 18pt, 1× and 2×, on both sidebars. The small one reads; the full
      cut's rings and trail turn to hairlines (grey smudges at 1×). The small cut is used.
    - Checked in-process (`snap:`): dark and light, collapsed (the panes cover it; nothing moves into the top band),
      a theme switch while collapsed, then shown again. A click on the header only gives the sidebar the keys, as
      empty sidebar space does; there's no hover target there.
    - The prototype, in headless Chrome: the header in both themes, on the same pixels as the app ("Tasks" at x 46,
      centred on y 67; Today centred on y 105). Rows still open on a click, and a click on the header does nothing.
      Its line numbers are unchanged.
    - VoiceOver doesn't announce the header (it's not in the sidebar's accessibility elements).

13. **⌘Z in the notes and the text fields.** Edit ▸ Undo sends `undo:` up the chain from the first responder, and
    nothing took it before SwiftUI's window, which answered from the app's undo manager for the notes and the date
    field: Undo was greyed out while they had typing to undo. The notes, the rename field (`InlineField`: the detail
    title, a row's rename, a list's) and the date field now take `undo:` and `redo:` themselves (`FieldUndo`), from
    their own undo manager, titled "Undo Typing" and off with nothing left to undo, as a browser field does. Outside a
    field ⌘Z is the app's undo as before; when the notes commit, the session is one "Edit Notes".
    - `InlineField` and the date field named their `undoManagerForTextView:` without the selector, so Swift exported
      `undoManagerFor:`, the field editor never asked, and the typing went to an undo manager of AppKit's. The selector
      is spelled out now, so it lands in the field's own.
    - Found on the way: typing at the end of a line followed by a list item put the caret on the next line from the
      second keystroke (the prefix snap ran on the parse from before the keystroke). The snap waits for the parse now.
    - Checked in-process, through the menu's own path: `menukey:z` finds Edit ▸ Undo by its key equivalent, validates
      it and sends it as AppKit does with the window key (a background app has no key window), and `event` gives
      NSApp's event loop a pass, which closes undo groups as real input does. In the notes: Return continuing a list,
      two typing runs 1.7 s apart, a box toggle, ⌘B and a paste undo one at a time and redo in order, and Undo is off
      after the last; Esc then leaves one "Undo Edit Notes" that restores the original. The title, a list's rename, a
      row's rename (`-taskEditing inline`) and the date field undo and redo their typing, none of it carries into the
      next edit, and ⌘Z outside them undoes "Complete".
    - Not checked: the real key events (the menu's key equivalent from the keyboard, with the app active), and the
      Settings window's server URL field (SwiftUI's own field and undo; typing there writes the shared dev defaults).

15. **Today's Completed folds.** Its label (`GroupLabelView`) gets a heading's chevron: a 22pt `IconButtonLayer` with
    a 12pt glyph that only rotates, revealed on hover and kept while collapsed, the count after the name while
    collapsed. Collapsed, the layout leaves the done rows out and records them in `folded` under the label's key, so
    they fold into it and unfold from it exactly as a heading's tasks do (the label is raised above the rows when it
    folds). The list's hit test asks the label for its part first, so a press on the chevron (or a list label's +)
    never does anything else. Space: a click on the label selects it like a heading's row (its fill) and Space folds
    it; Space on selected done tasks still marks them not done, so it isn't taken over. Collapsing with done tasks
    selected moves the selection to the label; ↓ and ↑ from the label go to its first task and the row above.
    `WindowState.todayDoneCollapsed` and, for consistency, a list's Completed row being open (`completedOpen`, which
    now folds its tasks into the row the same way) are kept in UserDefaults across launches. No other view has a
    Completed group. Long names in any group label (a list's in Today, a day's date) now stop before the buttons
    with the title's 24pt end fade instead of running under them.
    - Checked in-process (`act:donewhere`, `act:trace`): the chevron is 12×12 in its 22pt button on the first render
      (hidden, pointing down), on the first hover (shown), and after a relaunch while collapsed (shown, pointing
      right); the chevron collapses and expands it (a click through the list's mouse path); a click on the label then
      Space collapses and expands it; Space on a done task unchecks it; collapsing with a done task selected leaves
      the label selected; ↑ from the label selects "Return library books"; it stays collapsed across two relaunches,
      and a list's opened Completed row stays open. Frame by frame, expanding starts all five done rows at the
      label's y (406) and spreads them to 438–566 on the `layout` spring as they fade in; collapsing raises them into
      it as they fade out in 150 ms; the label stays above them (`labelAboveRows`). At the 620pt minimum window, a
      65-character list name in Today's label ends in the fade short of its +.
    - Not checked: hover and press looks frame by frame, real pointer and keys with the app active, and VoiceOver on
      the label (it sets "Completed, collapsed, N" as its accessibility label, unheard).

16. **Long list names overlapping a row.** The list name after a title was laid out at its full width from the right,
    so a long one ran left over the title, the hint and the checkbox. A row's right side is now shared in an order
    (`TaskRowView`): the title keeps up to 120pt (all of a shorter one) with its notes hint; the date chips keep their
    size and are dropped from the first (When, then Deadline) rather than cut the title below that; the list name keeps
    up to 72pt and then truncates with the title's 24pt end fade, and goes when less than 32pt of it would show; space
    beyond those goes to the title first, then to the list name. A month row's " · Oct 22" stays whole after a cut
    name. Nothing draws over the leading content or past the row. At the list pane's 220pt minimum that means titles
    only, chips dropped; from about 300pt chips and cut names come back.
    - The rest of the audit: the large title (it lost its descenders when cut: the layer's own font now sets the line,
      and its date or "Archived" gives way first) and heading names end in an ellipsis, as the prototype's `.lhn` and
      `.ht` do; the band's title truncates after the name's priority; sidebar names already faded into their counts;
      the detail pane's header, List row and relative dates truncate at its 340pt minimum; menus ("Move to", "Put
      Back in", "Show in …", "New Task in …") cut names at 280pt with an ellipsis; the undo notice ("Moved to …")
      truncates inside the pane instead of running past it; tooltips cut at 300pt and stay inside the window by their
      measured width.
    - Checked with `-demoLongNames YES` (a list "SE 463 — Software Project Management, Requirements, and Analysis", a
      200-character list name, long titles, a long heading) at list panes of 220, 320 and 492, the detail pane at 340,
      the window at 420 tall, light and dark; before and after renders.
    - Found here, fixed elsewhere: Today's group labels and Upcoming's day labels cut a long list name hard (item 15
      gives `GroupLabelView` the end fade); and an empty list's notes editor drew its own "Notes" placeholder at rest,
      where §23 wants it only on hover, while renaming or with the caret (the list pane's editors now draw none at
      rest; the title block's fades in, and a heading's shows only with the caret in it).
    - Not checked: the menus as drawn (their titles were logged), and tooltips on screen.

## Markdown notes (design/MARKDOWN.md)

Built to the spec and the prototype (`design/prototype-markdown/`); §11 of the spec lists where the build differs.

- **Pieces:**
  - TasksCore `Markdown` scans lines and inline tokens over UTF-16 offsets, with the prototype's rules;
    `NotesSummary` (on `TaskModel`, worked out per notes change) feeds the row's hint.
  - `Detail/NotesMarkdown.swift` styles one line at a time: hidden marks are zero-advance glyphs; dots, numbers,
    boxes, quote bars, code backgrounds and link underlines are drawn by the layout manager.
  - `Detail/NotesView.swift` is the editor: the session, keys, paste, boxes, hover, VoiceOver.
  - `Detail/NotesPaste.swift` turns RTF (or HTML) into Markdown.
- **Checked in the scratch app** (screen locked: in-process renders, and new DebugScript steps `ncaret:`, `type:`,
  `nbox:`, `npaste:` (a private pasteboard, never the user's clipboard), `nhover:`, `nax:`, `nlog:`, `nfrag:`,
  `nbench:`, `mktask:`, `undo`):
  - the seed notes against the prototype in headless Chrome, at rest and with the caret in a code block, dark and
    light: the same layout, line for line;
  - the marks near the caret: a token's, a heading's `#`, both fences of a block;
  - typing, Return continuing a list or checklist, Return on an empty item ending it, Return at an item's start,
    Backspace at an item's start, Tab and ⇧Tab (two levels at most, ⇧Tab at the left edge back to the title), ⌘B on a
    word, Esc committing one "Edit Notes";
  - a box at rest (its own undo step in the window's undo) and in a session (a step of the notes' undo, nothing
    written until the session commits);
  - pastes: a URL over a selection, a block mid-line, RTF with a heading, bold, a link, mono and a list;
  - a link's hover (full underline, the address in the tooltip after 600 ms) and a box's;
  - VoiceOver's value (the text without marks) and the boxes as checkboxes;
  - the row hint: the glyph, "2/5", and a long title fading into the hint only when it's cut off.
- **Budgets** (an optimized build, `nbench:`): a 20,000-character note opens in about 25 ms (scan 0.15, styling 11.5,
  TextKit layout 13); a keystroke is 0.4 ms median (the session's first, about 12 ms, once); the scan alone is
  0.05 ms in TasksCore's release test.
- **Not checked:**
  - with the screen locked: the marks' 100 ms fade, the boxes' press, check and pop animations, frame by frame;
  - real typing with IME and dead keys (NSTextView's own marked text; restyling waits while there is any);
  - a real drag-select (NSTextView's mouse tracking blocks a background script, so marks waiting for the button to
    come up is only by the code);
  - HTML-only paste (WebKit), and pastes from real apps' RTF.

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
  `-debugAdd`, `-debugSidebarHidden`, `-debugRenderTimes`, the sidebar's `-debugSidebarScript`, the popover's
  `-debugPicker`).

## The four views: Upcoming, Undated, Completed, Trash (INTERACTIONS-v2 §22)

Built from §22 and the prototype (`design/prototype-v2/`, dc:3006–3318), with the user's picks:
- **Sidebar.** It reads Today, Upcoming, Undated, the lists, then 8pt and Completed and Trash, then the Archive group.
  - The four have no counts, no menu, and can't be renamed or dragged.
  - ⌘1–⌘9 (the menu and the held-⌘ hints) number the first nine rows top to bottom.
  - Type-select tries the lists first, then Today and the views.
- **Upcoming.**
  - It always shows the next seven days; an empty day's label is quiet but takes +, a double-click and a drop. Then
    one group per month: "Later in November", "December".
  - A task with both dates shows once, on the earlier one.
  - A row shows its list's name. Its own day isn't repeated as a chip, and a deadline on that day reads "Due".
  - + adds for the +'s day, else the selected task's day, else tomorrow.
  - ⌥⌘↑↓ moves a task a day, never past its deadline; a day before tomorrow is Today, with a notice.
  - Drag-to-reschedule: the day under the copy lights and opens a gap where the task will land. A month, or a day
    past a dragged task's deadline, doesn't take the drop. The drop sets When; the deadline is never touched.
- **Undated.** Open tasks with neither date, grouped by list as Today groups them. Its + adds to that list. A date
  takes a task out, with a notice.
- **Completed.** A logbook, newest first: a group per day for the last week, then per month. A month row shows
  "School · Oct 22". Unchecking holds the row unchecked for 1.5 s. ⌘N adds in the default list.
- **Trash.** Newest-deleted first, read-only.
  - Rows: titles `ink-secondary`, the checkbox at 60%; the checkbox and chips don't respond to the pointer.
  - Detail pane: fields don't respond; the footer reads "Created … · Deleted …"; ↶ Put Back replaces Delete. The notes
    editor is `inert` there too (no link or box hover, no I-beam): SwiftUI's `allowsHitTesting` stops clicks but not
    an AppKit view's tracking areas or cursor rects.
  - Put Back: ⌘⌫, the menu, or ↶. It returns the task to its old place, with Undo "Put Back". Put Back in ▸ and a
    drop on a list put it at the bottom of that list.
- **Drops from a task drag.**
  - Completed completes, and Trash deletes ("Deleted …").
  - Upcoming and Undated don't take drops.
  - From the Trash, a list puts the task back.
- Empty states for all four. Upcoming's sits 24 under its seven quiet days.
- The demo seed has the prototype's view tasks (dc:510–547, around the headings example), so the app and the prototype can be compared.

How it's built:
- `Route` gains the four cases, and the sidebar's key is the route (`Window/Views.swift`). Everything per view is
  there or in `TaskList/ViewLayout.swift`.
- No new model fields, and no TasksCore changes: Put Back is an op built in the app (`Patch(deleted: false)`).
- **When a task was deleted.** The Trash takes it from the task's last op (`updatedAt`). Nothing in the app edits a
  trashed task, so that's the op that set `deleted`. Two consequences:
  - Undoing a Put Back deletes the task again now, so it moves to Today's group.
  - An edit to a trashed task from elsewhere (the CLI) would move it too.
- **How a render stays cheap.** Each view's rows are cached (`ViewItems.read`) under a key of what they depend on:
  - Completed and the Trash: the lists' buckets (the Trash scans for deleted tasks only when one changes).
  - Upcoming and Undated: a revision. One observer per window, `ViewDates`, reads every open task's dates in a single
    tracked pass; when one changes it bumps the revision once, and the next read arms it again.

How it was checked (the screen was locked, so everything is in-process):
- Renders of all four views in the app (`snap:`), beside the prototype's in headless Chrome, both seeded the same:
  all four in dark and in light, and the four empty states. They match, except the lists' tile colours: the app
  derives them from the list id, as before.
- A new script step, `act:` (`Support/DebugViews.swift`), drives the actions that menu key equivalents would (they
  don't reach a background app). It logs the laid-out rows and labels (`act:rows`) and the context menus
  (`act:menu`). Checked with it:
  - ⌘1–⌘9 and the hints; type-select ("u", "t", "tr", "c");
  - Upcoming: ⌥⌘↑↓ in all three cases; removing a date; + by selection and by day; completing (held 1.5 s);
  - Undated: a date taking a task out; + in a list;
  - Completed: unchecking; ⌘N;
  - Trash: Put Back, Undo, Put Back in, ⌘⌫ as Put Back, and the guards (complete, dates and move do nothing);
  - every view's context menu.
- Drags: real mouse events through the script (`down:`/`move:`/`up:`), with `act:trace` sampling every row's,
  label's and the copy's presentation position and opacity before each commit:
  - Upcoming onto Wednesday: the gap opens at the landing slot, the label lights and unlights as the flight starts,
    the copy lands in 110 ms, and the row shows in the same turn the copy starts to fade.
  - Upcoming past a deadline and onto a month: nothing lights, the copy flies home, nothing is written.
  - Esc mid-drag: the copy flies home and the row springs back.
  - A reorder within an Undated group.
  - Sidebar drops: Today → Completed and → Trash; Completed → Trash and → a list; Trash → a list (put back).
- Cost with `-demoBulk 5000` (5,000 extra open, undated tasks), `-debugRenderTimes`:
  - a selection change in Upcoming or Undated: ~0.7 ms (5.5–12 ms before the cache);
  - switching to Upcoming: 8 ms; to Undated: 25 ms, laying out 5,006 rows;
  - a date edit in those two: ~17 ms. The observer reads every open task again after any change. That's linear in
    open tasks (about 2 ms at 500), so it's over SPEC §9's 1 ms for a local edit only with thousands open.
  - The proper fix is a projection index in TasksCore (open tasks by the day they reach Today, and deleted tasks),
    which I left alone (the SDK agent's area).

Not checked:
- Anything needing a real pointer or the screen: hover looks and tooltips ("New Task for Monday"), the menus as
  drawn, real ⌘-key shortcuts, trackpad drags.
- VoiceOver on the views' rows and labels.

## Headings, a list's text and the large title (INTERACTIONS-v2 §23)

Built from §23 (final, with "Bugs the prototype had") and the prototype (`design/prototype-v2/`, the PHYS 122 list:
the seed at dc:528–543, the layout at dc:3465–3499). The demo seed has PHYS 122, so the two can be compared; at the
same size they match line for line (title block 88 tall with two lines of notes, a heading's row 8 below its slot,
its notes 2 below its row).

- **Model:** a heading is a task with `kind: "heading"` (TasksCore `TaskItem.isHeading`), a list has `notes`. The
  projection keeps headings in the list's open order and in a `headings` bucket, so counts subtract them and Today,
  Upcoming, Undated and Trash never show one. The snapshot schema is 2 (old snapshots replay).
- **Layout** (`TaskLayout`): a heading's slot is 8 of air, its 32pt row, and its notes (measured, + 6); a collapsed
  heading's tasks aren't laid out and are kept in `folded` for the fold. Rows start under the title block (4 + 30,
  then a list's notes 4 below, then 12); Today and the views get the 46pt title line. Drags use real slot tops.
- **Views:** `HeadingRowView` (the + and the chevron are `IconButtonLayer`s, the chevron's glyph a fixed 12pt
  `GlyphLayer` that only rotates), `ListTitleView` (the large title, its rename field, the "Notes" placeholder). The
  list's and the headings' notes are the same notes editor, hosted through `NotesHost` (`NotesField.makeEditor`),
  quieter (`ink-secondary`), one `list.update` or `task.update` per session.
- **The +, the chevron and the row's press:** the rows are layers, and the list hit-tests them itself, so the
  equivalent of "subviews that win the hit test" is that `TaskListView.target(at:)` asks the heading for its part
  first: a press on the + or the chevron is that button, whatever its fade, and never selects or starts a drag.
- **Expanding and collapsing:** a revealed row or note is placed at the heading's row and moved to its place with the
  same additive `layout` spring as every other row, fading in on 220 ms ease-in, under the heading (heading views sit
  above the rows). Collapsing moves them up into the heading's row as they fade out (150 ms). A folding notes editor is
  inert, so it never takes a press while it passes over the heading.

How it was checked (scratch app, debug steps; the screen was locked):
- Rendered against the prototype in headless Chromium: PHYS 122 at 1180 wide, same rows, rules, notes and title.
- **Every way of expanding** opens a collapsed heading, and collapsing works the same ways: the chevron (a click
  through the list's real mouse path), Space, Collapse / Expand in its menu, its + (expands, then the new task lands
  at the end of the section), and ⌘N with it selected (`newTask`, which expands first).
- **Relaunch and sync:** collapsed headings stay collapsed after a relaunch on the same data, and through a sync with
  a fresh `wrangler dev` (8795) while the CLI renamed a collapsed heading and added a task under it; the chevron then
  expanded it with the CLI's task at the top of the section.
- **The chevron's size:** its glyph is 12×12 in a 22pt button on the first render after launch (hidden, pointing
  down), on the first hover (shown), and collapsed after a relaunch (shown, pointing right). `act:where` logs it.
- **Frame by frame** (`act:trace`): expanding Labs, its notes and three tasks start at the heading's y (168) and
  move with Exam prep and everything below on one curve; the last task stays exactly 40 above Exam prep's row in
  every frame, never over it. Collapsing is the reverse, the rows rising into the heading's row as they fade.
- ⌥⌘N above the selection (one `task.create` with `kind`), Esc and an empty name leave nothing, Tab writes it and
  goes on to its notes; Return renames; ⌥⌘↓ moves a section; a heading drag moves its section in one request
  (completed tasks included) and lands only before a heading or at the end; a task dropped across a heading changes
  section; delete keeps the tasks under the heading above ("Deleted heading “Exams”", Undo brings it back); ⌘A selects
  tasks only; the detail pane with a heading selected; the list's title renames in place and Tab goes to its notes;
  the band's title shows once the list has scrolled 24pt.
- TasksCore: 156 tests (SectionTests, fixture 12 byte for byte, headings in the randomized multi-Mac simulation);
  benchmarks within §9 (snapshot decode 17.8 → ~19.5 ms).

Notes for the script: steps run without passes of NSApp's event loop, so undo groups merge across steps unless an
`event` step sits between them (a real click or key is its own group). And a `click:` that lands on a notes editor
blocks the script: NSTextView tracks the mouse until a mouse-up the script never sends.

Not checked:
- Hover and press looks frame by frame, the band's 150 ms fade, the "Notes" placeholder on an empty list's hover,
  trackpad drags of a heading (driven with posted mouse events only), and VoiceOver on heading rows.
- Clicking into a list's or a heading's notes (the script can't; Tab and Add Notes were used instead).
