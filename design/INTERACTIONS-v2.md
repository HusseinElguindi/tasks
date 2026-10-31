# Tasks — interactions v2 (build spec)

Status: **final, 2026-10-30.** The user reviewed the prototype and made the four open choices
(`docs/TASK-interaction-decisions.md`). This replaces `design/INTERACTIONS.md`.

**Changed after the user tried the app (`docs/TASK-v2-feedback.md`):**

- Item 2: a single click on empty list space no longer adds a task; it clears the selection (or ends an edit). A
  double-click there adds one, as ⌘N does, and the hover "New Task" row is gone. §5, §6, §13, §16, §18.12 and §21 say
  so.
- Item 3: a pane alone in the window shows no focus; the focused look appears only with two panes (§4 Pane focus).
- Item 4: the sidebar's edge and the gap before the detail pane are dividers that resize the panes (§4 Resizing the
  panes).
- Item 5: no flicker on a rename or a drop. The rename field and the label swap in one frame, on the same pixels and at
  the same weight (§7); a dropped copy fades out over its row instead of vanishing while the row fades in (§14).
- Item 6: the detail pane's rows, separator, notes and footer start at the checkbox's left edge and span the width
  (§21 Detail-pane spacing).
- Item 7: dragging a task from one sidebar list to another is continuous. Each row takes half the 2pt gap on either
  side, so the target passes straight from row to row. Anywhere over the sidebar the copy stays a tag and the group
  stays closed up, so a row that takes no drop never snaps the copy back into the list. A drop there cancels, and a
  list's count changes color in the same frame as its row (§14).
- Item 8: Settings ▸ Edit tasks picks what double-click and Return do to a task: open it in the detail pane with the
  caret in its title (the default), or rename it in its row as before (§7 Edit tasks; §2, §4, §5, §15, §17 and §21 say
  so). Lists in the sidebar rename in place either way. In the prototype the strip's "Edit tasks" stands in for Settings.
- Item 9: Settings ▸ Theme (System, Dark, Light, in any order) and the system's own appearance switch the whole window
  in one frame, and the traffic lights stay at their centers through it (§4 Theme, The top band). System follows the
  system appearance as it changes.
- Item 10: Settings ▸ Interface style ▸ Glass shows the desktop through the window: a translucent ground and 88% pane
  fills (§4 Glass). It had changed nothing. The prototype draws Classic only.
- Item 12: the sidebar opens with a brand header, the app's mark and "Tasks", with Today below it (§12 Brand header).

The prototype source matches all eight (item 5's rename part is the app's drawing; the browser has no equivalent).
Items 9 and 10 have no counterpart there: the prototype has no System choice and no Glass, and draws its own window
controls.

**Views (`docs/TASK-design-views.md`):** Upcoming, Undated, Completed and Trash join Today, with the user's picks (§22).
The sidebar (§12) gains their rows, and ⌘1–⌘9 now open the sidebar's first nine rows (§22).

**The prototype is the reference implementation:** https://claude.ai/artifact/EnWEe86TBSG8voqqwbf7uf (press Play on the
main board, then click inside it once so it has the keys). It holds the four views and the v2 boards; the canvas from
before the views is https://claude.ai/artifact/QetdV1H57SC6kLXtNzJRXM. Its source is in `design/prototype-v2/`, and this spec cites
it by line:

- `css:160` is line 160 of `design/prototype-v2/tasks-v2.css`: every color, size, timing and curve.
- `dc:937` is line 937 of `design/prototype-v2/Main.dc.html`: the template is lines 1–254; the logic starts at
  `dc:256` (date helpers, then the component: layout, selection, editing, drag, undo, then
  the view model).

The user approved what the prototype does. If this text and the prototype disagree, the prototype is right; tell the
coordinator so the spec gets fixed.

Rex is the source of truth (`docs/TASK-source-of-truth.md`). Values marked **Rex** were measured
(`design/REX-REFERENCE.md`). The rest are Pane tokens or new decisions, and every difference from Pane is logged in
`design/PANE-UPSTREAM.md`. Values only a Rex measurement can settle are in §20. §21 collects the small details an audit of the spec against the
prototype turned up.

**Not part of the app** (prototype scaffolding): the strip under the window; the Keys panel (`?`); the ⌥N, ⌥T and
⌃1–9 alternates (the browser keeps ⌘N, ⌘T and ⌘1–9); the window's 12pt radius and shadow (`--win-edge`); the drawn
context menus, which stand in for native NSMenus (§15); the canvas's two side boards, which start mid-way through an
add and a date pick.

---

## 1. Decisions

| Area | Built | Not built |
|---|---|---|
| Adding a task | Opens straight in the detail pane, cursor in its title (§6) | The inline row where the task lands; date words read from titles |
| Date picker | Calendar popover: a field, quick picks, the month (§11) | The suggestion list |
| Drag feedback | The rows part to open a gap where the drop lands (§14) | The insertion line |
| Checked tasks | Stay put, then move to Completed 1.5 s after the last check (§8) | Moving when you leave the view |

**What the user called out, so it's a requirement, not polish:**

- **The animations.** Every curve and duration is in §3 (Motion), and each section repeats the ones it uses.
- **The hover states.** §16 lists every control's rest, hover, press and on state.
- **The top band.** The traffic lights, the sidebar toggle, each pane's title and the icon buttons at each pane's top
  right are all centered on one line, y = 25 (§4).
- **The sidebar buttons after the sidebar collapses.** The traffic lights and the toggle stay put, and the list pane's
  header slides its title over to make room for them (§4).
- **The small details generally.** Every value in this spec, down to the 1pt hit-area overlap between rows (§5).

---

## 2. Principles

1. **One gesture, one meaning.** Click selects. Double-click or Return edits the title (a task's in the detail pane or
   in its row, as Settings ▸ Edit tasks says, §7). Drag moves. Right-click opens the menu. Escape cancels or finishes.
   ⌘Z undoes. This holds for tasks and lists alike.
2. **Hover only reveals, and only where something can be clicked.** Task rows never change on hover except that their
   trailing › fades in. Navigation rows (the sidebar) brighten their title, as Rex does. Controls (checkbox, chips,
   icon buttons) answer when the pointer is on *them*.
3. **No confirmations; everything undoes.** Anything that removes items from the view (delete, move, archive, a date
   that takes a task out of Today) says so in a notice with Undo.
4. **Things appear where they'll live.** A new task's row appears at its landing slot while its details open beside
   it. A checked task stays put, then moves (§8). Nothing jumps somewhere you can't see without a notice.
5. **Rex's timing.** Hover is near-instant in, prompt out. Layout changes ride one spring. Switching lists and themes
   never animates. Reduce Motion turns all of it off.
6. **Native where the system can take the theme** (context menus are NSMenus; text fields are real fields); drawn
   only where it can't (rows, chips, the date popover, notices, tooltips, the drag).

---

## 3. Tokens

### Colors

Dark `css:46–61`, light `css:63–78`. The CSS name is
what to search for in the prototype.

| Token | CSS | Dark | Light | Use |
|---|---|---|---|---|
| `surface-ground` | `--ground` | #181818 **Rex** | #F5F5F5 | Window, sidebar |
| `surface-base` | `--base` | #1C1C1C **Rex** | #FFFFFF | Focused pane |
| `surface-dim` | `--dim` | #181818 | #FAFAFA | Unfocused pane; a pane alone in the window |
| `surface-popover` (new) | `--popover` | #262626 | #FFFFFF | Menus, date popover, notices, tooltips |
| `fill-lift` (new) | `--lift` | #2C2C2C | #FFFFFF | The dragged row |
| `line-pane` | `--line-pane` | #323334 | #D4D5D6 | Focused pane's 1pt inset edge |
| `line-pane-dim` | `--line-pane-dim` | #282929 | #EBEBEC | Unfocused pane's edge; a pane alone in the window |
| `line-separator` | `--line-sep` | #363738 | #E7E8E8 | Hairlines; ghost chip ring |
| `line-field` | `--line-field` | #696B6E | #848689 | Checkbox ring |
| `ink` | `--ink` | #E6EDF3 | #1F2328 | Titles, task text |
| `ink-secondary` | `--ink-2` | #A8ADB1 **Rex** | #626568 | Sidebar titles at rest, labels, values |
| `ink-tertiary` | `--ink-3` | #7F8386 **Rex** | #6C6F72 | Group labels, counts, placeholders, untitled rows |
| `ink-quiet` | `--ink-q` | #6D7072 **Rex** | #888A8D | Pane-header icons at rest, strike-through, other months' days |
| `fill-row-selected` (new) | `--sel` | #333333 | #E6E6E8 | Selected task rows, focused pane or a pane alone |
| `fill-row-selected-dim` (new) | `--sel-dim` | #292929 | #EFEFF0 | Selected task rows, unfocused pane |
| `fill-control` | `--fill-control` | #2D2E2E | #EDEDEE | Chips, the date field, a list being renamed, the archive banner |
| `fill-track` | `--fill-track` | #303132 | #E9E9EA | Toolbar icon hover circle, capsule buttons, quick-pick hover |
| `fill-strong` | `--fill-strong` | #444444 **Rex** | #E0E0E1 | Current sidebar row, list tiles (dark) |
| capsule edge | `--edge-outer` / `--edge-inner` | #5E5E5E / #535353 **Rex** | #CFCFD0 / #D6D6D7 | 0.5pt outer + 1pt inner inset on the current sidebar row |
| `hover` (new) | `--hover` | white 7% | #1F2328 6% | Fill behind a hovered icon button, day, ghost chip |
| `press` (new) | `--press` | white 12% | #1F2328 11% | Fill behind a pressed icon button |
| `accent` | `--accent` | #2F81F7 | #0969DA | Checked box, highlighted day, menu highlight, focus rings |
| `accent-text` | `--accent-text` | #5799F6 | #0969DA | Today's date number, links, drop-target text, tinted buttons |
| `accent-tint` | `--accent-tint` | #1E2938 | #E6F0FB | Chip with its popover open, drop target, tinted buttons |
| `on-accent` | `--on-accent` | #FFFFFF | #FFFFFF | Checkmark, highlighted day, highlighted menu item |
| `danger` / `danger-tint` | `--danger` / `--danger-tint` | #FF7B72 / #3C2928 | #CF222E / #FBEBEC | Overdue chip |
| `attention` / `attention-tint` | `--attn` / `--attn-tint` | #D29922 / #352E1D | #9A6700 / #FAF7F2 | Due-today chip; the other date's dot in the calendar |
| `text-selection` | `--text-sel` | accent 45% | accent 25% | Selected text in fields `css:80` |

List colors: a list's tile glyph uses one of the seven ANSI slots (`--ansi-*`). The prototype hands them out in turn
(`dc:418`, `dc:1156`); the app hashes the list id (DIRECTIONS decision 3).

Shadows: `shadow-popover` = a 0.5pt ring of white 14% (dark) / #1F2328 16% (light) plus `0 12 32` black 50% /
#1F2328 16%. `shadow-lift` = the same ring (light: 14%) plus `0 8 24` black 50% / #1F2328 18%
(`css:58`, `css:75`).
`css:57`, `css:74`.

### Type

System font (SF Pro), 13/16 by default `css:25`. Weights and sizes are given with each element below:
group labels 11/14 semibold, chips 11/14 medium, the detail title 15/20 semibold, notes 13/19, the Created line 11/14,
tooltips 11/14. Tiles and inline code use SF Mono. Counts and day numbers use tabular figures.

### Metrics (points)

| Thing | Value | Source |
|---|---|---|
| Row grid | Every row is a 30pt shape on a 32pt pitch **Rex** | `dc:398` |
| Toolbar band | 50 tall. Traffic lights 14pt circles 9 apart, first at (18, 18), so centers x 25, 48, 71, y 25 **Rex** | `css:87–89` |
| Sidebar toggle | 28pt circle at (93, 11), center (107, 25) **Rex**; glyph 16pt | `css:92–95` |
| Sidebar | 230 wide **Rex** by default, 180–400 by its divider (§4); its content starts at y 50: the brand header (34), then Today 6 below it, at y 90 (§12) | `dc:399`, `dc:400` |
| Sidebar row | Capsule x 10–219 (209 wide), 30 tall, radius 15 **Rex**; tile 10 in; title 7 after the tile, nudged up 0.5 **Rex**; count right-aligned 8 from the capsule's right edge | `css:102–105`, `css:107–120` |
| List tile | 20×16, radius 4, 700 10pt mono glyph; dark `fill-strong` with a white 10% 0.5pt ring, light #E3E3E4 with a #1F2328 10% ring. Small (headers, menus): 16×13, radius 3.5, 8.5pt | `css:123–125` |
| Group label | A 32pt slot: 11/14 semibold `ink-tertiary`, 12 in from the row edge, text top 10 **Rex**. Reveal button 22×22, radius 6, 5 from the right, top 6 | `css:131–139` |
| Panes | 8 from the window edges and each other (the list pane starts at x 230 **Rex**); radius 10; 1pt inset edge | `css:142–144`, `dc:401` |
| Pane header | 34 tall from the pane's top, so its contents center on y 25; padding 12 left, 8 right; 8 between items; title 13 medium | `css:145–150` |
| Pane-header icon button | 26×26, radius 6, glyph 14, 2 apart | `css:151–154` |
| Task row | 10 in from the pane's sides, 30 tall, radius 8; the first row 4 below the header (64 in an archived list, under the banner). Padding 10 left, 5 right. Checkbox at 10; title 10 after it, nudged up 0.5, its last 24pt fading out; chips 8 after the title, 6 apart; › 22×22 (radius 6) 4 after the chips, 5 from the right edge, its slot always kept | `css:159–179`, `dc:885` |
| Checkbox | 16 circle, 1.5 ring; check glyph 10, stroke 2.2, round; hit area 30×30 | `css:190–202` |
| Chip | 18 tall, radius 9, padding 7, gap 4, 11/14 medium, icon 11. Large (detail pane): 22 tall, radius 11, padding 9, gap 5, 12pt | `css:205–215` |
| Detail pane | 420 wide by default, 340 and up by its divider (§4); body padding 8 / 18 / 18; title row: checkbox 2 down, 10 to the title (15/20 semibold); property rows 32 tall from 12 below the title, from the checkbox's left edge, label column 81 (the icon centered in the checkbox's 16pt column, the word at 26 with the title's text); the separator, notes and footer span the content width like the title row | `css:253–282` |
| Menu (stand-in) | 216 wide (submenu 204), padding 5, radius 10; items 24 tall, radius 5, padding 9 / 10; separator 1pt inset 9 | `css:306–315` |
| Date popover | 288 wide, padding 8, radius 12; field 28 tall, radius 8; quick picks 22 tall; day cells 28 tall, radius 14 | `css:317–342` |
| Notice | 34 tall, radius 10, 12 from the list pane's bottom-right corner | `css:344–347` |
| Tooltip | padding 4 / 7, radius 6, 11/14 | `css:349–350` |
| Capsule button | 24 tall, padding 12, radius 12, gap 6 | `css:292–296` |

### Motion

The prototype can't run SwiftUI springs, so it samples them into CSS `linear()` curves over their settle time
(`natural`, `layout` and `snappy` below). In the app, use the springs themselves.

| Token | Value | SwiftUI | Used for | Source |
|---|---|---|---|---|
| `hoverIn` | 60 ms, cubic-bezier(0, 0.8, 0.2, 1): ~86% on the first frame **Rex** | `.timingCurve(0, 0.8, 0.2, 1, duration: 0.06)` | Anything appearing because the pointer arrived | `css:14` |
| `hoverOut` | 85 ms, cubic-bezier(0, 0, 0.2, 1), starting the moment the pointer leaves **Rex** | `.timingCurve(0, 0, 0.2, 1, duration: 0.085)` | Anything going because the pointer left | `css:15` |
| `icon` | 100 ms, cubic-bezier(0, 0, 0.2, 1), both ways **Rex** | `.timingCurve(0, 0, 0.2, 1, duration: 0.1)` | Icon-button, chip, day and quick-pick fills; the dimmed details coming back | `css:16` |
| `focus` | 60 ms, cubic-bezier(0, 0, 0.2, 1) **Rex** | `.timingCurve(0, 0, 0.2, 1, duration: 0.06)` | Pane focus: fill, edge, header icons | `css:17` |
| `sidebar` | 300 ms, cubic-bezier(0.16, 1, 0.3, 1) **Rex** | `.timingCurve(0.16, 1, 0.3, 1, duration: 0.3)` | Sidebar show and hide | `css:18` |
| `natural` | **unchanged from v1** | `.smooth(duration: 0.3)` (sampled over 450 ms) | Detail pane open and close | `css:8–9` |
| `layout` (new) | critically damped spring | `.smooth(duration: 0.25)` (sampled over 380 ms) | Every row that moves: reorder, insert, remove, settle, drag gaps, sidebar rows | `css:10–11` |
| `snappy` | slight overshoot (to 1.006) | `.snappy(duration: 0.2)` (sampled over 300 ms) | The checkbox pop | `css:12–13` |
| Fade in | opacity 0 → 1, 180 ms ease-out | `.easeOut(duration: 0.18)` | A row, a Today group label, a list's Completed row or a sidebar row appearing | `css:370`, `css:163` |
| Fade out | opacity → 0, 150 ms ease-out, while `layout` carries it | `.easeOut(duration: 0.15)` | Rows and labels leaving | `css:159–160`, `css:162` |
| Popover in | 120 ms, cubic-bezier(0, 0, 0.2, 1): opacity 0 → 1, y −3 → 0, scale 0.985 → 1 about its center | | Date popover (menus are native) | `css:371`, `css:317` |
| Notice in / out | In: 220 ms, cubic-bezier(0.2, 0.8, 0.2, 1), opacity 0 → 1, y +8 → 0. Out: 160 ms ease-in to opacity 0, y +4 | | Notices | `css:344–346`, `css:373–374` |
| Tooltip in | opacity 0 → 1, 100 ms ease-out; out at once | | Tooltips | `css:349` |
| Drag flight | transform 160 ms, cubic-bezier(0.2, 0.8, 0.2, 1); width and opacity 160 ms ease-out | | The dropped or cancelled copy | `css:243` |
| Instant | no animation | `Transaction(animation: nil)` | Selection, list switches, theme, every press-in except the checkbox's (§8), the first frame | `css:83`, `dc:833–837` |

Reduce Motion: every duration is 0 `css:376–377`. In SwiftUI, read
`accessibilityReduceMotion` and pass `nil` animations.

### Timers

All in `dc:402–416`.

| Constant | Value | What |
|---|---|---|
| `SETTLE_MS` | 1.5 s | Checked rows stay put this long after the last check (§8) |
| `NOTICE_MS` / `NOTICE_INFO_MS` | 5 s / 1.8 s | A notice with Undo / one without a button |
| `NOTICE_REARM_MS` | 2 s | A hovered notice leaves this long after the pointer does |
| `NOTICE_OUT_MS` | 170 ms | The notice's 160 ms exit, then it's gone |
| `TIP_DELAY` / `TIP_WARM_MS` | 600 ms / 600 ms | Tooltips appear after 600 ms, and at once within 600 ms of the last one closing |
| `HINT_HOLD_MS` | 450 ms | Holding ⌘ shows ⌘1–⌘9 in the sidebar |
| `TYPE_SELECT_MS` | 1 s | Type-to-select keeps adding letters typed within this |
| `DETAIL_CLOSE_MS` | 460 ms | The detail pane's exit, then it's removed |
| `FLY_MS` | 170 ms | A dropped copy's 160 ms flight, then the change is written |
| `MOTION_WINDOW_MS` | 240 ms | How long a row keeps its entering or leaving state |
| `DRAG_SLOP` | 4 pt | How far a press moves before it's a drag |
| `SCROLL_EDGE`, `SCROLL_STEP` | 24 pt, 8 pt per 16 ms | Drag autoscroll near the list's top or bottom |

---

## 4. Window, top band and panes

**Layout.** Sidebar (ground) | list pane | detail pane, as A1. Under about 900pt wide the detail pane replaces the list
instead of splitting (A3's drill-in, unchanged; the prototype is a fixed 1180×720 window).

### The top band

Everything in the top 50pt is centered on one line, **y = 25**:

| Item | Geometry | Source |
|---|---|---|
| Traffic lights | 14pt circles at x 18–32, 41–55, 64–78 (centers 25, 48, 71) **Rex** | `css:87–89` |
| Sidebar toggle | 28pt circle, center (107, 25), glyph 16pt in `ink-secondary` **Rex** | `css:92` |
| Each pane's header | 34 tall starting 8 from the window's top, so the title and the icon buttons center on 25 | `css:142`, `css:145` |
| List pane's top right | + (New Task ⌘N) and the split button (Show/Hide Details ⌘D), 26×26, 2 apart, 8 from the pane's edge | `dc:53`, `dc:54` |
| Detail pane's top right | trash (Delete ⌘⌫) and × (Hide Details ⌘D) | `dc:120`, `dc:122` |

So the window controls, the sidebar toggle, the pane titles and the buttons at each pane's top right read as one row.
In AppKit: hidden title bar, and move `standardWindowButton(.closeButton …)` to those centers (v1 already places them
as Rex does, commit 21fbc2f). They stay there through every layout AppKit gives the title bar, an appearance change
included: it shrinks the title bar back to 32pt and leaves the buttons where they were, so they rose to the window's
top edge. They're put back from the title bar's own frame change, before that frame is drawn (v2 feedback 9).

**Theme.** Settings ▸ Theme is System (the default), Dark or Light; System follows the system appearance as it
changes. A switch is instant (§2.5), and everything changes in the same frame to the same scheme: the window's
appearance (the traffic lights, native controls, menus and tooltips) and every drawn surface (rows, the sidebar, the
detail pane, the date popover, notices).

### Hiding and showing the sidebar (⌃⌘S, the toggle)

- The panes' left edge moves from 230 to 8 on `sidebar` (300 ms, cubic-bezier(0.16, 1, 0.3, 1)); the sidebar doesn't
  move and is simply covered `css:142–143`.
- The traffic lights and the toggle stay exactly where they are and now sit over the list pane's header (they're above
  the panes) `css:87`, `css:92`.
- The list pane's header padding grows from 12 to 124 on the same curve, so its tile and title start at window x 132,
  11pt right of the toggle's circle `css:145`, `dc:2608`.
- The toggle's tooltip becomes "Show Sidebar ⌃⌘S". If the sidebar had keyboard focus, the list takes it
  `dc:2409`.
- Showing reverses all of it on the same curve.

### Detail pane: keep v1 exactly

The user likes it. Keep v1's code:

```swift
if let id = window.detailTaskID {
    DetailPane(...).frame(width: 420)
        .transition(.move(edge: .trailing).combined(with: .opacity))
}
// on the HStack:
.animation(PaneMotion.natural, value: window.detailTaskID == nil)   // .smooth(duration: 0.3)
```

The list pane narrows on the same spring while the detail slides in from the right and fades up; closing reverses it.
The prototype copies this: the pane mounts its own width plus 8 to the right (+428 at the default width) and at opacity 0, and two frames later moves to 0 / 1 on `natural`
while the list pane's right edge moves on the same curve; closing runs it backwards and removes the pane after 460 ms
(`css:253–255`, `dc:1020–1034`).

| Trigger | Result |
|---|---|
| ⌘D, the header's split button, a row's › | Show the detail pane (⌘D and the button toggle; the button is `ink-secondary` while it's open) |
| Esc with nothing else to cancel, the pane's × | Hide it |
| Adding a task (§6) | Show it with the new task |
| Double-click or Return on a task with Edit tasks on "Open in detail pane" (§7) | Show it with that task, the caret in its title |
| Selection changes while it's open | It shows the new selection at once (no animation) |
| Several tasks selected | "3 tasks selected" (15/20 semibold), the List, When and Deadline rows that apply to all, "Mixed" where they differ |
| Nothing selected | "No task selected" / "Select a task to see its notes and dates.", 40% down |

Header of the detail pane: the task's list tile (small) and name in `ink-secondary`, regular weight; trash and × at the
right `dc:114–124`.

### Resizing the panes

User feedback (`docs/TASK-v2-feedback.md` item 4). `design/REX-REFERENCE.md` doesn't cover dividers, so this is the
plain native behaviour:

| | |
|---|---|
| Where | The sidebar's edge: 8 wide, centered on the list pane's left edge (while the sidebar shows). The gap between the list and the detail pane: the 8pt gutter itself (while the pane is beside the list). Nothing is drawn. |
| Pointer | The column-resize cursor over a divider; at a limit, the one-way cursor (`NSCursor.columnResize(directions:)`, or `resizeLeft`/`resizeRight` before macOS 15). It stays while dragging. |
| Drag | Resizes at once, no animation; the other panes and their contents follow live. A press there doesn't end an edit or move focus. |
| Limits | Sidebar 180–400; detail pane 340 and up; the list pane never goes under 220 from a divider (a divider stops there, with the other pane as it is). |
| Double-click | Springs back to the default (230 or 420) on `natural`. |
| Remembered | Both widths, across launches. The detail pane opens at its last width, and its open and close (above) work at any width. |
| Window narrower than the widths | The sidebar keeps its width; the detail pane gives way down to 340 so the list keeps 220; below that, or under 900 wide, the window is narrow (the detail pane replaces the list). |

The prototype draws the dividers as `.pdiv` (`.lim-l`/`.lim-r` at a limit), keeps the widths in `localStorage`, and
switches the panes' transitions off while dragging (`.resizing`) and to `natural` for a double-click (`.springback`); its
`.dp.out` slides by its own width plus 8. Source: `Main.dc.html` after the view model ("Dividers"), the CSS at the end
of `tasks-v2.css`.

### Pane focus (Rex's rule)

The pane you last pressed in (on mouse-down) or moved to with the keys is focused. Focused: `surface-base` and a 1pt
inset `line-pane` edge. Unfocused: `surface-dim`, `line-pane-dim`, header icons at 55% opacity, title in
`ink-secondary`. Fill, edge and icon opacity change on `focus` (60 ms); the title's color switches at once
(`css:142–150`). Pressing the sidebar focuses the sidebar, and both panes
show unfocused; the sidebar has no focus look of its own. Selected rows in an unfocused pane use
`fill-row-selected-dim`.

**Only with two panes** (user feedback, `docs/TASK-v2-feedback.md` item 3). A pane alone in the window (the list with
the detail pane closed, or the narrow window's detail pane) shows no focus, whatever has the keys: `surface-dim` and
`line-pane-dim`, header icons at 100% and the title in `ink`, selected rows in `fill-row-selected`. With both panes
open the rule above applies. Becoming or ceasing to be the only pane rides the detail pane's open and close: the fill,
edge, icons and title change on `natural` while the pane slides (in the prototype the list pane takes `.swap` for the
460 ms of the move); selected rows switch at once, as they always do (`css:144`, `css:149–150`, `css:183`, `dc:1024`,
`dc:1030`, `dc:2606`).

### Glass (Settings ▸ Interface style)

Settings ▸ Appearance ▸ **Interface style** is Pane's Classic / Glass choice, kept per Mac in UserDefaults
(`interfaceStyle`: `classic` or `glass`, the default `classic`). Classic is everything above: an opaque ground and
opaque panes. In Glass the window shows what's behind it (v2 feedback 10):

- **The ground** (under the sidebar, the gutters and the top band) is the sidebar material blending behind the window,
  in the theme's appearance, with `surface-ground` over it at 60%. The desktop shows through, blurred, while the
  ground keeps its color, so the sidebar's tokens and contrast hold. It stays translucent when the window isn't key.
- **The panes** keep `surface-base` / `surface-dim` at 88% (DIRECTIONS: 84–90% keeps `ink-secondary` legible), so a
  little of the glass shows through them. Their edges, rows, chips, popovers and the lifted copy stay opaque.
- **Hiding the sidebar** also fades it out on the same curve, since the panes would otherwise show it through their
  fills. Showing it fades it back in. In Classic it's simply covered, as above.
- The choice applies at once, with no animation, like the theme.

The prototype has no interface-style switch; it draws Classic.

---

## 5. Selection and moving around

**Mouse.** Selection happens on mouse-down (`dc:1780–1798`).

| Gesture | Result |
|---|---|
| Click a row | Select only it; the list takes focus |
| ⌘-click | Add or remove it; it becomes the anchor |
| ⇧-click | Select the range from the anchor, in visual order |
| Click a row that's part of a multi-selection | Nothing until mouse-up (so the selection can be dragged); then select only it |
| Click empty space below the rows | Clear the selection, as in Rex and Finder (in a list and in Today). With something being edited, the first press only ends that edit: a new task is written, or dropped if it has no title. It never starts a task `dc:1848–1852` |
| Double-click empty space below the rows | Add a task, exactly as ⌘N does (§6) `dc:1853–1861` |
| Click a checkbox | Completes that row; the selection doesn't change |
| Click a chip | Selects the row if it wasn't selected, then opens its date popover (for the whole selection if the row was in it) `dc:1839–1845` |
| Click › | Selects only that row and shows the details `dc:1846` |

**Look.** A selected row fills with `fill-row-selected` at radius 8 (`fill-row-selected-dim` when its pane isn't
focused and isn't alone, §4). Adjacent selected rows join into one block: the inner corners go square and the 2pt gap between them is
filled (`css:182–186`, `dc:2569–2573`). Selection
never animates. Task titles stay `ink` at rest and selected.

**The rows' hit area** reaches 1pt above and below each row, so the 2pt gaps belong to a row and the pointer never
falls between two (no hover flicker) `css:187`.

**Keys** (list focused, not editing) `dc:1629–1719`:

| Key | Result |
|---|---|
| ↑ ↓ | Previous / next row (the first or last when nothing is selected) |
| ⇧↑ ⇧↓ | Extend from the anchor |
| ⌘↑ ⌘↓, Home, End | First / last row (⇧ extends) |
| Page Up, Page Down | Scroll the list a page (its height less one row); the selection stays, as in NSTableView `dc:1699` |
| ⌘A | All open tasks in the view |
| Letters and digits | Type-to-select: the first title starting with what was typed within the last second `dc:1738–1750` |
| Return | Edit the selected task (one selected) as Settings ▸ Edit tasks says: in the detail pane, or renamed in its row (§7); with nothing selected, select the first row |
| ← | Focus the sidebar |
| Tab / ⇧Tab | Next pane: list → details (when open) → sidebar → list. ⇧Tab: list → sidebar, details → list |
| Esc | Close the date popover, else hide the detail pane, else clear the selection |

The selected row scrolls into view, ending 8pt below the top or 12pt above the bottom of the list
(`dc:997–1003`). Sidebar keys are in §12.

---

## 6. Adding a task: it opens in the detail pane

### Triggers

| Where you are | Trigger | The new task goes |
|---|---|---|
| A list | ⌘N; the header's + | That list, at the bottom of its open tasks (SPEC §3: new tasks append) |
| A list or Today | Double-clicking the empty space under the rows | As ⌘N (its first press has already cleared the selection, so in Today the task goes to the default list). A single press never adds |
| An empty list | ⌘N, +, or double-clicking anywhere in the pane: the empty space is the whole pane, and the empty state says "Double-click anywhere here or press ⌘N to add one." | The first slot |
| An archived list | As a list (SPEC §2: nothing is read-only) | That list |
| Today | ⌘N; the header's + | The selected task's list if a task is selected, else the default list (the first active list, SPEC §2); **When = today**. It lands at the bottom of that list's Today group; if the group wasn't showing, its label fades in above it |
| Today | A group label's + (revealed on hover) | That list, When = today |
| The sidebar | A list's context menu → "New Task in School" | Opens School, then as a list |
| The sidebar focused | ⌘N | As the open view |
| No active lists | ⌘N | Nothing is added; notice "Create a list first: ⇧⌘N" (1.8 s, no button) |

The header +'s tooltip names the target in Today: "New Task in Inbox ⌘N" `dc:2613`. That is the
discoverable mark of the default list; the sidebar carries none.

Source: `dc:1114–1151`, `dc:1853–1861`, `dc:1863`.

**No ghost row.** Hovering the empty space under the rows shows nothing: since a single click there never adds a
task, there's no "New Task" row to advertise one (v2 feedback 2; `dc:66–70`, `css:218–223` record the removal).

### What happens (one frame)

1. A **draft** is made: it isn't written yet (no op, no undo step).
2. Its row appears at the landing slot, fading in over 180 ms while the rows below it (and the Completed row) move down
   on `layout`, and scrolls into view. The row is selected; its title reads "New Task" in `ink-tertiary` until there is
   one; its checkbox is a placeholder ring (`ink-quiet` at 70%, ignoring the pointer) until the task is written
   (`css:169`, `css:201–202`).
3. The detail pane opens on `natural` (v1's transition) if it was closed; if it was open it switches to the draft at
   once.
4. The detail pane takes focus (so the list pane shows unfocused and the draft's row uses `fill-row-selected-dim`), and
   the caret is in its empty title, placeholder "New Task" (`dc:815–829`).
5. **While the title is empty**, everything under it is dimmed to 45% and ignores the pointer: List, When, Deadline,
   the separator, Notes and the Created line, and also the pane's checkbox and trash button. Pressing anywhere in the
   pane but its × leaves the caret in the title. The first character brings the sections back to 100% on `icon`
   (100 ms) and the trash at once; the checkbox stays a placeholder ring, still ignoring the pointer, until the task is
   written (`css:285–286`, `dc:2650`).
6. The row shows the title as it's typed (`dc:1898–1906`).

### Keys in the title

`dc:1910–1922`, and for the menu commands `dc:1648–1668`.

| Key | With a title | Still empty |
|---|---|---|
| Return, Tab | Writes the task and moves the caret to the notes (empty, editing) | Drops it |
| Esc | Writes it. The keys go back to the list with the new task selected; the pane stays open (Esc again closes it) | Drops it |
| ⇧Tab, ⌘Return | As Esc | Drops it |
| ⌘N | Writes it and starts the next one in the same place | Nothing new: the caret stays in this title |
| ⌘S, ⇧⌘D | Writes it and opens the date popover under the detail pane's When / Deadline chip | Nothing |
| ⌘T, ⌘K, ⇧⌘M | Writes it, then When: Today / Complete / Move to… | Nothing |
| ⌘D | Writes it and hides the pane | Drops it and hides the pane |
| ⌘1–⌘9 | Writes it and goes to that view | Drops it and goes |
| ⇧⌘N | Writes it and starts a new list | Drops it and starts a new list |
| ⌃⌘S | Hides or shows the sidebar; the caret stays | The same |

### The pointer while adding

| Press | With a title | Still empty |
|---|---|---|
| Anywhere in the detail pane but its × (the title, the dimmed rows, the header) | Normal editing | The caret stays in the title |
| Another row | Writes it; that row is selected (and shown in the pane) | Drops it; that row is selected; the pane closes if the add opened it |
| The empty space under the list | Writes it (the first press only ends the edit) | Drops it (the first press only ends the edit) |
| The header + | Writes it and starts another | The caret goes back to the title (no second draft) |
| A Today group's + | Writes it and starts another in that group | The draft moves to that group; the caret stays |
| Anything else (sidebar, another view, the pane's ×) | Writes it, then does that | Drops it, then does that |

`dc:1595–1608` decides which presses keep the caret.

### Dropping an untitled task

No op, no undo step, no notice. The selection goes back to what it was before ⌘N, unless the press that dropped it
selected something else. The detail pane closes again if the add opened it; otherwise it shows that selection. The
list gets the keys (`dc:1097–1108`).

### Writing it

One `task.create` when the title commits: the trimmed title, the list, `order = keyBetween(last, nil)`, and When =
today if it was added from Today (`dc:1059–1069`).
Its checkbox becomes a normal one. Undo ("Undo New Task") removes it and restores the selection from before ⌘N; notes
typed afterwards are their own step ("Edit Notes"). Drafts never enter the undo history (`dc:853`).

---

## 7. Editing

### Edit tasks (Settings)

Settings (⌘,) ▸ Behavior ▸ **Edit tasks**, a pop-up with two choices, decides what these do to a task (v2 feedback 8):
double-clicking its row, Return on it (one task selected, with the list or the detail pane focused) and Rename in its
context menu. It's kept with the other settings in UserDefaults (`taskEditing`: `detail` or `inline`), never in the sync
log, and applies at once. The row's description says what the choice does. Source: `dc:2847–2867` (the prototype's
strip stands in for Settings).

| Choice | Result |
|---|---|
| **Open in detail pane** (the default) | The task is selected and shown in the detail pane (which opens as it does for ›), the pane takes focus and the caret goes to the end of its title (§7 The detail title). If the pane already shows that task, only the title takes the caret. Nothing edits in the list |
| **Rename in the list** | The title is renamed in place in its row (below) |

The same in both: the › and ⌘D show the details without the caret; ⌘N, + and a double-click on empty space add a task
(§6); lists in the sidebar rename in place; a double-click on a completed task only selects it (Return and › still
work).

### Task titles in rows ("Rename in the list"), and list names

| Trigger | Caret |
|---|---|
| Double-click a title | Where you clicked |
| Double-click the rest of a row | At the end |
| Return on the selected task (list focused) or list (sidebar focused) | Whole title selected |
| Rename in the context menu | Whole title selected |

The field replaces the title in place, in the same font, origin and color, and in the same frame: the title hides and
the field draws in one Core Animation transaction, never a frame with neither or both. Its text lands on the title's
pixels at the same weight (the labels are `CATextLayer`s, which draw without font smoothing, so the field's editor
draws without it too; AppKit's default editor drew the title visibly bolder while renaming, v2 feedback 5). The row is
always selected while it's renamed,
so it keeps `fill-row-selected` and adds a 1.5pt inset `accent` ring at radius 8; the › is hidden
(`css:165`, `css:182`: the `.row.editing` fill never shows, because the selection
rule comes later); a list row in the sidebar gets `fill-control` with the same ring
(`css:119`). Return, Tab or a press elsewhere commits (one `task.update` / `list.update`, only if it
changed). Esc restores the old text. A list name can't be empty: committing an empty name keeps the old one. Pressing
inside the field moves the caret and never ends the edit (Rex fixed the same bug, preview.12). Double-click doesn't
rename a completed task; Return and the detail pane still do. While a new or renamed list's name is typed, its tile's
letter follows it (`dc:2699`). Source: `dc:1813–1826`,
`dc:1879–1887`, `dc:1050–1086`.

### The detail title (an existing task)

Always an editable field: no ring, the caret is the cue; 15/20 semibold `ink`, wrapping and growing with its text
(`css:259`). Pasted line breaks become spaces.

| Key | Result |
|---|---|
| Return, Tab | Commit, caret to the notes |
| Esc | Put the old title back; the keys go to the list |
| ⇧Tab, ⌘Return | Commit; the keys go to the list |
| A press elsewhere | Commit |

An existing task's row updates when the title commits (only a new task's row follows each keystroke).

### Notes

**Replaced by `design/MARKDOWN.md`** (Markdown notes, final 2026-10-31, built): one always-editable view of the
Markdown source, rendered in place, with the marks showing faintly only near the caret; checklists with square boxes
that toggle `[ ]` / `[x]` in the text; a hint after a row's title (the notes glyph, or "2/5"); links open on a plain
click; no link shortcut, so ⌘K completes everywhere. `design/prototype-v2/` carries the same editor, merged from
`design/prototype-markdown/` (whose lines MARKDOWN.md cites) with `markdown.css` beside `tasks-v2.css`. What stays
from here:

| Key | Result |
|---|---|
| ⇧Tab (outside a list) | Commit, back to the title with its text selected |
| Esc, ⌘Return | Done: keeps the text (notes are long; Esc never throws them away); the keys go to the list |
| A press elsewhere | Commit |

One `task.update` per editing session. The footer is "Created Oct 26" (and " · Completed Oct 30"), 11/14
`ink-tertiary`, 14 below the notes, plus " · 19,412 / 20,000" from 18,000 characters.

---

## 8. Completing

**Checkbox** (16pt circle, 1.5pt inset ring in `line-field`, hit area 30×30) `css:190–199`:

| State | Look | Timing |
|---|---|---|
| Hover (on the box) | Ring → `ink-secondary` | `hoverIn` / `hoverOut` |
| Pressed | Scales to 0.86 | 80 ms ease-out in; back on `snappy` (300 ms) when released |
| Checked | Fill and ring `accent`; the check (10pt, stroke 2.2, round) draws in `on-accent`; the box pops from 0.8 | Fill 160 ms ease-out; the stroke draws 0 → 100% in 160 ms ease-out after 40 ms; the pop on `snappy` |
| Unchecked | The same, backwards, and the box pops from 0.8 again | Same |
| Checked row | Title → `ink-tertiary` with a strike in `ink-quiet` | Color 200 ms ease-out; the strike is instant (`css:171`) |

Triggers: click the box, Space or ⌘K on the selection (a mixed selection completes all; an all-done selection
uncompletes), the context menu, the box in the detail pane (`dc:1162–1179`).

**Checked rows stay put, then move.** A checked row stays checked in its place until **1.5 s** pass with no further
checks; each check restarts the wait, so you can check a run of tasks or undo a misclick by clicking again. Then every
waiting row moves together on `layout`: in a list it slides down into the Completed row while fading out (150 ms) and the
Completed count ticks up; in Today it slides into the Completed group at the bottom. Leaving the view settles them at
once. Unchecking mirrors it: the row stays in the completed area, then slides back to its old place (its order key never
changed, SPEC §3). Implementation: a `pins` map holds checked and unchecked tasks where they were
(`dc:847`); the timer clears it (`dc:1179`); a leaving row is carried to the Completed row
(`dc:2495–2520`).

**Where done rows go.**

- A list ends with a disclosure row, "› Completed 23": one empty slot plus 8pt below the last open task, its chevron 12 in from the row's left edge, `ink-
  secondary`, "Completed" in medium, the count in `ink-tertiary`. It brightens to `ink` on hover (`hoverIn`/`hoverOut`),
  fades in when the first task is completed, and its chevron turns 90° in 200 ms ease-out. Collapsed by default;
  expanded, it lists the done tasks newest first (`css:226–231`, `dc:896–899`).
- Today ends with a "Completed" group (a group label like the others, 8pt further down) holding tasks completed today,
  oldest first, each with its list's name at the right in 12pt `ink-tertiary` (`css:172`).

---

## 9. Deleting, undo and notices

**Delete**: ⌘⌫, "Delete" in the context menu, the detail pane's trash. All selected tasks go at once, with no
confirmation. Rows fade out (150 ms) while the rest close up on `layout`. The selection moves to the next row below,
else above, so repeated ⌘⌫ walks down the list like Mail; if nothing is left to select, the detail pane closes
(`dc:1190–1199`, `dc:1180–1189`).

**Notice.** An action that takes items out of the view says so at the bottom-right of the list pane: "Deleted “Buy
milk”" (titles over 28 characters end in …), "Deleted 3 tasks", "Moved to School", "Moved 3 tasks to School", "Archived
School", "Scheduled for Fri, Nov 6", "Due Fri, Nov 6", "Removed from Today" (the last three only when a date takes a task
out of Today).

| Part | Value |
|---|---|
| Box | 34 tall, `surface-popover`, `shadow-popover`, radius 10, padding 12 left / 5 right, 10 between text and button, one line |
| Undo button | A tinted capsule (`accent-tint`, `accent-text`, 24 tall, padding 12, radius 12) reading "Undo ⌘Z", the keys in 12pt `ink-tertiary`; hover brightness 1.12 (light 0.97), press 0.86 at once |
| In / out | In: 220 ms, cubic-bezier(0.2, 0.8, 0.2, 1), rising 8 and fading in. Out: 160 ms ease-in, sinking 4 and fading |
| Life | 5 s with Undo, 1.8 s without. Hovering holds it; it leaves 2 s after the pointer does |
| A new notice | Replaces the text in place (no second entrance) |

Source: `css:344–347`, `dc:1292–1296`,
`dc:1297–1302`, `dc:106–109`.

**Undo.** ⌘Z / ⇧⌘Z undo and redo every change as new ops (SPEC §6), with these action names so the Edit menu reads
"Undo Delete", "Redo Move": New Task, Rename Task, Edit Notes, Complete / Complete 3 Tasks / Mark Not Done, Delete /
Delete 3 Tasks, Move / Move 3 Tasks, Set When / Remove When / Set Deadline / Remove Deadline, New List, Rename List,
Move List, Archive List, Unarchive List. After an undo or redo the app goes back to the view where the change was made (at once, if it's
another view), selects what was selected just before the change (for a redo, what was selected at the undo), and
scrolls it into view. A notice without a button confirms it ("Undo Delete",
1.8 s). The notice's Undo is the same as ⌘Z. Inside a text field ⌘Z is the field's own undo
(`dc:860–872`, `dc:872–880`, `dc:1646`).

---

## 10. Moving between lists

| Trigger | Notes |
|---|---|
| Drag onto a sidebar list | §14 |
| Drag onto Today | Sets When = today (the task stays in its list) |
| ⇧⌘M | Pops the "Move to" menu under the first selected row (34 in from its left, 2 below it): a header 'Move “Buy milk” to' or 'Move 3 tasks to', every active list with its tile and ⌘1–⌘9, the current list checked and disabled, the first other list highlighted (`dc:1362–1371`) |
| Context menu → Move to ▸ | The same list, as a submenu |
| Detail pane → List pop-up | The same list, under the pop-up (`dc:1372–1378`) |

Moved tasks land at the bottom of the target (SPEC §3). In a list view they leave (fade, close up, selection moves on)
with the notice "Moved to School". In Today they stay visible, regrouped, with no notice. Archived lists are never
offered (`dc:1200–1210`).

---

## 11. Dates

### How chips read (rows)

`dc:291–297`, `dc:298–305`

| Date | When chip (calendar icon) | Deadline chip (flag icon) |
|---|---|---|
| Past | "Today" (a past When carries forward, SPEC §4) | "Overdue · 2d", `danger` on `danger-tint` |
| Today | "Today" | "Due today", `attention` on `attention-tint` |
| Tomorrow | "Tomorrow" | "Tomorrow" |
| 2–6 days | "Mon" | "Mon" |
| Later this year | "Nov 9" | "Nov 9" |
| Another year | "Jan 4, 2027" | "Jan 4, 2027" |

When comes before Deadline. In Today a When on or before today is left out (it's why the task is there). Done rows show
no chips. Neutral chips are `fill-control` with `ink-secondary` text. A chip is a button: hover brightens it
(brightness 1.18 dark, 0.96 light, on `icon`), press darkens it to 0.86 at once, and while its popover is open it's
`accent-tint` with `accent-text` (`css:205–212`).

**Detail pane rows** (List, When, Deadline): 32 tall, an icon and label in `ink-secondary` in a 76pt column, then the
value (`css:261–274`, `dc:2632–2637`).

- **List**: a pop-up button (tile, name, ⌃⌄ in `ink-tertiary`), 22 tall, radius 6; `hover` fill, `press` fill at once.
- **A set date**: a large chip with the full date ("Fri, Nov 6"), then the relative date in 12pt `ink-tertiary` ("in 7
  days", "2 days ago", "today"). Hovering the row reveals a × (Remove When / Remove Deadline, 22×22, radius 6) in the
  slot 2pt after the chip, in on `hoverIn`, out on `hoverOut`; its own hover is the `hover` fill with `ink-secondary`.
- **No date**: a ghost chip "Add date": transparent, a 1pt `line-separator` ring, `ink-tertiary`; hover gives it the
  `hover` fill and `ink-secondary`. "Mixed" when several tasks differ.

### Opening the popover

Click a chip (row or detail pane), ⌘S (When…) or ⇧⌘D (Deadline…) on the selection, or "Choose Date…" in the context
menu. It applies to every selected task. It hangs 6pt under its anchor, left-aligned with it and kept 8pt inside the
window, and flips above the anchor when it wouldn't fit. The anchor is the chip that was clicked; from the keyboard it's
the detail pane's chip when the focused detail pane shows those tasks, else the row's chip, else the row's right end
(`dc:1400–1412`, `dc:1413–1423`). It opens on
"Popover in" (120 ms). The field has the keys and is empty; the highlighted day starts at the current date, or today.
Pressing outside closes it and does nothing else (the press doesn't reach what's under it; Rex, preview.18). Setting a
date closes it and gives the keys back to the window; the focused pane stays as it was (from the detail pane's chip,
the detail pane).

Quick sets without the popover: ⌘T (When: Today); the context menu's When ▸ Today / Tomorrow / This Weekend / Next
Week / Remove, and Deadline ▸ Remove.

### The popover (288pt)

`dc:199–207`, `css:317–342`, the view model
`dc:2735–2751`.

Top to bottom:

1. **The field**: 28 tall, `fill-control`, radius 8, a calendar icon in `ink-tertiary`, 7 to the text. Placeholder
   "When: try tom, fri, 3d, nov 9" or "Deadline: try fri, nov 9, 2w".
2. **Quick picks**, 8 below: Today · Tomorrow · Next Week, and Clear (in `ink-secondary`) when the tasks have a date.
   22pt capsules, `fill-control`, 12pt `ink`, 6 apart. Hover: `fill-track`, brightened 1.12 (`icon`). The pick that
   matches what's typed is tinted `accent-tint` / `accent-text`.
3. **The month**: "November 2026" in semibold, with ‹ › buttons (22×22, radius 6, `ink-secondary`; hover `hover` fill
   and `ink`); they keep the keys in the field.
4. **The grid**: a weekday row (10/12 semibold `ink-tertiary`, 20 tall), then six weeks of 28pt day capsules, 2pt
   apart, 12pt tabular. The week starts on the locale's first day (the prototype: Sunday).
   - Hover: `hover` fill (`icon`).
   - Days outside the month: `ink-quiet`.
   - Today: `accent-text` semibold.
   - The current date: a 1.5pt inset `accent` ring.
   - The *other* date (the deadline while picking When, and the reverse): a 4pt `attention` dot, 3pt from the bottom.
   - The highlighted day: `accent` fill, `on-accent` semibold, no ring.
5. **The footer**, under a `line-separator` hairline (6 above it, 8 inside): what Return sets, "Fri, Nov 6 · in 7 days"
   in `ink` with a ↩ glyph in 11pt `ink-tertiary` at the right; or "No date matches “xyz”" in `ink-tertiary`.

Behavior (`dc:2439–2448`, `dc:2449–2461`):

- Typing moves the highlighted day (and the month) to the text's meaning: the exact reading of the whole text, else the
  first of Today, Tomorrow, This Weekend, Next Week, Next Month, Monday … Sunday that starts with it ("th" → Thursday,
  "next" → Next Week) (`dc:388–395`). Clearing the field puts it back.
- ← → move it a day, ↑ ↓ a week. The field never needs its caret keys.
- Return sets the highlighted day; nothing when there's no match. Clicking a day or a quick pick sets it.
- ⌫ in the empty field clears the date. Esc closes.

### Typed dates

Calendar dates only (SPEC §2). Today is the Mac's local date. `dc:342–383`

| You type | Result |
|---|---|
| `tod`, `today`, `now` | Today |
| `tom`, `tmr`, `tmrw`, `tomorrow` (and partials like `tomo`) | Tomorrow |
| `mon` … `sun`, full names, unique prefixes (`th`, `we`) | The next one after today (on a Friday, "fri" is next Friday) |
| `next fri` | Friday of next week (weeks start Monday) |
| `weekend`, `this weekend` | Saturday (today if it's the weekend) |
| `next weekend` | Saturday of the weekend after this one; on a Saturday or Sunday, the coming Saturday |
| `next week` | Next Monday |
| `next month` | The 1st of next month |
| `3d`, `3 days`, `in 3 days`, `2w`, `in 2 weeks`, `1m`, `a month`, `1y`, `+5` | Relative |
| `nov 9`, `9 nov`, `november 9th`, `11/9`, `2026-11-09`, with an optional year | That date; without a year, the next one that isn't past |
| `9`, `9th`, `the 9th` | The next 9th of a month |
| `yesterday` | Yesterday (allowed; deadlines can be past) |

Numeric dates follow the user's locale order in the app (the prototype reads M/D).

### Clearing

Clear in the popover, ⌫ in its empty field, the × beside a detail-pane chip, the context menu's Remove.

---

## 12. Lists and the sidebar

**Sidebar rows** (Today, lists, archived lists) `css:107–120`, `dc:2676–2692`:

| State | Look |
|---|---|
| Rest | Title `ink-secondary` **Rex**; count `ink-tertiary`, tabular |
| Hover | Title → `ink` (`hoverIn`, out on `hoverOut`). No fill, no trailing action |
| Current | `fill-strong` capsule with the two-step edge, title `ink`, count `ink-secondary` **Rex** |
| Archived | Title `ink-tertiary`, `ink` on hover or when current; no count |
| Drop target (a task drag) | `accent-tint` fill, 2pt inset `accent` ring, title and count `accent-text` |
| Being renamed | `fill-control`, 1.5pt inset `accent` ring, the name as a field in place |
| Holding ⌘ (450 ms) | Counts give way to ⌘1–⌘9 on the sidebar's first nine rows (Today, Upcoming, Undated, then lists; §22) in 12pt `ink-secondary` (Rex, preview.16); any key or letting go hides them |

Pressing a row opens it on mouse-down (instantly) and focuses the sidebar. Counts are open tasks (Today: open tasks in
Today). Long names fade out over 16pt before the count instead of an ellipsis (Rex) `css:112`.

**Layout**: the brand header, Today 6 below it, Upcoming and Undated, the "Lists" label, the active lists, then 8pt and
Completed and Trash (§22), then 8pt and the "Archive" label when anything is archived (`dc:952–977`).

**Brand header** (v2 feedback 12; the logo canvas's "Sidebar header" board, `design/logo/Sheet.dc.html` ~168)
`dc:22`, `dc:400`, `dc:955`, `css:396–411`:

- A 34pt row at the top of the sidebar's content, inset 10 like the rows.
- The bare 04 · Log mark at 18pt, 10 in.
- 8 after the mark, "Tasks" in 13/16 semibold `ink`.

The mark is the icon's small cut (`design/logo/final/gen.py`: the rings are dots and the strokes are thicker); the full
cut's rings and check are hairlines at 18pt. It's drawn as vectors.

| Sidebar | Head | Head's bar | Rings | Trail |
|---|---|---|---|---|
| Dark | `#2F81F7` | `#E6EDF3` | `#A8ADB1` | `#6D7072` |
| Light | `#0969DA` | `#1F2328` | `#626568` | `#A9ACAF` |

The dark colours are the icon's own. The light ones are the variant the mark was designed with, since the icon itself
is dark only. In both, the check is cut out of the head.

It's a label. It has no hover, and a press there is a press on the sidebar's empty space. It scrolls with the sidebar's
content, and when the sidebar collapses the panes cover it with everything else; it never moves into the top band.

**Group labels.** "Lists" reveals a + (New List ⇧⌘N) on hover. "Archive" reveals a chevron, and pressing the label
toggles the group (collapsed by default; the chevron turns 90° in 200 ms ease-out and stays shown while open). The
reveal is in on `hoverIn`, out on `hoverOut`; the button's own hover is the `hover` fill with `ink-secondary`, its press
the `press` fill at once (`css:133–139`). Labels never take selection.

**Sidebar keys** (sidebar focused) `dc:1721–1736`: ↑ ↓ open the previous / next row; letters
type-select by name; Return renames; ⌥⌘↑ ⌥⌘↓ move the list; ⌘⌫ archives it; → Tab ⇧Tab Esc go back to the list. Anywhere: ⌘1–⌘9
open the sidebar's first nine rows (§22).

**Create**: ⇧⌘N, the "Lists" +, or the menu on the sidebar's empty space. A row appears at the bottom of Lists in the
renaming state with the placeholder "New List" and a tile in the next color whose letter follows the typing. Return or
a press elsewhere creates it (one `list.create`) and opens it at once, with the list focused so ⌘N adds its first task;
Esc or an empty name cancels and writes nothing (`dc:1152–1158`).

**Rename**: double-click (Rex, preview.15), Return, or Rename in the menu (inline here; Rex sends menu renames to its
palette, which Tasks doesn't have).

**Reorder**: drag (§14), ⌥⌘↑ ⌥⌘↓, or Move Up / Move Down in the menu (Rex has the same pair for sessions). Today and
archived lists don't move.

**Archive**: Archive in the menu or ⌘⌫ with the sidebar focused. No confirmation. The row fades as the rows below close
up; if it was open, the first active list opens (Today if none). Notice "Archived School". The Archive group appears
when the first list is archived (`dc:1260–1271`).

**The archive view.** Archived lists sit in the collapsible Archive group at the bottom of the sidebar, newest first.
One opens as a normal list pane, header "School  Archived", with a banner on top: archive icon, "Archived Oct 28 · Not
in Today or Move to. Everything still edits." and a tinted **Unarchive** button (banner: `fill-control`, radius 8,
padding 9 / 10 / 9 / 12, 6 from the header; `css:287–289`). Rows start 64 below the header.
Unarchive (or Unarchive in its menu, or ⌘Z right after) puts it back in its old place in Lists (SPEC §2). An empty
archived list shows no empty state.

---

## 13. Today

- Groups follow sidebar order; each starts with its list's name as a group label in a 32pt slot; rows keep their list's
  order (SPEC §4) (`dc:883–927`). A group label's + adds a task to that list for today (§6). Labels fade
  in and out with their first and last rows (`css:234–237`).
- Drag reorders within a group only; the row can't leave its group (§14). Dropping on a sidebar list moves the task and
  it regroups; dropping on Today does nothing new.
- A date change that takes a task out of Today (⌘S → "tom") fades it out and shows "Scheduled for Sat, Oct 31" with
  Undo (`dc:1211–1222`).
- **Empty states**, centered, never clickable; title 13 medium `ink-secondary`, text 12/16 `ink-tertiary` (at most
  280 wide), 6 apart (`css:299–303`, `dc:2596–2600`):
  - Nothing today: a sun glyph (22pt, `ink-quiet`), "Nothing for today", "Tasks you plan for today, or that are due,
    show up here." 34% down.
  - All done (only completed tasks today): a check-circle in `accent`, "All done for today", 40 below the header, with
    the Completed group under it from y 132.
  - An empty list: "No tasks" and "Double-click anywhere here or press ⌘N to add one.", 34% down.

---

## 14. Drag

One model for task rows and sidebar lists. **No grip; the whole row is the handle.** The rows part to open a gap where
the drop will land; there is no insertion line. Source: `dc:1447–1462`,
`dc:1463–1500`, `dc:1512–1547`, `dc:929–950`, `dc:2869–2876`,
`css:240–250`.

| Phase | Behavior |
|---|---|
| Press | Selects (§5). Nothing lifts yet |
| Move 4pt | Lift: a copy of the row (the grabbed row, for a multi-selection) follows the pointer, keeping the grab offset: `fill-lift`, radius 8, `shadow-lift`, the checkbox ring, title and chips (chips on #3A3A3A in dark). The rows being dragged leave their places (hidden). Several tasks: an `accent` badge with the count, 18 tall, 11 semibold `on-accent`, 7pt past the copy's top-right corner. Tooltips, menus and popovers close |
| Over the list | The other rows in the group part on `layout` to open a gap (as many slots as rows dragged) at the target. The target is the nearest slot to the copy. The copy stays inside its group: it stops 6pt past the first and last slot (a list's open tasks; one Today group) |
| Near the top or bottom (24pt) | The list scrolls 8pt every 16 ms |
| Over the sidebar | The gap closes and everything below the group moves up (the rows are leaving). The copy becomes a compact tag, 210 wide (width on 160 ms ease-out) at the pointer +12, +8, so the target stays readable. It stays a tag, and the group stays closed, anywhere over the sidebar, on a target or not. The row under the pointer shows the drop-target state if it takes the drop. Each row's hit area takes half the 2pt gap on either side, so the state passes straight from one row to the next, with the fill, ring and count changing in one frame and the title easing on `hover-out`. Today is a target (sets When = today) unless you're in Today; the current list, archived lists and labels aren't, and over them nothing is highlighted |
| Drop on the list | The copy flies into its slot (160 ms, cubic-bezier(0.2, 0.8, 0.2, 1)); at 170 ms the new order is written (one op per task, `keysBetween`, SPEC §3) and the grabbed row shows at once, exactly under the copy, which then fades out over it (150 ms ease-out), so the lift dissolves into the row; the other rows that came along fade in (150 ms). Dropping where it started writes nothing |
| Drop on a sidebar list | The copy flies to the row's left (x 10) and fades out (160 ms); at 170 ms the move is written; notice "Moved to Errands" |
| Drop on the sidebar elsewhere | As Esc: the copy flies home, widening back into the row, and nothing is written |
| Esc (or the system cancelling the drag) | The copy flies back to where it started (160 ms) and the gap closes; the row then shows under it and the copy fades out over it, as for a drop. Nothing is written. Releasing anywhere else drops at the last slot shown, as in a Mac list |

**Sidebar lists** drag the same way, vertically only, after 4pt: the copy is the capsule (`fill-strong`, the row's
width, radius 15, `shadow-lift`, tile and name in `ink`, the name on the row's text line) at x 10, clamped 6pt past the
first and last list; the other lists part on `layout`; the drop flies to its slot (160 ms), the order is written at
170 ms, and the row shows at once under the copy, which fades out over it (150 ms; Esc the same). Today and archived
lists can't be dragged (`dc:1550–1558`, `dc:1559–1573`, `dc:1574–1588`, `css:242`).

---

## 15. Context menus (native NSMenu)

The prototype draws its menus because a web page can't show native ones; build them as NSMenus. For reference, the
drawing (`css:306–315`) highlights items in `accent` with white text and keys at white 78%, and
draws disabled items at 40%.

**A task** (right-click selects it first unless it's already in the selection; the menu then acts on the selection)
`dc:1311–1343`:

```
Show Details            ⌘D        (one task)
Rename                  ↩         (one task; as Return, §7 Edit tasks)
Show in School                    (one task, in Today)
────────
Complete                ⌘K        ("Complete 3 Tasks"; "Mark as Not Done" when all are done)
When                    ▸  Today ⌘T · Tomorrow · This Weekend · Next Week · ── · Choose Date… ⌘S · ── · Remove
Deadline                ▸  Choose Date… ⇧⌘D · ── · Remove
Move to                 ▸  "Move to" header · each active list with its tile, ⌘1–⌘9, current ✓ and disabled
────────
Delete                  ⌘⌫        ("Delete 3 Tasks")
```

**A list** `dc:1344–1361`: New Task in School · Rename ↩ · ── · Move Up ⌥⌘↑ · Move Down ⌥⌘↓ ·
── · Archive ⌘⌫. **An archived list**: Unarchive · Rename ↩. **Empty sidebar space**: New List ⇧⌘N.

Items that don't apply are disabled, not hidden (Remove with no date set; Move Up on the first list). No ellipsis on
actions that happen at once (Archive, Delete); "Choose Date…" keeps one because it asks for input (macOS rule).

---

## 16. Hover, press and focus for every control

Presses never animate in (`transition: none` on `:active`); they ease back out on the control's own timing. The
checkbox is the exception: it shrinks over 80 ms ease-out and comes back on `snappy` (§8).

| Control | Rest | Hover | Pressed | On / current | Source |
|---|---|---|---|---|---|
| Task row | — | Only the › fades in (`hoverIn` / `hoverOut`) | Selects on mouse-down | §5 | `css:176` |
| › (show details) | `ink-tertiary`, hidden; never shown while renaming, on done rows, or while the detail pane is open | `hover` fill, `ink-secondary` (`icon`) | `press` fill | — | `css:174–179` |
| Checkbox | 1.5pt `line-field` ring | Ring `ink-secondary` | Scale 0.86, 80 ms ease-out | §8 | `css:193` |
| Chip | §11 | Brightness 1.18 dark / 0.96 light (`icon`) | Brightness 0.86 | Popover open: `accent-tint` | `css:207–209` |
| Ghost chip ("Add date") | `line-separator` ring, `ink-tertiary` | `hover` fill, `ink-secondary` | — | — | `css:214`, `css:215` |
| Detail-row × | Hidden | Revealed with the row's hover; own hover `hover` fill, `ink-secondary` | — | — | `css:266–269` |
| List pop-up (detail) | `ink` | `hover` fill, radius 6 (`icon`) | `press` fill | — | `css:271–273` |
| Sidebar row | §12 | Title `ink` | Opens on mouse-down | §12 | `css:108` |
| Group label's + / chevron | Hidden | Revealed with the label's hover; own hover `hover` fill, `ink-secondary` | `press` fill | Chevron turned and kept shown while open | `css:135–137` |
| Completed row | `ink-secondary` | `ink` (`hoverIn` / `hoverOut`) | — | Chevron turned | `css:229` |
| Empty space under the rows | — | Nothing | Clears the selection; a double-click adds (§5, §6) | — | `dc:1848–1861` |
| Pane-header icon button | `ink-quiet`; at 55% in an unfocused pane (never in a pane alone, §4) | `hover` fill (radius 6), `ink-secondary` (`icon`) | `press` fill, `ink` | Split button `ink-secondary` while the detail pane is open | `css:151–154` |
| Toolbar icon (sidebar toggle) | `ink-secondary` | `fill-track` circle, `ink` (`icon`) **Rex** | `press` fill | — | `css:93–94` |
| Capsule button (Undo, Unarchive) | Tinted | Brightness 1.12 / 0.97 (`icon`) | Brightness 0.86 | — | `css:293–295` |
| Quick pick (popover) | `fill-control` | `fill-track`, brightness 1.12 (`icon`) | — | Matches the typing: `accent-tint` | `css:322–324` |
| Month arrows | `ink-secondary` | `hover` fill, `ink` (`icon`) | — | — | `css:329` |
| Day | — | `hover` fill (`icon`) | Sets it | Highlighted `accent`; current ring; today `accent-text` | `css:333` |
| Menu item | — | `accent` + white, instant (native) | — | ✓ column when the menu has checks | `css:310` |
| Notice | — | Holds it open | — | — | `dc:2468` |
| Text fields | — | — | — | Row and list renames: a 1.5pt `accent` ring on the row; the detail title and notes: the caret only; selected text `text-selection` | `css:165` |
| Disabled | 45% (the detail pane under an untitled new task) | — | — | — | `css:286` |

**Tooltips** (Rex draws its own, with keys, preview.23) on the toolbar and pane-header buttons, the row's ›, and the
"Lists" +: the name, then the shortcut in `ink-secondary`, 6 apart ("New Task ⌘N", "Hide Sidebar ⌃⌘S"). A Today group's
+ ("New Task in School") and the detail rows' × show the name only; the Archive chevron and the popover's month arrows
have none. They appear 600 ms after the pointer arrives, at once if
another closed within the last 600 ms, 6pt below the button with its left edge 60pt left of the button's center (kept between 6 and the window's width − 160), and fade in
over 100 ms; they go at once on a press or when the pointer leaves, and never during a drag or with a menu open
(`dc:2473–2479`, `css:349–350`).

---

## 17. Keyboard (complete)

| Keys | Action |
|---|---|
| ⌘N | New task (§6) |
| ⇧⌘N | New list |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌘1–⌘9 | The sidebar's first nine rows: Today, Upcoming, Undated, then the first six lists (§22); hold ⌘ to see them |
| ⌃⌘S | Show or hide the sidebar |
| ↑ ↓ ⇧↑ ⇧↓ ⌘↑ ⌘↓ Home End ⌘A | Selection (§5) |
| Page Up, Page Down | Scroll the list a page |
| Letters | Type-to-select (tasks or lists, by focus) |
| ← → Tab ⇧Tab | Move between sidebar, list and details |
| Return | Edit the selected task (§7 Edit tasks) or rename the selected list |
| Space, ⌘K | Complete or uncomplete |
| ⌘D | Show or hide details |
| ⌘S / ⇧⌘D | When… / Deadline… |
| ⌘T | When: Today |
| ⇧⌘M | Move to… (⌘1–⌘9 inside it) |
| ⌥⌘↑ ⌥⌘↓ | Move the selection (or the sidebar list) up or down |
| ⌘⌫ | Delete tasks; with the sidebar focused, archive the list |
| Esc | Cancel or finish the innermost thing: drag, menu, popover, edit, then the detail pane, then the selection |
| ⌘R / ⌘, | Sync now / Settings (unchanged) |

**In text fields** the field's own keys win: Space, Return, ⌘⌫, ⌘Z and the arrows edit text. The menu commands still
work from a task's fields, as menu key equivalents do on the Mac: ⌘N (§6), ⇧⌘N, ⌃⌘S, and ⌘D, ⌘K, ⌘S, ⇧⌘D, ⌘T, ⇧⌘M,
⌘1–⌘9, which first end the edit the way a press elsewhere would, then run. A new task that's still untitled isn't a task
yet, so only ⌘D (it's dropped and the pane hides), ⌘1–⌘9 (dropped, then go), ⇧⌘N (dropped, a new list starts) and
⌃⌘S (the sidebar toggles, the caret stays) do anything there
(`dc:1648–1668`).

Menu bar: File ▸ New Task ⌘N, New List ⇧⌘N · Edit ▸ Undo, Redo, Select All · Task ▸ Show Details ⌘D, Complete ⌘K,
When… ⌘S, When: Today ⌘T, Deadline… ⇧⌘D, Move to… ⇧⌘M, Move Up ⌥⌘↑, Move Down ⌥⌘↓, Delete ⌘⌫ · View ▸ Today ⌘1,
Upcoming ⌘2, Undated ⌘3, lists ⌘4–⌘9, Completed, Trash, Show/Hide Sidebar ⌃⌘S.

---

## 18. Building it (SwiftUI and AppKit)

Where SwiftUI's defaults fight the design, and what to use instead.

1. **Task list rows.** Give rows identity by task id inside the lazy stack and animate model changes with
   `withAnimation(PaneMotion.layout)`; wrap list switches in a transaction with animation disabled. That's what makes
   reorder, insert, delete and settle move instead of jump. v1's positional slots made switching faster but can't
   animate a moving task; measure switching against SPEC §9 with ids, and if it's over budget keep the slots and animate
   with a FLIP (remember each task's last y, start the new slot's content at the old y with `.offset`, animate to 0).
   Entering rows use `.transition(.opacity)` on a 180 ms ease-out, leaving ones 150 ms; the prototype's
   `MOTION_WINDOW_MS` bookkeeping (`dc:2495–2520`) is what SwiftUI's transitions do for you.
2. **Hover: one tracker per list, not per row.** `.onContinuousHover` on the list container; the hovered row is
   the one whose `[top − 1, top + 31)` holds the pointer, from the layout's own row positions (Today's labels, the
   archived banner and the Completed row's extra 8pt break the plain 32pt grid; each 2pt gap is split 1/1, §5); store `hoveredTaskID` in an observable
   that only the two affected rows read. Recompute on scroll (the pointer is still but the rows move). `.ended` clears
   it. This replaces v1's `PaneHoverRegion` and its missed exits. The checkbox, chips and › use their own `.onHover`:
   they're small and never stacked.
3. **Selection and keys.** The list is `.focusable()` with `.focusEffectDisabled()`; keys through `.onKeyPress` (macOS
   14), letters through `.onKeyPress(characters: .alphanumerics)` with a 1 s buffer. Take focus on mouse-down in the
   list (v1 found SwiftUI won't).
4. **The new-task draft lives in window state, not the store.** `WindowState.draft: Task?` (with the selection and
   whether the pane was open before ⌘N). The list renders it at its landing slot and the detail pane binds to it; the
   store sees one `task.create` when the title commits. Dropping it is just setting `draft = nil` and restoring the
   saved selection and pane state. Undo registration happens at the create, never for the draft.
5. **Focus for adding.** `@FocusState` on the detail title, set in the same transaction that sets the draft (it must
   work when the pane is already open, where the view isn't re-created). While the title is empty, the rows under it
   are `.disabled(true).opacity(0.45)` and taps on them are swallowed, so the title keeps focus. Commands that need a
   task are disabled in the menu bar while the draft is untitled; that is what makes ⌘S and friends do nothing there.
6. **Inline text fields.** An `NSTextField` subclass in `NSViewRepresentable`, borderless, no background, same font and
   origin as the label it replaces. Caret at the click: after it becomes first responder, set
   `currentEditor()?.selectedRange` from the click's character index (`NSLayoutManager.characterIndex(for:in:…)` on
   the label's text). Return/Tab/Esc via `control(_:textView:doCommandBy:)` (`insertNewline`, `insertTab`,
   `cancelOperation`). Esc restores, so keep the original string. The detail title is a wrapping field with the same
   hooks (`insertBacktab` for ⇧Tab); the notes are an `NSTextView` (Tab inserts, `insertBacktab` goes to the title).
7. **Context menus** are `.contextMenu` (native, submenus via `Menu`). ⇧⌘M pops the same `NSMenu` under the row with
   `NSMenu.popUp(positioning:at:in:)` from a small AppKit bridge; ⌘1–⌘9 are its items' key equivalents.
8. **Date popover.** Not SwiftUI's `.popover` (macOS draws an arrow and its own animation). Draw it in the window's
   overlay layer anchored to the chip's `anchorPreference`, with a full-window transparent catcher behind it that
   consumes the press that closes it (so it doesn't also select a row). The field takes focus with `@FocusState` when
   it appears.
9. **Notices and tooltips** live in the same overlay layer. Tooltips are custom (Rex's own style); `.help()` would give
   the system's delay and look.
10. **Drag is in-window and custom.** A `DragGesture(minimumDistance: 4, coordinateSpace: .named("window"))` on each row
    drives a window-level drag model; the overlay draws the lifted copy; the list derives the target slot from the
    pointer and the 32pt pitch and opens the gap by offsetting the rows at and after it; sidebar rows publish their
    frames as anchor preferences for hit-testing; Esc cancels via the focused list's `.onKeyPress(.escape)`. Not
    `.draggable`/`.dropDestination`: v1 hit cancelled async item providers, `dropUpdated` after `performDrop`, and had
    no control over the lifted image, the gap or cancel.
11. **Checked rows that wait.** A `pins: [TaskID: Placement]` map in the window state places checked/unchecked tasks
    where they were; a 1.5 s debounce (restarted by each check) clears it inside `withAnimation(PaneMotion.layout)`; a
    route change clears it too.
12. **The empty space.** The space below the rows has no hover. A press clears the selection (or ends an edit); a press
    with a click count of 2 adds a task as ⌘N does.
13. **Held ⌘.** `NSEvent.addLocalMonitorForEvents(matching: .flagsChanged)`, 450 ms timer; any key or release hides.
14. **Undo** registers on the window's `UndoManager` with `setActionName` (the names in §9) and the selection to
    restore.
15. **Accessibility basics.** The prototype's labels are the ones to use: a row's checkbox is "Complete: Buy milk" /
    "Mark not done: Buy milk" (`dc:2587`; the detail pane's is just "Complete"), the › is "Show details", icon buttons carry their tooltip's name, the date popover is a
    dialog "Choose a date" with its field "Type a date", notices are status messages, the Completed row is "Completed
    tasks" (`dc:89`, `dc:199`, `dc:106`). Rows
    are selectable list items whose label is the title, then the chips' text.

---

## 19. What changed from v1, and why

| v1 (`design/INTERACTIONS.md`) | v2 | Why |
|---|---|---|
| ••• on every hovered task row, opening a menu | Right-click for the menu; one › that opens the details | The menu duplicated right-click; the › opens the pane the user likes |
| Hover regions per row with their own tracking | One tracker per list; rows reveal only the › | Missed exits and lit rows were the "horrendous" part |
| `fill-selected` (#272728) selection | #333333 / #292929, joined across rows | #272728 is 1.1:1 on the pane: selection was hard to see |
| Quick add editor: title, notes, chips, key hints | ⌘N opens the new task in the detail pane, its row at its landing slot | The user's pick: one place for everything about a task |
| Move to… sheet | Native menu at the row | A sheet for a one-word choice |
| Notes: Edit / Preview control, mono editing | Click to edit in place, same font | No mode switch, no reflow |
| Archive pane beside the list | A collapsible Archive group in the sidebar | One less pane type |
| SwiftUI item-provider drags | In-window custom drag, rows part for the gap, Esc cancels | v1's drop bugs; no control over the lift |
| Rows jump when order changes | Rows move on one spring | The list should show what happened |

The detail pane's open and close is unchanged.

---

## 20. Questions for a Rex measurement (for the coordinator)

I didn't drive Rex (per the brief). These are the values chosen without it:

1. **Notices**: which corner, size, lifetime, and entry/exit motion. (Tasks: bottom-right of the pane, 34pt, 5 s, rise
   8pt in 220 ms.)
2. **Tooltips**: delay, fill, radius, padding, and the key style. (Tasks: 600 ms, `surface-popover`, radius 6.)
3. **Inline rename** of a sidebar tab: the field's look (fill? ring?) and whether the text is selected.
4. **Sidebar tab drag**: does Rex part the rows (gap) or draw a line? What does the lifted tab look like?
5. **Light theme**: the current capsule's fill and edge, and the ink ladder (Tasks uses Pane's light values).
6. **Unfocused pane fill**: is it exactly `surface-ground` (#181818)?
7. **Context menus**: native `NSMenu`? (Assumed: hot items white on accent.)
8. **Held-⌘ hints**: glyph style and position in the sidebar.

---

## 21. Details the sections above don't state

Found by an audit of the spec against the prototype; each is what the prototype does.

- **Switching views** (a sidebar row, ⌘1–⌘9, Show in…): instant; clears the selection, ends any edit, closes the
  popover and menus, settles checked rows, and scrolls the new list to its top. An open detail pane stays open and shows
  "No task selected" (`dc:1006–1014`).
- **Today's look**: the sidebar's Today tile holds a 12pt sun in ANSI yellow; the Today header shows a 14pt yellow sun
  (no tile), "Today", then the date ("Fri, Oct 30") in `ink-secondary` (`dc:48`,
  `dc:2693`).
- **List colors** (`--ansi-*`): dark red #FF7B72, green #3FB950, yellow #D29922, blue #58A6FF, magenta #BC8CFF, cyan
  #39C5CF, ink #E6EDF3; light #CF222E, #116329, #9A6700, #0969DA, #8250DF, #1B7C83, #1F2328
  (`css:56`, `css:73`). New lists take them in the order blue, magenta, green,
  cyan, yellow, red, ink (`dc:418`); the seeded Inbox is ink. A new list's tile shows "·" until its
  name has a letter or digit (`dc:431`).
- **Relative dates** in the detail pane: "today", "tomorrow", "yesterday"; "in N days" under 14 days, "in N weeks"
  (rounded) under 60, else "in N months"; past: "N days ago" under 14, else "N weeks ago" (`dc:280–287`).
- **The detail pane's Deadline chip** takes the row chip's tone: `danger` when overdue, `attention` when due today
  (`dc:2635`).
- **Detail-pane spacing**: everything under the title starts at the checkbox's left edge and spans the content width,
  as the title row does (user feedback, `docs/TASK-v2-feedback.md` item 6). The label's icon is centered in the
  checkbox's 16pt column and its word sits 10 after it, at 26, in line with the title's text; the value starts 8 after
  the 81pt label column; the relative date sits 26 past a set chip (room for its ×); the separator is 1pt, 10 below the
  rows and 12 above the notes; the notes area is at least 120 tall; "3 tasks selected" is indented 26, in line with a
  title's text and the labels (`css:261–277`, `css:260`).
- **Several tasks, or none, in the detail pane**: tasks from different lists show "Several lists" with a "…" tile and
  the List row reads "Mixed"; the trash's tooltip is "Delete 3 Tasks". With nothing selected the header shows only the ×
  (`dc:2643`).
- **The Completed row** is only as wide as its content, so a press to its right lands on the empty space (it clears
  the selection).
  Collapsing slides the done rows up into it while they fade; expanding fades them in where they sit. It disappears at
  once when its last task goes (`css:226`, `dc:2495–2520`).
- **After a checked row settles** the selection doesn't move: in a collapsed list the done task stays selected though
  hidden, and the detail pane keeps showing it (`dc:1179`).
- **Counts**: zero shows nothing. The sidebar count drops the moment a box is checked; a list's Completed count waits
  for the 1.5 s settle (`dc:2604`, `dc:2698`).
- **Today's Completed group** holds only tasks completed today that are dated today or earlier
  (`dc:915`).
- **The date popover**: closes with no exit animation. No day is highlighted while nothing matches. The footer is 12pt.
  The weekday row reads S M T W T F S. Day cells are a seventh of the 272pt grid, about 38.9 × 28. ‹ › change only the
  month shown, not the highlighted day (`dc:2464`). Clear, ⌫-to-clear and the current-date ring
  appear only when every selected task has the same date (`dc:1404`). From the keyboard without a
  chip, its left edge is 300 left of the row's right end (`dc:1421`).
- **The drag copy**: 10 padding on both sides and no › slot, so its chips sit 21pt further right than in the row; in
  light theme its chips sit on `fill-track`; the compact tag over the sidebar drops the chips. Only selected rows from
  the grabbed row's group come along (`dc:1451`). After a drop the grabbed row shows at once under the copy, which
  fades out over it (150 ms); the other rows fade back in (150 ms). Never hide the copy while its row fades in: that
  leaves a frame or more with neither (v2 feedback 5). A sidebar row being dragged fades out over 150 ms rather than
  vanishing (`css:118`).
- **Keys**: ↑ / ↓ with several rows selected go below the last or above the first of them
  (`dc:982–996`). Scrolling a row into view starts within 4pt of an edge and jumps (no
  animation). With the detail pane focused but not editing, arrows and letters act on the list and move focus there;
  Return edits the selected task (§7 Edit tasks: its title in the pane, or renamed in its row with the list focused).
  With the sidebar focused, Space, ⌘K and ⌘T still act on the selected tasks. Sidebar type-select tries lists
  before Today, so "t" goes to "Tasks app" (`dc:1738–1750`).
- **Renaming a task** keeps the text as typed (not trimmed) and may leave it empty; an empty title shows "New Task" in
  `ink-tertiary` (`css:169`).
- **The archive banner**: "Archived Oct 28" in 13pt `ink`, the rest in 12pt `ink-secondary`, the icon in
  `ink-secondary`; 10 in from the pane's sides, 10 between icon, text and button (`dc:60–64`).
- **Glyphs**: icons are drawn with 1.5pt round strokes, 14pt by default. The ›, group + and chevron, Completed chevron,
  date ×, month arrows and ⌃⌄ are 12pt; chip icons 11pt. The group buttons and the date × rest in `ink-tertiary`. "Add
  date" has no icon (`css:40–43`).
- **Menus on the sidebar**: right-clicking a list doesn't open it; Today has no menu (`dc:2392–2398`).
- **Truncation**: pane titles end in an ellipsis; sidebar names fade (§12).
- **Scroll padding**: the list's content ends 24pt below its last row, the sidebar's 16pt.

---

## 22. Upcoming, Undated, Completed and Trash

Status: **final, 2026-10-31.** The user picked from the designs in `docs/TASK-design-views.md` and approved the rest as
drawn. The canvas is https://claude.ai/artifact/EnWEe86TBSG8voqqwbf7uf, with a board for each view in dark and light.
The code is one block at the end of the component (`dc:2878–3189`) plus small hooks where the views meet Today's code,
and the CSS is appended (`css:413–430`).

The four views are siblings of Today: the same list pane, header, 30pt rows on the 32pt pitch, 32pt group labels,
detail pane, notices and undo. Only what differs is written here; everything else is as §4–§21 say.

**No new model fields.** Every view is a query over the fields SPEC §2 has. Trash orders by when a task was deleted:
the client takes that from the `at` of the op that last set `deleted: true`, the way it derives `createdAt` and
`updatedAt` (SPEC §2), so nothing new is written or synced. (The prototype stores it as `deletedAt`, `dc:1190–1197`.)
The app as built takes the task's `updatedAt`, the `at` of its last op of any kind: the app never edits a trashed
task, so that's the op that deleted it. An edit made elsewhere (the CLI) would move it in the Trash, and undoing a
Put Back deletes it again at that moment.

### The sidebar

Top to bottom: the brand header, **Today, Upcoming, Undated**, the "Lists" label and the lists, then 8pt and
**Completed, Trash**, then the Archive group (`dc:952–976`, `dc:2895–2901`). The views you plan from sit under Today;
the logbook and the Trash sit after the lists. **No counts** on the four: Today and the lists keep theirs.

| Row | Glyph (in the 20×16 tile; 14pt bare in the header) |
|---|---|
| Upcoming | calendar, `ansi-magenta` |
| Undated | three stacked layers, `ansi-cyan` |
| Completed | check in a circle, `ansi-green` |
| Trash | the trash can (the detail pane's Delete glyph), `ink-secondary` |

They are rows like Today: hover, current and ⌘ hints as §12. Type-select tries the lists first, then Today and the
views, so "t" still goes to "Tasks app" and "u" to Upcoming (`dc:1738–1745`). They can't be dragged, renamed or
archived, and have no context menu. Trash is always shown, empty or not, so a deleted task always has somewhere to be
found. Template: `dc:26`, `dc:48`; tiles `dc:420`.

**⌘1–⌘9 open the sidebar's first nine rows, top to bottom** (`dc:2900`, `dc:1672`): Today, Upcoming, Undated, then the
first six lists. Holding ⌘ shows the numbers as before (§12). (The user may revisit this.)

**Drops from a task drag** (`dc:3104–3121`): Completed completes the dragged tasks; Trash deletes them (notice
"Deleted …" with Undo). Upcoming and Undated aren't targets (a drop there would have to invent a date or erase two).
From Trash, a list puts the tasks back into that list; Today and Completed don't take them.

### What each view shows

| View | Tasks | Groups, in order | Row extras | Source |
|---|---|---|---|---|
| Upcoming | Open, in active lists, whose **earlier date is after today**. Each sits on the day it will reach Today (SPEC §4: either date brings it in), so every dated open task is in exactly one of Today and Upcoming. A task with both dates shows **once**, on the earlier date | **The next seven days, always**: "Tomorrow", then weekday names, each with its date after it in 400 `ink-quiet` ("Monday  Nov 2"). An empty day's label is `ink-quiet` and still takes +, a double-click and a drop. **Then one group per month**: "Later in November" (the rest of the seventh day's month), "December", "January 2027". Within a group: by date, then the list's sidebar order, then the list's order | The list's name after the title (12pt `ink-tertiary`, as Today's Completed rows). In a day group the day's own date isn't repeated: When on that day shows no chip, and a deadline on that day reads "Due" (neutral flag chip). The other date shows as its usual chip | `dc:2928–2955`, `dc:2978`, `dc:2980–2986` |
| Undated | Open, in active lists, with **no When and no Deadline** | By list, in sidebar order, each list's name as the label with its +; rows in the list's order. Exactly Today's grouping | none | `dc:2921–2927` |
| Completed | Completed, in active lists, **newest first, all of them**: it's the logbook (kept forever, SPEC §2; the app draws only what's on screen) | A group per local day for the last 7 days ("Today", "Yesterday", weekday names, with the date), then per month | The list's name; in a month group also the day ("School · Oct 22") | `dc:2956–2972` |
| Trash | Deleted, in active lists (a deleted task in an archived list shows once the list is unarchived), newest-deleted first | As Completed, by the day it was deleted | The list's name (and the day, in a month group). Titles `ink-secondary` (completed ones keep their struck `ink-tertiary`); the checkbox at 60% and, with the chips, deaf to the pointer | `dc:2956–2972`, `css:425–428` |

Label metrics are Today's (`css:131`, `css:234–237`); the date part is `css:419`, an empty day `css:420`. Group labels
keep one node per id while the view is open, so they move with their rows (`dc:2988–3012`).

### What you can do in each

| | Today (for reference) | Upcoming | Undated | Completed | Trash |
|---|---|---|---|---|---|
| + and ⌘N | `when` = today | `when` = the +'s day; else the selected task's day; else tomorrow. List: the selected task's, else the default (§6) | No dates; the group's list, else the selected task's, else the default | No + in the header. ⌘N opens the default list and adds there | As Completed |
| Double-click empty space | Adds (§6) | Adds, as ⌘N; double-clicking a day's label adds for that day | Adds | Nothing | Nothing |
| A group label's + | Adds to that list, for today | Adds for that day (days only; months have none) | Adds to that list | none | none |
| Drag in the list | Within a group (§14) | Onto any day: sets When (below) | Within a group, as Today | Rows don't part; only the sidebar takes the drop (move to a list, Trash) | As Completed; a list puts it back there |
| ⌥⌘↑ ⌥⌘↓ | Move in the group | A day earlier or later (sets When); never past the deadline; earlier than tomorrow is Today | Move in the group | nothing | nothing |
| Space, ⌘K | Complete | Complete; the row leaves after 1.5 s (§8) | Same | Uncomplete; the row stays 1.5 s unchecked, then goes back to its list at its old place | nothing |
| Return, double-click a row | Edit (§7) | Edit | Edit | Edit (title only; done rows don't rename in place, as now) | Shows the task in the detail pane |
| ⌘S, ⇧⌘D, ⌘T | Dates | Dates; a task whose earlier date becomes today or none leaves with a notice ("Scheduled for Sat, Oct 31", "Removed from Upcoming") | Dates; any date takes it out ("Scheduled for …", "Due …") | Dates | nothing |
| ⇧⌘M, List pop-up | Move | Move; the row stays, its list name changes | Move; it regroups | Move | nothing (use Put Back in ▸) |
| ⌘⌫ | Delete | Delete | Delete | Delete | **Put Back** |

Sources: adding `dc:1114–1158`, `dc:3021–3034`, `dc:3013–3020`; dates leaving a view `dc:1211–1222`, `dc:3038–3045`;
⌥⌘↑↓ `dc:1243–1244`, `dc:3047–3067`; Trash guards `dc:1163`, `dc:1190–1191`, `dc:2860`.

**Keyboard navigation** is the list's (§5, §17): ↑ ↓ walk every row across groups, ⇧ extends, ⌘A selects all, letters
type-select, ← → Tab move between the sidebar, the list and the details.

### Rescheduling by drag in Upcoming

`dc:3122–3172`. The press, the 4pt slop, the lifted copy, autoscroll and Esc are §14's. What differs:

- The copy follows the pointer up and down the whole list (clamped 6pt past the first label and the last row), not
  one group.
- The target is the group whose label is the last one above the copy's middle. When it's a **day**, the dragged rows
  are laid out on that day, so the rows there part on `layout` to open the gap exactly where the task will land (its
  slot by list order), the source group closes up, and the day's label turns `accent-text` (in on `hover-in`, out on
  `hover-out`, `css:421–422`).
- A **month** is not a target, and neither is a day after any dragged task's deadline: there the gap stays at home and
  no label lights. (Moving When past the deadline wouldn't move the task: it would still reach Today on its deadline.)
- Drop on a day: the copy flies into the gap (160 ms), then When is set to that day (one `task.update` per task,
  undo "Set When"); the deadline is never touched. Drop at home, on a month, or past a deadline: the copy flies home
  and nothing is written. Over the sidebar it's §14's tag; Today sets When to today, Completed and Trash as above.

### Trash

- **Read-only.** A trashed task can be selected, read and put back, nothing else: the detail pane shows it with its
  title read-only and its List, When, Deadline and notes deaf to the pointer (`dc:130`, `css:429–430`). The footer
  reads "Created Aug 20 · Deleted Oct 28" (`dc:3090–3097`). Editing a deleted task would be an edit nobody sees, and
  Finder works the same way.
- **Put Back** (`dc:3070–3080`): ⌘⌫ (Finder's key for it), Put Back in the context menu, or the ↶ button that
  replaces the detail pane's trash (`dc:121`). It writes `deleted: false` (SPEC §5): the task returns to its list
  **at its old place** (order untouched) with its dates and completion. Notice "Put back “Buy a second lamp” in Home"
  (or "Put back 3 tasks"), with Undo; undo label "Put Back" / "Put Back 3 Tasks". The selection moves to the next row,
  as a delete does.
- **Put Back in ▸** (context menu) and a drag onto a sidebar list put it at the bottom of another list
  (`set {deleted: false, list, order}`). Context menu: Show Details, Put Back, Put Back in ▸ (`dc:3081–3089`).
- **Deleting from every other view** is unchanged (§9): soft, immediate, "Deleted …" with Undo. The notice doesn't
  say Trash; the sidebar row is always there to find it.
- **No "Delete Forever" and no "Empty Trash"** (the user's call): SPEC §1 and §11 defer hard deletes. Trash only grows,
  and says nothing about it.

### Empty states

All centered, 34% down, as §13 (`dc:422–427`, `dc:98`):

| View | Glyph (22pt, `ink-quiet`) | Title | Text |
|---|---|---|---|
| Upcoming | calendar | Nothing upcoming | Tasks with a date after today show up here, on the day they reach Today. (Drawn 24 under the seven empty days) |
| Undated | layers | Every task has a date | Open tasks with no When and no Deadline show up here, by list. |
| Completed | check circle | Nothing completed yet | Tasks you check off show up here, newest first. |
| Trash | trash can | Trash is empty | Deleted tasks wait here until you put them back. |

### The header

Each view's header is Today's: the glyph in its colour, the name in 13 medium `ink`, no subtitle, then + and the
details button. Completed and Trash have no + (`dc:53`, `dc:2903`, `css:415`). The detail pane is unchanged except in
Trash.
