# Renaming a list's large title on the Mac

The user, 2026-11-07, with a screenshot of the Mac renaming "CS 489 — Introduction to Natural Language Processing":
"this feels a bit wierd on the mac app. what else can we do? claude design."

This is a design proposal. Nothing in `app/` changed.

**Mock-ups (Claude Design):** https://claude.ai/artifact/W9pNv3LyUiArhNUWsZW1bA (private, not shared). There are five
boards: today as built, then directions A to D. Each board shows the list pane at rest, when editing starts (whole name
selected), and while typing a longer name. They use the dark theme's tokens (Ember accent, `fill-control`, `ink`), a
520pt pane and the tile as the app draws it.

---

## 1. What's weird today, and why

These come from the code (`TaskListView.updateTitleField`, `ListTitleView.configure`) and the screenshot. I didn't
build or measure the app: the screenshot already shows each one.

| # | What you see | Cause |
|---|---|---|
| 1 | The field is narrower than the name it replaces. The name is cut mid-word ("Natural Langu") with no ellipsis | The field is capped at 360pt: `min(360, …)` in `updateTitleField`, from the prototype's `flex: 0 1 360px` (`css:449`). At rest the label uses the whole line (about 456pt in a 520pt pane) and ends in an ellipsis |
| 2 | The text jumps about 4pt left when editing starts, and its first letter touches the ring | The field starts 6pt left of the name (`x = titleX - 6`, the prototype's `margin-left: -6px`). The prototype pads it back by 6 (`padding: 0 6px`), but the NSTextField pads only 2 |
| 3 | The ring crowds the tile | The tile and the name are 9pt apart. The field's −6 leaves 3pt between the tile and the ring |
| 4 | Blue selection under an orange ring | The list-title field never sets `selectedTextAttributes`, so the selection is the system's colour. The sidebar rename, the detail title and the notes all use the theme's `text-selection` (Ember at 42%) |
| 5 | The text gets wider when editing starts, and narrower again on commit | The label has −0.2 tracking (`ListTitleView.kern`). The field's text has none, so the name is about 10pt wider in this example |
| 6 | Typing at the end scrolls the start out of view | It's a one-line scrolling field (`InlineField` with `cell.isScrollable`), so a long name is never all visible while you edit it |
| 7 | On commit everything jumps back | The width, the x position and the tracking all change back at once |

Items 1, 2 and 3 are in the spec too (`css:449`, §23 "Renaming"). Items 2 and 4 to 6 are differences between the app
and the prototype.

### The other renames

- **A task's title in the detail pane doesn't have this problem.** `TitleField` uses the same `InlineField`, but in its
  wrapping mode (`makeWrapping()`): no ring, no fill, no width cap, Ember selection, wraps and grows (§7 "The detail
  title"). It's the model for direction B.
- **A task renamed in its row** ("Rename in the list") and **a heading** use the one-line `InlineField` in the row's
  title slot, with the row's ring. A long title scrolls there too, but that's the usual Mac idiom for a row (Finder's
  list view, Xcode's navigator), and rows are a fixed 30pt, so I'd keep it. They share bug 4: neither sets the theme's
  selection colour, so both select in system blue.
- **The sidebar rename** sets the selection colour and fills the row to its end. It's fine.

---

## 2. How good Mac apps do it

From memory of the apps, not checked on this Mac:

- **Things 3:** a project's title is large text at the top that you click into and edit as plain text. No box, no
  ring. Long titles wrap, at rest and while editing.
- **Reminders:** the list name in the header is edited in place as text, with no visible field. Colour and icon are
  in a separate list info sheet.
- **Notes:** a note's title is its first line, so it's just text. Folder renames in the sidebar use a field with a
  ring in the row.
- **Finder:** in list view, a one-line field with a ring in the row. In icon view, the field wraps under the icon and
  grows with the name.
- **Xcode:** renames in the navigator use a one-line field in the row.

The pattern: **a row** renames as a boxed field, because it sits in a list of rows; **a page title** is edited as
plain text in place, because it's the content.

---

## 3. Directions

| | At rest | Editing starts | Typing a long name | Tile | Spec |
|---|---|---|---|---|---|
| **A. Fix the box** | One line, ellipsis (as now) | Box as wide as the line (−5 to +6 around the text), 6pt padding so the text doesn't move, tracking kept, Ember selection | Still one line, so it scrolls | Ring 4pt from the tile | Keeps §23 Renaming (fill, ring, radius 6) and §7's same-pixels rule. Changes `css:449` (no 360 cap) |
| **B. Plain text that wraps** (recommended) | Wraps onto as many lines as it needs. The tile sits on the first line | The same text, selected. No box, no ring: the caret and the selection are the cue | A new line opens and the notes move down, as they will after the commit | Unchanged | Changes `css:447` (`nowrap` + ellipsis → wraps) and §23 Renaming (fill and ring → none, the detail title's rule from §7). Keeps §7's same-pixels rule, with nothing left to match but the text |
| **C. A box that grows** | One line, ellipsis (as now) | The box fills the line and wraps the whole name, so a long name adds a line and pushes the notes down | Grows a line at a time | Unchanged (it stays on the first line) | Keeps §23 Renaming and `css:447`. Changes `css:449` (fills the line, wraps) |
| **D. Rename popover** | One line, ellipsis (as now) | The title stays a label. A popover under it (like the date popover) holds a wrapping name field | In the popover. The header changes on Return | Unchanged | Changes §7 and §23: the large title no longer renames in place. The sidebar and rows still do |

Trade-offs:

- **A** is the smallest change: width, padding, tracking and selection, all in `updateTitleField`. It fixes 1–5 and
  7, but a name longer than the line still scrolls (6).
- **B** fixes all seven, because there's nothing to swap: rest and editing are the same text in the same place. It's
  how Things does it and how our detail title already works, and it reuses `TitleField`'s wrapping `InlineField`. The
  costs: a long name takes two or three lines at the top of the list, and the editing state is quieter than a box.
- **C** shows the whole name while editing but trades the horizontal jump for a vertical one: a long name adds a line
  when editing starts and takes it away on commit.
- **D** avoids any swap in the header but adds a surface for something that's in place everywhere else, and Tab from
  the name to the notes no longer reads naturally. It only earns its place if the list grows more settings (a colour,
  an icon).

## 4. Recommendation

**B.** The large title is page content, so it should behave like the detail title: wrap, and edit in place as text.
That removes the swap the user is reacting to instead of tuning it.

Also, whichever direction is picked: set the theme's selection colour on the row and heading rename fields (bug 4),
which needs no design decision.

If B is picked, the build is roughly:
- `ListTitleView`: the title wraps (CATextLayer → a wrapping text layout); the band's scrolled title stays one line.
- `updateTitleField`: the field becomes the wrapping `InlineField` (as `TitleField`), with no fill or ring, placed
  exactly on the label, with the label's tracking.
- The list re-measures the header while the name is typed, as the detail pane does with `onLiveText`.
- Spec: `css:447` and `css:449`, §23 "Renaming", and §16's text-field row.

## 5. For the user to decide

1. Which direction: A, B, C or D (or B with a limit on lines at rest, say two lines and then an ellipsis).
2. With B: should Today and the views' titles wrap too? They're short, so it only matters for consistency.
3. Fix the blue selection in row and heading renames now, separately from this? It's a one-line change per field.
