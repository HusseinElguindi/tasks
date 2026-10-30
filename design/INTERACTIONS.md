# Tasks — interaction rules

Status: 2026-10-30. How every control in the macOS app responds to the pointer, the keyboard and drags.

Built from `design/REX-REFERENCE.md` (Rex measured live: sampled colors, scripted hovers, 60 fps recordings), with
Pane for the tokens ([Claude Design](https://claude.ai/artifact/MS3VdrN9VHU7A7pTUTzpm8)). Where they disagree, Rex
wins; each difference is logged for Pane in `design/PANE-UPSTREAM.md`. The app implements these
through shared styles in `app/Tasks/Pane/PaneComponents.swift` and the hover model in `WindowState`; views don't
style states themselves. The bar is the detail pane's open and close, which stays exactly as it is.

## Principles

1. **Hover is barely there and only reveals.** No row, chip or checkbox ever gets a hover fill. A navigation row's
   title brightens and its trailing action fades in; an icon button gets a small fill behind its glyph. That's all.
2. **Selection is the one strong state**: a filled capsule (sidebar) or a filled row (tasks).
3. **Nothing shifts.** Trailing actions take a slot the layout always reserves; long titles fade out with a gradient
   before it instead of ending in "…".
4. **Rex's timing, not a web page's.** Hover-in is near-instant; hover-out is a short fade that starts the moment the
   pointer leaves (nothing lingers); switches are instant. With Reduce Motion on, nothing animates.
5. **One rule everywhere.** The sidebar, task rows and group labels share the same row metrics, hover model and
   trailing-action slot; views get them from the shared components, never their own copies.

## Motion (`PaneMotion`)

| Interaction | Rex (measured) | Tasks |
|---|---|---|
| Row hover in | ~80% on the first frame, settled in 50–70 ms | `hoverIn`: 60 ms on a fast-out curve (measured: 78% on the first frame) |
| Row hover out | fades ~85 ms from the moment the pointer leaves; no hold | `hoverOut`: ease-out 85 ms, at once (measured: settled 67–83 ms after the exit) |
| Icon-button hover in and out | ~100 ms ease-out, no delay | `icon`: ease-out 100 ms both ways |
| Pane focus change | ~60 ms | `focus`: ease-out 60 ms |
| List / tab switch | instant | instant (no animation) |
| Sidebar collapse / expand | ~300 ms, decelerating; the pane slides over the sidebar, which stays put | `sidebar`: 300 ms decelerating curve, same geometry |
| Split (detail pane) | ~230 ms fade + scale from the right | unchanged: the existing `natural` move-and-fade, which the user likes |
| Press | — | instant in, `icon` out |
| Checkbox done | — | `snappy` 200 ms for fill, check, strike and dim, together |

## States

| Element | Rest | Hover | Pressed | Selected / current |
|---|---|---|---|---|
| Sidebar row (Today, lists, Archive, New list) | title `ink-secondary`, icon unchanged; count `ink-tertiary` | title → `ink`; a list's count gives way to its ••• | — | `fill-strong` capsule with the two-step edge, title `ink`, ••• shown (lists) |
| Group label ("Lists", Today's list groups) | `label`, `ink-tertiary` | reveals ⊕ (New List; New Task in that list) in the trailing slot, `ink-tertiary` | — | — |
| Task row | title `ink`, chips | the trailing ••• fades in (`ink-secondary`) | — | `fill-selected` at `radius-row`; ••• shown |
| Row action (•••, ⊕) | revealed by its row | glyph → one step stronger, translucent rounded-square fill (reads on any row fill) | fill one step stronger | — |
| Pane-header icon | glyph `ink-quiet` | `fill-selected` rounded square (`radius-field`), glyph `ink-secondary` | `fill-control`, glyph `ink` | — |
| Toolbar icon (beside the traffic lights) | glyph `ink-secondary` | `fill-track` circle, glyph `ink` | `fill-control`, glyph `ink` | — |
| Capsule button | per kind | — | darkens to 86% (`brightness(0.86)`) | — |
| Chip as button, checkbox | per kind | — | darkens to 86% | an open picker shows the chip `accent-tint` |
| Menu / popover item | — | `accent` + `on-accent`, instant | — | — |
| Pane | unfocused: `surface-dim`, `line-pane-dim`, header icons faded | — | — | focused: `surface-base`, `line-pane`, header icons full |
| Text entry (quick add, rename, date field) | — | — | — | focused: 2 pt `focus-ring`; gone when focus leaves |
| Disabled anything | `opacity-disabled` 0.45 | — | — | — |

Task titles stay `ink` at rest. Rex dims its *sidebar* titles because they are navigation; a task list is content,
and dimming every title would cost the list its legibility for a hover effect. (A decision for the user; see
`app/NOTES-overnight.md`.)

**Hover model** (`PaneHoverRegion`). Each region (the sidebar; a pane's rows, Today's group labels included) holds
one hovered item. Entering an item hovers it at once and un-hovers the previous one; leaving it fades it at once. The
region also clears when the pointer leaves it, when the hovered item disappears (scrolled away, deleted, another list
opened) and when a drag starts, so a missed exit can't leave anything hovered, and two items never look hovered at
once. Each row reads its own flag, so moving the pointer redraws the two rows involved, not the whole list.

**Tooltips** on every icon button: the name and the shortcut, "New Task ⌘N", after the system delay.

## Row metrics (Rex, measured)

Shared by sidebar rows, task rows and group labels (`PaneSize`):

- Rows are a **30pt shape on a 32pt pitch** (2pt gaps).
- **Sidebar**: 230pt wide; capsules 10pt from its left edge and 11pt from its right; the 20pt tile column 10pt inside
  the capsule; the title 7pt after the tile (text at x 47); text baseline 4pt below the row's middle.
- **Tiles**: Rex's 5:4 program tile, 20 × 16 in the sidebar (16 wide in headers and menus, 12 in chips).
- **Trailing action**: a 22pt slot 5pt in from the row's edge, so the glyph sits 16pt in (the sidebar's ••• spans
  x 195.5–210.5, exactly Rex's). ••• is three 3.75pt dots on a 5.5pt pitch; counts right-align with the dots.
- **Group labels**: 12pt in from the capsule edge (x 22 in the sidebar), baseline 27pt above the next row's middle.
- **Ink** (dark): title at rest `ink-secondary` #A8ADB1, hovered or current `ink` #E6EDF3, labels and counts
  `ink-tertiary` #7F8386. Current capsule `fill-strong` with Rex's edge (an outer #5E5E5E pixel over #535353).

## Sidebar collapse

The traffic lights and the sidebar toggle stay where they are. The panes slide left over the sidebar (which doesn't
move) and keep their rounded corners and edge; the first pane's header makes room for the window controls, so its
title moves right of the toggle. Expanding reverses it.

## Drag

- **No grip.** The whole row is the handle, as in Rex's sidebar and Mac lists.
- **Task rows** use the system table's drag: the row image follows the pointer and the native insertion line (an
  accent line with a ring at its leading end, the A1 shape) marks the drop. Today groups refuse drops from other groups.
- **Sidebar lists** lift as a `fill-strong` capsule with `shadow-lift`; the `PaneInsertionLine` sits in the 2 pt gap.
- **Drop target** (tasks over a sidebar list): `accent-tint` fill, 2 pt `focus-ring` edge, label `accent-text`, a
  "Move to …" chip; `hoverIn` in, instant out.

## Keyboard

| Key | Action |
|---|---|
| ↑ ↓, ⇧↑ ⇧↓, ⌘-click, ⇧-click | Move and extend the selection (the system table) |
| Return | Open the selected task in the detail pane |
| Space | Complete or uncomplete the selection |
| ⌘N / ⇧⌘N | New task (quick add) / new list |
| ⌘D | Show or hide the detail pane |
| ⌃⌘S | Show or hide the sidebar |
| ⌘K | Complete |
| ⇧⌘M | Move to…; ⌘1–9 pick a list there and in the quick-add list menu |
| ⌘T | When: Today |
| ⌘⌫ | Delete (undoable, so no confirmation) |
| Esc | Close quick add, then the detail pane |
| ⌘Z / ⇧⌘Z | Undo / redo every change, as new ops |
| ⌘R | Sync now |
| ⌘, | Settings |

Text fields keep their own keys: while typing, Space, Return and ⌘⌫ edit text. Clicking a row puts keyboard focus
in the list (SwiftUI's List doesn't take it on a click, so the list takes it when its selection changes). ⌘N scrolls
quick add into view before focusing it.
