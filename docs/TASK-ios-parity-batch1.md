# Task (iOS): parity batch 1, bringing the iPhone in line with the Mac's rules

The user approved this on 2026-11-03. Every item below follows a rule the Mac already has, so no design decision is
needed. The evidence for each one is in `docs/IOS-MAC-PARITY.md`, which has file:line on both sides: read the cited
section before each fix and copy the Mac's rule exactly. If something doesn't fit, stop and ask through the
coordinator.

Start it after the drag, tapped-row and headings work.

## Gaps (parity §1)
1. **Notices for moves and date changes** (gap 1):
   - a move gets "Moved to School", with Undo;
   - a date change that takes a task out of Today, Upcoming or Undated gets "Scheduled for Fri, Nov 6", "Removed from
     Upcoming", "Due …" and the like, with Undo.

   Use the Mac's wording and rules (`WindowActions.swift:575`, `:648`; IX:701–704).
2. **Dates on rows** (gap 3): hide only the date that places the row, as the Mac does. In Today, that's a When on or
   before today. In Upcoming, it's the group's own day. Everything else shows (`TaskListView.swift:345`).
3. **A list's notes** (gap 5): editable under the large title, with the existing notes editor. "Add Notes" or "Edit
   Notes" goes in the list's "…" menu. One update per session, undo name "Edit List Notes".
4. **Completed folds** (gap 8):
   - Today's Completed group is open by default;
   - Today's group and each list's Completed row keep their fold across launches, saved per device and never synced,
     as in `WindowState.swift:134–147`.
5. **"Show in <list>"** (gap 9): in a task's long-press menu and in the sheet's header, from Today and the views. It
   opens that list with the task shown.

## Accidental differences (parity §3)
6. **No list counts** on Home or in the large title's subtitle (the user removed them on 2026-10-31). Today keeps its
   count, as on the Mac.
7. **The Trash verbs:** a task says Put Back ("Put back “…” in Home", "Read-only until you put it back"); a list
   says Restore. That's the Mac's `TrashVerb`.
8. **Trash's empty text and header** match the Mac's §28 wording.
9. **A deleted list's count:** open tasks, then "N completed" or "Empty", as on the Mac.
10. **Checked rows:** settle after 1.5 s. A new check restarts the timer, so a run of checks moves together, and the
    strike comes at once (IX:660–669).
11. **Today's done rows show their list name.** Completed and Trash rows in a month group show the day ("School ·
    Oct 22").
12. **The calendar's week starts on the locale's first weekday**, as in `DatePopover.swift:327`.
13. **Titles have no line breaks:** pasted ones become spaces, and Return submits (IX:599).
14. **Notices:** 5 s with Undo, 1.8 s without, and titles cut at 28 characters. **Keep the completion notice with
    Undo.** The user decided this on 2026-11-03, since the phone has no ⌘Z. Record it in SPEC §8's iOS notes.
15. **Reduce Motion** also stops the checkbox's pop and the floating controls' animation.
16. **VoiceOver:** the checkbox names its task and reads the ring, notices are announced, and a stopped sync is
    announced.
17. **Notes past 20,000 characters:** say "Notes hold up to 20,000 characters", and show the counter from 18,000.
18. **The + with no live lists** shows "Create a list first".

## Rules (the user's, from 2026-11-02)
- **Tests:** targeted tests per item, then the full iPhone suite once before the install. An intelligencetasksd crash
  gets one rerun and no investigation.
- **Screenshots and iPad:** none unless asked, and no iPad runs.
- **Commits:** a few logical commits on `ios`, under `ios/` only, with the SPEC §8 note in its own docs commit. A
  core helper needs the user's OK first.
- **Install and push:** install on the phone after the batch, keeping the data and the token, then push `ios`.
