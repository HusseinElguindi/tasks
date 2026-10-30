# The user's decisions on the v2 prototype

The user's words: "ok yea these are goood. date picker shape should be A, the calendar with the input and common chips below. Drag should be gap. Checked rows, move after 1.5s. Add is a little iffy for me, let's go with the detail view. The animations here are great and so are the details, like hover, aligned 3 dots are the top right with the collapse side bar, the side bar buttons after collapse, etc. We should make the real thing like this."

## Decisions

- **Date picker:** A. The calendar, with the typing input and the common chips below it.
- **Drag:** the rows part to open a gap. No insertion line.
- **Checked tasks:** move to Completed after 1.5 s.
- **Adding a task:** C. It opens straight in the detail pane.
- **What the user praised, which is now a requirement for the build:**
  - the animations;
  - the hover states;
  - the ••• aligned at the top right, in line with the collapse-sidebar control;
  - the sidebar buttons after the sidebar collapses;
  - the small details generally.

## For the Design agent

Finalize `design/INTERACTIONS-v2.md` with these choices:
- Remove the alternatives that weren't picked from the spec. Keep them in the prototype only if that's cheap.
- Spell out C (add opens in the detail pane) fully: the trigger from each context (a list, Today, an empty list), focus, what Return, Escape and Tab do, and what happens to an empty title.
- Make the spec precise enough to rebuild the prototype's animations and details 1:1. Give every timing, curve, offset and token, and cite the file and line in `design/prototype-v2/` it comes from. The Mac agent will treat the prototype as the reference implementation.
- Update the prototype's default variants to the chosen ones and republish the same canvas URL.

Commit, then report back.
