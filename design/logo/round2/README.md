# App icon, round 2

Canvas: https://claude.ai/artifact/3YwirhrEHxooT5pJcRoHN1 (private until it's shared from its Share menu). Brief:
coord T38, after the user said on 2026-11-08: "i dont like our logo that much. let's explore more."

This is exploration only. No app assets changed, and round 1's canvas and `final/` are untouched.

## Where the current logo lives

| Where | What | How it's built |
|---|---|---|
| Mac app | `app/Tasks/AppIcon.icon` (Icon Composer: four SVG layers and `icon.json`) | Copied from `design/logo/final/AppIcon.icon`; `app/project.yml` sets `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` |
| Mac exports | `design/logo/final/` (SVG masters, the iconset PNGs 16–1024 with a small cut below 60px, `AppIcon.icns`, `system/*.png`) | `final/export.sh` from the geometry in `final/gen.py` |
| iOS app | `ios/Tasks/Assets.xcassets/AppIcon.appiconset/icon-1024.png`, one PNG for both any and dark | `ios/Tools/MakeIcon.swift` draws it with Core Graphics |
| Widgets, menu bar, web | None. Widgets draw no brand mark, the Mac app has no menu-bar item, and `server/` and `remote/` serve no favicon | |

The icon is **04 Log** (picked 2026-10-31). It's dark only, with a head in Rex blue #2F81F7, and COLOR.md (2026-11-01)
kept it that way when the app's accent moved to Ember #E6683D.

## What might be weak about it

These are guesses for the user to confirm, not the user's stated reasons:

1. It's off-palette: the head is still blue while everything you act on in the app is Ember.
2. Its idea (the sync log drawn as a commit graph) doesn't show. To anyone else it's a bulleted checklist, the most
   common to-do glyph there is.
3. At 16 and 32 it has no silhouette of its own: just a blue dot and grey dashes.
4. It doesn't share the app's finish: the app draws solid, lit tiles with white glyphs, and the icon is a flat diagram.
5. It's busy, with nine parts, for an app whose point is quiet.

## The directions

| # | Direction | One line |
|---|---|---|
| 00 | Current · Log | Sync's commit graph with a checked task at its head |
| 01 | Spark | The checked Ember box and the eight-ray completion spark (COLOR.md D) |
| 02 | Ember tile | The app's lit tile at full size with one big check; in dark, the check goes Ember on the dark body |
| 03 | Fan | Your lists as a fan of tiles in the sidebar's colours, today's on top and checked |
| 04 | Steps | A check built from five tiles, light Ember to deep |
| 05 | t | A lowercase t: the stem in ink, the crossbar an Ember task row |
| 06 | Breakout | A check breaking out of its ring: done, and moving on |
| 07 | Daybreak | Today's sun rising behind a checked box |
| 08 | Cursor | A check, then the block cursor; round 1's top pick, in Ember |
| 09 | Chain | Two linked rounds of the append-only log, over and under |
| 10 | Tick | One heavy check, the short stroke Ember |

**Top 3:** 05 t, then 06 Breakout, then 01 Spark. The canvas's green note says why. 02 Ember tile is the safe fallback.

## Files

- `Icon.dc.html` draws every mark as up to fourteen paths in 1024 units on the macOS grid. Its props are `mark`, `look`
  (dark or light), `shape` (mac or ios) and `size`. Below 60px it uses a small cut. iOS scales the mark ×1.2427 onto
  the full-bleed body; its corners are a plain `rx` 230, not Apple's continuous curve.
- `Sheet.dc.html` lays out one direction: macOS and iOS in light and dark, 128 to 16, the Dock and a Finder list.
  Each of `D00` … `D10` mounts it with one `mark`.
- `Main.dc.html` is the overview. `canvas.json` holds the layout, the two notes and the Pane design-system record.
  The canvas runtime and Pane's `tokens.json` come from the Design type and from Pane, and aren't stored here.
