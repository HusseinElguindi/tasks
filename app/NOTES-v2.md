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

## Notes for whoever drives the UI next

- Scratch tools (not committed) are in the session scratchpad's `tools/`: `ui` (window-relative HID input that only
  targets the "Tasks Dev" bundle and refuses if another window is on top), `cdp.mjs` (drives the prototype in
  headless Chrome), `imgdiff`/`px` (pixel comparisons), `track` (per-frame samples from a recording). The prototype's
  runtime (`support.js`) came from the canvas artifact.
- Launch the scratch app through LaunchServices (`open -n … --args …`): run directly from a shell, it has no
  accessibility windows. Its windows are owned by "Tasks" (the display name), so find them by bundle id or PID.
- Debug flags are in `app/README.md` (`-demoData`, `-demoBulk`, `-debugRoute`, `-debugSelect`, `-debugDetail`,
  `-debugAdd`, `-debugRenderTimes`, the sidebar's `-debugSidebarScript`, the popover's `-debugPicker`).
