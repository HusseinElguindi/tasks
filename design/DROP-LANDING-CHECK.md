# Drop landing check

The rule, from design/DECLARATIVE-DRAGGING.md (borrow items 1 and 2, the user, 2026-11-08: "ok yea go ahead with 1
and 2"): **a drag's preview is the layout of the state its drop writes.** The gap is where the dropped row lands,
and every other row is already where it will end up.

## The Mac (done)

- **Upcoming's preview** comes from the same `ViewItems.build` that the landing reads. It runs over `ViewDates`'
  entries with the drop's write applied: the dragged tasks' When is set to the day under the copy. The second,
  hand-written sort in `buildView` is gone.
- **The days the rows left keep their labels while the pointer is down**, as before. They close up at the release, so
  the copy flies into the drop's own state (`ViewItems.CacheKey.keep`, `endViewDrag`).
- **The drop's writes are shared:** `WindowActions.dropInGroup` (list, Today and Undated order, and a heading's
  section) and `dropOnDay` (Upcoming). `endDrag` and the check both call them.
- **The check:** `app/Scripts/drop-landing-check.sh` runs `act:dropcheck` (`app/Tasks/Support/DebugDropCheck.swift`)
  in the Debug app on demo data. Covered:
  - views: Today, Upcoming, Undated, School, Errands, and PHYS 122, open and with Labs, then Lectures, collapsed
  - drags: every task, every heading's section, and two selected tasks that aren't adjacent
  - drops: onto every slot, or every day in Upcoming
  - each drop is written, laid out as the landing renders it, compared row by row and label by label, then undone

  It reads layouts only, with no pointer and no frames, and runs 731 checks in about 10 s.
- **Allowed differences, by design:**
  - A heading's tasks and notes are folded into its copy until it lands (§23), so for a heading only it and the rows
    above its gap are compared.
  - A task dropped right under a collapsed heading folds into its section, and the gap closes after it.

## The iPhone version (to do on the ios branch)

The functions are in `ios/Tasks/Views/Collection/TaskCollection+Drag.swift`. All of them are `private` to
`CollectionDrag`, so the check belongs in that file under `#if DEBUG`, as `func debugDropCheck() -> [String]`. Run
it from a `-debugScript` step (`ios/Tasks/App/DebugScript.swift`), or from a UI test that reads its output.

For each row that `canLift(_:)` accepts in the open list (a task or a heading; Home's lists have the same parts in
`HomeCollection`):

1. **Build the drag state** the way `lift` and `begin` do:
   - `State(id:height:grab:slot:ticked:run:)`, with `run` set by `run(of:)` in Today and Undated.
   - For a heading, its section folded (`begin(_:)`). Or skip headings in a first version.
2. **Take each place it can drop.**
   - Lists, Today and Undated: each `(slot, y)` in `slotTops(d)`.
   - Upcoming: one copy position per day label. Set `copyTop` so that `copyTop + d.height / 2` sits just under the
     label's drawn top, then call `upcomingTarget(d, copyTop)`; it returns the slot and whether that day is lit.
3. **Read the preview.** Set `state.slot = s` and call `moveGap(animated: false)`. For every shown item `i`, the
   preview y is `owner.layout.modelFrame(i).minY + shift(id).dy`; the dragged row's preview y is the slot's `y`.
4. **Write the drop.** If `moves(d)` is true, call `write(d)`: it calls `AppModel.drop` (`dropOnDay` in Upcoming),
   applies the new order, and returns the landed frame. A nil frame with `foldedInto(d.id)` set means the row fell
   into a collapsed heading, which is allowed; compare only the rows above the gap.
5. **Compare.** The landed frame's `minY` must equal the slot's `y` (within 0.5 pt). Every other item's
   `modelFrame(i).minY` after the write must equal its preview y.
6. **Undo** through the app's undo (the write is one "Move" step). Clear `landing` and call `settle()` so the next
   case starts clean, and check the items are back as they were.
7. **Report** a line per disagreement and an `ok`/`FAIL` summary per view.

Cover the cases the Mac's check found:

- Undated, whose rows come from a cache refreshed a turn later.
- Upcoming days inside a month with a single task, whose label goes once the task leaves.
- A drop under a collapsed heading.
- Today's runs.

To prove the check works, break the preview on purpose: in `upcomingTarget`, put the row after its own list's tasks
on that day. The check must fail, and pass again once the break is reverted.
