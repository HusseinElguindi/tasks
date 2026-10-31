# Task: finalize logo 04 · Log and put it in the app

The user picked **04 · Log**: the append-only history drawn like a commit graph, with a checked task at the head.

1. **Refine it into the final mark.**
   - Polish the 1024 master and the simplified small-size version used below 60pt.
   - Optical checks at 16, 32 and 64.
   - Light and dark appearance, plus tinted and clear.
   - Keep it faithful to what the user picked; don't redesign it.
   - Add a "Final" board to the same canvas (https://claude.ai/artifact/ScTE29QmxCwxJxfRdnrNPd) and republish it at the same URL.
2. **Export it** to `design/logo/final/`: SVG masters, plus PNGs at every macOS app-icon size (16, 32, 128, 256 and 512, each @1x and @2x).
   - Use the light/dark/tinted variants if the macOS 26 icon format supports them with our toolchain (an Xcode asset catalog `AppIcon` or an Icon Composer `.icon`). Otherwise use a single icon set and note what was left out.
3. **Wire it into the app.**
   - Add the `AppIcon` to the Tasks target (`app/project.yml`, plus an asset catalog under `app/Tasks/`).
   - Build Release to confirm the icon appears in the built bundle's Finder icon and Dock icon. Check it by launching the built app with `-dataDirectory` pointing to a scratch folder, never the real data folder.
   - If the sidebar header or the About panel shows an app glyph, use the bare mark there.
   - Don't install anything to `~/Applications`, and don't touch the live server or Rex.
   - Keep `app/` edits to the icon only; the Mac v2 agent owns the rest of `app/`.
4. **Commit** per path, never `git add -A` and never push. End commit messages with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

When you're done, report the canvas link, the commit, and the path of the Release build to the coordinator.
