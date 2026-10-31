# Task: a continuously scrolling calendar in the date popover

The user's words: "I want calendar to be scrollable (i.e. up and down and all connected), instead of left-right buttons. can we explore this"

**This is design only.** Do it after §24 is finalized.

## Start from

- **The date popover as it is:** the picked shape A, with the typing field, quick picks and the month grid with left and right buttons.
- **Where it's specified:** `design/INTERACTIONS-v2.md` (the date popover section) and §24's popover changes. The prototype is `design/prototype-v2/`.

## Explore

- **The core:** one continuous column of weeks that scrolls vertically, with months flowing into each other ("all connected"), rather than paging month by month.
- **Month labels:** a sticky month and year header that updates as you scroll; month names inline at the first week; or a faint month boundary, such as alternating tints or a gap. Show two or three variants.
- **Viewport:** how many weeks are visible, the initial scroll position (centred on the selected date or today), and where today sits.
- **Snapping:** whether scrolling snaps to weeks or rows.
- **Trackpad momentum:** how it feels with a trackpad.
- **Getting back:** a "today" affordance when you've scrolled far away.
- **The keyboard:** arrows move by day and week, Page Up and Page Down move by month, and selection scrolls into view.
- **Typed dates:** typing a date in the field scrolls the grid to it, with an animation.
- **Other cues:** how the deadline and When markers (the "other date" dot) and the §24 cues appear in a scrolling grid.
- **Range:** how far back and forward it goes, and how cheaply it renders (a virtualized list in AppKit or SwiftUI; say how).

Where there's a real choice, show variants side by side. Make it clickable on the same dates canvas, or a new one if that's cleaner. Add a spec section marked proposed, commit per path, and report back with a recommendation.
