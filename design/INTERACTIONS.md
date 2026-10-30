# Tasks — interaction rules

Status: 2026-10-30. How every control in the macOS app responds to the pointer, the keyboard and drags.

Built from `design/REX-REFERENCE.md` (Rex measured live: sampled colors, scripted hovers, 60 fps recordings), with
Pane for the tokens ([Claude Design](https://claude.ai/artifact/MS3VdrN9VHU7A7pTUTzpm8)). The app implements these
through shared styles in `app/Tasks/Pane/PaneComponents.swift` and the hover model in `WindowState`; views don't
style states themselves. The bar is the detail pane's open and close, which stays exactly as it is.

## Principles

1. **Hover is barely there and only reveals.** No row, chip or checkbox ever gets a hover fill. A navigation row's
   title brightens and its trailing action fades in; an icon button gets a small fill behind its glyph. That's all.
2. **Selection is the one strong state**: a filled capsule (sidebar) or a filled row (tasks).
3. **Nothing shifts.** Trailing actions take a slot the layout always reserves; long titles fade out with a gradient
   before it instead of ending in "…".
4. **Rex's timing, not a web page's.** Hover-in is near-instant; hover-out waits, so a trailing action stays reachable;
   switches are instant. With Reduce Motion on, nothing animates.

## Motion (`PaneMotion`)

| Interaction | Rex (measured) | Tasks |
|---|---|---|
| Row hover in | ~80% on the first frame, settled in 50–70 ms | `hoverIn`: ease-out 60 ms |
| Row hover out | holds ~300 ms, then fades ~85 ms | the row lingers 300 ms, then `hoverOut`: ease-out 85 ms |
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
| Sidebar row (Today, lists, Archive, New list) | title `ink-secondary`, icon unchanged; count `ink-secondary` | title → `ink`; a list's count gives way to its ••• | — | `fill-strong` capsule with the hairline edge, title `ink`, ••• shown (lists) |
| Group label ("Lists") | `label`, `ink-tertiary` | reveals ⊕ (New List) at the right | — | — |
| Task row | title `ink`, chips | the trailing ••• fades in | — | `fill-selected` at `radius-row`; ••• shown |
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

**Hover model.** Each pane keeps one hovered row and one lingering row in the window state. Entering a row makes it the
hovered row at once; leaving it makes it the lingering row for 300 ms, then it fades; leaving the list clears the
hovered row the same way. A missed exit event can never leave a row looking hovered.

**Tooltips** on every icon button: the name and the shortcut, "New Task ⌘N", after the system delay.

## Sidebar collapse

The traffic lights and the sidebar toggle stay where they are. The panes slide left over the sidebar (which doesn't
move) and keep their rounded corners and edge; the first pane's header makes room for the window controls, so its
title moves right of the toggle. Expanding reverses it.

## Drag

- **No grip.** The whole row is the handle, as in Rex's sidebar and Mac lists.
- **Task rows** use the system table's drag: the row image follows the pointer and the native insertion line (an
  accent line with a ring at its leading end, the A1 shape) marks the drop. Today groups refuse drops from other groups.
- **Sidebar lists** lift as a `fill-strong` capsule with `shadow-lift`; the `PaneInsertionLine` sits in the 4 pt gap.
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

Text fields keep their own keys: while typing, Space, Return and ⌘⌫ edit text.
