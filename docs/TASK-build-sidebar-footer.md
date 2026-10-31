# Task: build the sidebar footer (§27, direction A)

The user picked **direction A**. The spec is `design/INTERACTIONS-v2.md` §27 (0b5c30c) and the canvas is https://claude.ai/artifact/NHtjhN5ihASTqJR2Yd4dAC.

- **The footer:** 36pt, pinned to the bottom of the sidebar, with no divider and no fill of its own.
  - "+ New List" at the left in quiet grey. Its tooltip reads "New List ⇧⌘N" and it shows a fill on hover.
  - A Settings icon at the right, with the tooltip "Settings ⌘,".
- **Long lists:** the last 20pt of the list fades above the footer through a transparency mask, which works on Glass. The fade goes once you've scrolled to the end.
- **Sizes and states:** it fits at the 180pt minimum sidebar width, and is covered with the sidebar when that's hidden.
- **The sync cloud stays in the header row (§26).**

Build it after §26. It can go to a worktree subagent if that doesn't collide.
- Mark §27 final in the spec, with the other directions removed (a short edit).
- Verify hover, the tooltips, the fade at the end of a scroll, 180pt, Glass and dark/light.
- Rules as before. Make a Release build and report back.
