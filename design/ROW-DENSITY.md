# Rows that mix lists and dates: making them readable

The user, 2026-11-08, with two screenshots of the Mac's Upcoming (wide, and beside the detail pane):
"another design task. there is quite a lot of information here. what can we do about that to make it more readable.
this applies elsewhere too, not just upcoming, though it matters most here since it merges both: lists and dates."

The user's pick, later that day: "Ok for the row readability, i like the C approach. [...] Also, how will we fix on
iphone?" (with two iPhone screenshots). C is the Mac's direction; §6 is the iPhone.

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
- **iPhone:** see §6. The first idea here (the mark on a second line inside the 48pt row) fixes Upcoming only; the
  iPhone's plain lists are cut too, so §6 recommends a title line and a detail line on every view.
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
5. **iPhone:** see §6.5.
6. **The notes glyph** on nearly every course row: leave it, or show it only on hover in mixed views?


---

## 6. The iPhone

The user, 2026-11-08: "how will we fix on iphone?", with two screenshots: Upcoming, and the CS 489 list (today is Sun,
Nov 8). Mock-ups: the iPhone boards at the end of the same canvas (https://claude.ai/artifact/GRcqfVRJASqquUDWhjztFz):
the two screenshots as built, then options 1 to 4, each as Upcoming, the CS 489 list and Today at iPhone 15 width (393pt),
dark theme, on the screenshots' data. Where a screenshot cuts a title off, its ending in the mock-ups is my guess
("Assignment 3 — Prompting and evaluation"). Today's rows other than CS 489's come from the Mac boards' data.

### 6.1 What the screenshots show

The coordinator's reading is right: the iPhone is worse than the Mac, and not only in mixed views. One 48pt line
(`Metric.rowHeight`) holds the title, the checklist count or notes glyph, the When, the list name in mixed views
(`TaskRow.whereName`, up to 94pt, the Mac's 72 × 1.3) and the deadline capsule. Everything after the title is kept
whole, so the title keeps only its 156pt (`Metric.titleKeep`) and the rest is cut:

| View | What's cut | By what |
|---|---|---|
| Upcoming | "Lecture 13: Mechanistic", "Discussion 3 — initia", "Renew iOS signing on t" | the count or notes glyph, the list name (itself cut: "CS 489 — Intro", "EARTH 1") and the deadline |
| CS 489 list | "Assignment 3 — Pro", "Lecture 11: Syntax and cont", "Lecture 12: Probing syntacti" | the count, the When ("Today", "in 5d") and the deadline |

Three more things:

- **Said twice in lists:** a blue ring already means "planned for today or earlier" (`RingCue.planned`, off in Today),
  and the row also says "Today" (Assignment 3, Lectures 11 and 12).
- **Mixed formats in Upcoming:** "5d left" next to "Dec 4" and "Nov 27" (§1, 3). C's rule (dates as dates) fixes it on
  the phone too.
- **The + button** covers the last visible row's deadline (Discussion 3 — replies). Not new, and not fixed by any
  option; noted.

### 6.2 How others do it on the iPhone

From memory, not checked on a phone:

- **Things 3:** the title is one line. In Today and Upcoming the project's name is small grey text under it. Notes and
  a checklist show as small glyphs; the deadline is a flag with "n days left". Rows with a second line are taller.
- **Reminders:** the title wraps, never cut. Under it, a grey line with the date (red when overdue), and the list's
  name in Today and Scheduled; then the notes' first line. Rows are as tall as they need.

Both put the details on a line under the title. Neither keeps title, list, date and deadline on one phone line.

### 6.3 Options

All four use C's rules from §4: the day labels inside months, dates as dates in Upcoming, "Due" on a group's own day,
the mark (tile and short name) in mixed views, counts in lists and Today.

| | Layout | Row height | Upcoming | CS 489 list | Today |
|---|---|---|---|---|---|
| **1. Mark under the title** (my first idea) | The mark on a quiet second line in mixed views; the rest stays on line 1 | 48 | Better: name whole, in colour | Unchanged: still cut | Unchanged |
| **2. One line, condensed** | No notes glyph; the count only once one item is checked; no "Today" where the blue ring says it; the mark for the name | 48 | Still cut when a row has a mark and a deadline (title ~150pt) | Better: most lectures fit; assignments still cut | Better |
| **3. Title line, detail line** (recommended) | Line 1: the title alone. Line 2, quiet: the mark, the When, the count, the notes glyph, and the deadline capsule at its right edge. One line when there's nothing for line 2 | 56 with details, 48 without | Titles get ~315pt, twice today's 156 | Same | Same |
| **4. Wrapped titles** | As 3, but the title wraps to up to two lines | 48, 56 or 78 | Whole titles | Whole titles | Whole titles |

- **1** keeps the height and fixes Upcoming's list name, but leaves every plain list and Today as they are, and 22 + 15pt
  of text in 48pt leaves 5pt above and below.
- **2** keeps the height and gains 40 to 90pt a row, which isn't enough: "Discussion 3 — initial post" with its mark
  and deadline is still cut. It also drops things the user may use ("0/12" says not started; the notes hint).
- **3** fixes every view and drops nothing. Deadlines line up in one column at the right of line 2. It costs 8pt on
  rows with details: a screen holds about one row in seven fewer (12 instead of 14, with no labels).
- **4** shows every title whole, but rows come in three heights, the details don't line up from row to row, and fewer
  rows fit. It's Reminders' answer, and Reminders is a list you read, not one you drag much.

### 6.4 Recommendation: 3, a title line and a detail line

The rule, for the iPhone (not the Mac, and not the widgets):

- **Line 1:** the title, 17/22, the whole width from the checkbox to the row's end (~315pt on a 393pt phone). Cut off,
  it fades as now.
- **Line 2:** 13pt `ink-tertiary`, 20pt tall, 2pt under line 1. In order: the mark (in views that mix lists), the When
  (as each view words it, and hidden where its group says it: Today, an Upcoming day), the checklist count, the notes
  glyph; then, at its right edge, the deadline capsule at 20pt. When it runs out of room, the mark's short name fades
  first, then the When goes; the tile, the count and the deadline never go.
- **Height:** 56pt when line 2 has anything, else one 48pt line (the notes glyph alone stays after the title on
  line 1). In Upcoming every row has a mark, so every row is 56. Rows keep their minimum height and grow with
  Dynamic Type, as now.
- **iPad:** the same row in a narrow column; I'd keep the Mac's one-line row when the list column is wider than about
  600pt (a decision below).

What it means for:

- **Row height:** two heights, 48 and 56. Upcoming, Today and most course lists are mostly 56: about one row in seven
  fewer per screen.
- **Drag:** rows already size themselves (Dynamic Type), and the drag gap already takes the lifted row's own height
  (`TaskCollection+Drag.swift`, `State.height` from the row's frame), so mixed heights need no new drag model. One new
  case: a row changes height when it gains or loses line 2 (a When set or cleared, a deadline added). It should resize
  on the layout curve like a row being typed into (`CollectionEditing`), and while a drag holds updates, it waits like
  any other resize (T27). Swipe actions and select mode's joined fills follow the row's height.
- **Widgets:** no change from this. Widget rows stay one line (23pt medium, 24pt large): they show no count or notes
  glyph, and a widget can't scroll, so density matters more there. T2's change stands: the medium Today widget's tile
  gets the short name.
- **The Mac:** unchanged; C's one-line row (§4) has the room.

Spec changes if 3 is picked: §3 Metrics (the iPhone's 56pt two-line row), §24 (on the iPhone the When and the deadline
are on line 2, the deadline at its right), and feedback 16's narrow order gets an iPhone line ("the title keeps its line;
on line 2 the short name goes first, then the When").

### 6.5 For the user to decide

1. **Which option:** 1, 2, 3 (recommended) or 4?
2. **One line when there's nothing to show,** or always two lines so every row is the same height? I'd keep one line:
   in a list, a bare task shouldn't carry an empty line.
3. **"Today" in lists:** hide the When when it's today or earlier, since the blue ring says it (as Today hides it)? I'd
   do it on the iPhone; the Mac can follow if the user likes it.
4. **Checklist count and notes glyph:** keep both on line 2 (they cost nothing there), or show the count only once an
   item is checked?
5. **iPad:** the one-line row when the list column is wide (over ~600pt), or the two-line row everywhere?
