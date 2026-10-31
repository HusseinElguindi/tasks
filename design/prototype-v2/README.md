# Interactions v2 prototype (Claude Design)

Canvas: https://claude.ai/artifact/EnWEe86TBSG8voqqwbf7uf (private until shared from its Share menu). It holds the
prototype with Upcoming, Undated, Completed and Trash, a board for each of those views in dark and light, the three
choices they leave open side by side, and the v2 boards. The canvas from before the views is
https://claude.ai/artifact/QetdV1H57SC6kLXtNzJRXM.

This is the reference implementation for the Mac app's v2 interactions. `design/INTERACTIONS-v2.md` restates it with
every value and cites these files by line (`css:N`, `dc:N`), so keep the two in step: a change here moves the
citations.

- `Main.dc.html`: the whole prototype. Template first (lines 1–250), then its logic: date parsing, layout, selection,
  adding, editing, drag, undo, then the view model (`renderVals`). The four views (§22, proposed) are the block at
  the end of the component.
- `tasks-v2.css`: every color, size, timing and curve the prototype uses.
- `Add.dc.html`, `Dates.dc.html`: the v2 side boards. Each mounts `Main` part-way through an add or a date pick.
- `Upcoming-*`, `Undated-*`, `Completed-*`, `Trash-*`: each view in dark and light. `Choice-*`: the open choices, A
  beside B (props `sidebar`, `upcoming`, `both` on `Main`; the strip's switches flip them in the main board).
- `canvas.json`: the canvas layout and its notes.

The user's picks (add opens in the detail pane, the calendar popover, drag opens a gap, checked rows move after 1.5 s)
are the only v2 behavior here; the alternatives they didn't pick were removed. The views' choices stay as props until
the user picks. The canvas runtime (`support.js`) comes from the Design artifact type and isn't stored here.
