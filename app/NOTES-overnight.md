# Overnight notes (macOS app)

What changed overnight (docs/TASK-overnight-mac.md, docs/TASK-interaction-mac.md, docs/TASK-sidebar-hover.md, then
docs/TASK-next-mac.md: see "Second batch" below), what's left, and how to install the new build. Everything below was checked on a scratch "Tasks Dev" instance with its own
data folder and a local `wrangler dev`; your app, its data and the production server were never touched.

## Install the new build

The Release build of the last commit (see `git log -1 -- app/`) is at `app/.build/DerivedData/Build/Products/Release/Tasks.app` (ad-hoc signed,
`com.elguindi.Tasks`, same data folder and settings as the one you run).

1. Quit Tasks (⌘Q), so it writes everything down.
2. `rm -rf ~/Applications/Tasks.app && cp -R app/.build/DerivedData/Build/Products/Release/Tasks.app ~/Applications/`
3. Open it. Ad-hoc builds change signature every build, so macOS may ask whether Tasks may use the
   `com.elguindi.Tasks.sync` Keychain item: choose Always Allow. Nothing else migrates or changes.

## Second batch (since 9dd6eca): list switching, lifted drag row, window controls

- **List switching, 2–3× faster** (21fbc2f). Profiling (Time Profiler with signposts; SwiftUI's own instrument records
  nothing under `xctrace`) showed the time was SwiftUI's `List` (an NSTableView) diffing every row out and in on each
  switch, then measuring and preparing each new row (automatic row heights 30%, row preparation 22%). Our row code
  was ~5%. What changed:
  - The task list is a lazy stack whose rows are positional slots. A switch updates the rows already built (a task
    row shows another task) instead of building new ones.
  - Today and lists are one pane, so moving between them updates the header in place.
  - The sidebar's current row and hover use per-row flags, and its fills stay in place and change opacity. Inserting
    the current capsule rebuilt it on every switch.
  - A row's ••• menu is a real `Menu` only under the pointer. A `Menu` took ~3.5 ms to build.
  - One drop target for the whole list instead of one per row.
  - The pane header's ••• menu no longer depends on which list is open (it reads the open list when an item is
    chosen), so a list switch doesn't rebuild it.

  Main-thread work per switch, optimized build, medians of 8 rounds, with latency to the first new row in brackets:

  | Switch | Before (List): latency | Now: work (latency) |
  |---|---|---|
  | between lists that reuse rows (School → Tasks app, Home → Errands) | 30–38 ms | 15–16 ms |
  | to a list with one more row (Tasks app → Home) | 31–35 ms | 16 ms (13) |
  | Today → a list | 40–49 ms | 19–20 ms (16–17) |
  | to a longer list (Inbox 2 → School 7) | 41–44 ms | 25 ms (22) |
  | into the 2,000-task list | 53–69 ms | 40 ms (36–37) |
  | out of it, to Today | 95–102 ms | 29–31 ms |

  The one-frame budget (16.7 ms) is met only by the first two rows. The rest comes from building new rows (~2 ms
  each, mostly SwiftUI's own work) and a fixed ~6 ms (sidebar ~3, pane ~3). Next steps would be hover, click and drag
  handled once for the list instead of per row, and cheaper rows. `app/Scripts/switch-bench.sh` runs the benchmark
  (each switch is also a "switch" interval in Instruments' Points of Interest) and fails above 45 ms as a regression
  guard.
- **Lifted drag row** (A1): a dragged task is a raised copy of the row with `shadow-lift`, plus a count when several
  move; the source rows stay at 35% until the drag ends; our insertion line, inset to the row text, marks the drop.
  I couldn't measure Rex's drag: that means dragging in Rex, which the rules rule out.
- **Window controls**: the traffic lights and the sidebar toggle are where Rex has them (circles 18–32pt from the
  corner, centers 25/48/71; toggle centered at 107; all on the pane titles' line). Hit-testing shows the pane-header
  buttons still get their clicks under the taller title bar.
- **Keys from the start**: the task list has keyboard focus when the window opens, so ↑ ↓ work without a click.

### Verified, and not yet

The screen locked again around 06:45, so this batch was checked offscreen: renders after every kind of switch (the
first try at recycling rows showed stale tasks and was replaced), and events posted inside the app for ↑ ↓, ⇧↓,
Space, Return and Esc (`-debugScript`). Clicks and ⌘-shortcuts can't be checked that way, because a window that isn't
key drops first clicks and menu commands. **Still to check live**: click, ⌘-click and ⇧-click selection,
double-click to open, hover •••, drags (lifted row, insertion line, drop on a sidebar list, list reorder), ⌘N in a
long list, ⌘Z, and the traffic lights through a resize and full screen.

Compared with the `List`, these aren't there yet: ⌘A to select all, type-to-select, Home/End/Page Up/Page Down,
scrolling while dragging near an edge, and the table's VoiceOver semantics.

## Done (first batch)

- **Debug builds can't touch the real app** (6f6ef97, then "Tasks Dev"): Debug is `com.elguindi.Tasks.dev`, product and
  process name "Tasks Dev", its own defaults, saved state, Keychain item and data folder (`Application Support/Tasks Dev`),
  and it only syncs with a local `wrangler dev` (unless `-allowRemoteServer YES`). Release is unchanged.
  An early timing run (Debug, before this change) launched without `-serverURL`; its data folder shows no `log.jsonl`
  and all ops still pending, so it never completed a sync with any server.
- **List performance** (7c20fa6): task rows are exactly one view each (a conditional row made the List build all
  2,000 rows to count them: 182 ms → ~50 ms to open a 2,000-task list); one List is kept across list switches.
  Still over SPEC §9's "one frame to first rows": typical lists 16–43 ms (route change → first row on screen,
  optimized build). Next step would be Instruments' SwiftUI template.
- **Interaction redesign** (design/INTERACTIONS.md, built from design/REX-REFERENCE.md), verified live on a scratch
  instance with screenshots:
  - No hover fills anywhere. A hovered task row reveals only its trailing •••; sidebar titles rest in ink-secondary
    and brighten on hover, with the list's ••• taking the count's place. (This first pass lingered 300 ms on
    hover-out; that's gone, see below.)
  - Selection is the strong state: `fill-selected` rows, the current sidebar row a `fill-strong` capsule with •••.
  - Icon buttons as in Rex: a rounded-square fill in pane headers, a circular fill for the sidebar toggle (now right
    after the traffic lights), 100 ms; tooltips "Name ⌘X".
  - Collapse/expand: the panes slide over the stationary sidebar (300 ms, decelerating); the traffic lights and toggle
    stay put and the leftmost pane header makes room for them. ⌃⌘S toggles.
  - Gone: the drag grip (whole-row drag instead), the default-list "+", the pinned band behind Today's group labels
    (labels are plain rows now), pressed overlays (presses darken to 86%).
  - Unfocused panes fade their header icons; focus changes take 60 ms. The detail pane's open/close is unchanged.
  - Opening a task no longer moves keyboard focus into an empty notes editor.

- **Sidebar hover, redone after your feedback** (docs/TASK-sidebar-hover.md). Measured against Rex's
  rest/hover sheet with the same pixel tool (sRGB), dark theme:

  | | Rex | Before | Now |
  |---|---|---|---|
  | Hover out | ~85 ms fade, at once | held 300 ms, then faded; rows swept by the pointer stayed lit | 85 ms fade, at once |
  | Title at rest / hovered | #A8ADB1 / #E6EDF3 | #919598 / #E6EDF3 | #A8ADB1 / #E6EDF3 |
  | Sidebar width, capsule x | 230, 10–219 | 220, 8–212 | 230, 10–219 |
  | Row pitch (capsule 30pt) | 32 | 34 | 32 |
  | Capsule edge (outer / inner px) | #5E5E5E / #535353 | #525354 / #525354 | #5F6060 / #545555 |
  | Tile | 20 × 16 at x 20 | 20 × 20 at x 16 | 20 × 16 at x 20 |
  | Title ink starts / baseline | x 47.5 / middle + 4 | x 44.5 / middle + 5 | x 47.5 / middle + 4 |
  | Trailing action | ••• x 195.5–210.5 | ••• (SF, bold) ~x 189–205 | ••• x 195.5–210.5 |
  | Group label x / color | 22.5 / #7F8386 | 16.5 / #85898B | 22.5 / #7F8386 |

  Applied through shared pieces so the rest of the app moved with it: one hover model (`PaneHoverRegion`: one hovered
  item per region, cleared when the pointer leaves the region, the item disappears or a drag starts), the dark ink
  ladder (`ink-secondary`, `ink-tertiary` at Rex's values, so every dimmed text in the app changed with the sidebar),
  `PaneRowMenu` (Rex's dots and slot, task rows too), 5:4 list tiles everywhere, task rows on the same 30/32 rhythm,
  and Today's group labels now reveal ⊕ (New Task in that list) like the sidebar's "Lists". Each Pane difference is in
  design/PANE-UPSTREAM.md.

## Fixed after the screen was unlocked (verified live with HID input on the scratch build)

- **Hover, live**: a 60 fps recording shows hover-in at 78% on its first frame (Rex ~80%) and hover-out settled 67–83 ms
  after the pointer leaves, with the exit and the fade in the same millisecond of the event log. Moving onto a row's
  ••• keeps the row hovered; opening its menu and moving away clears it; scrolling under a still pointer moves the
  hover row by row and ends on the row under the pointer.
- **Keyboard in task lists** (was known bug 1): SwiftUI's List never takes keyboard focus when a row is clicked on
  this macOS. A bare `List(selection:)` with plain text rows does the same, and an in-app click event too, while Tab
  does focus it. So it wasn't our row code: the list now takes focus when its selection changes (unless text is being
  edited). ↓, Space, ⌘Z, Return and Esc verified.
- **⌘N focus**: quick add's focus request was made before its List row was in the window, and in a long list the row
  sits below the last open task, offscreen, so it was never built. ⌘N now scrolls it into view and focuses it after
  the row appears; typing lands in the field (verified in a 47-task list and in Today).
- **Dropping tasks on a sidebar list didn't work** (was known bug 2): the dragged row's item provider was cancelled
  before the asynchronous load finished, so nothing moved, and SwiftUI calls `dropUpdated` again after `performDrop`,
  so the "Move to …" highlight stuck. Drags now record their payload when they start and drops read it directly;
  the highlight only shows during a live drag. The insertion line above the first list was clipped by the sidebar's
  scroll view; it now has room. Verified: reorder within a list, drop on a sidebar list, sidebar list reorder.
- **Detail pane fields** (was known bug 3): they take focus on click and accept typing; nothing to fix.
- **The stopped reviewer's lead** (was known bug 4): four crash reports at 04:35–04:40 are from its own probe build
  (bundle `com.elguindi.TasksProbe`, its modified code), not from your app or mine. All four segfault inside Swift's
  runtime main-actor check in the closure of `ListModel.monogram`. Our builds ran dozens of times tonight without it,
  so I couldn't reproduce it; the helper is now nonisolated so that closure carries no such check.
- My `typetext` tool posts per-process Unicode key events, which text fields here ignore; typing tests use HID keys.

## For the user to decide

- **Task titles at rest**: they stay full brightness (`ink`). Rex dims its sidebar titles until hovered; doing that
  to every task title would cost the list its legibility for a hover effect. It's a one-line change if you want it.
- The default list is shown only by the quick-add list chip now (the sidebar "+" read as stray).

## Checks (after the last change)

- `swift test` in app/TasksCore: 101 tests, 0 failures (the live-server test is skipped without its env vars); re-run
  after the second batch.
- Release benchmarks, all within budget and unchanged: launch 22 ms, snapshot decode 18 ms, local edit 3 µs,
  1,000 remote ops 0.9 ms, reorder in 2,000 tasks 0.18 ms, midnight rebuild 0.46 ms, full replay of 100k ops 0.31 s.
- End-to-end (`app/Scripts/e2e.sh`, local wrangler with wiped state): phase 1 converged (two Macs with offline edits
  and a fresh third), phase 2 converged after a server wipe (both recover, a fresh fourth sees everything), no
  backups left behind.

## Known issues, not done

- Switching lists is within a frame only between lists of similar length (see "Second batch").

## Spec and design notes

- Pending ops live in `pending.jsonl` (one verbatim op per line, appended), not the spec's `pending.json`.
- The layout is a custom split, not `NavigationSplitView`: on macOS 27 that adds a toolbar band and a glass sidebar
  button Rex doesn't have.
- The Inbox seed op has the same id on every Mac but its own `at`, so confirming pending ops compares whole ops, not
  ids. Archiving or unarchiving a list rescans "done today".
- ⌘W closes the window; the detail pane closes with ⌘D or Esc.
- The detail pane says "Created Oct 30" without A1's "in School" (the List row right above it says that).
- Pane's dark `ink-secondary` and `ink-tertiary` now follow Rex (design/PANE-UPSTREAM.md), so every dimmed text in the
  app is a little brighter (secondary) or dimmer (tertiary) than Pane's canvases.

## Notes for whoever drives the UI next

- Debug aids: `-debugHover` hovers items in offscreen renders (`-snapshotTo`), and `-debugKeyLog <file>` also logs
  hover changes. The scratchpad's `ui/` tools refuse any process that isn't "Tasks Dev", post clicks and keys only
  after checking that the scratch app is frontmost and owns the topmost window at the point, and move the pointer via
  HID. Type with HID keys (`key`), not per-process Unicode events.
- Something else on this Mac was sending keystrokes to whatever app was frontmost: while my scratch window was in
  front it received "c", "o", "m" before any event of mine. Name-based window tools can also match the wrong
  "Tasks"; dev builds are "Tasks Dev" now to avoid that.
- Local server for tests and e2e: `wrangler dev` on 127.0.0.1:8791 in the Rex tab "mac: wrangler dev :8791"
  (block `block:01a18c2e-c02d-7c83-b9fa-1aa5cd47c049`), state in the scratchpad.
- `-debugScript "click:X,Y; key:125; snap:/p.png; log:/p.txt; hit:X,Y"` posts events inside the app and renders
  snapshots, for checks while the screen is locked (keys work; first clicks and menu commands need a key window).
- `-debugThenRoute list:<name>` switches 0.8 s after launch, to render the state after a switch.
