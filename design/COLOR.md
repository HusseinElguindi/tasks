# Colour

**Status: proposed, 2026-11-01** (`docs/TASK-design-color.md`). Nothing is built. What the user said: "I feel like
we don't have enough color... a bit bland", "I like the surface colors", "I like the orange in this image"
(`docs/feedback/color-reference-orange.png`: a rounded tile, #D66F49, with a white spark, on dark grey), "be creative".

**Canvas:** https://claude.ai/artifact/ANUrtropTfm2GwdAAXWAYv (private until shared from its Share menu). Its
prototype is `design/prototype-color/`, a copy of `design/prototype-v2/` at 54681b8. Press Play on the first board and
click inside once. The strip at its foot picks Dark or Light, a direction (Now, A–D or the pick), or each feature on
its own, so they can be mixed. Below it are the tokens and contrast board (every ratio is computed from the hexes)
and a looping close-up of D's spark. Then one row per direction: School with a task just checked, the completed
tasks shown and the When popover open; Today with a task selected; dark and light. D and the pick also show Today all done.

## 0. The short version

Four directions, each a different kind of colour. Each can be switched on alone, and they combine:

| | Direction | Where colour goes | New or changed tokens |
|---|---|---|---|
| A | **Ember**: a warm accent | Everywhere the accent is now, in the reference's clay | `accent`, `accent-text`, `accent-tint`, `text-selection`; new `plan` |
| B | **Tiles**: colour as iconography | Solid tiles with white glyphs, like the reference; nothing else | new `tile-*` (8) |
| C | **Rooms**: colour per list and view | The open list's hue on its title, wash, checks, selection, capsule, popover | two list slots retuned; derived wash, selection, capsule |
| D | **Moments**: colour in time | Nothing at rest; a spark on completing, a sunrise when Today is done | new `spark` |

**Recommended: A + B + D** (the pick). The surfaces, the greys, the rows and the quiet stay. Colour goes in three
places: the sidebar's column of tiles, the clay accent where you act, and a spark when a task is done. §5 says why.

What every direction keeps: Rex's surfaces and greys, metrics and motion; the deadline tones (red when overdue, amber
when due today); the When ring's blue. Colour is never the only signal (§24's words and shapes stay).

## 1. A · Ember: a warm accent

The accent becomes the reference's clay. In dark it is the reference's own value.

**Colour:** the checked box, the highlighted day, today's date and the Today pill in the popover, the quick pick and
the chip with its popover open (tint), the highlighted menu item, focus and rename rings, a drop target, links in
notes, tinted buttons (Unarchive, Undo), text selection, the Today sun (sidebar, band and large title), and the brand
mark's head.
**Grey:** surfaces, rows and titles, the sidebar capsule, group labels, chips at rest. Tiles keep their list colours.

| Token | Dark | Light | Was |
|---|---|---|---|
| `accent` | #D66F49 | #AE4E2B | #2F81F7 / #0969DA |
| `accent-text` | #DA8B6E | #AE4E2B | #5799F6 / #0969DA |
| `accent-tint` | #342722 | #F7EDEA | #1E2938 / #E6F0FB (the same rule: base → accent 13% / 10%) |
| `text-selection` | accent at 42% | accent at 22% | 45% / 25% |
| `plan` (new) | #5799F6 | #0969DA | the When ring read `accent-text` |
| `on-accent` | #FFFFFF | #FFFFFF | unchanged |

**Contrast:** accent-text on base 6.41 / 5.35, on the popover 5.69 / 5.35, on accent-tint 5.41 / 4.65 (floor 4.5).
White on the accent 3.37 / 5.35 (floor 3; Rex's blue is 3.75). The accent on base 5.06 / 5.35 and `plan` on base
5.92 / 5.19 (floor 3).

**With the semantic colours.** The When ring moves to its own token, `plan`, which keeps today's blue, so "planned"
stays cool while warm means doing and deadlines. Danger (#FF7B72 / #CF222E) and attention (#D29922 / #9A6700) don't
change. Clay sits between them in hue (16°, against 4° or 356° and 41°), so they're kept apart by shape. Clay fills
(the check, the day, the menu item) and outlines whole rows. Red and amber are rings on open boxes and capsules at the
row's end. The nearest pair is dark danger against accent-text, and they never share a shape. The Today sun moves off
amber, which then means only "due today". The app icon's head stays blue unless the logo follows; that's a separate
question.

## 2. B · Tiles: colour as iconography

Every tile becomes a solid colour with a white glyph, the shape of the reference. These are Pane's category tiles,
applied to Tasks' tiles. They are the same in both appearances.

**Colour:** every tile: the sidebar's rows (Today, the views, the lists), the band's and the large title's tile, the
detail pane's List, Move to and the other menus, a dragged list. An archived list's tile is at 55%.
**Grey:** everything else. The accent stays blue.

| Tile | Fill | White on it |
|---|---|---|
| Today (the sun) | #D66F49 | 3.37 (a glyph: floor 3) |
| Upcoming, and the magenta slot | #7C5CD6 | 4.82 |
| Undated, and the cyan slot | #17808A | 4.68 |
| Completed, and the green slot | #27824A | 4.80 |
| blue slot | #2F6FEB | 4.57 |
| yellow slot (ochre) | #946818 | 4.94 |
| red slot (rose) | #C9456B | 4.62 |
| Trash, and the ink slot (graphite) | #5A6068 | 6.35 |

Every tile with a letter holds 4.5:1. **With the semantic colours:** nothing changes. Tiles never sit beside a date. Rose and ochre stand in for red and yellow, so a list's tile doesn't read as an alert. Today's tile is clay rather than yellow, because amber means due today.

## 3. C · Rooms: colour per list and view

Each list keeps its slot, and the slot's hue paints the open list's pane. Views have their own hues: Today clay,
Upcoming violet, Undated teal, Completed green, Trash none.

**Colour:** the large title (its text and a solid tile), a wash at the top of the pane (the hue fading out over
220pt), checked boxes, the selection, the current sidebar capsule (the hue mixed in, edges too), the date popover's
highlighted day, today's date and quick picks, and the views' glyphs and empty states. In Today each group keeps its
own list's hue: its label and its checks.
**Grey:** row text, chips at rest, the sidebar at rest, the band, the detail pane except its checkbox. Inbox (the ink
slot) and Trash keep the greys. Inbox's checks stay the accent. Focus and rename rings stay the accent.

| Token | Dark | Light |
|---|---|---|
| list slots | ANSI, unchanged: #58A6FF #BC8CFF #3FB950 #39C5CF | #0969DA #8250DF #116329 #1B7C83 |
| red slot → rose | #F778BA | #B4357F |
| yellow slot → lime | #A3C94A | #567312 |
| Today | #D66F49 (title #DA8B6E) | #AE4E2B |
| wash | hue at 12%, to nothing over 220pt | hue at 8% |
| selection | base → hue 18% (unfocused 10%) | 12% (7%) |
| current capsule | fill-strong → hue 24% | 16% |
| check mark | the base colour, cut out of the hue | white |

**Contrast** (the board has all 70): every hue as text on base 6.41 to 8.94 dark and 4.93 to 7.39 light (floor 4.5).
The title on its wash is 4.46 to 7.02 (floor 3, large text). ink-2 on the tinted selection is 4.85 to 5.91, and ink on
the tinted capsule 5.30 or more (floor 4.5). The check on its hue is 4.93 or more (floor 3). In dark the check is cut out,
since white on the six list hues is under 3:1 (1.9 to 2.5).

**With the semantic colours.** Rings stay urgency and fills stay done, so a checked box in a list's hue never means
a deadline. Red and yellow move to rose and lime because a red or yellow room would otherwise sit on danger and
attention. A slot is a role, not a hue (THEMES §2.1), and the app hands slots out by id, so nobody picked "yellow".
The When ring stays blue; in a blue list it matches the checks (a ring beside a fill).

**The cost:** every list repaints the pane, the selection is no longer one grey, and Today can hold seven hues at
once. It's the most colour and the least Rex.

## 4. D · Moments: colour in time

Grey at rest, exactly as now. Colour comes with an event and is gone within a second.

- **Completing a task:** a ring and eight rays (the reference's spark) leave the box in `spark`, the box fills from
  the spark to the accent, and the row and title flash warm and settle: ring 460 ms, rays 560 ms, box 520 ms, row and
  title 700 ms. The prototype holds its `pop` 720 ms (prototype-v2: 320).
- **Today all done:** the check-circle becomes a sun in `spark` whose rays turn in once (900 ms), under a faint
  sunrise at the top of the pane, with the title in ink.
- **Reduce Motion:** none of it. The box fills at once, as now.
- **Proposed, not drawn:** a new list's tile pops in its colour. The sync cloud (§26) stays quiet, with colour only
  for an error. A deadline's ring doesn't move: urgency shouldn't animate.

| Token | Dark | Light |
|---|---|---|
| `spark` (new) | #E8845C | #BA5530 (with A: = `accent-text`) |

**Contrast:** the spark on base 6.40 / 4.74 (floor 3 for the ring and rays; 4.5 for the title's first frame). One
pair fails on purpose: in light, the flashing title on a selected row starts at 3.80 and fades to ink-3 within
700 ms. The words are the same before and after, so nothing is ever read in the spark.
**With the semantic colours:** the spark is gone before a ring could be confused with it, and it never touches a date.

## 5. The pick: A + B + D, and why

- **B puts colour where it's always seen and never in the way.** The sidebar gets a column of solid tiles in the
  reference's own shape, and the content keeps its greys. So the deadline tones stay the only colour among the rows,
  as §24 intends. It's also Pane's vocabulary (its category tiles), not a new one.
- **A gives the app one warm signature where you act,** and makes the Today sun, the Today tile and the mark agree.
  Its one cost is a good split: `plan` keeps the When ring blue. Blue then means planned, clay means doing and done,
  and red and amber mean deadlines.
- **D adds delight at the moment that earns it** and nowhere else. With A, the spark is the accent, so a check simply
  blooms in its own colour.
- **Not C.** It's the most colourful, but it paints the content: every list restyles the selection, checks and title,
  Today becomes a patchwork beside the rings, and two slots have to move. It's the "paint everywhere" the brief warns
  against. If the pick still feels quiet, C's cheapest part is already in B: the large title's tile in its colour.

In the pick: `accent` #D66F49 / #AE4E2B, `plan` #5799F6 / #0969DA, the B tiles, and `spark` = `accent-text`.

## 6. Through the theme rules (THEMES.md)

THEMES is tabled, but each direction is a few tokens a theme could set. Its rules don't change.
- **`plan`** (new): default = `accent-text`. A theme whose accent is warm pins it cool, as Ember does. Floor: 3:1 on
  base (a ring).
- **`tile-*`** (new, 8 values): default as in §2, the same for both appearances. Floor: white on the tile 4.5:1 for
  letters, 3:1 for a glyph. Where B is off, a theme's `lists` still colour the glyphs on grey tiles.
- **`spark`** (new): default = `accent-text`. A theme with a cool accent sets its own warm one (D's #E8845C / #BA5530).
- **Rooms** are rules, not inputs: wash, selection and capsule are fixed mixes of base or fill-strong toward the slot's
  hue, like §2.4's. They're checked as the board does: hue 4.5:1 on base, ink-2 4.5:1 on the selection, the check 3:1.

## 7. The prototype

`design/prototype-color/` (the canvas's files):
- `Main.dc.html`: prototype-v2's Main at 54681b8 plus the `dir` prop and the strip's Colour controls (`DIRS`,
  `FEATS`, `colorCls`), the list's colour as a class on rows, Today's labels and the detail pane, `demo="colorlist"`
  and `"alldone"`, the spark in the checkbox, the all-done sun, and the views' glyphs as `c-today` … `c-trash`. In the
  demo data, School and Errands swap colours (School is cyan), so the list boards show a list whose hue isn't the
  accent's.
- `color.css`: every direction's rules. `tasks-v2.css` and `markdown.css` are prototype-v2's, unchanged; with no
  feature on, `color.css` resolves to their values.
- `Palette.dc.html` (tokens and contrast), `Spark.dc.html` (the loop), and the boards `<Direction>-<List|Today|Done>-<Dark|Light>`.
- `canvas.json`: the layout.
