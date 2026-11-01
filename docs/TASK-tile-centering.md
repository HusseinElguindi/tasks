# Task: centre the glyphs and letters in tiles

The user: "the icons and text feel not centered within a box btw, even in the swift app (very slightly). can we
figure out why."

Their screenshot is `docs/feedback/tile-centering.png`, a zoom of the colour canvas's lit tiles. The coordinator
measured it: the ink of each glyph (sun, calendar, stack) is horizontally centred, but its centre sits **≈1 pt below**
the tile's centre (+12.5 to +16 px at about 15.7 px/pt).

## Leads
- **The app does it on purpose.** `app/Tasks/Theme/Draw.swift` around line 298 sets
  `sun.position = CGPoint(x: d.width / 2, y: d.height / 2 + 1)`, with the comment "1pt below center, as the
  prototype's tile lays its sun out (measured in Chrome)". The app copied a quirk.
- **The prototype tile:** `design/prototype-v2/tasks-v2.css:124–127` is `display: grid; place-items: center;
  font: 700 10px/1 mono`, with a 12px `svg.i` (viewBox 16) inside. On paper that's centred, so find out what really
  shifts it in a browser: line box, baseline, the svg's display, or the glyph paths themselves. The colour prototype
  is `design/prototype-color/color.css`, with `.tile` and `.vg`.
- **Letters:** `letter.place(x: 0, lineTop: (d.height - font.pointSize) / 2, lineHeight: font.pointSize, …)`
  centres the line box, not the capital's ink. A cap in a 1.0 line box usually sits off-centre. Measure it.

## Do
1. Measure the real ink centres:
   - In the app: Debug build, run against a scratch data folder with sync off, using its debug hooks and a
     screenshot.
   - In the prototype: render it headless. Chrome isn't installed, so use `uv run --with playwright` and its
     browsers, or WebKit.

   Cover each view glyph (sun, calendar, stack, check, trash) and a few monograms (S, E, I, P, C), at both tile
   sizes. A glyph whose own path is off-centre in its box should be fixed in the glyph, not by nudging.
2. Fix the centring in the app for the tiles, the sidebar, list headers and the brand mark if it shares the code.
   Centre on the ink: for a glyph, its path's bounds; for a letter, the cap height (`capHeight`, centred), not the
   line box. Remove the +1.
3. Fix the prototypes to match: `prototype-v2` and `prototype-color`. Then republish the colour canvas
   (https://claude.ai/artifact/ANUrtropTfm2GwdAAXWAYv) if its files changed.
4. Note the rule in `design/INTERACTIONS-v2.md` (§12's tile row, or wherever the tile is specified): glyphs and
   letters are centred on their ink, citing "the user, 2026-11-01".
5. Report before and after offsets in pt for each glyph and letter.

## Rules
- Build Release into `app/.build/DerivedData` and run the tests.
- Per-path commits only (`git commit -m … -- <paths>`), ending with `Co-Authored-By: Claude Opus 5.5
  <noreply@anthropic.com>`. Never `git add -A`. Never push.
- Don't touch the installed app in ~/Applications, its data, the live server, or Rex. The coordinator installs.
- The colour design agent may still be open, but it's idle. Commit only your own paths.
