# Rex reference: measured hovers, colors and motion

Observed live in Rex Beta (dark theme) on 2026-10-30 with scripted hovers, window screenshots and 60 fps screen recordings.
Frame strips are in `.uitools/rex-*.png` (gitignored); tooling in `.uitools/*.swift`.

## Surfaces and selection (sampled pixels)
| Thing | Value |
|---|---|
| Sidebar (ground) | `#181818` |
| Pane (base) | `#1C1C1C` |
| Selected sidebar row | capsule ~29pt tall, fill `#444444`, hairline edge `#5D5D5D` top / `#575757` bottom |
| Focused vs unfocused pane | focused: base background, bright header icons, solid block cursor; unfocused: slightly darker (dim), header icons faded, hollow cursor |

## Hover
- **Sidebar rows: no fill.** At rest the title is dimmed (ink-secondary); on hover it brightens to full ink.
  The only other change is a trailing action fading in at the right (× close). Status glyphs (•••) swap to × on hover.
- Long titles fade out with a gradient mask before the trailing action; no "…".
- Group headers ("ECE 358") reveal ⊕ and a chevron on hover; host rows reveal a "new session" icon and a chevron.
- An overlay scroll indicator appears at the sidebar's right edge while the pointer is over it.
- Icon buttons (toolbar, pane header): quiet ink at rest; on hover a small fill appears behind the glyph (circle in the
  toolbar, rounded square in pane headers). A tooltip with the name and shortcut ("Split Right ⌘D", "Show Activity ⌘.")
  appears after a delay.
- Pane-header actions that don't apply (e.g. close on the only pane) are drawn disabled (fainter).

## Motion (measured)
| Interaction | Timing |
|---|---|
| Row hover in | near-instant: ~80% on the first frame, settled in ~50–70 ms |
| Row hover out | holds ~300 ms after the pointer leaves, then fades out over ~85 ms (forgiving, so the trailing × stays reachable) |
| Icon-button hover in/out | ~100 ms ease-out, no delay either way |
| Pane focus change | ~60 ms (2 frames) |
| Tab switch | instant (no cross-fade) |
| Split right | ~230 ms: the new pane fades and scales in from the right while the existing pane shrinks; header actions ride the moving edge |
| Sidebar collapse/expand | ~300 ms decelerating; the pane slides over the sidebar (the sidebar stays put underneath and is covered), keeping its rounded corners and edge |

## What this means for Tasks
- Task rows: no full-width hover fill. Brighten ink on hover, fade in trailing actions only.
- Selection is the one strong state: the capsule fill + hairline edge.
- Hover-out grace (~300 ms) and instant hover-in; ~100 ms for icon buttons; tooltips with shortcuts.
- Pane open/close (the detail pane): match the split motion above. The user already likes this one.
- Don't animate list/tab switches.
