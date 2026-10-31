# Task: design a sidebar footer

The user's words: "you know what, start something on a sidebar footer design." This came right after they approved the §26 sync indicator in the header row and said "maybe we'll do a sidebar footer later".

**This is design only.** Start from the current sidebar in `design/prototype-v2/` and the specs:
- §12, the sidebar;
- §22 and §23, the views, archive and headings;
- §26, the sync indicator.

Look at how Rex itself ends its sidebar (`design/REX-REFERENCE.md`). Don't drive Rex.

## Explore

- **What belongs in a footer, if anything.** Candidates:
  - sync status: a quiet "Synced 2 min ago" line, or §26's cloud moved down here;
  - a "New list" button (today it's ⇧⌘N or the Lists header's +);
  - a Settings button;
  - the Archive toggle;
  - possibly the brand header's mark and name.

  Keep it Rex-quiet. Your earlier concern was that a footer line says "Synced" all day, so address it, for example with text that only appears on hover or when something's wrong.
- **How it relates to §26.** Should the sync indicator live in the footer instead of the header row, in both places, or should the footer hold other things? Recommend one.
- **Layout:** height, divider or none, how it sits over a scrolled list (pinned, with a fade above), how it behaves when the sidebar collapses or is resized, and Glass.
- **Show two or three directions side by side,** in dark and light, on a small canvas focused on the sidebar. No full-prototype integration testing.

**Output:** the canvas, a short spec section marked proposed, per-path commits with the co-author line (never push), and a report with your recommendation.

The Mac v2 agent will start building §26 after the calendar. If your recommendation would move the indicator, say so clearly in your report, so the coordinator can hold that build.
