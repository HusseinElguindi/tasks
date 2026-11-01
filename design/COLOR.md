# Colour

**Status: final: A + B + D, the user, 2026-11-01** (`docs/TASK-build-color.md`): "let's forget Rooms (C). A is
good. make this accent color easily changed (in case we pick up the theming later). B is good. use the tiles as above.
D is good. so yea ABD." Built in the app (§8). The brief was `docs/TASK-design-color.md`; what the user said then:
"I feel like we don't have enough color... a bit bland", "I like the surface colors", "I like the orange in this
image" (`docs/feedback/color-reference-orange.png`: a rounded tile with a white spark, on dark grey), "be creative".
The follow-up (`docs/TASK-design-color-2.md`) gave the tile's source, `docs/feedback/reference-tile.svg`: its fill is
#E6683D, lit from above (§2).

**Decided at the build** (the coordinator, 2026-11-01; the user can still change them):
- **The accent is #E6683D,** the source tile's own colour, in place of round 1's #D66F49, so the accent and Today's
  tile are one colour. It's one value for the whole theme (§6): light's accent, `accent-text` and `accent-tint` are
  derived from it by THEMES' rules, and Today's tile follows it.
- **Today's sun stays white on #E6683D,** as in the reference, though the tip of its top ray is 2.57:1.
- **Danger red stays.** **The app icon stays as it is.**

**Canvas:** https://claude.ai/artifact/ANUrtropTfm2GwdAAXWAYv (private until shared from its Share menu). It
still draws round 1's accent, #D66F49 / #AE4E2B, and C; §1's table has the built values. Its prototype is `design/prototype-color/`, a copy of `design/prototype-v2/` at 54681b8. Press Play on the first board and
click inside once. The strip at its foot picks Dark or Light, a direction (Now, A–D or the pick), or each feature on
its own, so they can be mixed. Below it are the tokens and contrast board (every ratio is computed from the hexes)
and a looping close-up of D's spark. Then one row per direction: School with a task just checked, the completed
tasks shown and the When popover open; Today with a task selected; dark and light. D and the pick also show Today all done.
The Finish board compares B's tiles now, flat and lit, at 1× and 2×, dark and light, with every hue at 4×.

## 0. The short version

Four directions, each a different kind of colour. Each can be switched on alone, and they combine:

| | Direction | Where colour goes | New or changed tokens |
|---|---|---|---|
| A | **Ember**: a warm accent | Everywhere the accent is now, in the reference's clay | `accent`, `accent-text`, `accent-tint`, `text-selection`; new `plan` |
| B | **Tiles**: colour as iconography | Solid tiles with white glyphs, lit like the reference; nothing else | new `tile-*` (8) |
| C | ~~Rooms~~: dropped (§3) | | |
| D | **Moments**: colour in time | Nothing at rest; a spark on completing, a sunrise when Today is done | new `spark` |

**Picked: A + B + D.** The surfaces, the greys, the rows and the quiet stay. Colour goes in three
places: the sidebar's column of tiles, the clay accent where you act, and a spark when a task is done. §5 says why.

What every direction keeps: Rex's surfaces and greys, metrics and motion; the deadline tones (red when overdue, amber
when due today); the When ring's blue. Colour is never the only signal (§24's words and shapes stay).

## 1. A · Ember: a warm accent

The accent becomes the reference's clay: the source tile's own fill, #E6683D (round 1 drew #D66F49). It's the
theme's one accent value (§6). Dark uses it as it is. Light's accent is derived from it by THEMES §2.5's raise: 2%
steps toward black until it holds 4.5:1 as text, on base and on its own tint, since light's `accent-text` is the
accent (as Rex's and round 1's are). That takes 13 steps, to #B1502F, a level or two from round 1's #AE4E2B.

**Colour:** the checked box, the highlighted day, today's date and the Today pill in the popover, the quick pick and
the chip with its popover open (tint), the highlighted menu item, focus and rename rings, a drop target, links in
notes, tinted buttons (Unarchive, Undo), text selection, the Today sun (sidebar, band and large title), and the brand
mark's head.
**Grey:** surfaces, rows and titles, the sidebar capsule, group labels, chips at rest. Tiles keep their list colours.

| Token | Dark | Light | Was |
|---|---|---|---|
| `accent` | **#E6683D** (the source) | #B1502F (the source, raised for text) | #2F81F7 / #0969DA |
| `accent-text` | #E68565 (accent → ink 22%) | #B1502F (= accent) | #5799F6 / #0969DA |
| `accent-tint` | #362620 | #F7EDEA | #1E2938 / #E6F0FB (the same rule: base → accent 13% / 10%) |
| `text-selection` | accent at 42% | accent at 22% | 45% / 25% |
| `plan` (new) | #5799F6 | #0969DA | the When ring read `accent-text` |
| `on-accent` | #FFFFFF | #FFFFFF | unchanged |

**Contrast:** accent-text on base 6.43 / 5.18, on the popover 5.71 / 5.18, on accent-tint 5.44 / 4.52 (floor 4.5:
checked when the theme is derived, and raised if it fails). White on the accent 3.28 / 5.18 (floor 3, fine for
glyphs and checkmarks; Rex's blue is 3.75). The accent on base 5.20 / 5.18 and `plan` on base 5.92 / 5.19 (floor 3).
(Round 1's figures, for #D66F49 / #AE4E2B: 6.41 / 5.35, 5.69 / 5.35, 5.41 / 4.65; 3.37 / 5.35; 5.06 / 5.35.)

**With the semantic colours.** The When ring moves to its own token, `plan`, which keeps today's blue, so "planned"
stays cool while warm means doing and deadlines. Danger (#FF7B72 / #CF222E) and attention (#D29922 / #9A6700) don't
change. Clay sits between them in hue (16°, against 4° or 356° and 41°), so they're kept apart by shape. Clay fills
(the check, the day, the menu item) and outlines whole rows. Red and amber are rings on open boxes and capsules at the
row's end. The nearest pair is dark danger against accent-text, and they never share a shape. The Today sun moves off
amber, which then means only "due today". Danger stays red. The app icon stays as it is (its head stays blue).

## 2. B · Tiles: colour as iconography

Every tile becomes a solid colour with a white glyph, finished as the reference tile is: a dark halo, lit from
above. These are Pane's category tiles applied to Tasks' tiles, with Rex's own finish.

**Colour:** every tile: the sidebar's rows (Today, the views, the lists), the band's and the large title's tile, the
detail pane's List, Move to and the other menus, a dragged list. An archived list's tile is at 55%. The brand mark's
head takes the same light (below).
**Grey:** everything else. (With B alone the accent stayed blue; in the pick it's A's.)

### The finish

The source (`docs/feedback/reference-tile.svg`) draws the tile at 58.5×45.5, radius 13.8. Scaled to our 20×16, radius
4 (`TileLayer`), its hairlines fall under a device pixel, so each is snapped to one device pixel with its alpha set to
keep the same amount of light or dark. Bottom to top, each a sublayer of the tile:

| Layer | Source | At 20×16 | CALayer |
|---|---|---|---|
| Halo | the shape grown 0.5, black 40%; under it the shape grown 0.23, solid black | 0.5pt outside the edge: black 35% dark, 18% light (at 1×, 1pt at half that) | a layer 0.5pt larger all round, radius 4.5, `borderWidth` 0.5, `borderColor` black at that alpha |
| Fill | flat #E6683D | the hue, flat | the tile's `backgroundColor`, radius 4, `masksToBounds` |
| Light | radial from the top middle, radii 1.4 × width and 1.1 × height | the same, in proportion | `CAGradientLayer`, `type = .radial`, `startPoint` (0.5, 0), `endPoint` (1.9, 1.1), colours and locations below |
| Specular | a 1-unit strip on the top edge, white 0 → 36% → 0, left to right | 0.5pt, white 0 → 25% → 0 (at 1×, 1pt at 12%) | `CAGradientLayer` (axial, left to right), frame (0, 0, 20, 0.5), clipped by the fill |
| Ring | a 1-unit ring inside the edge, white 10% | 0.5pt, white 7% (at 1×, 1pt at 3.5%) | a layer the tile's size, radius 4, `borderWidth` 0.5, `borderColor` white at 7% |
| Glyph | white, flat | white, no shadow | as now, in white |

**The light's stops** (the source's easing: white 0.216 × (1 − s(d / 0.58)) out to 0.58, then black 0.072 × s((d −
0.58) / 0.42) to the rim, where s is smootherstep, 6u⁵ − 15u⁴ + 10u³):

| Location | 0 | 0.0725 | 0.145 | 0.2175 | 0.29 | 0.3625 | 0.435 | 0.5075 | 0.58 | 0.65 | 0.72 | 0.79 | 0.86 | 0.93 | 1 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Colour | white .216 | .213 | .194 | .157 | .108 | .059 | .022 | .003 | clear | black .003 | .015 | .036 | .057 | .069 | .072 |

**The specular's stops**, 0 to 1 in sixteenths, mirrored about the middle: 0, .003, .058, .111, .157, .196, .226,
.244, **.25**, then back down.

Points are in the unit space of a top-left-origin layer (`isGeometryFlipped`, as the tile's other sublayers are); in
AppKit's default bottom-left space the light runs from (0.5, 1) to (1.9, −0.1). Nothing here depends on the hue: a tile is its hue plus these fixed layers, so any list colour (and any theme's)
takes the same finish. The halo's lighter value in light mode keeps the edge from reading as an outline on the pale
sidebar.

### The hues, and the white glyph

The light lifts the top of a letter by about 13% white (a 10pt bold letter's cap top sits 4.5pt down, where the light
is still strong). So each hue is round 1's, darkened toward black in 2% steps (THEMES §2.5's fix) until white holds
4.5:1 at the lightest point under the letter. It took six or seven steps for each. A tile is the same in both
appearances; only the halo differs.

| Tile | Flat (round 1) | Lit | White: middle | White: under the glyph | Floor |
|---|---|---|---|---|---|
| Today (the sun) | #D66F49 | **#E6683D**: the accent's source, and it follows it | 3.23 | 2.57 at the top ray's tip | 3 |
| Upcoming, and the magenta slot | #7C5CD6 | #6B4FB8 | 5.90 | 4.61 | 4.5 |
| Undated, and the cyan slot | #17808A | #146E77 | 5.78 | 4.52 | 4.5 |
| Completed, and the green slot | #27824A | #227040 | 5.89 | 4.56 | 4.5 |
| blue slot | #2F6FEB | #285FCA | 5.71 | 4.50 | 4.5 |
| yellow slot (ochre) | #946818 | #825C15 | 5.78 | 4.53 | 4.5 |
| red slot (rose) | #C9456B | #AD3B5C | 5.75 | 4.59 | 4.5 |
| Trash, and the ink slot (graphite) | #5A6068 | #5A6068 | 6.14 | 4.64 | 4.5 |

**Today is the one exception:** it keeps the source's own fill, #E6683D, which is also the accent's source, so
Today's tile follows the accent (a theme that changes the accent changes Today's tile, in both appearances). Its sun is
white, 3.2:1 through the middle and 2.6:1 at the top ray's tip, as the reference's spark is (decided: it stays). If
that tip should hold 3:1 too, Today is #CA5C36, which is visibly darker than the reference.

**The brand mark:** its head (a 5pt dot at 18pt) takes the light, the inner ring and the halo, and no specular, since
a 0.5pt strip across a 5pt dot is just a fleck.

**With the semantic colours:** nothing changes. Tiles never sit beside a date. Rose and ochre stand in for red and
yellow, so a list's tile doesn't read as an alert. Today's tile is clay rather than yellow, because amber means due
today.

## 3. C · Rooms: dropped

Dropped by the user ("let's forget Rooms (C)"): it paints the content, every list restyling the selection, checks and
title, which is the "paint everywhere" the brief warned against (§5); round 1's text is in git at 22c9f20.

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
| `spark` (new) | = `accent-text`: #E68565 | = `accent-text`: #B1502F |

Without A it would be #E8845C / #BA5530 (a theme with a cool accent sets its own warm one, §6).

**Contrast:** the spark (= accent-text) on base 6.43 / 5.18 (round 1's own spark: 6.40 / 4.74) (floor 3 for the ring and rays; 4.5 for the title's first frame). One
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

In the pick: `accent` #E6683D (light #B1502F, derived), `plan` #5799F6 / #0969DA, the B tiles, lit, and `spark` =
`accent-text`.

## 6. Through the theme rules (THEMES.md)

THEMES is tabled, but each direction is a few tokens a theme could set. Its rules don't change.
- **`accent`:** one value per theme, the source (#E6683D). Dark's accent is the source; light's is the source raised
  by §2.5's 2% steps toward black until it holds 4.5:1 on base and on its own tint (light's `accent-text` is the
  accent). A theme may still give each side its own. Everything that reads the accent derives from it: `accent-text`
  (checked against its 4.5:1 floor and raised if it fails), `accent-tint`, `focus`, `text-selection` (42% / 22%),
  `on-accent`, `mark-head`, `spark`, the checked box, the highlighted day, the highlighted menu item and Today's
  tile. To change it, see THEMES §6.
- **`plan`** (new): default = `accent-text`. A theme whose accent is warm pins it cool, as Ember does. Floor: 3:1 on
  base (a ring).
- **`tile-*`** (new, 8 values): default as in §2, the same for both appearances, with the fixed finish over them.
  Seven are one table (`tiles`, by list slot; the views share theirs); Today's is the accent's source.
  Floor: white 4.5:1 for letters and 3:1 for a glyph, checked at the lightest lit point under the glyph. Where B is off, a theme's `lists` still colour the glyphs on grey tiles.
- **`spark`** (new): default = `accent-text`. A theme with a cool accent sets its own warm one (D's #E8845C / #BA5530).
- **`tile-halo`** (new): black at 35% / 18%, the finish's one per-appearance value.

## 7. The prototype

`design/prototype-color/` (the canvas's files):
- `Main.dc.html`: prototype-v2's Main at 54681b8 plus the `dir` prop and the strip's Colour controls (`DIRS`,
  `FEATS`, `colorCls`), the list's colour as a class on rows, Today's labels and the detail pane, `demo="colorlist"`
  and `"alldone"`, the spark in the checkbox, the all-done sun, and the views' glyphs as `c-today` … `c-trash`. In the
  demo data, School and Errands swap colours (School is cyan), so the list boards show a list whose hue isn't the
  accent's. The `tiles` prop and the strip's Lit tiles / Flat tiles switch B's finish (`flat` on the root).
- `color.css`: every direction's rules. `tasks-v2.css` and `markdown.css` are prototype-v2's, unchanged; with no
  feature on, `color.css` resolves to their values.
- `Palette.dc.html` (tokens and contrast), `Spark.dc.html` (the loop), `Finish.dc.html` (B's tiles now, flat and lit,
  with the light model and the contrast at the glyph computed live), and the boards `<Direction>-<List|Today|Done>-<Dark|Light>`.
- `canvas.json`: the layout.
