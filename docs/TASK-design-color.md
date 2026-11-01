# Task: design more colour into the app

## What the user said
- "I feel like we don't have enough color that it's a bit bland."
- "I like the surface colors and stuff, but maybe we can make some designs for how to introduce more color."
- "for some reference, i like the orange in this image." The image is `docs/feedback/color-reference-orange.png`: a
  rounded tile, its dominant colour #D66F49, with a white asterisk/spark on it, sitting on dark grey.
- "that orange is nice but be creative."

So the orange is a point of reference, not the answer. Be creative, but keep the app the user already likes.

## Scope
**This is design only.** Leave the app code alone. Start from `design/prototype-v2/` and the specs:
- the token table in `design/INTERACTIONS-v2.md` §1, including `accent` (#2F81F7), `accent-text`, `accent-tint`
  and the list hues;
- §12, the sidebar, where list tiles get a colour slot;
- §24, dates and checkbox rings.

Also read `design/THEMES.md`. It's tabled, but its derivation rules show how a new hue could flow through the
tokens. Rex (`design/REX-REFERENCE.md`) and the Pane vocabulary remain the baseline. The surfaces, the greys and the
quietness stay. Colour is added where it carries meaning or delight. It shouldn't be paint everywhere.

## Explore
Make **three to five directions** that differ in kind, not only in hue. Some ideas to push against, though you can
go elsewhere:

- **A warm accent.** Replace or complement the blue `accent` with a warm hue near the reference orange. Show checkboxes,
  the highlighted day, focus rings, selection, the Today sun and the brand mark.
- **Colour per list.** Each list's hue tints more than its tile: its large title, its checkbox fills, a faint wash at
  the top of the pane, the selection, and its row in the sidebar when current.
- **Colour per view.** Today warm or sunny, Upcoming cool, Trash muted, and so on. Each view gets an identity colour
  carried into its header and empty state.
- **Moments of colour.** Mostly quiet, with colour at events: completing a task (a burst or flash of hue), the
  sync indicator, deadlines, a done Today, and empty states.
- Something you think is better.

For each direction:
- What gets colour, and what stays grey. Be explicit.
- The exact tokens: new or changed hexes, in dark and light.
- Contrast checks for text on colour.
- How it plays with the existing semantic colours: red/amber deadlines, the blue When ring, and danger.

## Output
- A canvas (Claude Design, as earlier design tasks did). Show each direction side by side, in dark and light, on
  real screens: the sidebar with Today and the lists, a list with tasks and a checked task, and the date popover.
  Make it interactive enough to feel it, for example toggling between directions on the same screen.
- A short proposed section in `design/` (a new `COLOR.md`, or a THEMES.md addendum, whichever fits).
- Per-path commits only (`git commit -m … -- <paths>`), ending with `Co-Authored-By: Claude Opus 5.5
  <noreply@anthropic.com>`. Never `git add -A`. Never push.

## Don't
- Don't touch the installed app, its data, the live server, or Rex.

## Report
- The canvas link.
- One line per direction.
- Your recommendation and why.
