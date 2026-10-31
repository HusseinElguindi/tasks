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

The user's picks (add opens in the detail pane, the calendar popover, drag opens a gap, checked rows move after 1.5 s),
their picks for the views (Upcoming and Undated under Today, Completed and Trash after the lists; Upcoming's
seven days, then months; a task with both dates shown once) and for §23 (the large title, bold headings, notes on a
list and on its headings, no headings outside their list) are the only behavior here; the alternatives they didn't
pick were removed. The canvas runtime (`support.js`) comes from the Design artifact type and isn't stored here.
