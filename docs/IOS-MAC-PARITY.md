# iPhone vs Mac: what's missing or different

The user asked for this on 2026-11-03: "i want you to compare the missing/different features between mac and ios."
It's read-only analysis, done against main at 6da792f (iOS merged at 520c4af). Sources: `design/INTERACTIONS-v2.md`
(cited as `IX:line`), `design/MARKDOWN.md`, `design/COLOR.md`, `docs/SPEC.md` §8, the Mac code in `app/Tasks/` and the
iOS code in `ios/Tasks/`. Mac paths are relative to `app/Tasks/` and iOS paths to `ios/Tasks/`. Only the iPhone is
compared here.

**Shared, so the same on both:** everything in TasksCore. That covers the model, the ops, undo registration, sync and
its triggers, Today's rule, `ViewGroups` (Upcoming's days, Completed's and Trash's groups), `DateLabel` (chip
wording, tooltips and relative words), the checkbox ring's cue, ordering, the Markdown parser and list numbering,
`DatePhrase`, and the title and notes limits (1,000 and 20,000, clamped in `Store+Actions.swift:5–6`). Colour comes
from `TasksTheme` (tokens and the lit tiles). These are left out of the table unless the phone uses them differently.

**Spec versus Mac code:** §24 and §25 are headed "not built yet" (IX:1622, IX:1794), but the Mac ships both. The
When follows the title as quiet text (`TaskList/RowDates.swift:6`, `TaskRowView.swift:253`), and the calendar
scrolls in a 240pt popover with Today · Tomorrow · Clear (`Overlay/DatePopover.swift:9`, `:134`;
`Overlay/WeekCalendar.swift`). §26 and §27 are built (`Window/SyncIndicator.swift:16`,
`Sidebar/SidebarFoot.swift:20`). The theme-file picker in `THEMES.md` §4 isn't built on either app. Both offer only
System, Dark and Light (Mac `Views/SettingsView.swift:38–42`).

---

## 1. The gaps that matter most on the phone

Ranked by how often they'd bite in daily use.

| # | Gap | Recommendation | Size |
|---|---|---|---|
| 1 | **Missing notices.** Moving a task out of its list, or changing a date so it leaves Today, Upcoming or Undated, gives no notice and no Undo. The row just vanishes. The Mac says "Moved to School" or "Scheduled for Fri, Nov 6" with Undo (`Window/WindowActions.swift:575`, `:648`; IX:701–704). On iOS, `AppModel.move` and `setDate` (`Model/AppModel.swift:240–251`) show nothing. | **Build.** Use the Mac's rules and wording. | S |
| 2 | **No undo once the notice is gone.** iOS keeps its own `UndoManager` (`AppModel.swift:67`), and only the notice's button reaches it. Shake to undo, the three-finger gestures and redo can't reach it, and a hardware keyboard's ⌘Z doesn't either. The Mac undoes and redoes any step (IX:717–724). | **Adapt for touch.** Give the scene's undo manager the Store's steps, so shake and three-finger undo and redo work, and confirm each one with a notice, as the Mac does (`WindowActions.swift:82`). | S |
| 3 | **Rows hide dates the Mac shows** (a bug, §3). Today hides every When, and Upcoming does too. The Mac hides only the date that places the row: a When on or before today in Today, and the group's own day in Upcoming (`TaskList/TaskListView.swift:345`). So on the phone, a task that's in Today because of its deadline, or that sits on its deadline's day in Upcoming, never shows its When. | **Build.** Match the Mac's rule. | S |
| 4 | **No typed dates.** The sheet has quick picks and the calendar, but no field. The Mac's field takes "fri", "3d" or "nov 9" through `DatePhrase.match` (`Overlay/DatePopover.swift:96`), which is in the core. | **Adapt for touch.** Add a field at the top of the sheet. It moves the highlighted day as you type, and Return sets it. | M |
| 5 | **A list's notes can't be edited.** They render under the title (`Views/ListScreen.swift:86–90`), but nothing on iOS writes them. `setNotes(list:)` appears only in `Model/SampleData.swift:76`. The Mac edits them in place as "Edit List Notes" (`Detail/NotesView.swift:674`; IX:1540–1543). | **Build.** Reuse `NotesEditor` under the large title, with an "Add Notes" item in the list's "…" menu. | S |
| 6 | **No multi-select.** There's no way to complete, date, move or delete several tasks at once. The Mac has ⌘-click, ⇧-click and ⌘A, and every action works on the selection (`TaskListView.swift:1313`; IX:426–455). | **Adapt for touch.** Add Select in the list's menu: an edit mode with two-finger swipe selection and a bottom bar for Complete, When, Move and Delete. | L |
| 7 | **Trash is half-built.** Tapping a deleted list only expands it; it can't be opened and read (IX:2172–2207). A task can't be put back into another list. A task whose list is in Trash has no "Put back in": its banner only says to restore the list (`Views/TaskDetailView.swift:200–202`). The Mac has all three (`Window/DeletedLists.swift:168`, `:230`; `Window/Menus.swift:127–136`). | **Build** "Put back in ▸" in the task's menu and the sheet. **Adapt** opening a deleted list as a pushed, read-only list screen with a Restore banner. | M |
| 8 | **Completed folds don't stick.** Today's Completed group starts folded and forgets its state on relaunch, and so does a list's Completed row (`AppModel.swift:73`, in memory only). On the Mac, Today's group is open by default, and both are kept across launches (`Window/WindowState.swift:134–147`). | **Build.** Default Today's group to open and save both per device, as the Mac does. | S |
| 9 | **No "Show in School".** From Today or a view, there's no way to jump to the task's list. The Mac offers it in a task's menu (`Window/Menus.swift:60`; IX:982). | **Build.** Add it to the long-press menu and the sheet's header. | S |
| 10 | **No Moments, and Reduce Motion is incomplete.** There's no spark or warm flash on completing, and no lit sun or sunrise when Today is all done (Mac `Theme/Moments.swift:5–13`, `:145`; COLOR.md §4). The checkbox's pop ignores Reduce Motion (`Views/Components.swift:225–238`). | **Build.** Port the Moments, and gate every animation on Reduce Motion. | M |

Close behind these: VoiceOver labels (§3), the date sheet's week start and its "after the deadline" note (§3), and
Upcoming's per-day + (table, Upcoming).

---

## 2. Feature by feature

Status values: **same**; **on purpose** (decided: SPEC §8, a brief or the user); **in progress** (being built on the
Ex-Mac, per `docs/TASK-ios-reorder-and-selection.md` and `docs/TASK-ios-headings.md`); **accident** (diverges
without a decision); **missing**; **Mac-only** (Mac-only by nature).

### Selection, adding, editing

| Feature | Mac | iPhone | Status | Notes and citations |
|---|---|---|---|---|
| Select a row | Click selects; the detail pane follows (IX:426–441) | A tap opens the task's sheet (`Views/TaskRow.swift:84–86`) | on purpose | The SPEC §8 stack. The tapped row stays visibly selected while the sheet is open: **in progress** (reorder-and-selection §2) |
| Multi-select, ⌘A | ⌘-click, ⇧-click, ⌘A (`TaskListView.swift:1313`) | None | missing | Gap 6 |
| Arrow keys and type-to-select | IX:446–462 | None | Mac-only | No touch equivalent is needed; scrolling covers it |
| Add: trigger | ⌘N, the header +, a double-click on empty space (IX:470–480) | A floating + (`Views/RootView.swift:94–103`); Return adds the next one | on purpose | Touch adaptation |
| Add: where it lands | The bottom of the open tasks (IX:472) | The top (`AppModel.swift:351`) | on purpose | Already decided |
| Add: the draft | Opens in the detail pane, caret in its title (IX:490–506) | Inline row at the top (`TaskRow.swift:203–235`) | on purpose | Touch adaptation; Cancel in the bar (`ListScreen.swift:61–65`) |
| Add: a tap elsewhere | Writes the task, then does what was pressed (IX:525–534) | Only ends adding (`Components.swift:159–182`) | on purpose | SPEC §8 |
| Add in Today | The selected task's list, else the default; a group label's + adds to that list (IX:476–477) | Always the default list; no group + (`AppModel.swift:340–353`) | missing | Small: add a + to each Today and Undated group label |
| Add in Upcoming | The +'s day, else the selected task's day, else tomorrow; each day label has a + (IX:1307–1309) | Always tomorrow, with no per-day + (`AppModel.swift:348`) | missing | Small: a + on each day's label, for that day |
| Add in Completed and Trash | ⌘N adds in the default list (IX:1307) | No + (`AppModel.swift:34`) | on purpose | Reasonable on the phone: there's no ⌘N there |
| No lists left | Notice "Create a list first: ⇧⌘N" (`WindowActions.swift:341`) | The + does nothing (`RootView.swift:97`) | accident | Say something: "Create a list first" |
| Detail title | A wrapping field; Return or Tab commits and goes to the notes; Esc reverts; pasted line breaks become spaces (IX:596–608) | A vertical `TextField`; Return dismisses the keyboard (`TaskDetailView.swift:69–75`) | accident | Nothing replaces pasted line breaks, so a title can hold newlines (§3) |
| When edits are written | Once, only if changed (IX:628–646) | The same rule, through `EditSession` (`Model/EditSession.swift:8–11`, `TaskDetailView.swift:122–140`) | same | |
| Writing on leaving the app | Switching apps doesn't write (IX:644) | Going to the background writes (`App/TasksApp.swift:35–40`, `TaskDetailView.swift:114`) | on purpose | SPEC §8 |
| Edit tasks setting (detail or inline) | Settings ▸ Behavior (IX:555–570) | None | Mac-only | Phone titles edit only in the sheet |
| Detail: List, When, Deadline rows | A pop-up and large chips; × on hover; relative words in the deadline's tone (IX:765–773, IX:1750–1755) | The same rows; × always shown (`TaskDetailView.swift:234–310`) | same | Same words (`DateLabel`) |
| Detail: footer | "Created … · Completed …", plus " · 19,412 / 20,000" from 18,000 characters (`Detail/DetailPane.swift:434`) | "Created … · Completed …", with no counter (`TaskDetailView.swift:314–324`) | missing | Past 20,000 the core cuts the notes silently; the Mac warns (`Detail/NotesView.swift:703`) |
| Detail: several tasks, or a heading | "3 tasks selected", "Mixed"; a heading's summary (IX:344, IX:1535) | None | Mac-only | Comes with multi-select, if that's built |
| Zoom Pane, pane focus, Highlight focused pane, resizing | §29, §4 | None | Mac-only | The iPad shows a pane-focus look (`Views/RootView.swift:249–263`) |

### Completing, deleting, notices, undo

| Feature | Mac | iPhone | Status | Notes and citations |
|---|---|---|---|---|
| Check a box | Pop, spark, warm flash; the title is struck at once (IX:652–661) | Pop and a haptic, no spark; the strike waits for the settle, with the row at 75% opacity (`Views/TaskRow.swift:17`, `:35`, `:55`) | accident | Gap 10. The haptic is a good phone addition |
| Settle delay | 1.5 s after the last check (`Theme/TK.swift:344`) | 1.1 s, with no restart on another check (`AppModel.swift:205–209`) | accident | Each check runs its own timer, so a run of checks doesn't move together (IX:666–669) |
| Notice on completing | None | "Completed “…”" with Undo (`AppModel.swift:200`) | accident | Useful on a phone with no ⌘Z. Worth recording as a decision rather than undoing it |
| Swipe actions | None | Complete (leading); Delete and When (trailing); Put Back in Trash (`Views/ListScreen.swift:152–184`) | on purpose | The iOS idiom, in the iOS README |
| Delete | ⌘⌫, the menu, the trash button; the selection walks down (IX:696–699) | Swipe, the menu, the sheet's trash (`AppModel.swift:212–223`) | same | |
| Notice: when it shows | Delete, move out of a list, a date that takes a task out of a view, Delete List, Restore, Put Back, and undo or redo (IX:701–704; `WindowActions.swift:552–575`, `:648`) | Delete, complete, Delete List, Restore (`AppModel.swift:200`, `:220`, `:232`, `:270`, `:284`) | missing | Gap 1 |
| Notice: lifetime and text | 5 s with Undo, 1.8 s without; titles cut at 28 characters (`TK.swift:345–346`, `WindowActions.swift:47–51`) | 4 s for every notice; titles cut at 26 (`AppModel.swift:369`, `:380`) | accident | Small; align with the Mac |
| Notice: look | A box at the list pane's bottom right (IX:706–712) | A capsule floating above the + (`RootView.swift:161–185`) | on purpose | Touch layout |
| Undo and redo | ⌘Z and ⇧⌘Z for every step, with named actions; returns to the view and the selection (IX:717–724) | Only the notice's Undo (`AppModel.swift:374–378`) | missing | Gap 2 |

### Dates

| Feature | Mac | iPhone | Status | Notes and citations |
|---|---|---|---|---|
| How a row shows its dates | Quiet When after the title; a toned deadline capsule; the ring (§24; `RowDates.swift`) | The same pieces (`Views/Components.swift:263–311`) | same | |
| When hidden in Today and Upcoming | Only when it's ≤ today (Today) or the group's day (Upcoming) (`TaskListView.swift:345`) | Always hidden in both (`TaskRow.swift:68–74`) | accident | Gap 3 |
| Narrow rows | Title keeps 120, list name 72 (`TaskRowView.swift:442–443`) | × 1.3: 156 and 94 (`Theme/Metrics.swift:19–23`) | same | Scaled on purpose (520c4af) |
| Date picker: shape | A 240pt popover at the chip (§25) | A sheet (`Views/DatePickerSheet.swift`; `RootView.swift:56–58`) | on purpose | Touch adaptation |
| Picker: typed field | Yes (`DatePopover.swift:96`) | None | missing | Gap 4 |
| Picker: quick picks | Today, Tomorrow, Clear (`DatePopover.swift:134`) | Today, Tomorrow, This Weekend, Next Week, Clear (`DatePickerSheet.swift:114–134`) | on purpose | Without a field there's no "next" to type; the extra picks stand in |
| Picker: calendar | Endless weeks, sticky month, a Today pill, the week starting on the locale's first day (`DatePopover.swift:327`, `WeekCalendar.swift:54`) | Weeks from 26 back to 104 ahead; always starts on Sunday (`DatePickerSheet.swift:14–15`, `:25`, `:78`) | accident | Sunday is hard-coded. The bounded range is fine in practice |
| Picker: the footer line | Date · relative words, or "after the deadline" / "before the When" in `attention` (`DatePopover.swift:170–173`) | Date · relative words, with no note (`DatePickerSheet.swift:183–204`) | missing | Small |
| Quick dates from a menu | When ▸ Today, Tomorrow, This Weekend, Next Week, Choose Date…, Remove; Deadline ▸ Choose Date…, Remove (`Menus.swift:74–86`) | Today, Tomorrow, When…, Deadline… (`ListScreen.swift:200–203`) | on purpose | Fine on a phone; the sheet has the rest, including Clear |

### Moving, Trash, the views

| Feature | Mac | iPhone | Status | Notes and citations |
|---|---|---|---|---|
| Move to a list | ⇧⌘M, the menu, the List pop-up, a drag onto the sidebar (IX:728–741) | The menu and the List row (`ListScreen.swift:204–208`, `TaskDetailView.swift:234–262`) | same | No notice: gap 1. Dragging onto a list is out of scope (reorder brief) |
| Drag to reorder | §14, §23 | None | in progress | Reorder brief §1 |
| Upcoming: drag to reschedule | §22 (IX:1324–1338) | None | on purpose | Deferred ("later", reorder brief) |
| Today | Groups by list, a Completed group at the end that's open by default and kept (IX:923–939, IX:683–690) | Groups by list; Completed is a disclosure row, folded and not kept (`Model/Lines.swift:76–100`) | accident | Gap 8 |
| Today's done rows | Show the list's name (`TaskListView.swift:350`) | No name (`TaskRow.swift:77–82`) | accident | Small |
| Upcoming | Seven days, then months; the list name; "Due" on a deadline's own day (IX:1295) | The same groups and "Due" (`Lines.swift:106–132`, `Components.swift:291`) | same | Except the When (gap 3) and the per-day + |
| Undated | By list (IX:1296) | By list (`Lines.swift:137–150`) | same | No group + |
| Completed | By day, then month; month rows add the day ("School · Oct 22") (IX:1297) | By day, then month, with no day suffix (`Lines.swift:155–173`) | accident | The Mac's `whereSuffix` (`TaskListView.swift:351`) |
| Trash: tasks | Read-only; Put Back (⌘⌫, ↶); Put Back in ▸; "Put back “…” in Home" (IX:1340–1359) | Read-only; "Restore" (`AppModel.swift:226–235`; `TaskDetailView.swift:166–168`) | accident | The verb is Put Back for a task (`Window/DeletedLists.swift:12–31`); the iOS notice and banner say Restore. Put Back in is gap 7 |
| Trash: a deleted list's row | "11 tasks", "4 completed" or "Empty" (`TaskListView.swift:607–612`) | Counts open and completed tasks together (`TaskRow.swift:179`, `Lines.swift:195–197`) | accident | Small |
| Trash: opening a deleted list | A read-only list view in the detail pane with a Restore banner (IX:2172–2207) | Expand only (`TaskRow.swift:195–199`) | missing | Gap 7 |
| Trash: the header and empty text | No header text. Empty: "Deleted tasks and lists wait here until you put them back." (IX:1370) | Extra header line; the old empty text, "Deleted tasks wait here…" (`ListScreen.swift:91–95`, `Lines.swift:186`) | accident | Text changed in §28 |
| Delete List | ⌘⌫ or the menu; the next list opens; "Deleted School" (IX:913–917) | Home's long-press and the list's "…" menu (`Views/HomeView.swift:19–23`, `ListScreen.swift:233`; `AppModel.swift:258–273`) | same | The phone pops back to Home |
| Restore List | The banner, ↶, the menu, ⌘⌫ (IX:2212–2227) | Swipe, the menu, and the task sheet's banner (`ListScreen.swift:132–138`) | same | |

### Headings, notes, Markdown

| Feature | Mac | iPhone | Status | Notes and citations |
|---|---|---|---|---|
| Headings: show | Rule, air, chevron, a count when folded (IX:1404–1426) | Name, rule, a count always shown; no notes under it (`TaskRow.swift:109–126`) | in progress | The headings brief covers the chevron, folding, the count and notes |
| Headings: add, rename, fold, delete | §23 | None | in progress | `docs/TASK-ios-headings.md` |
| Headings: move a section | ⌥⌘↑↓, drag (IX:1501–1509) | None | in progress | Drag only (reorder brief) |
| Notes: editing | Live Markdown with the marks near the caret (MARKDOWN.md) | Rendered at rest, plain text while editing (`TaskDetailView.swift:365–403`) | on purpose | SPEC §8 |
| Notes: Return continues a list; Tab indents | MARKDOWN.md §6 (`NotesView.swift:188`, `:284`) | Plain `TextEditor` | on purpose | Follows from editing as plain text. Return-continues-a-list would be a cheap win (S) |
| Typing a box | `]` makes the box (MARKDOWN.md §5) | Plain text | on purpose | Same reason |
| Checklist toggle at rest | One op: "Check Item" or "Uncheck Item" (MARKDOWN.md §5) | The same (`TaskDetailView.swift:88–92`, `Views/MarkdownView.swift:170–176`) | same | |
| The row's notes hint | Glyph or "2/5" (MARKDOWN.md §7) | Glyph or "2/5" (`TaskRow.swift:90–106`) | same | |
| A list's notes | Edited in place (IX:1540–1546) | Shown, not editable (`ListScreen.swift:86–90`) | missing | Gap 5 |
| Pasting rich text, links over a selection | MARKDOWN.md §6 Pasting | The system's paste | Mac-only | Lower value on the phone |

### Lists, the sidebar, menus

| Feature | Mac | iPhone | Status | Notes and citations |
|---|---|---|---|---|
| Layout | Brand header; Today, Upcoming, Undated; Lists; Completed, Trash (IX:869–871) | The same on Home (`HomeView.swift:11–31`) | same | |
| Counts | Only Today has a count (IX:37–39, IX:857) | Every list shows its open count (`HomeView.swift:18`), and so does a list's large title (`ListScreen.swift:107–113`) | accident | The user removed list counts on 2026-10-31, and §23 says the title has "no count" (IX:1564) |
| New List | ⇧⌘N, the "Lists" +, the foot (IX:902–905, §27) | Home's bar opens an alert (`RootView.swift:107–139`, `:294–308`) | on purpose | The bar is the foot's analogue |
| Rename a list | In place: double-click, Return, the menu, the large title (IX:907, IX:1555) | An alert from the long-press or "…" (`HomeView.swift:20`, `ListScreen.swift:222`) | on purpose | Touch adaptation |
| Reorder lists | Drag, ⌥⌘↑↓, Move Up and Down (IX:910) | None | in progress | Reorder brief (Home drag) |
| A list's menu | New Task in X, Rename, Move Up, Move Down, Delete List (`Menus.swift:203–209`) | Rename, Delete List; the "…" adds Show/Hide Completed (`HomeView.swift:19–23`, `ListScreen.swift:216–240`) | missing | "New Task in X" is small; the moves come with drag |
| A task's menu | Show Details, Rename, Show in X, New Heading Above, Complete, When ▸, Deadline ▸, Move to ▸, Delete (`Menus.swift:57–93`) | Complete, Today, Tomorrow, When…, Deadline…, Move to, Delete (`ListScreen.swift:187–213`) | missing | Show in X is gap 9. New Heading Above is **in progress** |
| A Trash task's menu | Show Details, Put Back, Put Back in ▸ (`Menus.swift:127–136`) | Restore (`ListScreen.swift:192–195`) | missing | Gap 7 |
| Held-⌘ hints, ⌘1–⌘9 | IX:862, IX:1284 | None | Mac-only | |

### Sync, Settings, keyboard

| Feature | Mac | iPhone | Status | Notes and citations |
|---|---|---|---|---|
| Sync engine and triggers | Launch, the front, every 30 s, ⌘R | The same; pull to refresh is ⌘R (`Model/Sync.swift:86–111`) | same | SPEC §8 |
| Sync status | A cloud in the sidebar header with states, tooltips and timing (§26; `SyncIndicator.swift`) | A line of words under the views (`HomeView.swift:29`, `:77–92`; `Sync.swift:116–132`) | on purpose | In the iOS README. Gaps: the line isn't tappable (the Mac's opens Settings when the token is bad or sync is off), and it has no 300 ms or 5 s debounce, so it can flicker "Syncing…" on every edit |
| Sync stopped: VoiceOver | Announces it (`SyncIndicator.swift:229`) | Silent | accident | Small |
| Settings: Sync | Server, token, status, Sync Now | The same (`Views/SettingsView.swift:30–73`) | same | |
| Settings: Appearance | Theme, Interface style, Highlight focused pane (Mac `Views/SettingsView.swift:37–69`) | Appearance, Interface style (`SettingsView.swift:75–92`) | same | Highlight is Mac-only |
| Settings: Behavior, Data | Edit tasks; Show in Finder (Mac `Views/SettingsView.swift:71–92`) | About: version and counts (`SettingsView.swift:94–101`) | Mac-only | |
| Keyboard | Complete map, §17 | None: no `keyboardShortcut` or `UIKeyCommand` in `ios/` | Mac-only | Touch equivalents: ⌘N → +; ⌘K and Space → box or swipe; ⌘T and ⌘S → menu, swipe or sheet; ⇧⌘M → Move to; ⌘⌫ → swipe; ⌘D → tap; ⌘R → pull; Esc → Done or Cancel. A keyboard on an iPhone is rare, so no gap is ranked here |

### Look, motion, accessibility

| Feature | Mac | iPhone | Status | Notes and citations |
|---|---|---|---|---|
| Theme, tiles, accent | `TasksTheme` | `TasksTheme` (`Views/Components.swift:11–60`) | same | 1.3 × metrics, Dynamic Type |
| Glass | Settings ▸ Interface style (IX:403–418) | The same setting, with a wallpaper and Liquid Glass controls (`Components.swift:475–517`) | same | |
| Moments | Spark, flash, all-done sun and sunrise (`Theme/Moments.swift`) | None; the all-done state shows a static sun glyph (`Lines.swift:98`, `TaskRow.swift:238–254`) | missing | Gap 10 |
| Empty states | IX:930–939, IX:1361–1370 | The same titles; the list's says "Tap + to add one" (`Lines.swift:69`) | same | Except Trash's text (above) |
| Reduce Motion | Every duration 0 (IX:255) | `animate()` checks it (`Theme/Metrics.swift:61–64`), but the checkbox's keyframes, its `.animation` and the floating controls don't (`Components.swift:225–238`, `RootView.swift:90–91`) | accident | Gap 10 |
| Checkbox label | "Complete: Buy milk, overdue, planned for today" (`TaskList/TaskRowView.swift:510`) | "Complete" or "Completed" only (`Components.swift:240`) | accident | Small: add the title and `cue.words` |
| Notices for VoiceOver | Status messages (IX:1139) | `.updatesFrequently` with no announcement (`RootView.swift:182–183`) | accident | Post an announcement when a notice appears |
| Dynamic Type | None | Yes (`Metrics.swift:36–51`) | on purpose | Phone only |

---

## 3. Different by accident: likely bugs

Each is small unless noted.

1. **Rows drop the When in Today and Upcoming** whenever it isn't the date that placed them (`ios/Tasks/Views/TaskRow.swift:68–74`
   against `app/Tasks/TaskList/TaskListView.swift:345`).
2. **Lists show open counts** on Home and in the large title's subtitle (`ios/Tasks/Views/HomeView.swift:18`,
   `ios/Tasks/Views/ListScreen.swift:107–113`). The user removed list counts on 2026-10-31 (IX:37–39, IX:1564).
3. **The Trash verbs:** a task's Put Back reads "Restore" in the notice, the swipe, the menu and the banner ("Read-only until you restore it")
   (`ios/Tasks/Model/AppModel.swift:232`, `ios/Tasks/Views/TaskDetailView.swift:200`, `ios/Tasks/Views/ListScreen.swift:162`). The Mac
   says "Put back “…” in Home" and "Read-only until you put it back" (`app/Tasks/Window/DeletedLists.swift:24–30`, `:197`).
4. **Trash's empty text is the old one**, from before §28: "Deleted tasks wait here…" (`ios/Tasks/Model/Lines.swift:186`;
   IX:2292). The extra header line in Trash (`ios/Tasks/Views/ListScreen.swift:91–95`) isn't the Mac's either.
5. **A deleted list's count** includes completed tasks. The Mac counts open tasks, then shows "N completed" or "Empty"
   (`ios/Tasks/Views/TaskRow.swift:179`; `app/Tasks/TaskList/TaskListView.swift:607–612`).
6. **Checked rows:** the delay is 1.1 s, not 1.5 s, and a later check doesn't restart it, so a run of checks doesn't move as one. The strike
   also waits for the settle instead of coming at once (`ios/Tasks/Model/AppModel.swift:205–209`, `ios/Tasks/Views/TaskRow.swift:17`, `:35`; IX:660–669).
7. **Today's Completed starts folded**, and neither it nor a list's Completed row is kept across launches
   (`ios/Tasks/Model/AppModel.swift:73`; `app/Tasks/Window/WindowState.swift:134–147`).
8. **Today's done rows have no list name**, and Completed and Trash rows in a month group lack the day ("School ·
   Oct 22") (`ios/Tasks/Views/TaskRow.swift:77–82`; `app/Tasks/TaskList/TaskListView.swift:350–351`).
9. **The calendar always starts on Sunday** (`ios/Tasks/Views/DatePickerSheet.swift:25`, `:78`). The Mac uses the locale's first weekday
   (`app/Tasks/Overlay/DatePopover.swift:327`).
10. **Titles can hold line breaks.** Pasted ones are kept, since nothing replaces them (`ios/Tasks/Views/TaskDetailView.swift:69–75`, `:122–130`). Check on
    the simulator whether Return in that vertical field submits or inserts a newline. The Mac turns them into spaces (IX:599).
11. **Notices:** 4 s for all, not 5 s with Undo and 1.8 s without, and titles cut at 26 characters, not 28
    (`ios/Tasks/Model/AppModel.swift:369`, `:380`). A completion shows a notice the Mac doesn't (`:200`). Keep it, but record it as a
    decision.
12. **Reduce Motion** doesn't stop the checkbox's pop or the floating controls' animation
    (`ios/Tasks/Views/Components.swift:225–238`, `ios/Tasks/Views/RootView.swift:90–91`).
13. **VoiceOver:** the checkbox doesn't name its task or read the ring, notices aren't announced, and a stopped sync
    is silent (`ios/Tasks/Views/Components.swift:240`, `ios/Tasks/Views/RootView.swift:182–183`).
14. **Past 20,000 characters, notes are cut silently.** The Mac shows "Notes hold up to 20,000 characters" and the
    counter from 18,000 (`app/Tasks/Detail/NotesView.swift:703`, `app/Tasks/Detail/DetailPane.swift:434`).
15. **The + does nothing silently with no live lists** (`ios/Tasks/Views/RootView.swift:97`). The Mac says "Create a list first"
    (`app/Tasks/Window/WindowActions.swift:341`).

---

## 4. To improve later (noted by the user)

- **Dragging a heading can hover between tasks** (the user, 2026-11-03, on the phone at e13bc81). The built-in drag
  opens a gap inside a section, but a drop there is refused and the heading flies back. Nothing wrong is ever saved,
  and a valid drop moves the whole section. Better: only open gaps where a heading can land (before another heading,
  or at the end), as on the Mac (§23). The same goes for (c) below. This likely needs drag option B, our own gap
  (Ex-Mac, 2026-11-03).
- **Accepted with drag option A** (2026-11-03):
  - (a) the lifted row has the system's platter and shadow, not `fill-lift` and `shadow-lift`;
  - (b) a heading lifts alone, without its section folded in or the count badge;
  - (c) in Today and Undated, a row can hover over another list's group, and the drop is refused.
