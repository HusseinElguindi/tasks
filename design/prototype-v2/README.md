# Interactions v2 prototype (Claude Design)

Canvas: https://claude.ai/artifact/QetdV1H57SC6kLXtNzJRXM (private until shared from its Share menu).

This is the reference implementation for the Mac app's v2 interactions. `design/INTERACTIONS-v2.md` restates it with
every value and cites these files by line (`css:N`, `dc:N`), so keep the two in step: a change here moves the
citations.

- `Main.dc.html`: the whole prototype. Template first (lines 1–250), then its logic: date parsing, layout, selection,
  adding, editing, drag, undo, then the view model (`renderVals`).
- `tasks-v2.css`: every color, size, timing and curve the prototype uses.
- `Add.dc.html`, `Dates.dc.html`: the canvas's two side boards. Each mounts `Main` part-way through an add or a date pick.
- `canvas.json`: the canvas layout and its notes.

The user's picks (add opens in the detail pane, the calendar popover, drag opens a gap, checked rows move after 1.5 s)
are the only behavior here; the alternatives they didn't pick were removed. The canvas runtime (`support.js`) comes
from the Design artifact type and isn't stored here.
