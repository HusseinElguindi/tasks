# Markdown notes prototype (Claude Design)

Canvas: https://claude.ai/artifact/CmypwyraQx28AYcHSfb5c5 (private until shared from its Share menu).

A copy of `design/prototype-v2/` with the detail pane's notes replaced by a Markdown editor, as the user picked it
(live marks at the caret, square checklist boxes, the notes hint after the row's title, no link shortcut). The spec is
`design/MARKDOWN.md`, which cites these files by line (`dc:N`, `md:N`), so keep the two in step.

- `Main.dc.html`: the whole prototype. Against v2: the notes template (one always-editable view of the source), the
  row's notes hint after the title, the Keys panel's Notes section, the seed notes, and the Markdown code (parser, DOM ↔ source mapping, rich-text paste, then the editor's
  methods in the component).
- `markdown.css`: every new value. `tasks-v2.css` is v2's, unchanged.
- The other `.dc.html` files are the canvas's boards: each mounts `Main` in a theme and, for some, a starting state
  (caret in the notes, a hovered link, a long note scrolled).
- `canvas.json`: the canvas layout and its notes.

The canvas runtime (`support.js`) comes from the Design artifact type and isn't stored here.
