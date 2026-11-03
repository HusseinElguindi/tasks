# iOS parity batch 2: five designs for touch

Status: **proposed, 2026-11-03**, for the user to pick from. Brief: `docs/TASK-design-ios-batch2.md`. Each design is the
Mac's rule adapted for touch. Where touch forces a change, the reason is given with it. Sources:
`design/INTERACTIONS-v2.md` (cited as IX §n), `design/COLOR.md` §4, `docs/IOS-MAC-PARITY.md` (gaps 2, 4, 6, 7 and 10),
the Mac code in `app/Tasks/` and the iOS code in `ios/Tasks/`.

**What this builds on.** Three iOS briefs are being built now, and nothing here changes them. From the reorder and
selection brief, it uses the selected fill and its 300 ms fade, and the long-press drag. From the headings brief, it
uses the heading chevron and the heading menu. From parity batch 1, it uses the notices for moves and dates, the
lifetimes (5 s with Undo, 1.8 s without), the 28-character cut, the immediate strike, the 1.5 s settle, the Trash
verbs and the locale's week start. This batch should start after those three.

**Phone metrics** are the Mac's × 1.3 (`Theme/Metrics.swift`): 48pt rows, row radius 12, 22pt checkbox, 17pt titles.

**Mock-up** (scratchpad, not published): multi-select A and B, the date sheet while typing, a deleted list opened, and
Today all done, in dark and light. Its path is in the report.

---

## 0. Shared: a "…" menu on every list screen

Today, only a list has the bar's "…" (`ListScreen.swift:216–240`). Multi-select and the undo item need it in the views as
well. Top to bottom:

1. **Undo <step>** (↶) and **Redo <step>** (↷), each only when there's a step to undo or redo (§1).
2. **Select** (`checkmark.circle`) (§3).
3. The list's own items, as their briefs word them: New Heading (headings brief), Rename, Add Notes or Edit Notes
   (batch 1), Show Completed or Hide Completed.
4. **Delete List** (destructive).

Today, Upcoming, Undated, Completed and Trash get sections 1 and 2. A deleted list's screen has no "…" (§4).

---

## 1. Undo and redo on touch (gap 2)

**What it does.** Every change is a named step on the window's undo stack. Shake, the three-finger gestures, ⌘Z and ⇧⌘Z
on a hardware keyboard, the notice's Undo, and an item in the "…" menu all reach it. Each undo or redo takes you back
to the screen where the change was made, shows the rows it touched, and confirms with a notice, as the Mac does (IX §9;
`WindowActions.swift:59–88`).

### Is there a visible affordance, and where?

- **A · An item in the "…" menu (recommended).** "Undo Delete Task" and "Redo Move Task" go at the top of every list
  screen's "…" (§0). Each one appears only when there's a step. The notice lasts 5 s, and after that the gestures
  can't be seen; plenty of people never learn shake. The Mac has the Edit menu, which is always there, and the "…" is
  the phone's nearest equivalent. It adds no chrome.
  - Touch forces one change. The Mac's rule is that items are disabled, not hidden, and the Edit menu is global. Here
    the "…" belongs to each screen, so a greyed "Undo" at the top of every one would be noise.
  - Home has no "…", so shake and the notice cover it there.
- **B · Nothing more.** The notice and the gestures only. It's the cheapest, but after 5 s only people who know shake
  can undo.
- **C · A ↶ button in the bar while there's a step.** Rejected. The control would come and go on every screen, the
  bar's right side already holds "…", and Rex has nothing like it.

### Rules

- **One stack per window**, as on the Mac. `AppModel.undo` (`AppModel.swift:67`, its own `UndoManager()`) becomes the
  scene's: `RootView` reads `@Environment(\.undoManager)` and hands it to the model on appear, before any change can be
  made. Shake, the three-finger gestures and UIKit's ⌘Z all ask the responder chain for that manager. The
  `store.*(…, undoManager: undo)` calls don't change.
- **Named steps.** The Store already names each step (`Store+Actions.swift`: Delete Task, Move Task, Set When, Rename
  Task, Edit Notes, Complete, Put Back, Restore List…). The steps made from several tasks at once are named in §3.
- **The restore step.** Port the Mac's `undoable` (`WindowActions.swift:59–88`) into `AppModel`. It wraps each action's
  store call in one group with a step that records the screen (`path.last`, or `selection` on iPad) and the ids it
  touched. After an undo or a redo, in this order:
  1. Edits end, as the Mac's `endEdits` does: the new-task row is written (if it has a title) or dropped, select mode
     ends, and a heading rename commits.
  2. A task's sheet stays open if the step was that task's, and shows the change. Any other sheet closes (the date
     sheet, Settings, another task's details).
  3. The app goes to the screen where the change was made, at once, with no push animation. If that list is gone, it
     goes to Today (Mac `restore`, `WindowActions.swift:89`).
  4. The first row that was touched scrolls into view, ending 10pt under the bar or 16pt above the floating
    controls (the Mac's 8 and 12 × 1.3). The rows that were touched show `fill-row-selected` for 0.6 s, then fade out
    over 300 ms ease-out. That's the tapped-row fade from the reorder brief §2. A row that's gone, such as an undone
    add, shows nothing.
  5. A notice reads "Undo Delete Task" or "Redo Move Task", with no button, for 1.8 s (`WindowActions.swift:82`). It
     replaces any notice already showing.
- **Shake** brings up the system alert: "Undo Delete Task", Cancel, Undo, and Redo when there's a step to redo. It
  takes its words from the action names. **A three-finger swipe** left undoes and right redoes, with the system's small
  pill at the top. **A three-finger tap** opens the system's undo bar. None of these needs any drawing.
- **⌘Z and ⇧⌘Z.** If the system's commands don't reach the scene's manager when nothing has the caret, add two key
  commands that call the same undo and redo.
- **In a text field** (the sheet's title or notes, the new-task row, a name alert), the field's own typing undo wins,
  as on the Mac (IX §9). Check this on the device: once an edit ends, the Store's steps must still be on the stack under
  the typing steps.
- **The notice's Undo** is the stack's undo (the Mac: "The notice's Undo is the same as ⌘Z"), so it confirms the same
  way.
- **Notices over a sheet.** A task's sheet covers the root's notice. Give the sheet the same `NoticeView` at its foot,
  16 in from its sides and 12 above the bottom safe area, so undoing or checking the box there confirms where you can
  see it.

**Reuses:** the Store's undo registration and names; the Mac's `undoable`, `registerRestore` and `restore`, ported;
batch 1's notice lifetimes; the reorder brief's selected fill and fade. **No core change.**

**Size: M.** The wiring is S, the restore step is S, and the "…" item and the sheet's notice are S together.

---

## 2. Typed dates (gap 4)

**What it does.** The date sheet gets the Mac's field (IX §11). Typing moves the highlighted day through
`DatePhrase.match`, and Return sets it and closes the sheet.

### Where it sits

- **A · At the top, under the title row (recommended).** This is the Mac's order: field, quick picks, month,
  calendar, footer. While you type, the footer sits on the keyboard, so what Return will set appears right above the
  key.
- **B · At the bottom, merged with the footer.** It's nearer the thumb, but it breaks the Mac's order, and the field
  would jump when the keyboard comes up.

### Layout (A)

Top to bottom, inside the sheet's 20pt sides:

| Part | Rule |
|---|---|
| Title row | As now: "When" or "Deadline" and Done. For several tasks (§3), "When" is followed by " · 3 tasks" in `ink-tertiary`. The sheet hides the rows it acts on, which the Mac's popover doesn't |
| **Field** | 44 tall (the Mac's 28 × 1.3 is 36, and 44 is the phone's touch minimum), radius 12, `fill-control`. Padding is 14 on the left and 12 on the right. A 15pt medium `ink-tertiary` icon (`calendar` for When, `flag` for Deadline) sits 10 before the text. The text is 17pt `ink` |
| Placeholder | "Try fri, 3d, nov 9" or "Try fri, nov 9, 2w" in `ink-tertiary`. That's the Mac's text without "When:", since the title says it |
| Quick picks | 10 below the field. Keep the phone's five (Today, Tomorrow, This Weekend, Next Week, Clear). The Mac dropped Next Week only to fit its 240pt popover (`DatePopover.swift:132`), and on glass, tapping is faster than typing |
| Month row, weekdays, calendar | As now. The week starts on the locale's first day (batch 1, item 12) |
| Footer | As now (`DatePickerSheet.swift:183`), with the Mac's wording below |

### Rules

- **Focus.** The field doesn't take the caret when the sheet opens, though the Mac's does. Touch forces this: the
  keyboard would cover the calendar and the picks, and those are the faster way on a phone. Tap the field to type.
  With a hardware keyboard connected (`GCKeyboard.coalesced != nil`), the field takes the caret on open, as on the Mac.
- **The keyboard** is the default one, because "fri", "tom", "nov 9" and "next week" start with letters, and digits
  are one key away. Autocorrection, autocapitalization, spell checking, smart punctuation and inline predictions are
  all off, so "11/9" and "+5" stay as typed. The return key is `.done`. `.numbersAndPunctuation` would open on the
  digits, which most phrases don't start with.
- **While typing,** the sheet moves to its large detent and the footer rests on the keyboard. The calendar gets the
  height between the weekday row and the footer, at least two weeks, and keeps the highlighted week in view.
  Scrolling the calendar dismisses the keyboard interactively, and the sheet stays where it is.
- **The highlighted day** is filled with `accent` and set in `on-accent` semibold.
  - With text, it's `DatePhrase.match(text, today:, numericOrder: .numericOrder(for: .current))`, on every keystroke,
    as the Mac does (`DatePopover.swift:91–106`).
  - With the field empty, it's the current date, as now: nothing is highlighted when there's no date. The Mac
    highlights today here, but nothing on the phone has the keys until you tap the field, so a highlight would
    promise a Return that isn't there.
  - When the highlight moves off the current date, the current date gets the Mac's inset `accent` ring, 2pt on the
    38pt circle.
- **The calendar follows.** When the highlighted week isn't fully in view, the calendar scrolls the least that shows
  it, on `Motion.natural`. Under Reduce Motion it jumps.
- **Quick picks.** With text, the pick whose date the text means is tinted `accent-tint` / `accent-text` (the Mac's
  rule). With none, the pick that equals the task's date is tinted, as now.
- **The footer**, with text, says what Return will set: "Fri, Nov 6 · in 3 days". A deadline reads "Due Fri, Nov 6 · in
  3 days", and a past one ends "· 2 days overdue" in `danger`, as now.
  - A When after the deadline, or a deadline before the When, puts "· after the deadline" or "· before the When" in
    `attention` where the relative words were (the Mac's `hint`, `DatePopover.swift:171`). This also fills parity's
    missing footer note, so it applies with the field empty too.
  - When the line doesn't fit, it drops parts in the Mac's order: the full line, then without the weekday, then the
    date alone (`DatePopover.swift:151–163`).
  - There's no ↩ glyph: the phone's key says "Done", and the footer sits right above it.
- **No match.** No day is highlighted and no pick is tinted. The footer reads "No date matches “xyz”" in `ink-tertiary`,
  and the field's text stays `ink`. Return sets nothing and the keyboard stays, with a `.warning` haptic. The phone's
  return key can't grey out as the text changes, so the haptic says the press didn't take, and the footer already says
  why.
- **Return** sets the highlighted day, then the sheet closes after the existing 0.22 s pause, as a tapped day does.
  Tapping a day or a pick while typing sets it and closes the sheet, as now.
- **Clearing** is the Clear pick only. ⌫ in the empty field does nothing, though on the Mac it clears the date. Touch
  forces this: holding delete to erase a phrase would run on into clearing the date.
- **Hardware keys** (the Mac's, `DatePopover.swift:256`): ← → move a day, ↑ ↓ a week, Page Up and Page Down a month.
  Return sets, and Esc closes.
- **Several tasks** (§3). The date goes on every one. The current-date ring, Clear and the tinted current pick appear
  only when they all share the date (IX §21, `dc:1516`).
- **VoiceOver.** The field's label is "Date" and its hint is "Type a day, like Friday, 3 days or November 9". The
  footer is announced 0.5 s after typing stops.

**Reuses:** `DatePhrase.match` and `numericOrder(for:)`; `DateLabel.long`, `relative`, `deadlineWords` and
`monthDayYear`; the Mac's footer lines and its `hint` rule, ported from `DatePickModel`. **No core change.**

**Size: M.** The field and its rules are S. The detent and the calendar's height while typing are the rest.

---

## 3. Multi-select (gap 6)

**What it does.** Select in the "…" menu, or a two-finger swipe over the rows, puts the screen in select mode. A tap
selects a row, a bar at the bottom acts on everything selected, and Done leaves. The rules for a mixed selection are
the Mac's (IX §5, §8–§10, §22, §28).

### The selected look

- **A · The Mac's (recommended).** A selected row fills with `fill-row-selected` at the row radius, and selected rows
  next to each other join into one block. There are no circles. The checkboxes keep their rings and stop taking taps.
- **B · iOS's selection circles** (Mail, Reminders). Rejected. The app's checked box is an accent circle with a check,
  which is exactly what iOS's selected circle looks like, so a selected open task would read as two boxes with one
  checked. The circles would also push every title 40pt to the right. The mock-up shows both.

### Entering and leaving

- **Enter:**
  - "Select" in the "…" menu of any list screen (§0) starts with nothing selected.
  - A two-finger swipe down or up over the rows, as in Mail and Files, enters with the rows it crosses selected.
  - ⌘A on a hardware keyboard selects all.
  - Entering ends adding (`endDraft`).
- **Leave:**
  - Done, or Esc.
  - Any bar action, once it's done. Closing the date sheet or the Move menu without choosing keeps select mode.
  - The Mac keeps the selection after an action. On the phone, a selection that outlives what it was for gets in the
    way of the next tap, which is Mail's and Files' reason to end it too.
  - The back button is hidden and the edge swipe back is off while selecting, so a stray swipe can't drop the
    selection. Leaving the app keeps select mode. A task that sync removes leaves the selection.

### The top bar

- **Leading:** "Select All" or "Deselect All". Select All takes every open task row shown. In Completed and Trash it
  takes every task row shown. Rows folded under a collapsed heading or a closed Completed row stay out, because you
  can't see them (IX §2.4). This is ⌘A's rule (IX §5).
- **Middle:** "3 Selected" in 17pt semibold `ink`, with tabular figures, or "Select Tasks" in `ink-tertiary` when
  nothing is selected.
- **Trailing:** Done. The "…" is gone while selecting. The large title stays and scrolls as usual.

### Rows

- **A tap** anywhere on a task row toggles it. No sheet opens and there's no haptic, since the fill is instant.
- **Selected:** `fill-row-selected` at radius 12, with no animation either way (IX §5: selection never animates).
  Selected rows next to each other join, so the corners they share go square. The phone's rows sit on a 48pt pitch with
  no gap, so there's no gap to fill (the Mac fills its 2pt one, `css:184–188`). A heading, a group label or the
  Completed row breaks the block. Titles stay `ink`.
- **The checkbox** keeps its ring and its cue, but takes no tap of its own: a tap on it selects the row. One gesture
  has one meaning (IX §2.1).
- **Not selectable:**
  - headings (their chevron still folds, and the name doesn't rename);
  - group labels;
  - the Completed row (it still opens and closes);
  - a deleted list's row in Trash (its chevron still expands, and the tasks inside it select);
  - empty states.
- **Off while selecting:** swipe actions, drag (the reorder brief rules out dragging several rows), and rename on tap.
- **Long-press** opens the menu for the whole selection (IX §15: the menu acts on the selection): Complete 3 Tasks (or
  Mark as Not Done when all are done) · Today · Tomorrow · When… · Deadline… · Move to ▸ · ── · Delete 3 Tasks. In Trash
  it's Put Back · Put Back in ▸. Long-pressing an unselected row first adds it to the selection. The Mac selects only
  that row instead, but touch forces the difference: tapping a selection together takes longer than ⌘-clicking, so a
  long-press shouldn't throw it away.
- **The two-finger swipe**, in select mode or entering it, works as iOS's own does.
  - The row where it starts sets the mode: an unselected row means the swipe selects, and a selected one means it
    deselects.
  - Every row it crosses takes that state, and going back reverses it, back to where the swipe started.
  - Within 31pt of the top or bottom, the list scrolls 10pt every 16 ms (the Mac's drag autoscroll × 1.3).
  - Each row that changes gives a `.selection` haptic.
- **Build it on the app's own state** (`AppModel.selecting`, `selected: Set<EntityID>`), not on `List`'s edit mode,
  since edit mode draws the circles that B rejects. For the swipe, use a two-touch vertical pan
  (`UIGestureRecognizerRepresentable`) that maps the touch to row frames. If the native `List(selection:)` multi-select
  interaction can run without the circles, use that instead. Either way, check that a two-finger swipe that's mostly
  vertical, started on a row, selects, and that one-finger scrolling is untouched.

### The bottom bar

- **Where:** in place of the + (and Home's bar), a Liquid Glass capsule (`floatingGlass`, as `HomeBar`), 16 from the
  screen's sides, 6 above the bottom safe area, and 56 tall (`Metric.fab`).
  - The + leaves on its existing scale-and-fade transition, and the bar rises in on `Motion.natural`.
  - Notices float 12 above the bar.
- **Its segments** are equal width, each a 19pt medium SF Symbol over an 11pt medium word, 3 apart. They're `ink`,
  except Delete in `danger`. With nothing selected they're disabled at 40%.

| View | Segments |
|---|---|
| A list, Today, Upcoming, Undated | Complete (`checkmark.circle`) · When (`calendar`) · Move (`arrow.right.square`) · Delete (`trash`) |
| Completed | Not Done (`circle`) · When · Move · Delete |
| Trash | Put Back (`arrow.uturn.backward`) · Put Back in (`tray.and.arrow.up`) |

When every selected task is done, Complete reads Not Done in any view. A mixed selection reads Complete (IX §8).

### What each action does with a mixed selection

These are the Mac's rules. With one task selected, the single wording applies, as in "Deleted “Buy milk”".

| Action | What it does | Notice | Undo name |
|---|---|---|---|
| Complete | Completes the open ones. If all are done, marks them all not done (`Store.toggleComplete`). Each box it checks sparks (§5), with one haptic. Rows wait 1.5 s, then move together (batch 1) | "Completed 3 tasks", with Undo. That's the phone's completion notice, kept by the user on 2026-11-03. None for Not Done, as with one task now | "Complete 3 Tasks" or "Mark as Not Done" |
| When | The date sheet for all of them (§2) | When the date takes tasks out of the view: "Scheduled for Fri, Nov 6", "Due Fri, Nov 6" or "Removed from Upcoming", with Undo (batch 1's wording, the same for any count) | "Set When" or "Remove When" |
| Deadline… (menu only) | As When, for the deadline | As When | "Set Deadline" or "Remove Deadline" |
| Move | A menu. Its header is "Move 3 tasks to", and it lists every live list. The current list is checked and disabled when every selected task is in it. A task already in the list it's moved to stays where it is | In a list: "Moved 3 tasks to School", with Undo. In Today, Upcoming, Undated and Completed the tasks stay, regrouped, with no notice (IX §10, §22) | "Move 3 Tasks" |
| Delete | All at once, with no confirmation (IX §2.3) | "Deleted 3 tasks", with Undo | "Delete 3 Tasks" |
| Put Back (Trash) | If every task has a live list, each goes back to its old place in it. If any doesn't, the Put back in menu opens for all of them (IX §28) | "Put back 3 tasks", plus " in Home" when they share a list, with Undo | "Put Back 3 Tasks" |
| Put Back in (Trash) | At the bottom of the list picked (`Store.putBack(_:in:)`) | "Put back 3 tasks in Inbox", with Undo | "Put Back 3 Tasks" |

**iPad** works the same way in its list pane. The Mac's detail pane for several tasks ("3 tasks selected", "Mixed") is
out of scope.

**Reuses:** every Store action already takes `[EntityID]`; batch 1's notices; the reorder brief's selected fill; the
date sheet for several ids (§2); `undoable` (§1). **No core change.**

**Size: L.** The two-finger swipe is the unknown; the rest is M.

---

## 4. Trash (gap 7)

### 4a. "Put back in ▸"

**The long-press menu in Trash** (Mac `Menus.swift:127–140`; the tap stands in for Show Details):

- A task deleted on its own, whose list is live: **Put Back** · **Put Back in ▸**.
- A task whose list is in Trash, whether it went with the list or was deleted before the list was: **Put Back in ▸**.

**The submenu.** Its section title is "Put back in". It lists every live list and the task's own deleted list, in
sidebar order by key: the Mac's `putBackInItems` (`DeletedLists.swift:230`), with `orderPrecedes`, which is already in
the core. Names are cut as Move to cuts them (`MenuName.fit`).

- The task's own deleted list is there but disabled, with "In Trash" as its second line (the Mac puts it at the
  right).
- For one task whose list is live, that list is checked, and picking it is a plain Put Back.

**The swipe** doesn't change: the leading full swipe is Put Back, and only for a task that can go home (batch 1 renames
it). A task whose list is in Trash gets no swipe, because a swipe can't open a menu at the row. The menu and the sheet
have it.

**The sheet:**

- **The bar's ↶.**
  - When the list is live, it's Put Back.
  - When the list is in Trash, it's a menu button: a tap opens Put back in. That's the Mac's ↶, which "pops Put back
    in" (IX §28).
- **The banner** keeps batch 1's text.
  - For a task deleted on its own whose list is live, it has one tinted **Put Back**.
  - For a task whose list is in Trash, it has two buttons on a row under the text: a tinted **Put Back in** (a menu,
    with a chevron) and a neutral **Restore List**. The second line becomes "Its list is in Trash. Put it in another
    list, or restore the list."
- **The List row** stays read-only and reads "School  In Trash" (IX §28).
- **Afterwards,** the sheet closes. On the Mac, the detail pane moves on with the selection, and the task has left
  Trash. The notice reads "Put back “Email TA about midterm re…” in Inbox", with Undo, and the undo name is "Put Back".

### 4b. Opening a deleted list

**In Trash,** a tap on a deleted list's row pushes the list. The chevron, which keeps its 44×44 target at the right,
expands and collapses it in place. Today a tap anywhere on the row expands it (`TaskRow.swift:170`). The Mac's rule is
the same split: a click shows the list (in its detail pane), and the chevron or Space expands it (IX §28).

- **Long-press:** Open · ── · Restore List. On the phone, the Mac's Open and Show Details are the same thing.
- **Swipe:** Restore, as now.
- **VoiceOver** reads "School, deleted list, 11 tasks", with the actions Open, Expand and Restore List.

**The pushed screen is `ListScreen(source: .list(id))` itself**, read-only, not a copy. That follows the Mac's §28
detail-pane version and the user's "reuse is better" (2026-11-01).

- **The bar:**
  - the system back, to "Trash";
  - the folded title (tile and name), as for any list;
  - a ↶ icon labelled "Restore List" at the trailing end, where the Mac's header has its ↶;
  - no "…", since nothing in it applies.
- **The banner,** above the large title, uses the sheet's trash banner metrics: `fill-control`, radius 12, padding 12,
  10 in from the screen's sides, 4 under the bar. It holds:
  - the trash glyph in `ink-secondary`;
  - "Deleted Nov 1" in 15pt `ink`;
  - "Read-only until you restore it." in 12pt `ink-secondary`;
  - a tinted **Restore** capsule, 30 tall, at the right.

  It takes two lines, as the Mac's does in a narrow pane.
- **The large title** shows the tile, the name, and "In Trash" in `ink-tertiary` in the subtitle slot.
- **The notes** are rendered and read-only. With no notes there's no notes slot.
- **Headings** fold by their chevron, and **the Completed row** opens and closes. These are the list's own folds, so
  they're kept when it's restored. A heading's long-press is Collapse or Expand only (IX §28 As built).
- **The rows** have the trashed look: `ink-secondary` titles, the box at 60% and deaf, and no dates and no ring (IX
  §22). `TaskRow` already draws this through `isTrashed`. What a tap does:
  - **A · Nothing (recommended; the Mac's).** Rows take no tap, long-press or swipe. A single task comes out from
    Trash's expanded row (a tap opens its sheet, which has Put back in), as on the Mac.
  - **B · A tap opens the task's read-only sheet,** which has Put back in. That's handier on a phone, where finding the
    task in Trash's expanded row can take a long scroll, but it's a second way in that the Mac doesn't have.
- **There's no** +, new-task row, swipe or select mode.

**Restore** (the banner or ↶). The screen becomes the live list in place:

- the banner fades out (150 ms) as the rows close up on `layout`;
- "In Trash" goes;
- the "…" and the + come back;
- the notice reads "Restored School", with Undo, and the undo name is "Restore List";
- back still goes to Trash, where the row is now gone.

That's §28's list-pane rule ("the pane becomes the live list in place"). On the phone this screen is the list pane,
not a preview beside Trash, so the detail pane's "show the next row" has nothing to move to.

**Deleted on another device while open:** the same screen turns read-only in place under its banner, as the Mac's list
pane does. A new-task row there is dropped. Deleting a list on the phone still pops back to Home, as now.

**Reuses:** `ListScreen`, `Lines`, `TaskRow`'s trashed look; `Store.restoreList`, `putBack(_:in:)` and `trashedTasks`;
`Projection.isActive`; `orderPrecedes`; batch 1's `TrashVerb` wording. **No core change.**

**Size: M.** Put back in is S, and the pushed list is M.

---

## 5. Moments and Reduce Motion (gap 10)

### Completing (COLOR.md §4; IX §8; Mac `Moments.swift`, `TaskRowView.swift:319–331`)

The Mac's lengths scale with the box, by k = the box's size ÷ 16: 1.375 for a row's 22pt box, and 1.5 for the sheet's
24pt one. The numbers below are a row's.

| Part | Phone | Timing |
|---|---|---|
| Press | Scales to 0.86 | 80 ms ease-out in; back on `snappy` (as now) |
| Box | Fill and ring go from `spark` to `accent` | 520 ms ease-out |
| Check | Draws from 0 to 100%, in `on-accent` | 160 ms ease-out, after 40 ms |
| Pop | From 0.8 | `snappy` (as now) |
| Ring | Centred on the box; r 12.4; scale 0.9 → 2.1; stroke 3.4 → 0.55; opacity 0.95 → 0; `spark` | 460 ms, cubic-bezier(0.2, 0.8, 0.2, 1) |
| Rays | Eight, every 45°, from 15 to 23.4 out (the odd four 15.2 to 22), 2.4 wide with round caps, in `spark`. From scale 0.55, turned −8°, to scale 1.2. Opacity 0 → 1 at 22% → 0 | 560 ms, the same curve |
| Row | Its rounded fill (radius 12), from `spark` at 14% to clear | 700 ms ease-out |
| Title | From `spark` to `ink-tertiary`. The strike is instant (batch 1, item 10) | 700 ms ease-out |

- **Unchecking.** The fill and the check go out in 160 ms ease-out, the box pops from 0.8, and the title comes back in
  200 ms. There's no spark and no flash.
- **Drawing.** At its widest the spark reaches 28pt from the box's centre, 4pt past a 48pt row. Draw it above the
  neighbouring rows, unclipped.
- **When it fires.** On a check made on this device, from the box, a swipe, the menu, the sheet's box or the bar's
  Complete (every box at once, §3). A completion that syncs in from elsewhere just shows the task done.
- **The 75% row opacity** while a checked row waits (`TaskRow.swift:55`) goes. The Mac doesn't dim the row; the struck
  `ink-tertiary` title already says it's done.

### Today all done (IX §13; COLOR.md §4; Mac `Moments.swift:97–170`)

- **Order.** When Today holds only completed tasks, the all-done block comes first, under the large title, with the
  Completed group after it. Today it's the other way round (`Lines.swift:96–99`).
- **The sun.** The Mac's glyph (`Draw.swift:18`: eight rays around the r 2.6 circle, in a 16-unit box), at 40pt (the
  Mac's 30 × 1.3), with a 3.75 stroke, in `spark`, its centre filled. It sits 28 below the header block.
  - "All done for today" is 17pt medium `ink`, 8 below the sun.
  - The Completed group starts 24 below that.
- **As it appears** (when the last row settles while Today is open, or when Today opens already all done, but not when
  it scrolls back into view), the rays and ring turn in from scale 0.5 and −40° as they fade in, over 900 ms,
  cubic-bezier(0.2, 0.8, 0.2, 1). The filled centre doesn't move. Tie this to the state changing, not to the row's
  `onAppear`.
- **The sunrise.**
  - **Where:** above the ground and behind everything else, starting at the screen's top edge, so it's behind the
    status bar and the bar.
  - **Shape:** a radial ellipse 120% of the screen's width and 338 tall (the Mac's 260 × 1.3), centred on the top
    edge.
  - **Colour:** `spark` at 13% in dark and 9% in light, fading to clear by 70%.
  - **Timing:** it fades in over 900 ms ease-out, and goes at once when a task arrives.
  - It stays fixed and doesn't scroll. In Glass it sits over the wallpaper the same way.

### Haptics

Haptics stay on under Reduce Motion. The system's own haptics switch turns them all off.

| Moment | Haptic | Why |
|---|---|---|
| Check | `.success` | As now. The parity review called it a good phone addition |
| Uncheck | `.selection` | As now |
| Today all done, as the sun appears | `.impact(weight: .light)` | A soft echo of the last check, 1.5 s later |
| A two-finger swipe changes a row (§3) | `.selection`, once per row | iOS's own |
| Return with no date match (§2) | `.warning` | The key can't grey out |
| Drag lift and drop | Light | The reorder brief, unchanged |

There's none for undo or redo (the shake alert is the system's, and the notice confirms), Delete, Move, a tap that
selects, or a notice.

### Reduce Motion: exactly what each animation becomes

The rule is the Mac's: every duration is 0 (IX §3, `css:378–379`). The state still changes, in one frame.

| Animation | Under Reduce Motion |
|---|---|
| Checkbox press (0.86) and pop (0.8) | None. The box stays at its size (`Components.swift:225–238` today ignores the setting) |
| Box fill, check stroke | The box is `accent` and the check is drawn at once |
| Spark ring and rays | Not drawn |
| Row and title flash | None. The title takes `ink-tertiary` at once |
| Unchecking | The box empties at once |
| The settle, rows moving, inserts and removals (`layout`, fades) | At once (`animate()` already checks) |
| Chevrons turning (headings, Completed, deleted lists); folds | At once |
| Notices coming and going | At once |
| The +, Home's bar, the select bar coming and going; the keyboard-up fade (`RootView.swift:90–91`) | At once |
| The bar's folded title (150 ms) | At once |
| The date sheet's month title, Today pill and scrolling to a date | At once. The calendar jumps. The 0.22 s pause before the sheet closes stays, since it's a pause, not motion |
| The tapped-row fade (reorder brief) and the undo fill (§1) | The fill holds for 0.6 s, then goes at once |
| The drag's gap and the copy's flight (reorder brief) | The gap opens at once, and the copy lands at once |
| The all-done sun | Shown at rest, with no turn |
| The sunrise | Shown at once |
| Row press fill (`RowStyle`, 85 ms out) | Goes at once |
| Sheets, push and pop, menus, swipe actions, the keyboard, pull to refresh, the shake alert | The system's own; they follow the setting themselves |

**Building it.**

- Read `@Environment(\.accessibilityReduceMotion)` in views, which updates live when the setting changes.
- Pass `nil` animations and `.identity` transitions when it's on, and skip `keyframeAnimator` then.
- Route every `withAnimation`, `.animation(`, `.transition(`, `keyframeAnimator`, `phaseAnimator`,
  `contentTransition` and `symbolEffect` in `ios/` through one helper next to `animate()` (`Metrics.swift:61`).
- A grep for those names is the checklist.

**Reuses:** the Mac's numbers and curves; `spark` from `TasksTheme`; the sun's path from `Draw.swift`. **No core
change.**

**Size: M.**

---

## Lines for SPEC §8's iOS notes (deliberate differences)

These go in a docs commit with the build.

- The date sheet's field doesn't take the caret when the sheet opens, except with a hardware keyboard. ⌫ in the empty
  field doesn't clear the date.
- In select mode, long-pressing an unselected row adds it to the selection, and every bar action ends select mode.
- The "…" menu's Undo and Redo items appear only when there's a step to undo or redo.
- A deleted list opens as its own pushed list screen, and restoring it there makes it live in place.

## Sizes, and an order to build them in

| # | Feature | Recommendation | Size |
|---|---|---|---|
| 5 | Moments and Reduce Motion | Port the Mac's numbers × k; gate every animation | M |
| 1 | Undo and redo | The scene's stack, the restore step, and A: Undo in the "…" | M |
| 2 | Typed dates | A: the field at the top; no caret on open; the default keyboard | M |
| 4 | Trash | Put back in for menus and the sheet; a tap pushes the read-only list; restore in place; A: deaf rows | M |
| 3 | Multi-select | A: the Mac's joined fill; the four-segment glass bar; the Mac's mixed rules | L |

5 stands alone. 1 comes before 3, because 3's names and its undo build on `undoable`. 2 comes before 3, because the
sheet learns to take several ids. Everything starts after batch 1.

## Questions only the user can answer

1. **Undo:** an item in the "…" menu (A, recommended), or nothing beyond the notice and the gestures (B)?
2. **A deleted list's rows:** deaf, as on the Mac (A, recommended), or a tap opens the task's read-only sheet (B)?
3. **The selected fill in light.** On the phone, light lists sit on the ground (#F5F5F5), not the Mac's white pane, so
   `fill-row-selected` (#E6E6E8) is quieter than on the Mac. The mock-up shows it. Keep it, since it's the one selected
   look and the reorder brief already uses it, or ask for a stronger light value?
