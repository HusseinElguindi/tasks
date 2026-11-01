# Task: build colour A + B + D

**The user's pick (2026-11-01):** "let's forget Rooms (C). A is good. make this accent color easily changed (in
case we pick up the theming later). B is good. use the tiles as above. D is good. so yea ABD."

The spec is `design/COLOR.md`:
- §1 A, Ember;
- §2 B, Tiles, with the lit finish from `docs/feedback/reference-tile.svg`;
- §4 D, Moments;
- §5 the pick;
- §6 the theme rules.

The prototype is `design/prototype-color/`. The canvas is https://claude.ai/artifact/ANUrtropTfm2GwdAAXWAYv.
Where the spec and the prototype disagree, the prototype wins, as always.

## First
1. Make the spec final. Mark COLOR.md **final: A + B + D, the user, 2026-11-01**. Cut C down to one line saying
   it's dropped, and say why. Fold the decisions below in.
2. **Wait for the tile-centring work.** Another agent ("Tile centring", brief `docs/TASK-tile-centering.md`) is
   changing `TileLayer` in `app/Tasks/Theme/Draw.swift` and the tile CSS right now. Don't edit those until its
   commits land: check `git log` for its commits, and check that `git status` shows no uncommitted changes in
   `Draw.swift`. Until then, work on the parts that don't touch the tile.

## Decisions the coordinator made (the user can still change them)
- **The Ember accent is #E6683D, the source tile's own colour.** That replaces round 1's #D66F49, so the accent
  and Today's tile are the same hue. White on it is 3.28:1, which is fine for glyphs and checkmarks. Derive the
  light-mode value, `accent-text` and `accent-tint` by the §6 rules. Check `accent-text` against its text floor.
- **Today's sun stays white on #E6683D,** as in the reference, even though the tip of its top ray is 2.57:1.
- **Danger red stays** unless the build shows it can't be told apart from the accent. If so, say so and don't
  change it.
- **The app icon stays as it is.**

## The accent must be easy to change
The user wants to change the accent later, for theming. So it must be **one value per appearance in one place,
with everything else derived**: `accent-text`, `accent-tint`, `focus`, `text-selection`, the checked box,
the highlighted day, menu highlight, and Today's tile if it follows the accent (decide, and say which). Use the
THEMES.md derivation in `app/Tasks/Theme/Theme.swift`. No hex for the accent anywhere else in app code. Add a test
that changing the source accent changes every derived token. Note in THEMES.md how to change the accent.

Likewise, the tile hues are one table, and the lit finish is derived from any hue by rule, as §2 says.

## Build
- A, B and D as specified, in dark and light, Classic and Glass.
- B's tiles everywhere the prototype has them: the sidebar, list headers, the large title, menus, the detail pane's
  List, a dragged list, and the brand mark.
- D's completion moment and the all-done Today.
- Respect Reduce Motion.
- Build Release into `app/.build/DerivedData` and run all tests.
- Drive the Debug app with its debug hooks against a scratch data folder, with sync off. Take screenshots of the
  sidebar, a list, Today all done, and the date popover, in dark and light. Compare them with the canvas.
- Update `design/INTERACTIONS-v2.md` wherever tokens or tiles are described.

## Rules
- Per-path commits only (`git commit -m … -- <paths>`), ending with `Co-Authored-By: Claude Opus 5.5
  <noreply@anthropic.com>`. Never `git add -A`. Never push.
- Don't touch the installed app in ~/Applications, its data, the live server, or Rex. The coordinator installs.
- Compact yourself if context passes about 45% between steps.

## Report
In a few lines:
- what was built;
- where the accent lives, and how to change it;
- the test results;
- any departures from the canvas;
- the commit hashes.
