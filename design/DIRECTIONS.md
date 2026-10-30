# Tasks — design directions

Status: **decided, 2026-10-30. A1 · Split is the chosen direction.** Built on the **Pane** design system ([Claude Design](https://claude.ai/artifact/MS3VdrN9VHU7A7pTUTzpm8), `design/PaneTheme.swift`). macOS only. Reconciled with `docs/SPEC.md` as of its 02:46 revision.

All three directions are variations on one idea, **Panes**: the app looks and behaves like Rex, with tasks where Rex has terminals. A2 and A3 are kept for reference; two pieces of A3 are folded into A1 (see Decision). An earlier direction, B · Ledger, was dropped.

| Direction | Canvas | One line |
|---|---|---|
| **A1 · Split** (chosen) | https://claude.ai/artifact/9URE17WrdoaBVmYQeUUbJN | One list pane. Opening a task splits a detail pane to the right. |
| A2 · Tiles | https://claude.ai/artifact/K43Yt2VtS94Nu9FcHQpDWC | Lists are panes. Several sit side by side, and tasks open in place. |
| A3 · Drill-in | https://claude.ai/artifact/Dm2Qp7aLxZx69tYM1ztEwR | One compact Glass window. A task opens full-pane, with back and forward. |

The canvases are private until you share them from the page's Share menu. Every board has a **theme** tweak (dark/light), and each canvas shows both themes.

---

## What all three share

These parts are the same in every variation, so picking a direction only decides layout and navigation.

- **Sidebar (Rex session tabs).** Today is pinned at the top. Under a `Lists` group label come the lists as 30pt capsule rows, each with a 20pt monogram tile and a count. The current row gets `fill-strong` and `shadow-capsule`. Inbox is an ordinary row; it's first only because it was seeded first. A small `+` glyph after the first list marks it as the default for new tasks (spec §2).
- **Today, grouped by list** (spec §4). Groups follow sidebar order, under `label`-style list names in `ink-tertiary`, the same way Rex labels session groups. Each group keeps its list's manual order. Tasks completed today sit dimmed at the bottom.
- **Task row (32pt).** A checkbox, then the title in `body`, then a date chip only when it tells you something. The chips are *Overdue · 2d* (danger), *Due today* (attention), a future deadline like *Mon* (neutral, flag icon), or a `when` date (neutral, calendar icon). A `when` in the past carries forward with no badge, as the spec says. Rows have no separators; selection is `fill-selected` at `radius-row`.
- **Completed.** Each list ends in a collapsed *Completed 23* row.
- **Drag vocabulary** (A1 Reorder / DragAcross / Sidebar boards):
  - The whole row is draggable. A six-dot grip appears in the row's leading padding on hover, so nothing shifts.
  - The source row stays in place at 35% opacity. The lifted copy follows the cursor with `shadow-lift`.
  - The insertion point is a 2pt `accent` line inset to the row text, with an 8pt ring at its leading end.
  - **Cross-list:** a sidebar list under the cursor turns `accent-tint` with a 2pt `focus-ring`, and a badge reads *Move to Errands*. The task lands at the bottom of that list (spec §3).
  - **Lists** reorder in the sidebar with the same line. Today can't be dragged.
  - **In Today** you can drag within a group only; anywhere else shows the not-allowed cursor.
- **Keyboard.** ⌘N new task, Return opens, ⌘⇧M *Move to…*, ⌘Z undoes everything (moves, completes, deletes, archives), ⌘1–9 picks a list in menus.
- **No confirmations.** Every action can be undone (spec §6), so *Archive List* and *Delete* have no ellipsis and no dialog. That follows Pane's voice rule: an ellipsis means a confirmation comes next.

---

## A1 · Split (chosen)

https://claude.ai/artifact/9URE17WrdoaBVmYQeUUbJN

**Idea.** The window is Rex with one pane of tasks. Return or ⌘D splits a **detail pane** to the right, like *Split right* in Rex. The pane you're typing in is focused (`surface-base`, `line-pane`); the other fades to `surface-dim`, the same focus rule Pane uses for terminals.

Boards:

- **Today** (dark and light).
- **List + detail pane** (light). The When picker is open; notes render as Markdown.
- **Quick add in Today** (dark). The list menu is open and Inbox is preselected.
- **Drag to reorder** (dark).
- **Drop onto another list** (light).
- **Sidebar list reorder.**
- **Empty states.**
- **Archive** (dark). Archived lists sit in a pane. The selected one opens beside it as a normal, editable list with an *Archived* banner and *Unarchive*.

**Interactions.**

- **Detail pane.** It shows the title in `title` style, Markdown notes, and a hairline group of List / When / Deadline rows. List is a pop-up, so moving from the detail is one click. When and Deadline are large chips that open the date popover.
- **Quick add.** ⌘N opens an editor row with a focus ring. Title, then Tab to notes, then chips: list (preselected), When (prefilled *Today* when started from Today), Deadline. In Today the editor sits at the top of the pane. In a list it sits at the bottom of the open tasks, where the task lands (spec: new tasks go to the bottom).
- **Archive.** The Archive item appears at the bottom of the sidebar only when something is archived, matching the spec.

**Tradeoffs.**

- Pros:
  - The closest to Rex, and the least new UI.
  - It maps straight onto the spec's `NavigationSplitView` (sidebar | list | detail).
  - Detail has room for long notes without leaving the list.
- Cons:
  - Only one list is visible at a time. Cross-list work goes through the sidebar or ⌘⇧M.
  - Two panes in a narrow window get tight. Under about 900pt the detail should replace the list instead of splitting, which is A3's model.

## A2 · Tiles (not chosen)

https://claude.ai/artifact/K43Yt2VtS94Nu9FcHQpDWC

**Idea.** Push the Rex metaphor further: every pane is a list, and you tile as many as you like. ⌘D splits a new pane, ⌘W closes one, and clicking a sidebar list swaps the focused pane (⌘-click opens it beside). The sidebar marks open lists with `fill-selected` and the focused one with `fill-strong`.

Boards:

- **Today | School** (dark and light).
- **Task opened in place** (light), with the List menu open.
- **Quick add** at the bottom of the focused list (dark).
- **Drag between panes** with exact placement (dark).
- **New pane chooser** (light). It doubles as the Archive: archived lists sit at the bottom with *Unarchive*.

**Interactions.**

- **No detail pane.** Return grows the row into a card with the title, notes and three chips (list, when, deadline), and Esc closes it.
- **Quick add** needs no list picker, because it adds to the pane you're in.
- **Moving.** Drag a task into another pane and drop it exactly where the line shows.

**Tradeoffs.**

- Pros:
  - Today and a list side by side is genuinely useful (plan the day while looking at School).
  - Moving between lists becomes direct manipulation with exact placement.
- Cons:
  - **Layout is new persistent state:** which panes are open and their widths. It would be per-window local state, not in the log.
  - `NavigationSplitView` can't tile, so this needs a custom HStack of `PaneChrome` with resizable dividers.
  - A positioned cross-list drop needs a small spec change (below).
  - Inline cards squeeze long notes.
  - The most code of the three.

## A3 · Drill-in (not chosen; two pieces adopted into A1)

https://claude.ai/artifact/Dm2Qp7aLxZx69tYM1ztEwR

**Idea.** A smaller, quieter window (about 880×640) in Pane's **Glass** interface style. There's one pane, and its header is Pane's **Toolbar**: the back/forward history capsule and the page title. Return opens the task *in the same pane*, ⌘[ goes back.

Boards:

- **Today** (dark and light Glass).
- **Task page** (light). Notes are in Edit mode with an Edit / Preview segmented control.
- **Quick entry from anywhere** (dark).
- **Archived group** in the sidebar, with the list context menu showing *Archive List* (dark).

**Interactions.**

- **Task page.** Title, then a Pane card of List / When / Deadline rows, then notes with room to write.
- **Quick entry.** A floating Glass panel on ⌃⌥Space from any app adds to the default list (Inbox on a fresh install).
- **Archive.** A collapsed *Archived* group at the bottom of the sidebar.

**Tradeoffs.**

- Pros:
  - Simplest navigation: `NavigationSplitView(sidebar:detail:)` with a `NavigationStack` in the detail.
  - Fits a small window or a side-of-screen utility.
  - The best room for Markdown notes.
- Cons:
  - Opening a task hides the list.
  - Real `glassEffect` is macOS 26; macOS 14–15 fall back to `.ultraThinMaterial`.
  - Glass costs some contrast, so pane fills stay at 84–90% opacity to keep `ink-secondary` legible.
  - A global hotkey panel is an extra AppKit piece (an `NSPanel` plus a hotkey registration). It isn't pure SwiftUI.

---

## Decision

**Chosen: A1 · Split, in Classic style,** with two pieces from A3:

1. **A3's notes Edit / Preview control** in A1's detail pane. It makes the spec's raw-edit / rendered-view split explicit.
2. **A3's drill-in behavior as A1's narrow-window fallback.** Under about 900pt, Return pushes the task in place of the list instead of splitting.

**Glass** stays Pane's existing app-level *Interface style* setting, not a separate design. **A2's tiling** and **A3's global quick entry** are deferred to after v1. Both are additive and need no model changes.

Why A1: it's the simplest thing that is unmistakably Rex. It uses Pane's pane chrome and focus rule exactly as designed, maps onto the spec's `NavigationSplitView`, and keeps every interaction (drag, move, quick add, archive) on one consistent surface.

---

## New Pane components and tokens

Everything derives from the existing theme inputs and Pane's mix rules. Contrast figures were checked against the default Dark / Light themes.

| Component | Spec | Derivation |
|---|---|---|
| **Checkbox** | 16pt circle. Ring 1.5pt; done = filled with a 2.2pt check. A placeholder ring marks the editor row. | Ring `line-field` (3.2:1 dark, 3.65:1 light). Done is an `accent` fill with an `on-accent` glyph (4.55 / 5.19). The editor row uses `ink-quiet` at 60%. Fill and strike-through animate with `PaneMotion.snappy`. |
| **Date chip** | Capsule, 18pt (22pt in editors), 7pt side padding, 11/14 medium, 11pt calendar or flag icon. | Neutral is `fill-control` + `ink-secondary` (4.53 / 5.0); `fill-track` fails in dark (4.34). *Due today* is the **new `attention-tint`** + `status-attention`. *Overdue* is `danger-tint` + `danger-text` (5.40 / 4.64). Picked is `accent-tint` + `accent-text` (5.08 / 4.51). Ghost (*add date*) is transparent with an inset `line-separator`. |
| **List mark** | 20pt tile (16 in pane headers, 12–14 in chips and menus), monogram in mono bold. | Pane's *program tile*: `fill-strong` + `shadow-capsule`, glyph in an ANSI color. ANSI on `fill-strong` is about 3.7:1, which passes the 3:1 non-text bar. It's decorative and always next to the list name. |
| **Insertion line** | 2pt line, inset 32pt to the row text, with an 8pt leading ring. | `accent`; the ring is filled with `surface-base`. |
| **Drop target** | A sidebar row (or, in A2, a pane) under a drag. | `accent-tint` fill, `accent-text` label, 2pt inset `focus-ring`. |
| **Lifted row and grip** | The drag image; a 6-dot grip, 8×14. | Row on `surface-base` (light) / `fill-capsule` (dark) with the **new `shadow-lift`**. Grip in `ink-quiet`, hover only. |
| **Popover / menu** | 12pt radius, 6pt padding, 26pt items. | `surface-card` (dark) / `surface-base` (light), **new `shadow-popover`**. The hot item is `accent` + `on-accent`. Separators are `line-separator`, inset 8. |
| **Date popover** | A typed-date field, quick picks (Today, Tomorrow, Next week), a month grid, *No date*. | The field is Pane's search capsule. Days are 26pt capsules: today in `accent-text` semibold, picked in `accent` / `on-accent`, the other date's deadline as a 1.5pt `status-attention` ring. Native first: a tinted `DatePicker(.graphical)` can stand in for the grid. |
| **Editor row** (quick add) | Title, notes, chip row and key hints. | `fill-selected` with a 2pt `focus-ring`. Hints use a `kbd` style: 11/14 medium in `ink-secondary`. |
| **Markdown notes** | Rendered body 13/18; edited as raw text in mono 12/18. | Links in `accent-text` with a 1px underline offset 2; inline code in mono 12 on `fill-control`, radius 4. Edit mode may dim syntax marks in `ink-secondary`, but plain mono `TextEditor` is fine for v1. |
| **Archived banner** | Two-line text plus *Unarchive*. | `fill-selected`, `radius-row`, tinted button. |
| **Completed row** | Disclosure chevron, *Completed* in medium, count. | `ink-secondary`. |

New tokens:

- `attention-tint`
  - Dark: `mix(bg, ansi-yellow, 0.14)` = #352E1D.
  - Light: `mix(bg, ansi-yellow, 0.05)` = #FAF7F2.
  - Note: Light has to use 0.05, not Pane's usual 0.09–0.10. The light ANSI yellow on a 0.09 mix is only 4.33:1. Light attention text also fails on `surface-ground` (4.47), so keep attention chips on base or card surfaces.
- `shadow-popover`: `shadow-sheet` with a 12/32 blur instead of 24/64.
- `shadow-lift`: the same with an 8/24 blur.
- Sizes: `size-check` 16, `size-chip` 18 / `size-chip-large` 22. Task rows use `size-sidebar-row` (32).

Existing Pane parts used as-is: PaneChrome (focused and faded panes), the SessionTabs-style sidebar, Button kinds, the search capsule, Sheet-style radii, Toolbar and SegmentedControl (A3), and Classic / Glass.

---

## Where the data model and the design meet

These follow from `docs/SPEC.md` (not edited here). Items 1–6 are already reflected in the boards.

1. **Today is grouped, not sorted by urgency.** I first drew Today sorted (overdue, then due today, then the rest). The spec's grouping keeps the order you control, so the boards now group. The cost is that an overdue task can sit low in its group; the chips carry urgency instead.
2. **New and moved tasks land at the bottom.** So in a list the quick-add row sits at the bottom of the open tasks, where the task will appear. In Today it sits at the top, because Today has no order of its own; the task goes to the default list with `when = today`.
3. **There's no list color in the model. Decided: derive it from the list id.** A deterministic hash of the id picks one of 7 slots (ink, blue, magenta, green, cyan, yellow, red), so every Mac agrees and no field is needed. A `color` key on lists stays possible later as an additive change. The mockups hand-picked colors.
4. **Archived lists are editable** (spec §2). Banners say they're out of Today, not that they're locked. *Move to…* never offers archived lists.
5. **Notes render inline-only Markdown** (`AttributedString(markdown:)` with `.inlineOnlyPreservingWhitespace`): bold, italic, code, links. Bullet lines show as raw `- ` text, and the boards draw them that way. Block rendering is deferred in the spec.
6. **Edits commit on end of editing** (spec), so the detail pane and task page have no Save button. ⌘Z covers mistakes.
7. **Only if A2's tiling comes back later: one spec tweak.** Dropping into another *pane* at a position should write `{list, order: keyBetween(prev, next)}`. That's the spec's reorder op applied across lists: still one op, with `list` and `order` together. The spec currently says cross-list moves land at the bottom. A1 and A3 need no change.
8. **A2's pane layout and A3's window size are local view state.** They're per window, not synced, and not in the log.
9. **Spring-loading** (hover over a sidebar list during a drag to open it and drop at a spot) is optional. Dropping on the row is enough for v1.
