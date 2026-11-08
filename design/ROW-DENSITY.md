# Rows that mix lists and dates: making them readable

The user, 2026-11-08, with two screenshots of the Mac's Upcoming (wide, and beside the detail pane):
"another design task. there is quite a lot of information here. what can we do about that to make it more readable.
this applies elsewhere too, not just upcoming, though it matters most here since it merges both: lists and dates."

This is a design proposal. Nothing in `app/`, `ios/` or `widgets/` changed.

**Mock-ups (Claude Design):** https://claude.ai/artifact/GRcqfVRJASqquUDWhjztFz (private, not shared). Seven boards:
Upcoming as built, directions A to E, and C applied to Today, Completed, the iPhone and a widget. Each Upcoming board
shows the list pane wide (940, detail closed) and narrow (520, detail pane open at 400) with the screenshots' data
(today is Sat, Nov 7; long course names, When and Deadline, notes and checklists). Colours are the dark theme's,
sampled from the screenshots. The boards are HTML, not renders of the app, so truncation is approximate (they use an
ellipsis where the app fades).

---

## 1. What makes it hard to read today

From the screenshots, `design/INTERACTIONS-v2.md` §22 and §24, `app/NOTES-v2.md` (v2 feedback 16, §24's build
notes), `TaskRowView.swift` and `ios/Tasks/Views/TaskRow.swift`. I didn't build or run the app: the screenshots show
every point.

| # | What you see | Why |
|---|---|---|
| 1 | The full list name is the longest thing on most rows: "SE 463 — Software Project Management, Requirements, and Analysis" (66 characters), on every SE 463 row. Narrow, it's cut mid-word: "EARTH 121 —", "SE 463 — S" | §22 puts "the list's name" after the title in Upcoming, Completed and Trash. Feedback 16 gives it up to 72pt (`whereKeep`) and then fades it, so narrow it shows the part that tells courses apart least |
| 2 | Two date columns in a month group: the When after the title ("in 11d", "Nov 23"), the Deadline at the right ("11d left", "Nov 27") | §24 puts the When in the title's slot and the Deadline at the end. A task sits on its *earlier* date (§22), so the date that sorts the group is on the left for some rows and on the right for others: Nov 18 is "in 11d", "in 11d", then "11d left" |
| 3 | Two formats side by side: "9d left", "13d left" next to "Nov 27", "Dec 4"; "in 11d" next to "Nov 23" | §24 counts up to 14 days and shows a date beyond. A count under a future day counts from today ("9d left" under Friday Nov 13 is Monday the 16th; §24 says so), so the reader does a sum |
| 4 | Narrow, the title is cut first: "elguindi.com: check owner reply, else pla…" | The title keeps only 120pt before the When, the list name (up to 72pt) and the Deadline keep theirs (feedback 16). Correction to the brief's reading: the list name doesn't keep *all* its space, it keeps 72pt; but the When, a short name like "Inbox" and the Deadline together still squeeze the title |
| 5 | Nothing ties a row to its list's colour; the tiles are only in the sidebar | §22 chose text. Note that a tile alone wouldn't do: a tile's colour is a hash of the list's id over 7 hues (`ListModel.slot(for:)`), so Inbox and EARTH 121 are both red, ECE 358 and SE 463 both blue, and the letters repeat (E, E; S, S) |
| 6 | The notes glyph is on 16 of the 18 rows | Course tasks nearly all have notes, so the hint says little in this data. Not changed by any direction; noted for the user |

The brief's other readings are right: a row can carry the notes glyph or a checklist count, a When, the list name and a
Deadline; in a day group the When on that day is dropped (§22), but in "Later in November" and "December" every row
carries its own date.

## 2. How others do it

From memory of the apps, not checked on this Mac:

- **Things 3:** Upcoming lists the coming days one by one, then later dates by month. A to-do's project shows as
  small grey text, not a column, and in Today to-dos are grouped under their project or area. A deadline is a flag
  with "n days left". Projects have no colour, so there's nothing to show but the name.
- **Reminders:** Scheduled groups by day. A row's date (and list, in Today and Scheduled) sits on a second line under
  the title, so rows are two lines tall in the smart lists and one line in a plain list.
- **Our own widgets:** the medium Today widget already ends each row with the list's 16×13 tile and no name
  (`widgets/Shared/TodayViews.swift`, `MediumRows(trailing: .tile)`); the large one groups by list, like the app's Today.

The pattern: say each thing once, where the reader looks for it. The day is in the group, the list is either in a
label (grouped views) or a compact mark (mixed views), and a row carries only what differs from row to row.

## 3. Directions

| | The list on a row | Dates in Upcoming | Groups | Narrow (what goes first) | Spec |
|---|---|---|---|---|---|
| **A. Short names** | The name before its first " — " ("SE 463"), else the whole name; full name in the tooltip | As built | As built | As built, but the 72pt rule is rarely reached | §22 row extras |
| **B. List mark and calendar dates** | A mark in its own column: the 16×13 tile and the short name | Dates read as dates ("Nov 16"), never counts; "Due" on a group's own day; tone, ring and tooltip kept | As built | Title keeps 120; then the When; then (pane under ~420pt) the short name, leaving the tile. The tile and Deadline never go | §22 row extras; §24 "In Upcoming" wording |
| **C. Day by day** (recommended) | B's mark | B's rule | A month group lists its days too, each with a small label, so no row repeats its own day | As B | B's, plus §22's month groups |
| **D. By list within each group** | None on the row: list labels (tile and full name) inside each day and month | As built | Today's grouping inside each group | Rows are title and dates only | §22 groups and order |
| **E. Two-line rows** | Tile and full name on a quiet second line, with the When | As built | As built | Each line truncates on its own | §3 Metrics (a 42pt row), §22, §24's When slot, feedback 16 |

Trade-offs:

- **A** fixes the longest thing and nothing else. It's an hour of work, and on its own it already makes the narrow
  pane readable. The rule needs a decision (§5): derived from the name, or a field on the list.
- **B** adds what A lacks: colour, a column the eye can run down, and one date format. The mark is tile *and* code
  because the tile alone is ambiguous (§1, 5). Dates as dates suit Upcoming because its groups are a calendar; the
  count stays in the tooltip and the detail pane. It leaves two date columns in month groups.
- **C** finishes B by extending a rule the first week already has: a row never repeats the day it's filed under, and a
  deadline on that day reads "Due". With day labels inside months, every row in the screenshots' data shows at most
  one date, at the right, and the When almost never appears (only when it's later than the Deadline). Cost: a 24pt
  label per day with tasks (9 for 13 month rows here).
- **D** shows each list's full name once per group, but most labels sit over a single task (12 labels for 18 rows),
  a month is no longer in date order (Nov 18's "Deliverable 4" lands below Nov 27's OSAP check), and a drag to
  another day can jump the task under a different label. It reads best where a day holds many tasks from few lists.
- **E** is the most comfortable row by row, and it's what Reminders does, but it costs about a third of the rows on
  screen (42pt rows) and brings a second row height into drag, selection and motion. It doesn't fix the date formats.

### What to show on hover or selection only

In every direction the full list name is in the mark's tooltip, VoiceOver's label ("Deliverable 4, SE 463 — Software
Project Management, Requirements, and Analysis, due Nov 18") and the detail pane's header and List row. In B and C the
count ("9 days left") is in the Deadline's tooltip and the detail pane. I didn't move anything else to hover: the
notes hint and checklist count are small, and hiding them would make rows change width under the pointer.

## 4. Recommendation

**C, Day by day.** It's the only direction that addresses all five points, and it does it by extending rules the
user already picked rather than adding new kinds of thing: the first week's "the day isn't repeated" and "Due", the
sidebar's tiles, and Today's habit of saying the list once. The cost is vertical (day labels in months), and months
in Upcoming are usually sparse.

If C is too much at once, **A first** is a safe step (it's part of C) and fixes most of what the narrow screenshot shows.

### What it changes elsewhere

- **Today:** open tasks are already under list labels: no change. Its Completed group's rows get the mark in place of
  the full name. Counts ("1d left", "Due today") stay: in Today the frame *is* today.
- **Completed and Trash:** the mark, with the day after it in a month group ("CS 489 · Oct 30"). Their months stay
  months: a logbook doesn't need a label per day.
- **Undated and plain lists:** no change; they never show a list name. A list's rows keep §24's counts.
- **Search:** the app has none yet. Its rows would mix lists, so they'd take the mark.
- **iPhone:** the same rule set, with one difference: iPhone rows are already 48pt tall (`Metric.rowHeight`), so the
  mark goes on a quiet second line under the 17pt title (17/22 + 12/15 fits) and the title gets the whole first line.
  Upcoming gets the same day labels in months. The change is in `TaskRow.whereName` and the Upcoming grouping.
- **Widgets:** the medium Today widget's trailing tile becomes the mark (tile and short name), because the tile alone
  repeats colours. The large widget groups by list already. A future Upcoming widget would use C's rows.
- **The CLI:** its rows could print the short name too; not drawn.

### Spec changes if C is picked

- §22 "What each view shows", Upcoming: month groups list their days, each with an 11pt label ("Wednesday  Nov 18",
  24pt tall) that takes +, a double-click and a drop like a day group's label; within a day, the list's sidebar order,
  then the list's order (as now). Row extras: the mark (a 16×13 tile, 6pt, the short name in 12pt `ink-tertiary`, in a
  column as wide as the view's widest short name), not the name.
- §22 Completed and Trash: the mark, then " · Oct 22" in a month group.
- §24 "The wording", In Upcoming: both dates read as dates ("Nov 16", "Jan 3, 2027"); a deadline on its day's
  date reads "Due". Tones, the ring, tooltips and the detail pane's words are unchanged. Today and lists keep counts.
- Feedback 16's narrow order for mixed views: title keeps 120pt; then the When; then the short name (the tile stays);
  the tile and the Deadline never go; the mark is never cut mid-word.
- A new rule for the short name (see §5).

## 5. For the user to decide

1. **Which direction:** A, B, C (recommended), D or E, or A now and C after.
2. **Dates in Upcoming:** dates ("Nov 16") as in B and C, or keep §24's counts ("9d left") there too? §24 was the
   user's pick on 2026-10-31; this changes it in Upcoming only.
3. **The short name:** derived from the name (the part before " — ", " – ", " - " or ": ", when that part is 12
   characters or fewer, else the whole name; no model change), or a "Short name" field on a list (works for any name,
   but a new synced field, SPEC §2, and a field in the list's UI)?
4. **Tile colours:** a list's colour is a hash of its id, so with 8 lists colours repeat. Pick the colour per list (a
   new field), or leave it, since the mark always carries the code too?
5. **iPhone:** the mark on a second line under the title (fits the 48pt row), or at the right like the Mac?
6. **The notes glyph** on nearly every course row: leave it, or show it only on hover in mixed views?
