# App icon directions

Canvas: https://claude.ai/artifact/ScTE29QmxCwxJxfRdnrNPd (private until shared from its Share menu). Brief: `docs/TASK-logo.md`.

**Decision (2026-10-31): 04 Log is the app icon.** The others are kept on the canvas for reference.

Seven directions for the macOS app icon, all drawn in the Pane vocabulary (Rex colours from `design/REX-REFERENCE.md`,
light colours from `design/prototype-v2/tasks-v2.css`).

| # | Direction | One line |
|---|---|---|
| 01 | Row | The selected capsule is the app's one strong state: a single task, picked and checked. |
| 02 | Split | The detail pane sliding open beside the list, the move the whole window is built on. |
| 03 | Rise | Today's sun coming up behind a task row: the view you open first each morning. |
| 04 | **Log** (chosen) | Sync is a hash-chained, append-only log; the newest op at its head is a checked task. |
| 05 | Tile | The list monogram tile, scaled up. Its letter follows the name, so it changes if Tasks does. |
| 06 | Cursor | A check, then the block cursor waiting for the next task, in Rex's cursor blue. |
| 07 | Gap | Drag-to-reorder's insertion line and ring, parting two rows to make room. |

## Earlier recommendation (before the decision)

1. **06 Cursor.** It has the boldest silhouette at 16pt and doesn't resemble any other app's icon. A check followed by a block
   cursor reads as "done, and ready for the next one". The blue is Rex's cursor colour, which Pane uses as its accent.
2. **07 Gap.** The insertion line with its leading ring is the most app-specific detail, and the user liked the
   prototype's drag. Below 60pt it drops the row contents so it doesn't read as a menu glyph.

Watch-outs for the others:

- 01 Row can read as a toggle switch at 16pt.
- 02 Split is close to the system sidebar glyph.
- 03 Rise leans towards weather apps.
- 05 Tile depends on the working name.

## The chosen mark: 04 Log

- **Large (60pt and up):** a vertical spine with three nodes. The head is a filled accent circle with a check cut out in
  the body colour, and the two older ops are hollow rings. Each node has a bar for its entry: the head's in `ink`, the
  older ones in `ink-tertiary`.
- **Small (below 60pt):** the rings become solid dots, and the spine, bars and head get thicker.
- **Geometry** is in `Icon.dc.html` under `g.log`, in 1024 units.
- **Colours:** dark uses accent `#2F81F7` with the check cut out in `#1C1C1C`. Light uses accent `#0969DA` with a white
  check.

## What each sheet shows

- The 1024 icon on a construction grid: the 824 body with continuous corners, keyline square, portrait and landscape
  rectangles, and circles.
- Light and dark at 256, 128, 64, 32 and 16 (1×).
- Tinted (a single tint, adjustable with the Sheet's Tint tweak) and Clear, at 128 and 32.
- The bare mark in dark and light.
- In context: the Dock (dark and light desktops), a Finder icon view and list row, and the app's sidebar header with the
  mark at 18pt.

Neighbouring apps in the Dock and Finder are neutral placeholders, not real icons.

## Files

- `Icon.dc.html`: every mark as one SVG component. Its props are `mark`, `look` (dark, light, tinted, clear), `size`,
  `bare`, `grid` and `tint`. Below 60px each mark switches to a small cut that drops hairlines and thickens strokes.
  Geometry is in 1024 units.
- `Sheet.dc.html`: the per-direction layout. `D1-Row.dc.html` … `D7-Gap.dc.html` each mount it with one `mark`.
- `Main.dc.html`: the overview of all seven.
- `canvas.json`: the canvas layout, notes and design-system record. The canvas runtime (`support.js`) and the copied
  Pane `tokens.json` come from the Design type and from Pane, and aren't stored here.
