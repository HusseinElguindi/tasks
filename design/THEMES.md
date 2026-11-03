# Themes

**Status: tabled: tokens adopted in the app; picker, files and samples deferred** (`docs/TASK-design-themes.md`,
v2 feedback 17). The app draws from one palette with the §1 tokens, filled from one theme, Rex, by the §2.4 rules
with Rex's measured values pinned (`app/TasksCore/Sources/TasksTheme/Theme.swift`, shared by the Mac and iOS; the
Mac's palette is `app/Tasks/Theme/TK.swift`), as §6 steps 1–6 describe; nothing
looks different. Not built: the contrast check (§2.5), `contrast: "high"`, the theme file (§3), the picker (§4) and
the sample themes (§5). Where the app differs from §1: it adds `card` (Settings' grouped sections, Pane's card: dark
base → ink 1.5%, light = base) and has no `fill-thumb` (nothing draws one); Rex pins dark `hover`, `press`,
`tile-ring` and both shadows' rings as white, which it measures, rather than its ink; `focus` is read by the
editing rings (a row's, a heading's and the large title's rename, a sidebar row's rename) and the drop ring on a
sidebar row, and the date popover's keyboard day. PaneColors is gone: Settings reads the same tokens.
**Since COLOR.md's A + B + D (2026-11-01)** the one theme has the Ember accent and lit tiles: its accent is one value
for both appearances, from which every token that shows it derives (§6.1 says how to change it); new tokens `plan`,
`spark`, `tile-halo` and the eight `tile-*` hues; `text-selection` is accent at 42% / 22%; and the derivation holds
`accent-text`'s floor (§2.5), the one floor built so far. Rex's greys are still pinned.

**Canvas:** https://claude.ai/artifact/Hq16S8JLKGyQqTsbKzNukG (private until shared from its Share menu). Its prototype
is `design/prototype-themes/`, a copy of `design/prototype-v2/` at commit 16e9625 with a theme switcher. Press Play on
the first board; the strip at its foot picks the theme, Dark or Light, Classic or Glass, and an instant or faded
switch. `themes.js` is the reference implementation of everything below: the sample themes in the file format, the
derivation rules and the contrast check. Where this spec and `themes.js` disagree, `themes.js` wins, as the
prototype always has.

## 0. The short version

- **A theme is a few colours, not a palette.** Per appearance it gives `base`, `ink` and `accent`. It may add `ground`,
  six list hues, `danger`, `attention` and a high-contrast flag. The other 30-odd colour tokens are derived from those
  by fixed rules (§2.4).
- **The rules are Rex's own.** Each mix amount is solved from Rex's measured values, so Rex's three base colours
  reproduce its whole palette to within 1–4 levels per channel. The default theme pins the measured values anyway,
  so choosing it changes nothing.
- **A contrast check runs when a theme loads** (§2.5). A derived token under its floor is raised toward ink until it
  passes. A theme whose own `ink` or `accent` fails is rejected, and Settings says why.
- **Only colour is themable.** Metrics, type, radii, motion, shadow geometry, opacities and the Glass amounts stay
  fixed (§2.2).
- **A theme defines both appearances.** Light / Dark / System keeps working as it does now, inside the theme (§2.3).
- **The file is a small JSON document, kept on this Mac** in the app's Themes folder and never synced (§3).
- **The picker** is a grid of live cards in Settings ▸ Appearance, plus View ▸ Theme. A switch is instant, like the
  appearance switch (§4).
- **Seven built-ins:** Default (Rex), Paper, Contrast, Dusk, Harbor, Iris, Moss (§5).
- **In the app,** `TK.Palette` becomes a value derived once from `(theme, appearance)` and cached. No per-frame cost.
  Palette equality has to start including the theme, or a theme switch won't redraw (§6).

**The choices for the user**, each a board on the canvas:

| # | Choice | Options | Recommended |
|---|---|---|---|
| 1 | How a theme relates to Light, Dark and System | A: a theme is a pair. B: a theme is one appearance, with separate day and night themes. C: pairs, plus one-sided files that pin the appearance | **A**. C only if imported themes come to matter |
| 2 | The picker's form | A: live cards in Settings. B: a list with swatch dots. C: View ▸ Theme menu | **A, plus C** |
| 3 | Should a theme change radii or the font? | Tight / Default / Round radii; System / Serif / Mono font | **No: colour only.** Radii and SF Pro stay fixed |
| – | Switch animation | Instant / 180 ms cross-fade (the strip's Switch control) | **Instant** |

## 1. The token inventory

What's in use today, in the prototype (`design/prototype-v2/tasks-v2.css:46–78`, `markdown.css`) and the app
(`app/Tasks/Theme/TK.swift:12–79`). The Tokens board on the canvas shows each token live in any theme, with its
source, its rule and its lowest contrast.

### 1.1 Colour

**Rule** is how a derived theme makes the token (§2.4): `a → b t%` is t of the way from a to b in sRGB, and `x at t%`
is x with alpha t. The **Rex** columns are today's values, which the default theme pins.

#### Surfaces

| Token | CSS | Rex dark | Rex light | Rule dark | Rule light | Use |
|---|---|---|---|---|---|---|
| `ground` | `--ground` | #181818 | #F5F5F5 | input, else base → black 14% | input, else base → ink 4.5% | Window, sidebar, gutters, the top band |
| `base` | `--base` | #1C1C1C | #FFFFFF | **input** | **input** | The focused pane |
| `dim` | `--dim` | #181818 | #FAFAFA | = ground | base → ground 50% | An unfocused pane; a pane alone |
| `popover` | `--popover` | #262626 | #FFFFFF | base → ink 5% | = base | Menus, the date popover, notices, tooltips |
| `lift` | `--lift` | #2C2C2C | #FFFFFF | base → ink 7.8% | = base | The dragged row |

#### Ink

| Token | CSS | Rex dark | Rex light | Rule dark | Rule light | Use |
|---|---|---|---|---|---|---|
| `ink` | `--ink` | #E6EDF3 | #1F2328 | **input** | **input** | Titles, task text, headings |
| `ink-secondary` | `--ink-2` | #A8ADB1 | #626568 | ink → base 30.7% | ink → base 30% | Sidebar titles at rest, labels, values, a list's notes |
| `ink-tertiary` | `--ink-3` | #7F8386 | #6C6F72 | ink → base 51% | ink → base 34.4% | Group labels, counts, placeholders, done titles |
| `ink-quiet` | `--ink-q` | #6D7072 | #888A8D | ink → base 60% | ink → base 47% | Header icons at rest, strike-through, Markdown marks |

#### Lines and edges

| Token | CSS | Rex dark | Rex light | Rule dark | Rule light | Use |
|---|---|---|---|---|---|---|
| `line-pane` | `--line-pane` | #323334 | #D4D5D6 | base → ink 10.7% | base → ink 19.2% | The focused pane's 1pt inset edge |
| `line-pane-dim` | `--line-pane-dim` | #282929 | #EBEBEC | base → ink 5.8% | base → ink 8.9% | An unfocused pane's edge |
| `line-separator` | `--line-sep` | #363738 | #E7E8E8 | base → ink 12.7% | base → ink 10.7% | Hairlines, a heading's rule, the ghost chip |
| `line-field` | `--line-field` | #696B6E | #848689 | base → ink 37.5% | base → ink 54.9% | The checkbox ring, a checklist box |
| capsule edge | `--edge-outer` / `--edge-inner` | #5E5E5E / #535353 | #CFCFD0 / #D6D6D7 | base → ink 32.7% / 27.2% | base → ink 21.4% / 18.3% | The current sidebar row |

#### Fills (hover, selected, pressed)

| Token | CSS | Rex dark | Rex light | Rule dark | Rule light | Use |
|---|---|---|---|---|---|---|
| `fill-row-selected` | `--sel` | #333333 | #E6E6E8 | base → ink 11.4% | base → ink 11.2% | Selected task rows |
| `fill-row-selected-dim` | `--sel-dim` | #292929 | #EFEFF0 | base → ink 6.4% | base → ink 7.1% | Selected rows, unfocused pane |
| `hover` | `--hover` | white 7% | #1F2328 6% | ink at 7% | ink at 6% | Behind a hovered icon button, day, ghost chip |
| `press` | `--press` | white 12% | #1F2328 11% | ink at 12% | ink at 11% | Behind a pressed icon button |
| `fill-control` | `--fill-control` | #2D2E2E | #EDEDEE | base → ink 8.4% | base → ink 8% | Chips, the date field, inline code, the banner |
| `fill-track` | `--fill-track` | #303132 | #E9E9EA | base → ink 9.9% | base → ink 9.8% | Toolbar hover, capsule buttons, segmented tracks |
| `fill-strong` | `--fill-strong` | #444444 | #E0E0E1 | base → ink 19.8% | base → ink 13.8% | The current sidebar row, a quote's bar |
| `fill-thumb` | `--fill-thumb` | #4A4C4D | #FFFFFF | base → ink 22.5% | = base | A segmented control's thumb (the prototype's strip) |

Hover and press brighten chips and buttons with filters rather than fills (`TK.swift:66–71`): those factors stay fixed.

#### Accent, focus and state

| Token | CSS | Rex dark | Rex light | Rule dark | Rule light | Use |
|---|---|---|---|---|---|---|
| `accent` | `--accent` | #2F81F7 | #0969DA | **input** | **input** | The checked box, the highlighted day and menu item |
| `accent-text` | `--accent-text` | #5799F6 | #0969DA | accent → ink 22% | = accent | Links, today's date, drop targets, tinted buttons |
| `accent-tint` | `--accent-tint` | #1E2938 | #E6F0FB | base → accent 13% | base → accent 10% | A chip with its popover open, a drop target |
| `on-accent` | `--on-accent` | #FFFFFF | #FFFFFF | white if 3:1, else base | white if 3:1, else ink | The checkmark, text on the accent |
| `focus` (new name) | `--focus` | = accent | = accent | = accent | = accent | Editing rings (1.5pt), drop rings (2pt) |
| `text-selection` | `--text-sel` | accent 45% | accent 25% | accent at 42% | accent at 22% | Selected text in fields |
| `plan` (new, COLOR §1) | `--plan` | #5799F6 | #0969DA | = accent-text | = accent-text | The When ring (planned for today) |
| `spark` (new, COLOR §4) | `--spark` | = accent-text | = accent-text | = accent-text | = accent-text | D's spark, the all-done sun and sunrise |

**In the app, since COLOR.md (A):** the accent is the theme's one `accent` value, #E6683D. Dark's `accent` is it;
light's is it raised by §2.5's 2% steps toward black until it holds 4.5:1 on base and on its own tint (light's
`accent-text` is the accent), #B1502F. Then by the rules above: `accent-text` #E68565 / #B1502F, `accent-tint`
#362620 / #F7EDEA, `on-accent` white, `focus`, `mark-head` and `spark` follow, and Today's tile is the theme's
accent itself. Nothing here is pinned except `plan`, which keeps Rex's blue (COLOR §1: planned stays cool).
| `danger` / `danger-tint` | `--danger` / `--danger-tint` | #FF7B72 / #3C2928 | #CF222E / #FBEBEC | input or list red / base → danger 14.1% | input or list red / base → danger 9% | The overdue chip |
| `attention` / `attention-tint` | `--attn` / `--attn-tint` | #D29922 / #352E1D | #9A6700 / #FAF7F2 | input or list yellow / base → attention 13.7% | input or list yellow / base → attention 5% | The due-today chip, the other date's dot |

**There's no success colour.** A done task is ink-tertiary and struck through; the checkbox's fill is the accent. A
theme shouldn't add one.

#### Lists, tiles, drag and the brand mark

| Token | CSS | Rex dark | Rex light | Rule | Use |
|---|---|---|---|---|---|
| list slots 0–5 | `--ansi-blue … --ansi-red` | #58A6FF #BC8CFF #3FB950 #39C5CF #D29922 #FF7B72 | #0969DA #8250DF #116329 #1B7C83 #9A6700 #CF222E | input (`lists`), else Rex's | A list's monogram, its tile glyph |
| list slot 6 | `--ansi-ink` | = ink | = ink | = ink | The seventh slot |
| `tile-fill` (new) | `--tile-fill` | #444444 | #E3E3E4 | = fill-strong / base → ink 12.5% | A list's tile (gone from the app with COLOR B) |
| `tile-ring` (new) | `--tile-ring` | white 10% | #1F2328 10% | ink at 10% | its 0.5pt ring (gone with COLOR B) |
| `tile-*` (COLOR B) | color.css `--tc` | 7 slot hues + Today's | the same | input (`tiles`); Today's = the accent | A tile's solid hue, lit by the fixed finish (`TileArt`) |
| `tile-halo` (COLOR B) | `--tile-halo` | black 35% | black 18% | fixed | The lit tile's 0.5pt halo |
| `lift-chip` (new) | `--lift-chip` | #3A3A3A | = fill-track | base → ink 14.7% / = fill-track | A chip on the dragged copy |
| `mark-head` / `-bar` / `-rings` / `-trail` (new) | `--mark-*` | #2F81F7 #E6EDF3 #A8ADB1 #6D7072 | #0969DA #1F2328 #626568 #A9ACAF | accent / ink / ink-2 / ink-q (light: ink → base 61.6%) | The sidebar's brand mark |

A list's slot still comes from its id (`ListModel.colorSlot`); a theme changes the seven colours, never which slot a
list gets. The app icon stays as it is. The in-window mark follows the theme because it sits on the theme's sidebar.

#### Markdown and chips

These have no tokens of their own. They're drawn from the ones above, and the Tokens board draws them:

| Thing | Tokens |
|---|---|
| Chip (plain / due / late / popover open / ghost) | fill-control + ink-2 / attn-tint + attention / danger-tint + danger / accent-tint + accent-text / line-sep ring + ink-3 |
| Checkbox | line-field ring; ink-2 on hover; accent fill and on-accent check when done; ink-q while new |
| Checklist box | line-field ring; ink-3 fill when checked; on-accent check |
| Link | accent-text, its underline at 40% until hovered |
| Inline code, code block | fill-control, SF Mono 12 |
| Quote | a fill-strong bar, ink-2 text |
| Marks (`**`, `#`, …) | ink-q |
| Headings in notes | ink, semibold |

#### Glass material

Not colours of their own: the theme's `ground` at **60%** over the sidebar material behind the window, and the panes'
`base` / `dim` at **88%** (`app/Tasks/Window/GlassGround.swift:7–12`, `INTERACTIONS-v2.md` §4). Both numbers are
fixed.

#### Shadows

| Token | Dark | Light |
|---|---|---|
| `shadow-popover` | 0.5pt ring of ink 14%, then 0 12 32 black 50% | 0.5pt ring of ink 16%, then 0 12 32 ink 16% |
| `shadow-lift` | 0.5pt ring of ink 14%, then 0 8 24 black 50% | 0.5pt ring of ink 14%, then 0 8 24 ink 18% |
| `win-edge` (prototype only) | 0.5pt black 90%, inset 0.5pt white 14%, 0 22 60 black 35% | 0.5pt black 22%, 0 22 60 black 16% |

Geometry and the blur's darkness are fixed per appearance. Only the hairline ring takes the theme's ink.

### 1.2 Everything else (fixed)

| Kind | Values | Where |
|---|---|---|
| Type | SF Pro 13/16; labels 11/14 semibold; chips 11/14 medium; detail title 15/20 semibold; list title 20/26 semibold; headings 13/16 semibold; notes 13/19; tooltips 11/14; SF Mono for tiles (10 bold), code (12) and counts' digits | `TK.Font`, `css:25` |
| Radii | window 12, pane 10, row 8, sidebar capsule 15, chip 9 (large 11), menu 10, menu item 5, popover 12, date field 8, day 14, icon buttons 6, tile 4 (small 3.5), code 4 / 6 | `css` throughout, `TK.M` |
| Metrics | 30pt rows on a 32pt pitch, the 50pt band, 34pt headers, 8pt gutters, sidebar 230 (180–400), detail 420 (min 340), check 16 / ring 1.5 | `TK.M` |
| Motion | hover in 60 ms, out 85 ms, icon 100 ms, focus 60 ms, sidebar 300 ms; natural / layout / snappy springs | `TK.Motion`, `TK.CA` |
| Opacities | unfocused header icons 55%, inert 45%, disabled menu item 40%, trashed checkbox 60%, new checkbox 70%, link underline 40%, a shortcut on the accent 78% | `css:151, 288, 314, 430, 203`, `markdown.css:17`, `css:313` |
| Brightness | chip hover 1.18 dark / 0.96 light, buttons 1.12 / 0.97, press 0.86 | `TK.swift:66–71` |
| Window controls | the system's traffic lights, by appearance | |

### 1.3 Hard-coded values that bypass the tokens

These have to become tokens (or come from them) before a theme can reach them. The prototype's `themes.css` already
reroutes the CSS ones.

| Where | What | Becomes |
|---|---|---|
| `tasks-v2.css:123–124` | the tile's ring (white 10%) and its light fill #E3E3E4 | `tile-fill`, `tile-ring` |
| `tasks-v2.css:249` | the dark dragged chip #3A3A3A | `lift-chip` |
| `tasks-v2.css:313` | a shortcut on the highlighted menu item, white 78% | on-accent at 78% |
| `tasks-v2.css:405–413`, `app/Tasks/Sidebar/SidebarHeader.swift:59–66` | the brand mark's four fills as literals, per appearance | `mark-*` |
| `app/Tasks/Theme/TK.swift:36` | `Palette ==` compares `isDark` only: two themes in the same appearance compare equal, so rows wouldn't redraw | compare the theme too (§6) |
| `app/Tasks/TasksApp.swift:34–37` | two palettes chosen side by side: `PaneColors` (derived, for the Settings and popover components) and `TK.Palette` (literal) | one theme feeds both (§6) |
| `app/Tasks/Pane/PaneTheme.swift:343–356` | the Pane card's ring and drop (white 8%, ink 6–18%, black 50%) as literals | `shadow-*` rings, `line-sep` |
| `app/Tasks/Pane/PaneComponents.swift:412` | a hover fill as white 7 / 12% and black 5 / 9% | `hover`, `press` |
| `app/Tasks/Pane/PaneComponents.swift:354`, `PaneTheme.swift:446` | press as `colorMultiply(white: 0.86)` | stays (it's the fixed press factor), named `TK.Palette.pressBrightness` |
| `app/Tasks/Overlay/DatePopover.swift:280–562` (8 places), `TaskList/HeadingViews.swift:48, 193`, `TaskList/TaskRowView.swift:444`, `Detail/NotesMarkdown.swift:87–99`, `Pane/PaneComponents.swift` (6 places) | `.system(size:)` and `NSFont.systemFont` outside `TK.Font` | `TK.Font` entries. Not for theming (type is fixed), but so the type is in one place |

## 2. What a theme may change

### 2.1 The themable set

Per appearance (`dark`, `light`):

| Key | Required | Meaning | Default |
|---|---|---|---|
| `base` | yes | The focused pane | |
| `ink` | yes | Titles and task text | |
| `accent` | yes | The one strong colour | |
| `ground` | no | Window and sidebar | derived from base (§2.4) |
| `lists` | no | The six list hues: `blue`, `magenta`, `green`, `cyan`, `yellow`, `red` (any subset) | Rex's ANSI colours |
| `danger` | no | The overdue chip | `lists.red` |
| `attention` | no | The due-today chip | `lists.yellow` |
| `contrast` | no | `"standard"` or `"high"`: high halves the ink steps and strengthens lines and edges 1.6× | `"standard"` |
| `tokens` | no | Pins any derived token by name (`"ink-3": "#7F8386"`). For calibrated themes like the default; the floors still apply | none |

The keys name the role, not a hue. Calling a slot `blue` keeps it lined up with today's `--ansi-blue` and with how
the list colour is stored; a theme may make that slot any colour.

### 2.2 What stays fixed

Metrics, type, radii, motion, shadow geometry, the opacities, the brightness factors and the Glass amounts (§1.2).
They hold the layout and the Rex feel, and a theme that changed them would also change hit areas and text fitting.
The contrast floors (§2.5) are fixed too: a theme can't lower them.

**Choice 3, radii and font:** the Shape-Type board shows Tight / Default / Round radii and System / Serif / Mono type
on the real window. **Recommended: neither is part of a theme.** Tight reads cramped next to the 30pt rows, Round
reads soft and un-Rex, Serif sits oddly beside the SF Symbols glyphs and the chips, and Mono widens every title,
so more of them fade out.
If the user wants one later, it belongs in Settings as its own control, not in a theme file.

### 2.3 Light, Dark and System

**Choice 1, recommended A: a theme is a pair.** Every theme file has a `dark` and a `light` side. Settings ▸
Appearance keeps its **Appearance** control (System, Light, Dark; today's Settings ▸ Theme, renamed) and gains
**Theme**. System flips between the theme's two sides as the Mac changes. Two independent choices, each with an
obvious meaning, and no theme can break at sunset.

- B (a theme is one appearance; separate "Light theme" and "Dark theme" pickers) is twice the choosing, and an
  unmatched day and night pair is the likely result.
- C (A, plus files with only one side, which pin the appearance and dim the control) is the natural extension if
  people import one-sided themes. It's not needed for the built-ins, which all have both sides.

### 2.4 Derivation

Every derived token is either a straight sRGB mix of two inputs (`a → b t`) or one input at an alpha (§1.1 has
each rule). The amounts aren't invented: each one solves Rex's measured value from Rex's base, ink and accent. For
example, `sel` dark is (0x33 − 0x1C) / (0xE6 − 0x1C) ≈ 11.4% of the way from base to ink. So a theme with Rex's three
colours and no pins lands within 1–4 levels (of 255) per channel of every measured value. The Tokens board shows each derived value
beside its source. The one exception is dark `ink-3`: the rule gives #828587 rather than #7F8386, because the floor
(§2.5) raises it from Rex's 4.46:1 to 4.5:1.

Order matters only where a rule reads a derived token (`dim` reads `ground`, `tile-fill` reads `fill-strong`,
`mark-rings` reads `ink-2`). `themes.js` derives in a fixed order (`ORDER`).

`contrast: "high"` multiplies the three ink steps by 0.5 (ink-2, ink-3 and ink-q sit closer to ink) and the line and
edge steps by 1.6 (capped at 90%).

These are Pane's rules (`app/Tasks/Pane/PaneTheme.swift:108–132`) recalibrated on Rex. Pane derived from a terminal
theme's background and foreground; Tasks derives from the same two, renamed base and ink, plus the accent.

### 2.5 The contrast check

WCAG 2 contrast ratios, checked once when a theme loads, per appearance. **Fix** means a derived token below its floor
is moved toward ink (lighter in dark, darker in light) in 2% steps until it passes. **Reject** means the theme
doesn't load.

| Token | On | Floor | If below | Why |
|---|---|---|---|---|
| `ink` | base, ground, sel, popover | 7:1 (AAA) | reject | Titles and task text |
| `accent` | base | 3:1 | reject | The checked box, focus rings, the highlighted day (non-text) |
| `ink-2` | base, ground, sel, fill-control | 4.5:1 | fix | Labels, values, chip text, a list's notes |
| `ink-3` | base, ground | 4.5:1 | fix | Group labels, counts, placeholders |
| `ink-q` | base, ground | 3:1 | fix | Icons at rest, strike-throughs, marks (non-text) |
| `line-field` | base | 3:1 | fix | The checkbox ring (a control's edge) |
| `accent-text` | base, accent-tint | 4.5:1 | fix | Links, today's date, tinted chips |
| `danger` | danger-tint, base | 4.5:1 | fix | The overdue chip |
| `attention` | attn-tint, base | 4.5:1 | fix | The due-today chip |
| `on-accent` | accent | 3:1 | fix | The checkmark; text on the highlighted menu item |
| list slots | tile-fill | 3:1 | fix | A list's monogram on its tile |

- **Pinned tokens aren't fixed, only checked**, at 0.05 below the floor. That tolerance exists for one value: Rex's
  dark `ink-3` is 4.46:1 on its base. A pin that fails by more rejects the theme.
- **on-accent at 3:1, not 4.5:1:** white on the accent is the macOS convention for a highlighted menu item, and Rex's
  own blue is 3.75:1 with white. The check only switches to the dark ink when white falls below 3:1 (a yellow accent,
  say).
- **What Settings shows for a rejected theme:** one line under the cards with the file's name and the pair that
  failed, e.g. "Lagoon.json wasn't loaded: its ink is 5.8:1 on its base, and a theme's ink needs 7:1." The built-ins
  are tested to pass (a unit test runs the check on each, both sides).

The sample themes show the check at work. Paper, Dusk, Harbor, Iris and Moss each need one to six raises; the
Tokens board marks them "raised" with the ratio before and after. Dusk, the quietest, needs the most.

### 2.6 Glass

A theme doesn't know about Glass. Glass takes whatever `ground`, `base` and `dim` the theme gives, puts the ground at
60% over the sidebar material and the panes at 88%, and keeps everything else opaque (`INTERACTIONS-v2.md` §4). The
floors are checked on the opaque colours only. What shows through depends on the desktop, so it can't be checked.
Because the two amounts are fixed, every theme is exactly as legible in Glass as the default is, and no theme can
make Glass more see-through. The Glass boards show Harbor dark and Paper light over a busy backdrop.

## 3. The theme file

```json
{
  "format": 1,
  "id": "paper",
  "name": "Paper",
  "dark": {
    "base": "#1F1C18", "ground": "#1A1714", "ink": "#EAE3D8", "accent": "#E0905F",
    "lists": { "blue": "#8FB3D9", "magenta": "#D49AC4", "green": "#A8C07A", "cyan": "#7FC1B8", "yellow": "#DDB25C", "red": "#EE8A74" }
  },
  "light": {
    "base": "#FBF8F2", "ground": "#F1ECE2", "ink": "#2A2621", "accent": "#A44E2A",
    "lists": { "blue": "#2F5F8A", "magenta": "#8A4B7A", "green": "#4F6B2A", "cyan": "#2E6E6A", "yellow": "#8A6512", "red": "#B0362A" }
  }
}
```

The smallest theme is three colours a side (Iris, §5).

- **Format.** JSON, UTF-8, `#RRGGBB` sRGB only (no alpha, no names, no P3). `format` is 1; a file with a higher
  number is skipped with a line in Settings. Unknown keys are ignored, so a later format can add keys without
  breaking older builds.
- **`id`** is lowercase `[a-z0-9-]`, unique; it's what Settings stores. **`name`** is what the card shows.
- **Where it lives.** Built-ins are compiled into the app (`TK.Theme.builtIns`). A person's own themes are files in
  `~/Library/Application Support/Tasks/Themes/*.json`. Settings has Show Themes Folder; the folder is read at launch
  and when it changes (a file-system watch on the one folder). A file with a built-in's `id` is ignored.
- **The choice** is `UserDefaults` `themeID` (default `"default"`). The existing `theme` key (`system` / `dark` /
  `light`) keeps its meaning and stays as it is; only its label changes to Appearance. If the chosen id disappears,
  the app falls back to Default and keeps the stored id, so the theme comes back when its file does.
- **Sync: none.** Agreed with the brief: the theme is a per-Mac preference like Interface style, and syncing it would
  mean syncing files and settings that no other client (the CLI, the server) has a use for. Two Macs can differ, as
  they can in appearance.

## 4. The picker

### 4.1 Settings ▸ Appearance (the Picker board)

Top to bottom:

1. **Appearance**: System / Light / Dark, a segmented control (today's Theme row).
2. **Theme**: a grid of cards, three across, 148×96 each with its name under it. A card is a live miniature: the
   theme's ground, a sidebar with the current-row capsule, a pane with its edge, two task rows (a ring, a checked
   accent box, a due chip) and a selected row, all drawn from that theme's derived tokens. It shows both sides split
   on a diagonal, dark upper left, so the card doesn't change as the appearance does. The chosen card has a 2pt
   accent ring, 2pt out. Hovering brightens the name to ink and shows the card's 1pt `line-pane` edge, on `icon`.
   Clicking applies the theme at once. There's no OK and no hover preview of the whole window (a window that changes
   under the pointer as it crosses the grid isn't quiet).
3. **Interface style**: Classic / Glass, unchanged.
4. Under a hairline: "Themes are kept on this Mac. Add one by putting its file in the Themes folder." and **Show
   Themes Folder**. A file that failed (§2.5, §3) adds one line under it: a 6pt danger dot, the file's name in ink,
   the reason in ink-secondary.

Settings itself is drawn in the theme, like everything else.

**Choice 2.** B, a list with swatch dots, is denser and suits dozens of imported themes, but six dots say little
about how the window will feel. **Recommended: A.**

### 4.2 View ▸ Theme (choice 2C, recommended with A)

A submenu after Show Details, next to an Appearance submenu: the themes by name, the current one checked, then a
separator and Theme Settings…, which opens Settings ▸ Appearance. **No shortcut:** themes change rarely, and a
shortcut that repaints the window by accident is worse than none.

### 4.3 Switching

**Instant, in one frame** (recommended), as the appearance switch already is (`INTERACTIONS-v2.md` §2.5, §4): every
drawn surface, the window's appearance, menus, the popover, notices and tooltips change to the new palette before the
next frame is drawn. The prototype's strip also offers **Fade**, a 180 ms cross-fade of the whole window (the old
frame dissolving over the new), for the user to feel. It's smooth, but it's the only thing in the app that animates
a colour change across the whole window, and Rex doesn't animate tab or theme switches.

What has to update, from item 9 of the v2 feedback (`docs/TASK-v2-feedback.md`): layers with baked-in `CGColor`s,
cached row renders (rows compare palettes before redrawing), the traffic lights' placement (an appearance change
re-lays out the title bar), the date popover, tooltips and notices, the Glass ground's material appearance, and the
Settings window. A theme switch that keeps the appearance doesn't touch the window's `NSAppearance`, so the title-bar
re-layout from item 9 doesn't happen. A switch that changes both (picking a dark-only theme under choice C) takes the
existing appearance path.

## 5. The sample themes

All seven pass §2.5. The canvas shows each one across a list with headings, the detail pane on a task with Markdown
notes and the date popover open, and Today, dark and light.

| Theme | Mood | Dark: base / ground / ink / accent | Light: base / ground / ink / accent | Lists | Raised by the check |
|---|---|---|---|---|---|
| **Default** | Rex: graphite and white, a blue accent | #1C1C1C / #181818 / #E6EDF3 / #2F81F7 | #FFFFFF / #F5F5F5 / #1F2328 / #0969DA | Rex | nothing (pinned) |
| **Paper** | warm paper and brown ink, a rust accent | #1F1C18 / #1A1714 / #EAE3D8 / #E0905F | #FBF8F2 / #F1ECE2 / #2A2621 / #A44E2A | earthy, its own | dark ink-3; light ink-2 on sel, ink-3 and ink-q on ground |
| **Contrast** | black and white, high contrast | #0A0A0A / #000000 / #FFFFFF / #4AA8FF | #FFFFFF / #EDEDED / #000000 / #0047B3 | Rex | nothing |
| **Dusk** | muted slate, soft ink, periwinkle | #23232A / #1D1D23 / #D9DAE2 / #9AA7E0 | #F6F6F4 / #ECECE8 / #34353C / #55639D | muted, its own | dark ink-3, ink-q, line-field; light ink-2, ink-3, ink-q |
| **Harbor** | cool blue-grey, a sky accent | #15202B / #101922 / #DCE7F2 / #4CB2EC | #F7FAFD / #E9EFF6 / #18232F / #0E6FB5 | Rex | dark ink-3; light the three tinted chips' text |
| **Iris** | the default's surfaces, one vivid violet | #1C1C1C / #181818 / #E6EDF3 / #9B6BFF | #FFFFFF / #F5F5F5 / #1F2328 / #7A3FF2 | Rex | dark ink-3 (unpinned) |
| **Moss** | green-grey, a leaf accent | #1B1F1C / #161A17 / #DEE6DD / #62C08A | #FAFBF8 / #EDF1EA / #212822 / #2B7A4B | Rex | dark ink-3; light ink-2, ink-3, the tinted chips' text |

Contrast uses `contrast: "high"`. The names are plain words for the moods, not borrowed from existing themes or apps.

## 6. In the app

### 6.1 Changing the accent

The accent is one value, `accent:` in `Theme.rex` (`app/TasksCore/Sources/TasksTheme/Theme.swift`; the Mac calls it
`TK.Theme.rex`). Change that hex and everything that shows the accent follows, in both appearances: light's accent
(derived, `Theme.accent(dark:)`), `accent-text` (raised if it falls under 4.5:1), `accent-tint`, `on-accent` (white
while white holds 3:1 on it), `focus`, `text-selection`, `spark`, `mark-head`, Today's tile, and so the checked box, the
highlighted day and menu item, links and rings. No other app code has an accent hex. To give one appearance its own
accent instead, set that `Side`'s `accent`. `plan` (the When ring) is pinned, so it stays blue unless its pin goes. Then
run the theme's tests (`xcodebuild test -scheme Tasks` in `app/`: `TasksThemeTests` and the Mac's
`TasksTests/ThemeTests.swift`): they check the values, that every derived token follows a new accent and nothing else
moves, and the floors. The Mac's `ThemeGoldenTests` holds every token, palette colour and tile pixel to
`ThemeGolden.json`, so it fails on any change of colour, as it should: re-record it with
`TEST_RUNNER_THEME_GOLDEN_RECORD=1`, then commit the new JSON with the change.

### 6.2 The plan

The aim: a theme costs nothing per frame. A palette is built once per change of theme or appearance, and everything
already draws from a palette value.

1. **`TK.Theme`** (new, `app/Tasks/Theme/Theme.swift`): `Codable`, the file's shape (§3), with `builtIns` and a
   `load(from: URL) -> Result<TK.Theme, ThemeError>`. `ThemeError` carries the failing pair for Settings' line.
2. **`TK.Palette.init(theme: TK.Theme, dark: Bool)`** derives every token by the rules in §2.4 (port `derive` from
   `themes.js`; keep the rules as one table, as there), runs the check, and returns the palette or the error.
   `Palette.dark` and `.light` become `Palette(theme: .default, dark: true / false)`, and a unit test asserts they
   equal today's literals exactly (the pins).
3. **Equality.** `Palette` gets `let themeID: String` and `let revision: Int` (bumped when a file changes on disk), and
   `==` compares `(themeID, revision, isDark)`. Today it compares `isDark` only (`TK.swift:36`), so rows that check
   `palette != self.palette` before redrawing (`TaskRowView.swift:121`, `485`) would skip a theme switch.
4. **Caching.** `AppModel` holds `themeID`, the loaded themes, and `palette: TK.Palette`, recomputed in `didSet` of
   `themeID`, `theme` and `systemDark` and on a Themes-folder change. Deriving is about 40 mixes and 30 contrast
   checks: microseconds, once. `ThemedRoot` (`TasksApp.swift:28–43`) puts that one value in `\.tk`. `PaneColors` is
   built from the same `TK.Theme` (its `PaneTheme` init takes `background: base, foreground: ink, accent`), so the
   Settings and popover components can't disagree with the rows.
5. **AppKit layers** already take a palette and re-set their `CGColor`s when it changes (the item 9 path). Equality
   (3) makes that path fire on a theme switch too. Nothing reads a theme per frame; `CGColor`s are made when the
   palette is set, not when drawing.
6. **The brand mark** (`SidebarHeader.swift:59–66`) reads `palette.markHead` and the others instead of literals.
7. **Settings** (`Views/SettingsView.swift:38`): rename the row to Appearance, add the Theme grid (a SwiftUI
   `LazyVGrid` of cards; each card is a small view drawing from `TK.Palette(theme:dark:)` for both sides, built once
   per theme and kept), and the folder button and error line.
8. **Debug script** (`Support/DebugScript.swift`) gains `themeid:<id>` beside `theme:` so captures can cover every
   theme.

## 7. The prototype

`design/prototype-themes/` (the canvas's files):

- `Main.dc.html`: prototype-v2's prototype (commit 16e9625) plus `themeId`, `glass`, `shape` and `font` props, the
  strip's Theme, Style and Switch controls (in place of Edit tasks and the browser-keys note), `applyTheme` (instant or
  faded), `demo="theme"` (PHYS 122, Lab 3 selected with its notes in the details and its When popover open), and
  notes on Lab 3.
- `themes.js`: the sample themes, the derivation and the check (`window.TasksThemes`). `styleFor(id, appearance)`
  returns the root's CSS variables, cached.
- `themes.css`: the tokens that were literals, Glass, the shape and type variants, the cross-fade. `tasks-v2.css` and
  `markdown.css` are prototype-v2's, unchanged, so their `css:N` citations still hold.
- `Picker.dc.html`, `ThemeCard.dc.html`: Settings ▸ Appearance and its card.
- `Tokens.dc.html`: the inventory, live for any theme and appearance.
- `Appearance-Variants.dc.html`, `Picker-Variants.dc.html`, `Shape-Type.dc.html`: choices 1–3.
- `Glass-*.dc.html`, `<Theme>-List-*.dc.html`, `<Theme>-Today-*.dc.html`: the boards.
- `canvas.json`: the layout and notes.
