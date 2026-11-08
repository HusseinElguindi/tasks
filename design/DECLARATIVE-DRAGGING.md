# Declarative dragging, and what it means for Tasks

Read 2026-11-08 for the user ("i want you to take a look at https://declarative-dragging.github.io/").
Research only. Nothing in the app changed.

## Summary

- **What it is.** *Declarative Dragging* (D2) by Joshua Horowitz, Andrew Blinn and Jeffrey Heer (University of
  Washington and University of Michigan) is a UIST 2026 paper; the site says it won Best Paper. Its library,
  Dragology, is TypeScript, React and SVG, MIT licensed, and lives at github.com/declarative-dragging/dragology.
  You don't write drop zones. For each draggable element you list the model states a drag could end in. The engine
  renders each of those states, reads off where the dragged element would sit in each one, and builds the drag from
  that: the nearest target, the preview, snapping and the animations.
- **Tasks already works this way, written out by hand.** On both platforms our list drag is the paper's
  `d.closest(allOrders).withFloating()`: the copy follows the pointer, the slots come from the layout, the nearest
  slot wins, the other rows part to preview it, and the copy flies into the slot on drop. Upcoming on the Mac even
  lays out the would-be drop state while you drag.
- **Recommendation: don't adopt it, but borrow two or three ideas.** There's no native version. The paper says SwiftUI
  would need new platform hooks, and our lists aren't SwiftUI anyway (AppKit layers on the Mac, a UICollectionView on
  the iPhone). The iPhone's real pain points are gestures, cells and animation, which D2 doesn't cover. What's worth
  borrowing is its central rule: **the preview and the landing are the layout of the drop state**. That rule is
  exactly what the Upcoming "very weird jump" broke.

## The idea

**The problem it solves.** A good drag needs spatial logic (drop zones), timing logic (transitions) and rendering
logic (previews while dragging). Low-level pointer handlers can do anything, but they spread into every part of the
app. The source and target style (HTML5 DnD, SwiftUI `draggable`/`dropDestination`, both of which the paper cites)
feels flat and starts to fail once you need in-between drop targets. Specialised libraries such as sortable lists
feel polished but only within their one pattern.

**The model.** The view is a pure function from state to view. Each draggable gets
`dragologyOnDrag={() => spec}`, and a *drag spec* is built from:

- primitives:
  - `d.fixed(state)`
  - `d.vary(state, param(...), {constraint})`: numerical optimisation (COBYLA) of a continuous parameter, so the
    element stays under the pointer
  - `d.dropTarget(id, state)`: an explicit-zone fallback, for a trash bin, say
- combinators:
  - `d.closest([...])`: whichever target is nearest
  - `d.between([...])`: interpolates the whole view inside the convex hull of the targets
  - `.whenFar(spec)`: switches to another spec once the pointer is far from every target
  - `d.switchToStateAndFollow`: creates an element mid-drag, as when dragging one off a toolbar
- modifiers:
  - `.withFloating()`
  - `.withSnapRadius()`
  - `.withDropTransition()`
  - `.onDrop()`
  - `.during()`
  - `.withOverlay()`

Every frame, a *drag behavior* maps the pointer position to a preview (what to draw now) and a drop state (what to
commit if released now).

A reorderable list, from the docs:

```js
dragologyOnDrag={() => d.closest(state.items.map((_, j) => ({ items: moveItem(state.items, i, j) }))).withFloating()}
```

**How the engine works.** When a drag starts it renders every candidate state, extracts the dragged element's
position in each, and interpolates SVG trees attribute by attribute. Elements are matched across trees by global
`id`, so an element can move to a new parent. Debug visualisers show the pointer-to-target distances, the drop zones
on a grid, and the spec tree.

**The evidence.**

- A gallery of demos.
- A "lists in lists" task given to an LLM agent: Dragology succeeded 80% of the time, other libraries 0–40%, and the
  other libraries needed 87–103% more lines of code.
- Interviews with 13 developers. Their reactions included "where is the code?", that the results looked polished,
  and that it was easy to experiment.

**The limits the paper states.**

- It fits *repositional* drags. Create and delete need escape hatches.
- Developers found listing the reachable states hard: a "sharp cliff" at the reorderable list, where people tried to
  list every permutation.
- Two targets in the same place throw an error.
- One touch only.
- No model of velocity.
- Cost grows with the number of states. A reorderable list is quadratic, where a hand-written one is linear.
- It's SVG only. HTML would need DOM layout run once per candidate state.
- It isn't native. The paper says SwiftUI or Compose "would need new hooks … to extract position information and
  interpolate rendered views".

## How Tasks drags today

### Mac (AppKit with layer-drawn rows, `app/Tasks/TaskList/TaskListView.swift`)

- **Lift and multi-select.** The drag starts after `dragSlop`; the selected rows of the grabbed row's group come
  along (`TaskListView.swift:1745`, `:1759`). A heading drags its whole section (`:1791`).
- **Targets.** Every frame, `updateDrag` (`:1822`) works out slot tops from the layout (`TaskLayout.slotTops`,
  `TaskLayout.swift:432`), filters them (a heading lands only before another heading or at the end, `:1859`), and
  takes the nearest (`:1860`). The copy is clamped to 6 pt past the first and last slot.
- **Preview.** `TaskLayout.applyDrag` (`TaskLayout.swift:447`) lays the group out with a gap at the target. Over the
  sidebar the group closes up and the copy turns into a compact tag.
- **Moving to another list, Today, Completed or Trash.** `SidebarView.dropTarget` (`SidebarView.swift:335`) hit-tests
  the rows, and `endDrag` (`TaskListView.swift:1897`) flies the copy there and writes `move`, `setDate`,
  `completeTasks` or `delete`.
- **Upcoming.** `dayTarget` (`:1972`) chooses the day under the copy's middle and refuses one past the deadline. The
  preview is `ViewLayout`'s Upcoming case (`ViewLayout.swift:228`), which lays the rows out as though the dragged
  tasks were already on `toDay`: a speculative render of the drop state, written by hand.
- **Auto-scroll.** Within 24 pt of either edge the list scrolls 8 pt every 16 ms (`:1878`).
- **Landing.** The copy flies to the slot, the write happens at `TK.Timer.fly`, and `land(on:)` draws the row in the
  same transaction as the copy fades (`:2024`).
- **The Upcoming jump** (3907e2f, fixed 2026-11-06). The landing render read Upcoming's rows from a cache that
  `ViewDates` only refreshed a turn later. The row was laid out on the day it had just left, so it jumped, then slid
  back. The fix is `state.viewDates.invalidate()` before landing (`:2003`), and `app/Scripts/upcoming-drop-check.sh`
  now checks every frame. **This is the class of bug D2 rules out by construction**: our preview (the hand-sorted
  layout at `ViewLayout.swift:228`) and our landing (the real projection through a cache) were two different code
  paths, and they disagreed.

### iPhone (UICollectionView, `ios/Tasks/Views/Collection/TaskCollection+Drag.swift`, 1567 lines)

- **Press.** It uses its own `PressDrag` recognizer (`:717`): a hold of 0.35 s within 10 pt of the touch, sorted out
  against the row's menu (about 0.8 s), scrolling, swipes, and the rows' SwiftUI buttons (T29, a71d5e2, d7d4b22).
- **Targets.** `slotTops` (`:207`) lists the allowed slots and their y. Today and Undated stay within their run
  (`dragRuns`, `Model/Reorder.swift:90`). A heading lands only before another heading or at the end, and a task never
  lands between a heading and its notes. `follow()` (`:270`) runs every display-link frame and takes the nearest slot.
- **Upcoming.** `upcomingTarget` (`:239`) works out the day from the label positions, then the slot from
  `ViewGroups.upcomingPrecedes`.
- **Preview.** Cell transforms through `shift()` (`:146`) and `moveGap` (`:173`), on a spring with bounce 0.
- **Drop.** `write()` (`:683`) turns the slot into `.onMove`-style offsets and calls `AppModel.drop`
  (`Model/Reorder.swift:116`). The new order applies at once and the copy sets down on the cell's new frame.
- **Single row only.** Multi-select moves go through Move To, not drag. There's no sidebar target.
- **Auto-scroll.** `EdgeScroll` (`:892`).
- **The heading fold jank.** `design/IOS-LIST-NATIVE.md` isn't on main or on any local or remote branch I can see. The
  commits that record the problems:
  - 2758b0f: the folding pictures didn't move with the gap
  - f925398: a drop under a collapsed heading had no row to land on
  - c0e348b: the fold now runs on the Mac's spring, and a second tap reverses it from where it's drawn
  - 046db53: the heading lift
- **Tests.**
  - `ios/TasksUITests/FlowTests.swift`, about 30 drag tests: `testDragATaskIntoAnotherSection` (:812),
    `testDragAHeadingMovesItsSection` (:996), `testDropUnderACollapsedHeading` (:2260),
    `testDragInUpcomingSetsTheDay` (:3222), `testUpcomingTakesNoDropPastTheDeadline` (:3268), and others
  - `HomeDragTests.swift`
  - `DragFilmTests.swift`, with `Tools/film/drag.py` and `Tools/perf/drags.py`

## The comparison

| Behaviour | D2 / Dragology | Tasks now | Would D2 help? |
|---|---|---|---|
| Reorder within a list | `closest(allOrders).withFloating()` | The same, hand-written: slotTops → nearest → gap | Less code; same feel |
| Heading drags its section | Enumerate "section before heading k" states | An `allowed` filter on the slots | A little |
| Today/Undated runs | Enumerate only states within the run | A run filter in `slotTops` | A little |
| Upcoming day drop | `closest(days.map(d => when=d))` | Speculative layout at `toDay` plus a separate landing path | **Yes, the main lesson**: one path for preview and landing |
| Sidebar list / Today / Trash | `dropTarget(id, state)` (the escape hatch) | `SidebarView.dropTarget` | No: same idea |
| Far from targets → cancel | `.whenFar(state)` | Esc, or a sidebar gap counts as a cancel | No |
| Multi-select drag | Not covered | Mac: the group's selected rows | No |
| Auto-scroll | Not covered | Both platforms | No |
| Gestures versus menu, scroll and swipe | Not covered; one touch | `PressDrag`, much of the iOS work | No |
| Cell reuse and fold animation | Not applicable (SVG) | Where the iPhone's jank came from | No |
| Haptics and VoiceOver Move Up/Down | Not covered | Both done | No |

**What adopting it would cost.**

- **A rewrite of the Mac and iPhone drag layers.** About 300 lines in `TaskListView` plus `applyDrag`, and most of
  the 1567-line iPhone file.
- **New infrastructure first.** We'd need a way to "render" a candidate state and read a row's frame. `TaskLayout` is
  already a pure, analytic function, so laying out N states is cheap, but nothing generic exists.
- **Interpolating views wouldn't carry over.** Our rows are CALayers and UICollectionView cells, not trees you can
  diff.
- **Risk to the tests.** Every drag UI test (the timing, set-down and fold films) checks behaviour that was tuned by
  hand, which is a high risk for a rewrite.
- **No gain at the pain points.** The bugs we fought most were the stale-cache landing, gesture arbitration, fold
  pictures and lift timing. D2 addresses only the first.

## Worth borrowing

1. **The drop-state rule.** The landing frame is the real layout of the state the drop will write, and the preview
   gap is drawn at that same frame. Concretely, compute the Mac's Upcoming preview from the same projection path the
   landing uses, not from a second sort, so the two can't drift.
2. **A property test from the same rule, cheap on both platforms.** For every allowed slot (and every Upcoming day),
   check that the gap's y equals the dragged row's y in the layout built after `reorder`/`setDate` is applied. That
   catches the jump class of bug without filming: today, `upcoming-drop-check.sh` covers only one up drag and one
   down drag.
3. **Targets as states, in debug.** A debug overlay, like Dragology's visualisers, that draws each candidate slot's
   target y and the zone that wins it. The `-dragTrace` and `DragProbe` work already logs slots; drawing them would
   make tuning the clamps and heading rules quicker.

Not worth borrowing: `between`-style interpolation of the whole view, or `vary` numerical optimisation. Tasks has no
continuous drags (dates are picked, not dragged along a scale) and nothing to blend between.
