# Interactions v2 prototype (Claude Design)

Canvas: https://claude.ai/artifact/EnWEe86TBSG8voqqwbf7uf (private until shared from its Share menu). It holds the
prototype with Upcoming, Undated, Completed and Trash, a board for each of those views in dark and light, and the v2
boards. The canvas from before the views is
https://claude.ai/artifact/QetdV1H57SC6kLXtNzJRXM.

This is the reference implementation for the Mac app's v2 interactions. `design/INTERACTIONS-v2.md` restates it with
every value and cites these files by line (`css:N`, `dc:N`), so keep the two in step: a change here moves the
citations.

- `Main.dc.html`: the whole prototype. Template first (lines 1–270), then its logic: date parsing, layout, selection,
  adding, editing, drag, undo, then the view model (`renderVals`). The four views (§22) are the block at the end of
  the component.
- `tasks-v2.css`: every color, size, timing and curve the prototype uses.
- `markdown.css`: the Markdown notes (`design/MARKDOWN.md`). The editor came from `design/prototype-markdown/`, merged
  onto the views as the app has it; `markdown.css` is that copy's, unchanged.
- `Add.dc.html`, `Dates.dc.html`: the v2 side boards. Each mounts `Main` part-way through an add or a date pick.
- `Upcoming-*`, `Undated-*`, `Completed-*`, `Trash-*`: each view in dark and light.
- `canvas.json`: the canvas layout and its notes.

**Headings, text in a list and a clearer title (§23, `docs/TASK-design-sections.md`), final.** Its canvas is
https://claude.ai/artifact/9dQ4fC46yZLLhf61gLiELx (private until shared), laid out by `canvas-sections.json`. The
example list is PHYS 122: a course with notes, three headings with notes of their own, and a task before the first.
Its boards: `Sections` (the prototype on that list), `Title-Large` and `Title-Scrolled` (the large title, and the band's
title once it has scrolled under), `Heading-*` (adding, collapsed, mid-drag, from `demo="newhead|collapse|dragsec"`)
and the light ones. The code is the block at the end of the component, after the four views'.

**Proposed (§24, `docs/TASK-design-dates.md`): When and Deadline at a glance.** Its canvas is
https://claude.ai/artifact/2wUF9Dz2JEt8Xp2pBDahy2 (private until shared), laid out by `canvas-dates.json`. The prototype carries it
behind the strip's Dates (Pills, Quiet When, Text), Wording (Absolute, Relative under two weeks, Compact with "2d ago"
or "−2d") and Overdue cue (Off, Checkbox, Edge) switches; their defaults are the recommendations, and a board sets them
with `v-dates`, `v-words` and `v-cue`. Its boards: `When-Deadline` (the prototype on the School list), `Chips-*` (each
variant in Today and in a list, and light), `Cue-*`, `Upcoming-Dates`, `Narrow-*` (long names at narrow widths, from
`demo="narrow"`), `Detail-Dates` and `Popover-*` (from `demo="pickwhen|pickdl"`); these hold the wording at Absolute.
Section 3's are `Wording-Compare` (every distance in each wording, a static board generated from the prototype's own
functions), `Words-*`, and `Tip-*` (a date's tooltip held open, from `demo="tipwhen|tipdl"`).
The code is the block at the very end of the component; the CSS is the block at the end of `tasks-v2.css`. Until the
user picks, §11 describes the app.

The user's picks (add opens in the detail pane, the calendar popover, drag opens a gap, checked rows move after 1.5 s),
their picks for the views (Upcoming and Undated under Today, Completed and Trash after the lists; Upcoming's
seven days, then months; a task with both dates shown once) and for §23 (the large title, bold headings, notes on a
list and on its headings, no headings outside their list) are the only behavior here; the alternatives they didn't
pick were removed. The canvas runtime (`support.js`) comes from the Design artifact type and isn't stored here.
