# Task: design a better indication of When and Deadline dates

The user's words: "i also think that we should design some better indication of when and deadline dates."

**This is design only.** Nothing goes into `app/` until the user approves.

## Start from the references

- **The prototype:** `design/prototype-v2/`, with the views, Markdown notes, headings and the large title. Its canvases are https://claude.ai/artifact/EnWEe86TBSG8voqqwbf7uf and https://claude.ai/artifact/9dQ4fC46yZLLhf61gLiELx.
- **What dates do now:**
  - `design/INTERACTIONS-v2.md` (the chips, the relative date, the date popover, the Today and Upcoming rules);
  - `docs/SPEC.md` §1–4 (what When and Deadline mean, and how Today rolls them up);
  - `design/DIRECTIONS.md`, the original chip vocabulary: *Overdue · 2d*, *Due today*, a flag for a deadline, a calendar for When, and a past When carrying forward with no badge.
- **Recent feedback:** `docs/TASK-v2-feedback.md` item 16 is about long trailing labels overlapping, so whatever you design must hold up at narrow widths.
- **The look:** Rex is the source of truth (`design/REX-REFERENCE.md`), with Pane as the vocabulary. The user likes quiet, precise details and dislikes anything clunky. Don't drive Rex.

## Design

- **The problem:** today it's hard to tell at a glance what is planned (When) and what is due (Deadline), and how urgent it is. Work out what's weak in the current chips first, and say so.
- **Explore:**
  - how a row shows When versus Deadline, and both together;
  - urgency: overdue, today, soon, later;
  - relative versus absolute wording;
  - colour, icons and their placement;
  - how this differs between Today, Upcoming, a list and Completed;
  - the detail pane's When and Deadline rows;
  - the date popover;
  - perhaps a subtle row-level cue such as an edge or tint for an overdue deadline, if it stays quiet.
- **Constraints:** it must work in dark and light, at narrow widths, with long titles, and with the notes hint after the title.
- **Variants:** show two or three real variants side by side, and recommend one.

## Output

- **The prototype:** extend `design/prototype-v2/` (keep it clickable) and publish a new canvas with dark and light boards and the comparisons.
- **The spec:** add a new spec section marked proposed.
- **Commits:** per path with the co-author line, never push.
- **Report:** the link, the choices and your recommendation to the coordinator, then stop.

You may use subagents.
