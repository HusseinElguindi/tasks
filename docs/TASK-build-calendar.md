# Task: build the endless scrolling calendar (§25)

The user approved the design.
- **Spec:** `design/INTERACTIONS-v2.md` §25, final in b6332f5.
- **Prototype:** `design/prototype-v2/`.
- **Canvas:** https://claude.ai/artifact/2wUF9Dz2JEt8Xp2pBDahy2, board Cal-Proto.

As always, the prototype wins over the spec.

## The user's picks

- The calendar is one continuous column of weeks, endless in both directions and generated on the fly. Only the visible weeks plus a small buffer exist; the window recentres as you scroll, with no jump and no lost momentum.
- A sticky month header, with other months' days dimmed.
- It snaps to whole weeks when the scroll comes to rest.
- A "Today ↑/↓" pill appears when you're more than two weeks away from today.
- The keys: arrows move by day and week, Page Up and Page Down move by month, and a typed date animates to its month.
- **A narrower popover, 240pt instead of 288.**
  - The days are 32pt apart.
  - The Next Week quick pick is removed; typing "next" still works.
  - The hint is shorter, and the bottom line drops parts in the order the spec gives.
- **Approach:** an AppKit NSScrollView with about 14 reused week rows and a moving 120-week window, as the spec says. SwiftUI's ScrollView can't shift rows and scroll position together without a jump on macOS 14. If you find otherwise, say so.
- **Also check §24 against the change §25 made:** far past dates now read in months and years ("10 months ago", "1 year overdue"), not "1400 weeks". The app's formatter, and the CLI's, may need the same.

## Rules (as before)

- Use a scratch Tasks Dev and `wrangler dev` only.
- Commit per path with the co-author line, never push.
- Verify scrolling frame by frame: decades up and down, momentum through a recentre, snapping, the Today pill and typed jumps.
- Run the §9 benchmarks, and add one for the popover's open time and scroll frame cost.
- Make a Release build and report back.
