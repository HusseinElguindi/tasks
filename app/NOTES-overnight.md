# Overnight notes (macOS app)

Work log for docs/TASK-overnight-mac.md and docs/TASK-interaction-mac.md. In progress; this file is also the resume
point if the session is compacted.

## Done

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
    and brighten on hover, with the list's ••• taking the count's place; rows linger 300 ms after the pointer leaves
    (one hover model per window, so a missed exit can't leave a row looking hovered).
  - Selection is the strong state: `fill-selected` rows, the current sidebar row a `fill-strong` capsule with •••.
  - Icon buttons as in Rex: a rounded-square fill in pane headers, a circular fill for the sidebar toggle (now right
    after the traffic lights), 100 ms; tooltips "Name ⌘X".
  - Collapse/expand: the panes slide over the stationary sidebar (300 ms, decelerating); the traffic lights and toggle
    stay put and the leftmost pane header makes room for them. ⌃⌘S toggles.
  - Gone: the drag grip (whole-row drag instead), the default-list "+", the pinned band behind Today's group labels
    (labels are plain rows now), pressed overlays (presses darken to 86%).
  - Unfocused panes fade their header icons; focus changes take 60 ms. The detail pane's open/close is unchanged.
  - Opening a task no longer moves keyboard focus into an empty notes editor.

## Known bugs (next up)

1. **Keyboard in task lists**: clicking a row selects it, but the table never becomes first responder (the window
   stays first responder), so ↑ ↓, Space and Return do nothing; ⌘-shortcuts from the menu work, and quick add's title
   field doesn't get focus when ⌘N opens it. Removing the List's tap gesture didn't fix it. Suspects: the
   `.contextMenu(forSelectionType:primaryAction:)` / `.itemProvider` combination, or `PaneTableStyle`'s NSTableView
   tweaks. Bisect those, then re-test with the key logger (`-debugKeyLog <file>`).
2. Drag (reorder within a list, drop on a sidebar list, list reorder) not yet re-verified on screen.
3. The detail pane's tap gesture (`DetailPane.swift`) may have the same first-responder problem for its fields.
4. The UI reviewer subagent (reviewing the 2b367c9 code, stopped as stale) was last chasing an exception in one of its
   probes ("this run hung instead of crashing; I'll catch the throw under lldb"). Unknown whether it was the app or its
   probe; reproduce with the current build before assuming either.

## For the user to decide

- Task titles stay `ink` at rest (Rex dims its sidebar titles; dimming every task title would cost the list its
  legibility). Easy to flip if you want Rex's dim-then-brighten on task rows too.
- The default list is shown only by the quick-add list chip now (the sidebar "+" read as stray).

## Notes for whoever drives the UI next

- Something else on this Mac was sending keystrokes to whatever app was frontmost: while my scratch window was in
  front it received "c", "o", "m" before any event of mine. Name-based window tools can also match the wrong
  "Tasks"; dev builds are "Tasks Dev" now to avoid that.
- My UI tools (scratchpad `ui/`) refuse any process that isn't "Tasks Dev", post clicks and keys only after checking
  that the scratch app is frontmost and owns the topmost window at the point, and move the pointer via HID.
- Local server for tests and e2e: `wrangler dev` on 127.0.0.1:8791 in the Rex tab "mac: wrangler dev :8791"
  (block `block:01a18be2-f05e-747c-b5e2-b87cbc1c1e2b`), state in the scratchpad.

## Still to do (TASK-overnight list)

- Fix the known bugs above, re-verify drags and keys on screen.
- Item 2: remaining C5 gaps vs. the A1 boards (light theme pass, empty states, archive).
- Item 3: full test suite, release benchmarks, e2e (`app/Scripts/e2e.sh`, now pointing at "Tasks Dev").
- Item 4: finish this file with install steps for the new Release build.
