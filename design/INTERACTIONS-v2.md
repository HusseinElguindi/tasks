# Tasks — interactions v2 (build spec)

Status: **draft for the user's review, 2026-10-30.** Every interaction in the app, designed from a blank page and built
first as a prototype in Claude Design: https://claude.ai/artifact/QetdV1H57SC6kLXtNzJRXM (source in
`design/prototype-v2/`). Once approved this replaces `design/INTERACTIONS.md`.

Four choices are still the user's (§1). Everything else is decided; where a section depends on a choice, both options
are specified so the build can follow whichever is picked.

Rex is the source of truth (`docs/TASK-source-of-truth.md`). Values marked **Rex** were measured
(`design/REX-REFERENCE.md`); the rest are Pane tokens or new decisions, and every difference from Pane is logged in
`design/PANE-UPSTREAM.md`. Questions only a Rex measurement can answer are in §20.

---

## 1. Open choices

| Choice | Options in the prototype | Recommendation |
|---|---|---|
| **How adding works** (§6) | **A** inline row where the task lands · **B** the same row, reading trailing date words ("fri", "due nov 9") · **C** straight into the detail pane | A. B if the user wants dates while capturing; C only if most tasks get notes. |
| **Date picker shape** (§11) | **A** popover with a field, quick picks and the month · **B** a palette-style suggestion list, month on request | A for a planner who looks at weeks; B for keyboard-first. |
| Drag feedback (§14) | **Gap**: rows part to show the slot · **Line**: rows stay, a 2pt line marks the slot | Gap. |
| When checked rows move (§8) | **After 1.5 s** with no further checks · **On leave**: they stay until you switch views | After 1.5 s. |

The boards on the canvas show the first two side by side; the strip under the main prototype switches all four.

---

## 2. Principles

1. **One gesture, one meaning.** Click selects. Double-click or Return renames. Drag moves. Right-click opens the menu.
   Escape cancels. ⌘Z undoes. This holds for tasks and lists alike.
2. **Hover only reveals, and only where something can be clicked.** Task rows never change on hover except that their
   trailing › fades in. Navigation rows (the sidebar) brighten their title, as Rex does. Controls (checkbox, chips,
   icon buttons) answer when the pointer is on *them*.
3. **No confirmations; everything undoes.** Anything that removes items from the view (delete, move, archive, a date
   that takes a task out of Today) says so in a notice with Undo.
4. **Things appear where they'll live.** A new task's row opens at its landing spot. A checked task stays put, then
   moves (§8). Nothing jumps to a place you can't see without a notice.
5. **Rex's timing.** Hover is near-instant in, prompt out. Layout changes ride one spring. Switching lists and themes
   never animates. Reduce Motion turns all of it off.
6. **Native where the system can take the theme** (context menus are NSMenus; text fields are real fields); drawn
   only where it can't (rows, chips, the date popover, notices, tooltips, the drag).

---

## 3. Tokens

### Colors

| Token | Dark | Light | Use |
|---|---|---|---|
| `surface-ground` | #181818 **Rex** | #F5F5F5 | Window, sidebar |
| `surface-base` | #1C1C1C **Rex** | #FFFFFF | Focused pane |
| `surface-dim` | #181818 | #FAFAFA | Unfocused pane |
| `surface-popover` (new) | #262626 | #FFFFFF | Menus, date popover, notices, tooltips |
| `fill-lift` (new) | #2C2C2C | #FFFFFF | The dragged row |
| `line-pane` / `line-pane-dim` | #323334 / #282929 | #D4D5D6 / #EBEBEC | Focused / unfocused pane edge (1pt inset) |
| `line-separator` | #363738 | #E7E8E8 | Hairlines in menus and the detail pane |
| `line-field` | #696B6E | #848689 | Checkbox ring |
| `ink` | #E6EDF3 | #1F2328 | Titles, task text |
| `ink-secondary` | #A8ADB1 **Rex** | #626568 | Sidebar titles at rest, values, secondary text |
| `ink-tertiary` | #7F8386 **Rex** | #6C6F72 | Group labels, counts, placeholders, ghost row |
| `ink-quiet` | #6D7072 **Rex** | #888A8D | Pane-header icons at rest |
| `fill-row-selected` (new) | #333333 | #E6E6E8 | Selected task rows, focused pane |
| `fill-row-selected-dim` (new) | #292929 | #EFEFF0 | Selected task rows, unfocused pane |
| `fill-control` | #2D2E2E | #EDEDEE | Neutral chips, fields |
| `fill-track` | #303132 | #E9E9EA | Toolbar icon hover circle, neutral buttons |
| `fill-strong` | #444444 **Rex** | #E0E0E1 | Current sidebar row, list tiles |
| capsule edge | outer #5E5E5E over inner #535353 **Rex** | #CFCFD0 / #D6D6D7 | 0.5pt + 0.5pt on the current sidebar row |
| `hover` (new) | white 7% | #1F2328 6% | Fill behind a hovered icon button |
| `press` (new) | white 12% | #1F2328 11% | Fill behind a pressed icon button |
| `accent` / `accent-text` / `accent-tint` | #2F81F7 / #5799F6 / #1E2938 | #0969DA / #0969DA / #E6F0FB | Focus ring, hot menu item, picked day, tinted buttons |
| `on-accent` | #FFFFFF | #FFFFFF | Checkmark and hot menu item text (native) |
| `danger-text` / `danger-tint` | #FF7B72 / #3C2928 | #CF222E / #FBEBEC | Overdue chip |
| `attention` / `attention-tint` | #D29922 / #352E1D | #9A6700 / #FAF7F2 | Due-today chip, the other date's dot in the calendar |
| `text-selection` | accent 45% | accent 25% | Selected text in fields |

Shadows: `shadow-popover` = 0.5pt hairline of white 14% (dark) / #1F2328 16% (light), plus 0 12 32 black 50% / #1F2328
16%. `shadow-lift` = the same hairline plus 0 8 24 black 50% / #1F2328 18%.

List colors: a list's tile glyph uses one of the seven ANSI slots, chosen by hashing the list id (DIRECTIONS decision 3).

### Metrics (points)

| Thing | Value |
|---|---|
| Toolbar band | 50 tall. Traffic lights 14pt circles centered at x 25, 48, 71, y 25 **Rex**. Sidebar toggle: 28pt circle centered at (107, 25) **Rex** |
| Sidebar | 230 wide **Rex**. Rows from y 50 |
| Sidebar row | Capsule x 10–219, 30 tall on a 32 pitch, radius 15 **Rex**. Tile 20×16, radius 4, 10 inside the capsule; title 7 after the tile **Rex**; count right-aligned 8 from the capsule's right edge |
| Group label | A 32pt slot: 11/14 semibold, x 12 inside the row edge, text top 10 **Rex**. Reveal button 22×22 (radius 6) in the trailing slot, 5 from the edge, top 6 |
| Panes | 8 from the window edges and each other; list pane starts at x 230 **Rex**; radius 10; header 34 (title centered on the traffic lights' line); header padding 12 / 8 |
| Pane-header icon button | 26×26, radius 6, glyph 14 |
| Task row | 10 in from the pane edges, 30 tall on a 32 pitch, radius 8; first row 4 below the header. Checkbox 10 in; title 10 after it; chips 8 after the title, 6 apart; › button 22×22 (radius 6), 4 after the chips, 5 from the row's right edge (slot always reserved) |
| Checkbox | 16 circle, 1.5 ring; check glyph 10, stroke 2.2; hit area 30×30 |
| Chip | 18 tall, radius 9, padding 7, gap 4, 11/14 medium, icon 11. Large (detail pane): 22 tall, radius 11, padding 9, 12pt |
| Detail pane | 420 wide; body padding 8 / 18 / 18; title 15/20 semibold; property rows 32 tall with a 76pt label column, indented 26 to the title |
| Menu | 216 wide (submenu 204), padding 5, radius 10; items 24 tall, radius 5; separator 1pt inset 9 |
| Date popover | 288 wide, padding 8, radius 12; field 28 tall, radius 8; quick picks 22 tall; day cells 28 tall, radius 14 |
| Notice | 34 tall, radius 10, 12 from the list pane's bottom-right corner |
| Tooltip | padding 4 / 7, radius 6, 11/14 |

### Motion

| Token | Value | SwiftUI | Used for |
|---|---|---|---|
| `hoverIn` | 60 ms, cubic-bezier(0, 0.8, 0.2, 1): ~86% on the first frame **Rex** | `.timingCurve(0, 0.8, 0.2, 1, duration: 0.06)` | Anything appearing under the pointer |
| `hoverOut` | 85 ms ease-out, starting the moment the pointer leaves **Rex** | `.easeOut(duration: 0.085)` | Anything disappearing as the pointer leaves |
| `icon` | 100 ms ease-out both ways **Rex** | `.easeOut(duration: 0.1)` | Icon-button and chip fills |
| `focus` | 60 ms ease-out **Rex** | `.easeOut(duration: 0.06)` | Pane focus change |
| `layout` (new) | critically damped spring, perceptual 0.25 s | `.smooth(duration: 0.25)` | Rows and sidebar rows moving: reorder, insert, remove, settle, drag gaps |
| `natural` | **unchanged from v1** | `.smooth(duration: 0.3)` | Detail pane open and close |
| `snappy` | | `.snappy(duration: 0.2)` | Checkbox pop |
| `sidebar` | 300 ms decelerating **Rex** | `.timingCurve(0.16, 1, 0.3, 1, duration: 0.3)` | Sidebar show and hide |
| Row in / out | fade in 180 ms ease-out / fade out 150 ms ease-out, while `layout` moves the others | | Rows appearing and leaving |
| Popover in | 120 ms decelerate: opacity 0→1, y −3→0, scale 0.985→1 from the anchor | | Date popover, Keys panel |
| Notice | in 220 ms cubic-bezier(0.2, 0.8, 0.2, 1), rising 8; out 160 ms ease-in | | Notices |
| Drag fly | 160 ms cubic-bezier(0.2, 0.8, 0.2, 1); 200 ms back on cancel | | Lifted row landing or returning |
| Instant | no animation | `Transaction(animation: nil)` | Selection, list switches, theme, press-in |

Reduce Motion: every duration is 0.

Timers: checked rows settle after **1.5 s**; notices live **5 s** (undoable) or **1.8 s** (information), paused while
hovered and restarted at 2 s when the pointer leaves; tooltips after **600 ms**, then instant for 600 ms after the last
one closed; type-to-select buffer **1 s**; held-⌘ hints after **450 ms**; drag starts after **4 pt**.

---

## 4. Window and panes

**Layout.** Sidebar (ground) | list pane | detail pane, as A1. Under about 900pt wide the detail pane replaces the list
instead of splitting (A3's drill-in, unchanged).

**Detail pane: keep v1 exactly.** The user likes it.

```swift
if let id = window.detailTaskID {
    DetailPane(...).frame(width: 420)
        .transition(.move(edge: .trailing).combined(with: .opacity))
}
// on the HStack:
.animation(PaneMotion.natural, value: window.detailTaskID == nil)   // .smooth(duration: 0.3)
```

The list pane narrows on the same spring while the detail slides in and fades up. Closing reverses it.

| Trigger | Result |
|---|---|
| ⌘D, the header's split button, a row's › | Show the detail pane (⌘D and the button toggle) |
| Esc with nothing to cancel, the pane's × | Hide it |
| Selection changes while it is open | It shows the new selection at once (no animation) |
| Several tasks selected | "3 tasks selected": List, When and Deadline rows that apply to all; "Mixed" where they differ |
| Nothing selected | "No task selected", centered, `ink-secondary` / `ink-tertiary` |

**Pane focus** (Rex's rule). The pane you last pressed in is focused: `surface-base`, `line-pane`, header icons at full
strength, title `ink`. The others: `surface-dim`, `line-pane-dim`, header icons at 55%, title `ink-secondary`. The
change takes `focus` (60 ms) and happens on mouse-down. Pressing in the sidebar focuses the sidebar: both panes show
unfocused. The sidebar has no focus marking of its own.

**Sidebar show/hide** (⌃⌘S, the toggle): as v1. The panes slide over the sidebar (`sidebar` curve), the traffic
lights and toggle stay, and the first pane's header makes room for them (title starts at x 124).

---

## 5. Selection and moving around

**Mouse.** Selection happens on mouse-down.

| Gesture | Result |
|---|---|
| Click a row | Select only it (focus moves to the list) |
| ⌘-click | Add or remove it; it becomes the anchor |
| ⇧-click | Select the range from the anchor, in visual order |
| Click a row that's part of a multi-selection | Nothing until mouse-up (so the selection can be dragged); then select only it |
| Click empty space below the rows | In a list: new task (§6). In Today: clear the selection |
| Click a checkbox | Completes that row without changing the selection |
| Click a chip or › | Selects the row if it wasn't selected, then opens its picker or the details |

**Look.** A selected row fills with `fill-row-selected` at radius 8 (`fill-row-selected-dim` when its pane isn't
focused). Adjacent selected rows join into one block: inner corners square, the 2pt gap filled. Selection never
animates. Task titles stay `ink` at rest and selected.

**Keys** (list focused, not editing):

| Key | Result |
|---|---|
| ↑ ↓ | Previous / next row (selects the first or last when nothing is) |
| ⇧↑ ⇧↓ | Extend from the anchor |
| ⌘↑ ⌘↓, Home, End | First / last row (⇧ extends) |
| ⌘A | All open tasks in the view |
| Letters and digits | Type-to-select: the first title starting with what you typed in the last second |
| ← | Focus the sidebar |
| Tab / ⇧Tab | Next / previous pane: sidebar → list → detail (when open) |
| Esc | Close the date popover, else hide the detail pane, else clear the selection |

The selected row scrolls into view, keeping 8pt clear of the edges. Sidebar keys are in §12.

---

## 6. Adding tasks

**Triggers**

| Trigger | Where the task goes |
|---|---|
| ⌘N, the pane header's + | In a list: that list. In Today: the selected task's list, else the default list (the first active list, SPEC §2), with When = today |
| Clicking the empty space under a list's open tasks | That list. Hovering the space shows a ghost row in the landing slot: a dashed-feeling ring (`ink-quiet` at 80%) and "New Task" in `ink-tertiary`, in on `hoverIn`, out on `hoverOut` |
| A Today group label's + (revealed on hover) | That list, When = today |
| "New Task in School" in a sidebar list's menu | Opens School, then adds |

The header + tooltip names the target in Today: "New Task in Inbox ⌘N". That is the discoverable mark of the default
list; the sidebar carries none.

The new row opens **where the task will land**: the bottom of the list's open tasks (SPEC §3: new tasks append), or the
bottom of its group in Today, creating the group if it wasn't showing. Rows below slide down on `layout`; the new row
fades in (180 ms). It scrolls into view. If every list is archived, ⌘N shows the notice "Create a list first: ⇧⌘N".

**The editing row** (variants A and B): the row's fill becomes `surface-base` with a 1.5pt inset `accent` ring at radius
8, the checkbox shows as a placeholder ring (`ink-quiet`, 70%), and the title is a text field exactly where the title
text sits (same font, same origin: nothing shifts). Placeholder "New Task".

| Key or event | Result |
|---|---|
| Return with a title | Add it (one `task.create`), then open the next new row right below it, in the same list |
| Return or Tab on an empty row | Close it; nothing is created |
| Esc | Cancel this row; nothing is created |
| Clicking anywhere else | Add it if it has a title, else drop it |
| ⌘N again | Same as Return |

A dropped row writes no op. After the last row closes, the last added task stays selected and the list keeps keyboard
focus.

**Variant A, inline row.** Title only. Dates come afterwards: ⌘S, a chip, the context menu or the detail pane.

**Variant B, inline row that reads dates.** As A, and trailing date words are read as you type (strict grammar, §11):
"Call dentist fri" → When Fri; "Essay due nov 9" or "… by nov 9" → Deadline Nov 9; both together work ("Pay rent
tomorrow due fri"). Recognised dates show at once as chips in the row's chip slot with the `pending` look
(`accent-tint` fill, `accent-text`, 1pt `accent` ring). On Return the words leave the title and the dates are set. Only
the end of the title is read, so "Call Fri about tickets" stays a title. The strict grammar never reads bare numbers,
"sat" or "sun" (it would eat "Read chapter 4" and "Enjoy the sun"): use "saturday", "sunday".

**Variant C, straight into the detail pane.** ⌘N creates the task (still a draft, no op yet), selects its row, opens the
detail pane on `natural` and puts the cursor in the detail title. The row shows the title as it's typed. Return moves
to the notes. Esc or clicking elsewhere adds it if it has a title, or drops it and closes the pane if not. There is no
chaining; ⌘N again for the next.

---

## 7. Editing

### Titles in rows (tasks) and names (lists)

| Trigger | Caret |
|---|---|
| Double-click a title | Where you clicked |
| Double-click the rest of a row | At the end |
| Return on the selected task (list focused) or list (sidebar focused) | Whole title selected |
| Rename in the context menu | Whole title selected |

The field replaces the title in place (same font, origin and color), and the row shows the editing look of §6.
Return, Tab or clicking elsewhere commits (one `task.update`/`list.update`, only if it changed). Esc restores the old
text. A list name can't be empty: committing an empty name restores the old one. Clicking inside the field while editing
moves the caret and never ends the edit (Rex fixed the same bug, preview.12). Double-click doesn't rename a completed
(struck-through) task; Return and the detail pane still do.

### Detail pane

- **Title**: always an editable field (no ring; the caret is the cue), 15/20 semibold, wrapping to 4 lines. Return goes
  to the notes; Esc restores and leaves the field; clicking away commits.
- **Notes**: rendered inline Markdown (SPEC §2) in 13/19 `ink`; placeholder "Notes" in `ink-tertiary`. Clicking
  anywhere in it switches to the raw text **in the same font and place** (no mono switch, no Edit/Preview control), caret
  at the end. Clicking a link opens it instead. Esc, ⌘Return or clicking away is "done" and keeps the text (notes are
  long; Esc never throws them away). One `task.update` per edit session.
- Footer: "Created Oct 26" (and "· Completed Oct 30"), 11/14 `ink-tertiary`.

---

## 8. Completing

**Checkbox** (16pt ring, `line-field`):

| State | Look | Timing |
|---|---|---|
| Hover (on the box) | Ring → `ink-secondary` | `hoverIn` / `hoverOut` |
| Pressed | Scales to 0.86 | 80 ms ease-out |
| Checked | Fills `accent`, ring `accent`; the check draws (stroke 0→100%) in `on-accent`; a pop from 0.8 | fill 160 ms ease-out, draw 160 ms after 40 ms, pop on `snappy` |
| Checked row | Title `ink-tertiary` with a strike in `ink-quiet` | 200 ms ease-out |

Triggers: click the box, Space or ⌘K on the selection (mixed selections complete all; all-done selections uncomplete),
the context menu, the box in the detail pane.

**Checked rows stay put, then move** (open choice §1):

- *After 1.5 s* (recommended): the row stays checked in place until 1.5 s pass with no further checks (each check
  restarts the timer), so you can check a run of tasks or undo a misclick by clicking again. Then every checked row
  moves together on `layout`: in a list it slides down into the Completed row and fades (150 ms), and the Completed
  count ticks up; in Today it slides into the Completed group at the bottom.
- *On leave*: they stay in place until you switch lists or views.

Unchecking mirrors it: the row stays in the completed area, then slides back to its old place (its order key never
changed, SPEC §3).

**Where done rows go.** A list ends with a disclosure row "› Completed 23" (`ink-secondary`, 13 medium, count
`ink-tertiary`), collapsed by default; the chevron turns 90° in 200 ms; expanded, it lists them newest first. Today ends
with a "Completed" group (same label style as list groups) holding tasks completed today, oldest first, each with its
list's name at the right in `ink-tertiary`.

---

## 9. Deleting, undo and notices

**Delete**: ⌘⌫, "Delete" in the context menu, the detail pane's trash button. All selected tasks go at once, with no
confirmation. Rows fade (150 ms) while the rest close up on `layout`. The selection moves to the next row below, else
above, so repeated ⌘⌫ walks down the list like Mail.

**Notice.** An action that takes items out of the view shows a notice at the bottom-right of the list pane: "Deleted
“Buy milk”", "Deleted 3 tasks", "Moved to School", "Archived School", "Scheduled for Fri, Nov 6" (a date that took a
task out of Today). It has an **Undo ⌘Z** tinted capsule. A new notice replaces the old one. It lives 5 s, stays while
hovered, and leaves 2 s after the pointer does. Undo from the notice is ⌘Z.

**Undo.** ⌘Z / ⇧⌘Z undo and redo every change as new ops (SPEC §6), with the action names used here so the Edit menu
reads "Undo Delete", "Redo Move". After an undo or redo: the restored tasks are selected and scrolled into view; if they
live in another view, that view opens (instantly). A short notice without a button confirms it ("Undo Delete", 1.8 s).
Inside a text field ⌘Z is the field's own text undo.

---

## 10. Moving between lists

| Trigger | Notes |
|---|---|
| Drag onto a sidebar list | §14 |
| Drag onto Today | Sets When = today (the task stays in its list) |
| ⇧⌘M | Pops the native "Move to" menu under the first selected row: a header 'Move “Buy milk” to', every active list with its tile and ⌘1–⌘9, the current list checked and disabled |
| Context menu → Move to ▸ | The same list, as a submenu |
| Detail pane → List pop-up | The same list |

Moved tasks land at the bottom of the target (SPEC §3). In a list view they leave (fade, close up, selection moves on)
and the notice says "Moved to School". In Today they stay visible, regrouped, with no notice. Archived lists are never
offered.

---

## 11. Dates

### How chips read (rows)

| Date | When chip (calendar icon) | Deadline chip (flag icon) |
|---|---|---|
| Past | "Today" (a past When carries forward, SPEC §4) | "Overdue · 2d", `danger` |
| Today | "Today" | "Due today", `attention` |
| Tomorrow | "Tomorrow" | "Tomorrow" |
| 2–6 days | "Mon" | "Mon" |
| Later this year | "Nov 9" | "Nov 9" |
| Another year | "Jan 4, 2027" | "Jan 4, 2027" |

When before Deadline. In Today a When on or before today is left out (it's why the task is there). Done rows show no
chips. Neutral chips are `fill-control` + `ink-secondary`. A chip is a button: hover brightens it (`icon` timing), press
darkens to 86%, and while its picker is open it's `accent-tint` + `accent-text`.

**Detail pane rows**: List (pop-up: tile, name, ⌃⌄), When, Deadline. A set date is a large chip with the full date
("Fri, Nov 6") and the relative date after it in `ink-tertiary` ("in 7 days", "2 days ago"); hovering the row reveals a
× (Remove When / Remove Deadline) in the slot right after the chip. An empty date is a ghost chip "Add date"
(transparent, 1pt `line-separator` ring, `ink-tertiary`; hover `hover` fill and `ink-secondary`).

### Opening a picker

Click a chip (row or detail pane), ⌘S (When…) or ⇧⌘D (Deadline…) on the selection, "Choose Date…" in the context menu.
The popover opens 6pt under its anchor (the chip, or the row's right end for keyboard opens), flipping above when it
wouldn't fit, and applies to every selected task. The field has keyboard focus and is empty; the highlighted day starts
at the current date (or today). Clicking outside closes it and does nothing else (Rex, preview.18). Setting a date
closes it and returns focus to the list.

Quick sets without a picker: ⌘T (When: Today), the context menu's When ▸ Today / Tomorrow / This Weekend / Next Week /
Remove, and Deadline ▸ Remove.

### Typed dates

Calendar dates only (SPEC §2). Today = the Mac's local date.

| You type | Result |
|---|---|
| `tod`, `today` | Today |
| `tom`, `tmr`, `tmrw`, `tomorrow` | Tomorrow |
| `mon` … `fri`, any weekday, unique prefixes (`th`, `we`) | The next one after today (on a Friday, "fri" is next Friday) |
| `next fri` | Friday of next week (weeks start Monday) |
| `weekend`, `this weekend` | Saturday (today if it's the weekend) |
| `next week` | Next Monday |
| `next month` | The 1st of next month |
| `3d`, `3 days`, `in 3 days`, `2w`, `in 2 weeks`, `1m`, `a month`, `+5` | Relative |
| `nov 9`, `9 nov`, `november 9th`, `11/9`, `2026-11-09` | That date; without a year, the next one that isn't past |
| `9`, `9th` | The next 9th of a month |
| `yesterday` | Yesterday (allowed; deadlines can be past) |

Numeric dates follow the user's locale order in the app (the prototype reads M/D).

### Variant A: calendar popover (288pt)

Top to bottom: the field (calendar icon, placeholder "When: try tom, fri, 3d, nov 9"); quick picks Today · Tomorrow ·
Next Week (22pt capsules) and Clear when a date is set; the month ("November 2026", ‹ ›) and its grid (Sunday first;
28pt day capsules); a footer previewing what Return sets ("Fri, Nov 6 · in 7 days  ↩"), or "No date matches “xyz”".

- Typing moves the highlighted day (`accent` fill, `on-accent`) to the best match; the matching quick pick tints.
- ← → move it a day, ↑ ↓ a week (the field never needs its caret keys). Return sets it. Clicking a day sets it.
- Today's number is `accent-text` semibold; the current value has a 1.5pt `accent` ring; the *other* date (the deadline
  while picking When, and the reverse) has a 4pt `attention` dot.
- ⌫ in the empty field clears the date. Esc closes.

### Variant B: suggestion list (288pt)

The field, then a list like Rex's command palette: with nothing typed, Today, Tomorrow, This Weekend, Next Week; while
typing, the exact match first, then phrases that start with the text ("th" → Thursday, This Weekend; "3" → Tue, Nov 3,
In 3 days, In 3 weeks). Each row: the phrase, and the date right-aligned in `ink-tertiary`. Then "Choose on Calendar…"
(shows A's month below; arrows then move the day) and "Clear  ⌫" when a date is set. ↑ ↓ move the highlight (menu
style: `accent` fill, white text), Return chooses, clicking chooses. "No date matches" when nothing does.

### Clearing

Clear in the picker, ⌫ in the picker's empty field, the × beside a detail chip, the context menu's Remove.

---

## 12. Lists and the sidebar

**Sidebar rows** (Today, lists, archived lists):

| State | Look |
|---|---|
| Rest | Title `ink-secondary` **Rex**; count `ink-tertiary`, tabular |
| Hover | Title → `ink` (`hoverIn`, out on `hoverOut`). No fill, no trailing action |
| Current | `fill-strong` capsule with the two-step edge, title `ink`, count `ink-secondary` **Rex** |
| Archived | Title `ink-tertiary`; no count |
| Drop target (a task drag) | `accent-tint` fill, 2pt inset `accent` ring, title and count `accent-text` (`hoverIn`; instant out) |
| Being renamed | `fill-control`, 1.5pt inset `accent` ring, the name as a field in place |
| Holding ⌘ (450 ms) | Counts give way to ⌘1 (Today), ⌘2–⌘9 (active lists) in `ink-secondary` 12pt (Rex, preview.16) |

Clicking a row opens it on mouse-down (instantly) and focuses the sidebar. Counts are open tasks (Today: open tasks in
Today). Long names fade out under a gradient before the count (Rex: no ellipsis).

**Group labels.** "Lists" reveals a + (New List ⇧⌘N) on hover. "Archive" reveals a chevron; clicking the label toggles
the group (collapsed by default; the chevron turns 90°). Labels never take selection.

**Sidebar keys** (sidebar focused): ↑ ↓ open the previous / next row; letters type-select by name; Return renames;
⌥⌘↑ ⌥⌘↓ move the list; ⌘⌫ archives it; → Tab Esc return to the list. Anywhere: ⌘1 Today, ⌘2–⌘9 the first eight active
lists.

**Create**: ⇧⌘N, the "Lists" +, or the sidebar's empty-space menu. A new row appears at the bottom of Lists in the
renaming state with placeholder "New List" and a tile whose monogram follows the typing. Return or clicking away creates
it (one `list.create`) and opens it, with the list focused so ⌘N adds the first task; Esc or an empty name cancels and
writes nothing.

**Rename**: double-click (Rex, preview.15), Return, or Rename in the menu (inline here; Rex sends menu renames to its
palette, which Tasks doesn't have).

**Reorder**: drag (§14), ⌥⌘↑ ⌥⌘↓, or Move Up / Move Down in the menu (Rex has the same pair for sessions). Today and
archived lists don't move.

**Archive**: Archive in the menu or ⌘⌫ with the sidebar focused. No confirmation. The row fades as the rows below close
up; if it was open, the next active list opens (Today if none). Notice "Archived School · Undo". The Archive group
appears when the first list is archived.

**The archive view.** Archived lists sit in the collapsible Archive group at the bottom of the sidebar, newest first.
One opens as a normal list pane, header "School  Archived", with a banner on top: archive icon, "Archived Oct 28 · Not
in Today or Move to. Everything still edits." and a tinted **Unarchive** button. Unarchive (or Unarchive in its menu, or
⌘Z right after) puts it back in its old place in Lists (SPEC §2).

---

## 13. Today

- Groups follow sidebar order; each starts with its list's name as a group label; rows keep their list's order (SPEC
  §4). A group label's + adds a task to that list for today.
- Drag reorders within a group only; the row can't leave its group (§14). Dropping on a sidebar list moves the task and
  it re-groups; dropping on Today does nothing new.
- A date change that takes a task out of Today (⌘S → "tom") fades it out and shows "Scheduled for Sat, Oct 31 · Undo".
- **Empty states**, centered in the pane, never clickable:
  - Nothing today: sun glyph in `ink-quiet`, "Nothing for today" (`ink-secondary`, medium), "Tasks you plan for
    today, or that are due, show up here." (`ink-tertiary`, 12).
  - All done (only completed tasks today): a check-circle in `accent`, "All done for today", 40pt below the header,
    with the Completed group under it.
  - An empty list: "No tasks" and "Click anywhere here or press ⌘N to add one."; the ghost row shows in the first slot
    on hover.

---

## 14. Drag

One model for task rows and sidebar lists. **No grip; the whole row is the handle.**

| Phase | Behaviour |
|---|---|
| Press | Selects (§5). Nothing lifts yet |
| Move 4pt | Lift: a copy of the row (or the grabbed row of a multi-selection) follows the pointer, keeping the grab offset; `fill-lift`, radius 8, `shadow-lift`. Several tasks: an `accent` badge with the count at its top-right (18pt, 11 semibold). The source rows are hidden (gap) or drawn at 35% (line) |
| Over the list | **Gap**: the other rows part on `layout` to open a slot where it will land. **Line**: rows stay; a 2pt `accent` line with an 8pt ring at its leading end sits in the gap at the target (from x 46). The copy stays inside its group: it stops 6pt past the first and last slot (a list's open tasks; one Today group) |
| Near the top or bottom edge (24pt) | The list scrolls, 8pt per frame |
| Over a sidebar list (tasks) | The row's group closes up (it's leaving). The target row shows the drop-target state. The copy becomes a compact 210pt tag at the pointer (+12, +8) so the target stays readable. Today is a target (sets When = today); the current list, archived lists and labels aren't |
| Drop on the list | The copy flies into its slot (160 ms), then the rows are written (one op per task, `keysBetween`, SPEC §3) and shown in place |
| Drop on a sidebar list | The copy flies to the row and fades (160 ms); the move is written; notice "Moved to Errands" |
| Esc | The copy flies back (200 ms) and the rows close the gap. Nothing is written. (Releasing anywhere else drops at the last slot shown, as in a Mac list) |

**Sidebar lists** drag the same way, vertically only: the copy is the capsule (`fill-strong`, `shadow-lift`), clamped to
the Lists rows, and the other rows part. Today and archived lists can't be dragged.

---

## 15. Context menus (native NSMenu)

**A task** (right-click selects it first unless it's already in the selection; the menu then acts on the selection):

```
Show Details            ⌘D        (one task)
Rename                  ↩         (one task)
Show in School                    (one task, in Today)
────────
Complete                ⌘K        ("Complete 3 Tasks"; "Mark as Not Done" when all are done)
When                    ▸  Today ⌘T · Tomorrow · This Weekend · Next Week · ── · Choose Date… ⌘S · ── · Remove
Deadline                ▸  Choose Date… ⇧⌘D · ── · Remove
Move to                 ▸  "Move to" header · each active list with its tile, ⌘1–⌘9, current ✓ and disabled
────────
Delete                  ⌘⌫        ("Delete 3 Tasks")
```

**A list**: New Task in School · Rename ↩ · ── · Move Up ⌥⌘↑ · Move Down ⌥⌘↓ · ── · Archive ⌘⌫.
**An archived list**: Unarchive · Rename ↩.
**Empty sidebar space**: New List ⇧⌘N.

Removed items are disabled, not hidden. No ellipsis on actions that happen at once (Archive, Delete); "Choose Date…"
keeps one because it asks for input (macOS rule).

---

## 16. Hover, press and focus for every control

| Control | Rest | Hover | Pressed | On / current |
|---|---|---|---|---|
| Task row | — | Only the › fades in (`hoverIn` / `hoverOut`); hidden while the detail pane is open | Selects on mouse-down | §5 |
| › (show details) | `ink-tertiary`, hidden | `hover` fill, `ink-secondary` (`icon`) | `press` fill, instant | — |
| Checkbox | §8 | §8 | §8 | §8 |
| Chip | §11 | brightness 1.18 dark / 0.96 light (`icon`) | 86%, instant | picker open: `accent-tint` |
| Sidebar row | §12 | §12 | opens on mouse-down | §12 |
| Group label's + / chevron | hidden | revealed with the label's hover; own hover: `hover` fill, `ink-secondary` | `press` fill | chevron turned when open |
| Pane-header icon button | `ink-quiet`; 55% in an unfocused pane | `hover` fill (radius 6), `ink-secondary` (`icon`) | `press` fill, `ink`, instant | split button `ink-secondary` while the detail is open |
| Toolbar icon (sidebar toggle) | `ink-secondary` | `fill-track` circle, `ink` **Rex** | `press` fill | — |
| Capsule button (Undo, Unarchive) | tinted | brightness 1.12 / 0.97 | 86%, instant | — |
| Pop-up (detail List) | — | `hover` fill, radius 6 | `press` fill | — |
| Menu item | — | `accent` + white, instant (native) | — | ✓ column when the menu has checks |
| Date popover day | — | `hover` fill | — | highlighted `accent`; current ring; today `accent-text` |
| Notice | — | holds it open | — | — |
| Text fields | — | — | — | inline row/list fields: 1.5pt `accent` ring on the row; detail fields: caret only; selected text `text-selection` |
| Disabled anything | 45% | — | — | — |

**Tooltips** (Rex draws its own, with keys, preview.23): on every icon button and chip-less control: the name, then the
shortcut in `ink-secondary` ("New Task ⌘N", "Hide Sidebar ⌃⌘S"). 600 ms delay, 100 ms fade in, instant while moving
between buttons, gone on press or when the pointer leaves.

---

## 17. Keyboard (complete)

| Keys | Action |
|---|---|
| ⌘N | New task (§6) |
| ⇧⌘N | New list |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌘1 / ⌘2–⌘9 | Today / the first eight active lists; hold ⌘ to see them |
| ⌃⌘S | Show or hide the sidebar |
| ↑ ↓ ⇧↑ ⇧↓ ⌘↑ ⌘↓ Home End ⌘A | Selection (§5) |
| Letters | Type-to-select (tasks or lists, by focus) |
| ← → Tab ⇧Tab | Move between sidebar, list and details |
| Return | Rename the selected task or list |
| Space, ⌘K | Complete or uncomplete |
| ⌘D | Show or hide details |
| ⌘S / ⇧⌘D | When… / Deadline… |
| ⌘T | When: Today |
| ⇧⌘M | Move to… (⌘1–⌘9 inside it) |
| ⌥⌘↑ ⌥⌘↓ | Move the selection (or the sidebar list) up or down |
| ⌘⌫ | Delete tasks; with the sidebar focused, archive the list |
| Esc | Cancel the innermost thing: drag, menu, popover, edit, then the detail pane, then the selection |
| ⌘R / ⌘, | Sync now / Settings (unchanged) |

In text fields, text keys win: Space, Return (commit), ⌘⌫, ⌘Z and the arrows edit text. ⌘N still adds.

Menu bar: File ▸ New Task ⌘N, New List ⇧⌘N · Edit ▸ Undo, Redo, Select All · Task ▸ Show Details ⌘D, Complete ⌘K,
When… ⌘S, When: Today ⌘T, Deadline… ⇧⌘D, Move to… ⇧⌘M, Move Up ⌥⌘↑, Move Down ⌥⌘↓, Delete ⌘⌫ · View ▸ Today ⌘1,
lists ⌘2–⌘9, Show/Hide Sidebar ⌃⌘S.

---

## 18. Building it (SwiftUI and AppKit)

Where SwiftUI's defaults fight the design, and what to use instead.

1. **Task list rows.** Give rows identity by task id inside the lazy stack and animate model changes with
   `withAnimation(PaneMotion.layout)`; wrap list switches in a transaction with animation disabled. That's what makes
   reorder, insert, delete and settle move instead of jump. v1's positional slots made switching faster but can't
   animate a moving task; measure switching against SPEC §9 with ids, and if it's over budget keep the slots and animate
   with a FLIP (remember each task's last y, start the new slot's content at the old y with `.offset`, animate to 0).
2. **Hover: one tracker per list, not per row.** `.onContinuousHover` on the list container; the row index is
   `floor((y + scrollOffset − 4) / 32)`; store `hoveredTaskID` in an observable that only the two affected rows read.
   Recompute on scroll (the pointer is still but the rows move). `.ended` clears it. This replaces v1's `PaneHoverRegion`
   and its missed exits. The checkbox, chips and › use their own `.onHover`: they're small and never stacked.
3. **Selection and keys.** The list is `.focusable()` with `.focusEffectDisabled()`; keys through `.onKeyPress` (macOS
   14), letters through `.onKeyPress(characters: .alphanumerics)` with a 1 s buffer. Take focus on mouse-down in the
   list (v1 found SwiftUI won't).
4. **Inline text fields.** An `NSTextField` subclass in `NSViewRepresentable`, borderless, no background, same font and
   origin as the label it replaces. Caret at the click: after it becomes first responder, set
   `currentEditor()?.selectedRange` from the click's character index (`NSLayoutManager.characterIndex(for:in:…)` on
   the label's text). Return/Tab/Esc via `control(_:textView:doCommandBy:)` (`insertNewline`, `insertTab`,
   `cancelOperation`). Esc restores, so keep the original string.
5. **Context menus** are `.contextMenu` (native, submenus via `Menu`). ⇧⌘M pops the same `NSMenu` under the row with
   `NSMenu.popUp(positioning:at:in:)` from a small AppKit bridge; ⌘1–⌘9 are its items' key equivalents.
6. **Date popover.** Not SwiftUI's `.popover` (macOS draws an arrow and its own animation). Draw it in the window's
   overlay layer anchored to the chip's `anchorPreference`, with a full-window transparent catcher behind it that
   consumes the click that closes it (so the click doesn't also select a row). The field takes focus with `@FocusState`
   when it appears.
7. **Notices and tooltips** live in the same overlay layer. Tooltips are custom (Rex's own style); `.help()` would give
   the system's delay and look.
8. **Drag is in-window and custom.** A `DragGesture(minimumDistance: 4, coordinateSpace: .named("window"))` on each row
   drives a window-level drag model; the overlay draws the lifted copy; the list derives the target slot from the
   pointer and the 32pt pitch; sidebar rows publish their frames as anchor preferences for hit-testing; Esc cancels via
   the focused list's `.onKeyPress(.escape)`. Not `.draggable`/`.dropDestination`: v1 hit cancelled async item
   providers, `dropUpdated` after `performDrop`, and had no control over the lifted image, the gap or cancel.
9. **Checked rows that wait.** A `pins: [TaskID: Placement]` map in the window state places checked/unchecked tasks
   where they were; a 1.5 s debounce (restarted by each check) clears it inside `withAnimation(PaneMotion.layout)`;
   a route change clears it too.
10. **The add slot.** The empty space below the last open task is one `Color.clear.contentShape(Rectangle())` with
    `.onHover` (shows the ghost row in the landing slot) and a tap that adds.
11. **Held ⌘.** `NSEvent.addLocalMonitorForEvents(matching: .flagsChanged)`, 450 ms timer; any key or release hides.
12. **Undo** registers on the window's `UndoManager` with `setActionName` ("Delete", "Move", "Complete", "Rename Task",
    "Set When", "Archive List", "New Task", "New List"…) and the selection to restore.

---

## 19. What changed from v1, and why

| v1 (`design/INTERACTIONS.md`) | v2 | Why |
|---|---|---|
| ••• on every hovered task row, opening a menu | Right-click for the menu; one › that opens the details | The menu duplicated right-click; the › opens the pane the user likes |
| Hover regions per row with their own tracking | One tracker per list; rows reveal only the › | Missed exits and lit rows were the "horrendous" part |
| `fill-selected` (#272728) selection | #333333 / #292929, joined across rows | #272728 is 1.1:1 on the pane: selection was hard to see |
| Quick add editor: title, notes, chips, key hints | The row itself, where the task lands (A), or B/C | Fewer controls, nothing moves, Return chains |
| Move to… sheet | Native menu at the row | A sheet for a one-word choice |
| Notes: Edit / Preview control, mono editing | Click to edit in place, same font | No mode switch, no reflow |
| Archive pane beside the list | A collapsible Archive group in the sidebar | One less pane type |
| SwiftUI item-provider drags | In-window custom drag, gap model, Esc cancels | v1's drop bugs; no control over the lift |
| Rows jump when order changes | Rows move on one spring | The list should show what happened |

The detail pane's open and close is unchanged.

---

## 20. Questions for a Rex measurement (for the coordinator)

I didn't drive Rex (per the brief). These are the values I had to choose without it:

1. **Notices**: which corner, size, lifetime, and entry/exit motion. (Tasks: bottom-right of the pane, 34pt, 5 s, rise
   8pt in 220 ms.)
2. **Tooltips**: delay, fill, radius, padding, and the key style. (Tasks: 600 ms, `surface-popover`, radius 6.)
3. **Inline rename** of a sidebar tab: the field's look (fill? ring?) and whether the text is selected.
4. **Sidebar tab drag**: does Rex part the rows (gap) or draw a line? What does the lifted tab look like?
5. **Light theme**: the current capsule's fill and edge, and the ink ladder (Tasks uses Pane's light values).
6. **Unfocused pane fill**: is it exactly `surface-ground` (#181818)?
7. **Context menus**: native `NSMenu`? (Assumed: hot items white on accent.)
8. **Held-⌘ hints**: glyph style and position in the sidebar.
