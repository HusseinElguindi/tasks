# Pane upstream log

Where the Pane design system (design/PaneTheme.swift, the Claude Design canvases, design/DIRECTIONS.md) differs from
the real Rex app. Rex is the source of truth (docs/TASK-source-of-truth.md); the Tasks app already follows Rex in each
case below. Each entry: what Pane says now, what Rex does (measured as in design/REX-REFERENCE.md: window
screenshots sampled in sRGB with `.uitools/px.swift`, Rex Beta, dark theme), and the proposed change to Pane.

## Tokens

### `ink-secondary` (dark)
- **Pane:** `ink2` 0.42 (foreground mixed toward the background) = #919598.
- **Rex:** sidebar titles at rest measure #A8ADB1 on every row type, and the toolbar icons at rest are the same
  #A8ADB1. That is a 0.305 mix.
- **Proposal:** `ink2` 0.305 in dark.

### `ink-tertiary` (dark)
- **Pane:** `ink3` 0.48 = #85898B.
- **Rex:** group headers ("ECE 358") and the ⊕ and chevron they reveal measure #7F8386, a 0.508 mix.
- **Proposal:** `ink3` 0.508 in dark.

### `ink-quiet` (dark): agrees
- **Pane:** `quiet` 0.60 = #6D7072. **Rex:** secondary text inside a title ("Yazi ~/school") is #6E7274 (0.59).
  No change.

### `shadow-capsule` (dark)
- **Pane:** a 1pt inset hairline of white 7%, so both edge pixels of the selected capsule are #525354.
- **Rex:** the selected capsule's edge is two-step: an outer pixel of #5E5E5E over an inner #535353, on a #444444 fill,
  the same on all four sides; no drop shadow (the ground below it stays #181818/#191919).
- **Proposal:** white 8% at 1pt, plus white 6.5% on the outer 0.5pt.

### `fill-strong` (dark)
- **Pane:** derived toward the foreground (0.20), so it carries the foreground's blue: #454647.
- **Rex:** the selected capsule is neutral #444444, the ground (#181818) plus 19% white.
- **Proposal:** derive dark fills toward white rather than the foreground. (Not applied in Tasks: it's 1–3 levels.)

## Sizes and layout

### `size-sidebar`
- **Pane:** 220. **Rex:** the first pane starts at x 230.
- **Proposal:** 230.

### Rows: shape and pitch
- **Pane:** sidebar lists are "30pt capsule rows" with 4pt gaps; task rows are "32pt" (`size-sidebar-row`) with 2pt
  gaps, so 34pt apart.
- **Rex:** every row is a 30pt shape on a 32pt pitch (capsule y 295–325, next row's middle 32pt lower).
- **Proposal:** `size-row` 30 and a 32pt pitch for all rows, task rows included.

### Sidebar row geometry
- **Pane:** 8pt sidebar padding, 8pt inside the capsule, 8pt between tile and title.
- **Rex:** capsules 10pt from the sidebar's left edge and 11pt from its right (x 10–219 in a 230pt sidebar); tile
  column 10pt inside the capsule (x 20–40); title text 7pt after the tile (ink starts at x 47.5); the trailing
  action centered 16pt inside the capsule's right edge (× at x 199–207, ••• at x 195.5–210.5). Long titles fade out
  by x 185.
- **Proposal:** these insets; trailing actions in a 22pt slot 5pt in from the row's edge.

### Text baseline in a row
- **Pane:** text centered by SwiftUI (13pt body: baseline 5pt below the row's middle).
- **Rex:** baseline 4pt below the row's middle ("Mac" 368.5–378 in a row centered at 374), so text sits 1pt higher.
- **Proposal:** offset row text up 1pt.

### Program tile
- **Pane:** a 20pt square (radius 5); 16pt in headers.
- **Rex:** 20 × 16 (5:4), radius about 4, with a dark outline (its tiles are colored).
- **Proposal:** 5:4 tiles at every size (Tasks: 20 × 16, 16 × 13, 12 × 10), keeping Pane's fill-strong tile with
  the ANSI glyph.

### Group label
- **Pane:** 11 semibold `ink-tertiary` (agrees: Rex's ink widths match 11pt semibold), no hover behavior.
- **Rex:** at x 22 (12pt inside the capsule edge), baseline 27pt above the next row's middle; on hover it reveals ⊕
  and a collapse chevron at the right, in the label's own color.
- **Proposal:** a group-header component with the ⊕ reveal in the rows' trailing slot.

## Hover and motion

### Hover timing
- **Pane:** no hover tokens (motion is `snappy` 200 ms, `natural` 300 ms, `reveal` 600 ms).
- **Rex:** row hover-in ~80% on the first frame, settled in 50–70 ms; hover-out an ~85 ms fade that starts the
  moment the pointer leaves (no hold); icon buttons ~100 ms both ways; pane focus ~60 ms.
- **Proposal:** `duration-hover-in` 60 ms, `duration-hover-out` 85 ms, `duration-icon` 100 ms, `duration-focus` 60 ms.

### Row hover appearance
- **Pane:** no row hover state, except DIRECTIONS' six-dot drag grip that appears on hover.
- **Rex:** no fill on hover. A row's title goes from `ink-secondary` to `ink`, its trailing action fades in, icons
  don't change, nothing shifts; the whole row is the drag handle.
- **Proposal:** specify this hover for rows (sidebar and list rows alike) and drop the grip.

### Row action glyph
- **Pane:** SF Symbol `ellipsis` at 12pt bold.
- **Rex:** three 3.75pt dots on a 5.5pt pitch (15 × 3.75); revealed actions are `ink-secondary` (× measures
  #A9AEB2).
- **Proposal:** a dots glyph with these sizes.

### Icon buttons and panes
- **Pane:** `PaneIconButton` is a plain button in `ink-quiet` with no hover or pressed state; unfocused panes only
  dim their surface.
- **Rex:** on hover a small fill appears behind the glyph (a rounded square in pane headers, a circle in the
  toolbar), ~100 ms; tooltips read "Name ⌘X"; unfocused panes also fade their header icons; actions that don't apply
  are drawn disabled.
- **Proposal:** add the hover fills, tooltips with shortcuts and faded header icons to Pane's button and pane specs.

## Window

### Window controls
- **Pane:** not specified; with a hidden title bar AppKit puts the traffic lights at centers (16, 16), 39 and 62.
- **Rex:** the traffic lights' circles span 18–32pt (centers 25, 48, 71 at y 25), on the line of the pane titles, and
  the toolbar icons follow on the same line (sidebar toggle centered at x 107, then 145, 175, 205).
- **Proposal:** specify Rex's 50pt toolbar band: window controls and toolbar icons centered 25pt from the top.

## Interactions v2 (2026-10-30)

From `design/INTERACTIONS-v2.md` and its prototype. Rex has no task lists, popovers or notices to measure against in
`design/REX-REFERENCE.md`, so most of these are gaps in Pane rather than measured differences; the ones that need a Rex
measurement are listed in INTERACTIONS-v2 §20.

### `fill-selected` for content rows
- **Pane:** `fill-selected` #272728 (dark), "selected row in a sidebar or list".
- **Rex:** no content lists; its one selection is the #444444 capsule with the two-step edge (measured).
- **Tasks:** on a #1C1C1C pane #272728 is about 1.1:1 and selection was hard to find. Task rows use #333333 in the
  focused pane and #292929 in an unfocused one (light #E6E6E8 / #EFEFF0), and adjacent selected rows join into one
  block.
- **Proposal:** add `fill-row-selected` and `fill-row-selected-dim` with these values; keep `fill-selected` for
  settings sidebars.

### Popover surface
- **Pane:** popovers and menus on `surface-card` (#1F1F1F dark) with `shadow-popover` (DIRECTIONS).
- **Rex:** context menus are native; its own popups were not sampled.
- **Tasks:** #1F1F1F over a #1C1C1C pane is 1.07:1, so only the shadow separates it. The date popover, notices and
  tooltips use #262626 with a 0.5pt white 14% hairline.
- **Proposal:** add `surface-popover` (dark #262626, light #FFFFFF) and put the hairline in `shadow-popover`.

### Text on accent in menus and checkboxes
- **Pane:** `on-accent` is the theme background in dark (#1C1C1C), "never white".
- **Rex:** native menus draw the highlighted item white on the accent.
- **Tasks:** keeps Pane's cut-out label for capsule buttons, but highlighted menu items, suggestion rows and the
  checkmark in a checked box are white.
- **Proposal:** say so in Pane: `on-accent` for capsule buttons, white wherever the system draws the highlight.

### Icon-button hover and press fills
- **Pane:** `PaneIconButton` has no hover; v1 used `fill-selected` behind pane-header icons.
- **Rex:** "a small fill appears behind the glyph" (rounded square in pane headers, circle in the toolbar), ~100 ms;
  the fill's value wasn't sampled.
- **Tasks:** translucent fills that work on any surface: hover white 7%, press white 12% (light: #1F2328 6% / 11%).
- **Proposal:** `fill-hover` and `fill-press` tokens with those values; `duration-icon` 100 ms.

### Layout motion
- **Pane:** `snappy`, `natural`, `reveal`; nothing for rows that move.
- **Tasks:** one spring for every row that moves (reorder, insert, remove, a checked task settling, drag gaps):
  `.smooth(duration: 0.25)`. Switching lists stays instant (Rex: tab switches don't animate).
- **Proposal:** `motion-layout` = `.smooth(duration: 0.25)`.

### Text entry focus
- **Pane:** "a solid 2px `focus-ring` with a 1px gap" on fields.
- **Rex:** not measured (how its inline tab rename looks is INTERACTIONS-v2 §20 question 3).
- **Tasks:** a row being renamed shows a 1.5pt inset accent ring on the row itself; always-editable fields (the detail
  title and notes) show only the caret.
- **Proposal:** Pane's ring for form fields; this lighter treatment for in-place edits.

### Components Pane doesn't have yet
Specified in INTERACTIONS-v2 and drawn in the prototype; each is a candidate Pane component:
- **Notice**: one-line status with an Undo capsule, bottom-right of a pane, 5 s, held while hovered (Rex has notices;
  their corner and timing are §20 question 1).
- **Tooltip with keys** ("New Task ⌘N"): Rex draws its own since preview.23 (its style is §20 question 2).
- **Date popover**: a field, quick picks and the month (INTERACTIONS-v2 §11).
- **A new item's untitled state**: until a new task has a title, everything under it in the detail pane is drawn at 45%
  and ignores the pointer (INTERACTIONS-v2 §6). Pane has no disabled token; menus in the prototype use 40%.
- **Group-label reveal** (⊕ or chevron in the trailing slot on hover), which Rex has on session headers.
- **Ghost add row**: the landing slot under a list, revealed on hover.
- **Drag**: lifted copy (`fill-lift` #2C2C2C dark, `shadow-lift`), count badge, row gap, and a compact tag over drop
  targets.
- **Held-⌘ shortcut hints** in the sidebar (Rex preview.16).
