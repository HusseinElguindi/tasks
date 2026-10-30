# Interactions v2 prototype (Claude Design)

Canvas: https://claude.ai/artifact/QetdV1H57SC6kLXtNzJRXM (private until shared from its Share menu).

These are the canvas's own files, kept here so the values the Mac app copies can be read in one place:

- `Main.dc.html`: the whole prototype. Template first, then its logic (dates parser, layout, selection, drag, undo).
- `tasks-v2.css`: every color, size, timing and curve the prototype uses. `design/INTERACTIONS-v2.md` restates them.
- `QuickAdd{A,B,C}.dc.html`, `Dates{A,B}.dc.html`: the side-by-side variant boards. Each mounts `Main` with one setting.
- `canvas.json`: the canvas layout and its notes.

The canvas runtime (`support.js`) comes from the Design artifact type and isn't stored here.
