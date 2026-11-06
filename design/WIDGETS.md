# Widgets for Tasks: a plan for the iPhone and the Mac

The user, 2026-11-05: "yea have a worker (on this mac) draft a widget plan for both. use claude design for mockups too."

This is a plan, not a build. Nothing in `app/`, `ios/` or TasksCore was changed. Neither app has widgets today: there's
no WidgetKit, App Intents or extension target in `app/project.yml` or `ios/project.yml`, on main or on origin/ios. The
only earlier mention is `docs/TASK-app-brainstorm.md:34`.

**Mock-ups (Claude Design):** https://claude.ai/artifact/D1JxGqB9hBm5cH1EeLiYRi. The canvas is private and hasn't been
shared. It holds the MVP widgets at their real sizes on an iPhone home screen, an iPhone lock screen and a Mac desktop,
each in light and dark (§6).

---

## 0. The short version

- **MVP, both platforms:** a **Today** widget (small, medium, large) whose rows you can check off, and a **List** widget
  (medium, large) for one list that you pick. On the iPhone, add the **lock-screen** accessories (inline, rectangular,
  circular) and a **New Task** control for Control Center and the lock screen. StandBy comes for free with the small
  widget.
- **The architecture decision:** **the app stays the only process that writes the store.** The widget reads a small
  *feed* file the app writes into a shared container. A check-off in the widget appends a ready-made op to an *inbox*
  file next to the feed. The app drains the inbox through `Store.perform`, so the op gets undo, `pending.jsonl` and sync
  like any other edit. The store doesn't move and its files don't change format, and the extensions never open
  `log.jsonl` or `pending.jsonl`.
- **The signing finding:** an App Group is the one entitlement this needs. **On the iPhone's free personal team, App
  Groups are uncertain:** reports from 2025–26 conflict, and some free-team profiles come back with an empty group
  list. **On the Mac, the ad hoc / "Tasks Local Signing" identity has no Team ID.** macOS 15 and later refuse a group
  container to a signature that can't back it, and an open report shows exactly that on macOS 27, which this Mac runs.
  So the first step is two small signing spikes, before any widget code (§3.5, §4 Q1).
- **Not planned:** Live Activities (tasks have dates, not times, so nothing is "in progress"), and an interactive
  Upcoming widget in the first cut.

---

## 1. The widget set

### 1.1 What each widget shows

All widgets use the app's own theme (`TasksTheme`: Rex's surfaces, the Ember accent, the lit tiles; `design/COLOR.md`)
and the app's row anatomy: the 16–18 pt ring box with its cue (red overdue, amber due today, `plan` blue for a When
today), the deadline capsule with `DateLabel`'s words ("2d ago", "Due today", "4d left"), and the list tile. Lists have
no counts (the user, 2026-10-31). Only Today shows one, as in the sidebar.

| Widget | Family | Shows | Tap targets |
|---|---|---|---|
| **Today** | small | Sun, "Today", the open count large; "1 overdue · 1 due" in their colours; the first two titles with their ring cue | The whole widget opens Today |
| | medium | Header (sun, "Today", count, +); the first 4 rows in Today's order, each with its box, title, deadline capsule and list tile | Box: complete. Row: open the task. +: new task in Today |
| | large | Header with the date; Today grouped by list (tile + name labels), as the app's Today; Completed at the end, struck, checked | As medium; a checked box un-completes |
| **List** (configurable) | medium, large | The list's tile and name; its open tasks in list order, with the When as quiet text and the deadline capsule. Headings show as a small label in large only | Box, row, +: new task in this list |
| **Lock screen** (iPhone) | inline | "☀ 6 today · 1 overdue" in the date line | Opens Today |
| | rectangular | "Today 6", then the first two titles with a word for the urgent ones ("2d ago", "Due") | Opens Today |
| | circular | A gauge of done / (done + open) today, the open count in the middle | Opens Today |
| | circular (New Task) | A + glyph | Opens the app on a new task |
| **Control** (iPhone, iOS 18+) | Control Center, lock screen, Action button | "New Task" (+) and "Today" (sun) | Opens the app there |

**When a row is checked in the widget:** it stays in place, struck and checked, until the next reload after the app
has drained it, and the large size keeps today's completed tasks in a Completed group. That's Today's own rule (a task
completed today stays in Today), and it's the widget's undo: a mis-tap is taken back by tapping the box again. The
medium size drops completed rows to make room. See §4 Q4.

**Empty and edge states:** "All done" with the lit sun when Today has nothing open (COLOR.md §4's moment, drawn
static). "No tasks" for an empty list. When the feed is missing, because the app has never run since the widget was
installed, the widget says "Open Tasks to set up". A deleted list in a List widget shows "This list is in Trash".

### 1.2 Per platform, ranked

| Rank | iPhone | Mac | Why |
|---|---|---|---|
| **MVP 1** | Today: small, medium, large | Today: small, medium, large (desktop and Notification Center) | The most-looked-at view. It's mostly read-only, so it proves the feed |
| **MVP 2** | Check-off from Today and List | Same | The main reason to have a widget instead of opening the app |
| **MVP 3** | List widget: medium, large | Same | A second view for the same code |
| **MVP 4** | Lock screen: inline, rectangular, circular | — | Cheap once the feed exists; the phone's most-seen surface |
| **MVP 5** | Control: New Task, Today | Later: the same controls, if the Mac's Control Center takes third-party controls on this macOS (check in spike 0b) | One small extension point; quick add |
| Later | Upcoming widget (the next 7 days, by day); extra large on iPad | Upcoming; extra large | Needs a design pass for days in a small box |
| Later | App Shortcuts and Siri (§2.4) | Same, and Spotlight | Separate from widgets. Do it with them, since the same App Intents serve both |
| Later | StandBy tuning (night mode in red) | — | The small widget already works in StandBy; tune it only if it reads badly |
| Later | Tinted and clear home screen styles: tuned accented rendering | Desktop's monochrome "vibrant" rendering behind windows | See §3.6. MVP must merely stay legible in both |

---

## 2. Interactivity and related surfaces

### 2.1 Checking off a task

- `Toggle(isOn:intent:)` with a `SetTaskCompletedIntent(taskID, completed)` (App Intents, iOS 17+ / macOS 14+). The
  intent sets an explicit state rather than flipping it, so two quick taps settle on the second one's state.
- **Where it runs:** a plain `AppIntent` behind a widget button runs **in the widget extension's process** by default
  (Apple, "Adding interactivity to widgets and Live Activities"). It can't reach the app's `Store`, so it writes to the
  inbox (§3.3).
- `perform()` builds the op the app would build, `task.update {completedAt: now}` or `{completedAt: null}`, with a fresh
  lowercase-UUID id, `actor: "widget"` and a `batch` id. It appends that op to the inbox and returns. The system then
  reloads the timeline, and the provider shows the feed with the inbox applied on top (an overlay, as `pending` is for
  the app), so the row is checked at once.
- Then the intent posts a Darwin notification (the `SyncNudge` pattern, `app/TasksCore/Sources/TasksCore/SyncNudge.swift`,
  under a name of its own, say `com.elguindi.Tasks.widget`, with Debug's `.dev.` suffix). A running app drains at once,
  which on the Mac is the usual case. On the iPhone the app is usually not running, so the op waits until the app
  next comes to the front. See §4 Q3.
- **Undo:** in the widget, tap again. In the app, the drain passes the window's `UndoManager`, so on the Mac ⌘Z undoes
  a widget check like any other ("Undo Complete"). On the phone it shows the completion notice with Undo (SPEC §8) if
  the drain happens while the app is in front.

### 2.2 Opening a list or a task

- Neither app handles a URL today (no `onOpenURL` or `CFBundleURLTypes` in either). Add one scheme to both:
  `tasks://today`, `tasks://upcoming`, `tasks://list/<id>`, `tasks://task/<id>`, `tasks://new?list=<id>`.
- `widgetURL` on the small widget and `Link` on each row and +. On the iPhone, `task/<id>` opens the list and then the
  task's sheet. On the Mac it selects the list and the task (the detail pane follows).
- `OpenIntent` with App Entities is the newer route, but it gives nothing extra here for more work. Use URLs.

### 2.3 Quick add

- **A widget can't hold a text field** on either platform. The + in a widget, the New Task control and the lock-screen
  circle all **open the app on a new task row** (`tasks://new?list=…`). On the phone that's the inline row at the top
  with the keyboard up. On the Mac it's the draft in the detail pane (IX §6).
- **A real quick add without opening the app** is the `AddTaskIntent` (title, optional list, optional When) from
  Shortcuts, Siri and the Action button (§2.4). It runs in the app's process, so it calls `Store.createTask` directly,
  with no inbox.

### 2.4 The related surfaces, decided together

| Surface | Decision | Why |
|---|---|---|
| **Control Center controls** (iOS 18+) | **Yes, in the MVP:** "New Task" and "Today", as `ControlWidgetButton`s that open the app. They also go on the lock screen's two bottom buttons and the Action button | Lives in the same widget extension; a few dozen lines |
| **Live Activities** | **No** | A Live Activity tracks something in progress with a live state and an end, like a timer or a delivery. Tasks have calendar dates and no times (SPEC §2), so there's nothing to tick. Activities also end after 8 hours, and pushing updates needs APNs, which a free team can't use. If a "focus on one task" session is ever wanted, revisit it then |
| **Shortcuts / App Intents** | **Later, but designed now:** `AddTaskIntent`, `CompleteTaskIntent`, `OpenListIntent`, `ShowTodayIntent`, with `TaskEntity` and `ListEntity` | The widget's `ListEntity` (for picking a list) is the same entity Shortcuts uses. Built once, and Shortcuts is the free win |
| **Siri** | Through **App Shortcuts** only ("Add a task in Tasks", "What's on my Today in Tasks"). No SiriKit | App Shortcuts don't need the Siri capability, so the free team isn't a blocker. The spike checks it |
| **Spotlight (Mac and iPhone)** | Later, with the entities | `IndexedEntity` comes with the App Entities |
| **Share sheet capture** | Out of scope here | Another extension and another App ID; a separate decision |

---

## 3. Architecture

### 3.1 Targets (xcodegen)

Both projects gain one extension target each. They share sources, not a target.

```yaml
# ios/project.yml (sketch)
targets:
  TasksWidgets:
    type: app-extension
    platform: iOS
    sources:
      - path: ../widgets/Shared      # views, provider, intents, deep links: shared with the Mac
      - path: Widgets                # iOS-only: lock-screen accessories, controls
    dependencies:
      - package: TasksCore           # the model, Today, DateLabel, Op (Foundation only)
      - package: TasksCore
        product: TasksTheme
    entitlements:
      path: Widgets/TasksWidgets.entitlements   # com.apple.security.application-groups
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.elguindi.Tasks.Widgets
        INFOPLIST_KEY_NSExtension: { NSExtensionPointIdentifier: com.apple.widgetkit-extension }
  Tasks:
    dependencies:
      - target: TasksWidgets          # embeds it
    entitlements: { path: Tasks/Tasks.entitlements }  # the same group
```

The Mac's target is the same shape in `app/project.yml`. It has `platform: macOS` and the **App Sandbox on for the
extension**, which WidgetKit requires: macOS won't list an unsandboxed widget. The app stays unsandboxed (SPEC §7).
Debug builds get their own extension bundle id (`com.elguindi.Tasks.dev.Widgets` on the Mac), so the Mac's Debug app
still can't touch Release data.

`widgets/Shared/` is a new top-level folder: the SwiftUI views, the timeline provider, the intents and the URL builder.
The views are plain SwiftUI and compile for both platforms. The few differences (sizes, the lock-screen families, the
controls) are `#if os(iOS)`.

### 3.2 Reading: a feed, not the store

**What exists:** the data lives in each app's own Application Support (`ios/Tasks/App/TasksApp.swift:51–61`,
`app/Tasks/AppModel.swift:125–133`). `Persistence` is built for one writer: it keeps its file handles, `logSize` and
`logCursor` in memory, and runs all I/O on one in-process serial queue
(`app/TasksCore/Sources/TasksCore/Persistence.swift:33–60`). After each sync, `pending.jsonl` is rewritten atomically
from the Store's in-memory list (`rewritePending`, `:290`).

**Options weighed:**

| | Option | Verdict |
|---|---|---|
| A | Move the store into the App Group and let the extension open it read-only | **No.** It migrates the user's live data, and a 10k-task snapshot (3–5 MB JSON, SPEC §8) plus the projection is a lot for a widget extension's small memory limit. Reading while the app writes also wants care. All of that cost buys one widget view |
| B | Let the extension open the store and write | **No.** Two writers break `Persistence`'s in-memory offsets, and the app's next `rewritePending` would silently drop an op the extension appended to `pending.jsonl` |
| **C** | **The app writes a small feed into the group container; the widget reads only that** | **Yes** |

**The feed** (`<group>/Tasks/widget-feed.json`, or `<group>/Tasks Dev/` for Debug, so Debug and Release stay apart as
their data folders do):

```jsonc
{
  "schema": 1,
  "written": 1793938000000,
  "lists":  [ { "id": "…", "name": "School", "order": "a0", "slot": 0 } ],       // live lists, sidebar order
  "tasks":  [ /* TaskItem values, the Codable model itself */ ],
  "listTops": { "<list id>": ["<task id>", …] }                                   // first 12 open, in order
}
```

- **Which tasks:** every live open task whose When or deadline is on or before **today + 14** (Today for the next two
  weeks of timeline entries, and Upcoming later), every task completed today, and each live list's first 12 open
  tasks. That's a few hundred tasks at most, tens of KB.
- **The widget computes the views itself** with TasksCore's pure code: `Today.contains` (`Today.swift:35`),
  `DeadlineStatus`, `DateLabel` and `ViewGroups`. So **midnight needs no app.** The provider returns entries for now and
  for each of the next three local midnights, and Today rolls over on time even if the app hasn't run for days.
- **Written by each app** after any change to visible state, debounced 1 s, and after a sync that applied entries. It's
  written atomically (temp file, then rename), the way the snapshot is.

### 3.3 Writing: an inbox the app drains

- **`<group>/Tasks/widget-inbox.jsonl`**: one `Op` per line, in TasksCore's own JSON, built by the intent (§2.1).
  Appends take an `flock` on the file, or use `NSFileCoordinator`. Either works across processes in one container.
- **The provider's overlay:** decode the feed into a small `AppState`, `apply` each inbox op (the reducer, as is), then
  compute the view. The widget shows its own taps before the app has seen them.
- **The drain** (in each app): on launch, on becoming active, and on the widget's Darwin nudge.
  1. Lock, read the lines, unlock.
  2. `store.perform(ops, undoManager: window's, actionName: "Complete")`. `perform` keeps each op's id and `at`
     (`Store.swift:139–181`; it only sets `actor`/`batch` when attribution is on). So the op the widget built is the op
     that syncs.
  3. Lock, remove the drained lines (keeping any appended since step 1), unlock. Then write the feed and reload the
     timelines.
  - A crash between 2 and 3 performs the same op ids again. That's harmless: the server dedupes by id (SPEC §5), and
    pending drops every line whose id comes back in the log. The values are the same, so the overlay doesn't change.
- **Ops that no longer apply:** if the task was deleted on the Mac meanwhile, the update is ignored by the reducer, as
  any late update is (SPEC §5 rule 3).

**Later, on the iPhone only (§4 Q3): push-through.** The intent could also send its op straight to the server with
`POST /v1/sync {from: feed.cursor, base: feed.hash, ops: [op]}`, using a token shared through a Keychain access group.
The server accepts it whenever that base is still in its chain, which is always unless it was wiped. The extension
ignores the entries that come back, and the app later pulls the op from its own cursor and drops it from pending as
usual. The Mac would see the check within its 30 s tick, without the phone app ever opening. That costs the token in
the extension, a network call in a widget tap, and the feed carrying `cursor` and `hash`. It's not in the MVP.

### 3.4 Keeping it fresh

- **From the app:** `WidgetCenter.shared.reloadAllTimelines()` after each feed write. That covers local edits, syncs
  that brought other devices' changes, drains and day changes (`Store.refreshDay`). Reloads requested while the app is
  in front don't count against the widget's daily budget. Neither do the reloads the system does after a widget's own
  intent.
- **From the timeline:** entries at the next midnights (§3.2), `policy: .atEnd`.
- **Without the app (iPhone):** nothing refreshes the feed while the app is closed, so a change made on the Mac shows
  on the phone's widget at the next phone-app open. That follows from SPEC §8 ("nothing in the background"). A
  background refresh (`BGAppRefreshTask`) could sync and rewrite the feed a few times a day. It's listed in §4 Q3.
- **Mac:** the app runs most of the time, syncs every 30 s while a window is open, every 60 s with none (Settings ▸ Sync
  with no window open, on by default; 2026-11-06), and on the CLI's nudge, and rewrites the feed when it changed (at most
  every 2 minutes with no window, for WidgetKit's reload budget). Settings ▸ Open at login keeps it running after a
  restart. So Mac widgets stay current, and an agent's `tasks` CLI change reaches the desktop widget in about
  a second.

### 3.5 Signing

**iPhone (free personal team, 7-day profiles):**

| Need | Free team? | Notes |
|---|---|---|
| A widget extension | Yes, with limits | A second App ID (`com.elguindi.Tasks.Widgets`). Free teams are reported to be capped at **10 App IDs per 7 days**, which is a one-off cost here. Sideloading tools report that extensions count toward the **3-apps-per-device** limit. Check both in the spike |
| **App Groups** | **Uncertain: the gate** | Apple's capability table is read both ways. Recent reports conflict: one tool registers one group per app on a free team, while other projects found free-team profiles with an **empty group list** and failed to sign. **Spike first** |
| Interactive widgets, controls, App Intents, App Shortcuts | Yes | No extra entitlement |
| Keychain sharing (push-through only) | Reported to work on free teams | One project fell back to it for widget data when App Groups failed. It's awkward for a feed, but fine for a token |
| Push (APNs), Live Activity push | No | Not needed |

The 7-day expiry covers the extension too: when the profile lapses, the app and its widgets stop together, and a
rebuild from Xcode renews both. It's worth checking in the spike whether widgets placed on the home screen survive
that reinstall or have to be added again.

**Mac (ad hoc, or the self-signed "Tasks Local Signing"; no Team ID; `app/Signing.xcconfig`, `app/project.yml`):**

- The widget extension **must be sandboxed**, and it can only read the feed through a container both sides may open.
- On macOS 15 and later, a group container is refused, or the user is prompted, unless the group id is prefixed with
  the signing Team ID or a provisioning profile authorises it. An ad hoc signature has neither. One open report shows
  exactly this on **macOS 27** ("app-group container access rejected for ad hoc signed app and extension"), which is
  what this Mac runs (Darwin 27).
- Options are in §4 Q1. In short: sign the Mac app and extension with the same free Apple ID's **Apple Development**
  certificate (a Team ID, and a `<TEAMID>.com.elguindi.Tasks` group), or pay for the Developer Program, or skip a Mac
  extension and use **iPhone widgets on the Mac desktop** (macOS 14+ shows a nearby iPhone's widgets, and their buttons
  run on the phone).
- Re-signing the Mac app changes its designated requirement, so the Keychain item `com.elguindi.Tasks.sync` asks for
  access once again. The CLI reads that item too (`app/TasksCore/Sources/TasksCLI/Replica.swift:102`). That's a
  one-off, as the move to "Tasks Local Signing" was.

### 3.6 Look

- Colours come from `TasksTheme` (`Theme.rex`, `app/TasksCore/Sources/TasksTheme/Theme.swift:261`) through each app's
  existing colour adapter. The widget follows the system appearance. The app's own Appearance setting is per app, and
  the feed can carry it if wanted (§4 Q6).
- **iOS tinted and clear home screens, the Mac desktop's dimmed state:** WidgetKit renders in `accented` or `vibrant`
  mode there. The MVP must stay legible in them: the ring cues carry words as well as colour (as COLOR.md requires), the
  tiles get `widgetAccentable`, and the sun stays the accent group.
- Type: SF Pro, titles 14 pt on iPhone and 13 pt on the Mac; capsules 11 pt medium; tiles SF Mono, as in the app.

### 3.7 What TasksCore would need (not changed now)

All of it is **additive**, and the store's files and formats don't change:

1. **`WidgetFeed`**: the feed's `Codable` shape, `make(from: Projection, day:)` and `read/write(at:)`. Foundation only.
   It belongs in TasksCore (or a new Foundation-only target in the same package) because both apps write it and both
   extensions read it.
2. **`WidgetInbox`**: append with a lock, read, and remove-drained. Foundation only.
3. A **Darwin name** for the widget's nudge, next to `SyncNudge`'s.
4. Possibly a `Store` helper to perform ops built elsewhere, if the drain needs anything beyond `perform` (it doesn't
   seem to: §3.3).
5. Nothing in `Persistence`, the reducer, `Op`, sync or the snapshot.

The WidgetKit, SwiftUI and App Intents code stays out of TasksCore, in `widgets/Shared/`, so TasksCore and the CLI
don't link UI frameworks.

### 3.8 Shared between iOS and the Mac

| Shared | Per platform |
|---|---|
| Widget views, the provider, `SetTaskCompletedIntent`, `ListEntity`, the URL scheme (`widgets/Shared/`) | iPhone: lock-screen accessories, controls. Mac: nothing extra |
| `WidgetFeed`, `WidgetInbox`, the nudge name (TasksCore) | The feed writer and the drain hook in each app's model (`ios/Tasks/Model/AppModel.swift`, `app/Tasks/AppModel.swift`) |
| `TasksTheme` | Each app's colour adapter (existing) |
| — | Entitlements, bundle ids and signing |

---

## 4. Risks and open questions for the user

**Q1. Signing: how should the apps get an App Group?** *(blocks everything; decide after the spikes)*

- **A. Free team on both:** keep the iPhone's free team, and sign the Mac app and its extension with the same Apple
  ID's Apple Development certificate. Costs nothing. The Mac asks for the Keychain once. It only works if the spikes
  show free teams can hold a group, and the Mac may then also face 7-day profiles.
- **B. Apple Developer Program ($99/year):** App Groups are certain on both, profiles last a year instead of 7 days,
  and TestFlight opens up. It costs money, and the Mac moves off "Tasks Local Signing" either way.
- **C. iPhone only, for now:** build the iPhone widgets on the free team if the spike passes. On the Mac, add the
  iPhone's widgets to the desktop (macOS 14+), with no Mac extension at all. They show the phone's data, and checking
  one off runs on the phone when it's nearby.
- **Recommendation: spike first (S each), then decide.** If the iPhone spike passes, start with **C** and choose
  between A and B for the Mac once the Mac spike is in. If the iPhone spike fails, the honest options are B, or no
  widgets.

**Q2. Is a new feed file and an inbox file acceptable, with the app as the only writer?** *(the key decision)*

- **A. Feed plus inbox, the app drains (recommended).** Nothing in the store moves or changes, and undo and sync are the
  app's own. The cost is that a phone check waits for the phone app to open before it syncs (Q3).
- **B. Move the store into the App Group and let the extension write through `Store`.** The widget's writes would be
  immediate, but it migrates live data and needs `Persistence` made multi-process (locks, re-reading offsets). That's
  a large change to code the user is careful about.
- **C. Route the widget's intent into the app's process** (iOS: an intent adopting `LiveActivityIntent` runs in the
  app's process even from a widget). The real Store would write and sync at once, but it leans on a protocol meant for
  something else, the app is launched in the background on every tap, and it's iOS-only.
- **Recommendation: A**, and try C in the iPhone spike as a possible later upgrade to it.

**Q3. Is "a check on the phone's widget reaches the Mac when the phone app next opens" acceptable for the MVP?**

- **A. Yes, for now.** It's the simplest, and the same as the phone app's sync today (SPEC §8: nothing in the
  background).
- **B. Push-through** from the extension (§3.3): it reaches the Mac within 30 s. Cost M: the token in a shared
  Keychain group, and a network call per tap.
- **C. Background refresh** (`BGAppRefreshTask`): it also keeps the phone's widget fresh for changes made on the Mac,
  but iOS runs it rarely and on its own schedule.
- **Recommendation: A for the MVP, then B** if the delay bites. B is the only one that makes it prompt.

**Q4. A task checked in the widget: should it stay, struck, or leave?**

- **A. It stays, struck, until the day ends (large size: in the Completed group); medium drops completed rows.** It
  matches Today's rule, and it's the undo.
- **B. It leaves on the next reload**, as the app's rows settle after 1.5 s. The widget stays tidy, but a mis-tap
  can't be taken back from the widget.
- **Recommendation: A.**

**Q5. Which Today rows does medium show, and in what order?** Today's own order (by list, in sidebar order) or most
urgent first (overdue, then due today, then the rest)?

- **Recommendation: Today's own order**, so the widget is the app's Today in miniature. The ring colours already pull
  the eye to the urgent ones. The mock-ups happen to show both orders at once, since School is first.

**Q6. Appearance: should the widget follow the system, or the app's Appearance setting?**

- **Recommendation: the system.** A widget that ignores Dark Mode looks broken next to the others. The app's setting
  can carry over later through the feed if the user wants it.

**Q7. Should TasksCore get `WidgetFeed` and `WidgetInbox`?** *(asked because of the user's care about TasksCore)*

- **A. Yes, as new files in TasksCore (recommended).** It's additive and Foundation-only, and both apps and both
  extensions share it.
- **B. A new target in the same package** (`TasksShared`). It's the same code, kept away from the core proper, at the
  cost of one more product in `Package.swift`.
- **C. Copied into each app.** It would drift, so no.

**Other risks:**

- **The widget memory limit** is small and undocumented. The feed keeps the extension's working set to tens of KB plus
  SwiftUI. Test with the 10k-task fixture (SPEC §8's benchmark) to confirm the feed stays small.
- **Undo across devices:** a check undone in the Mac app after the phone's drain is a new op (SPEC §6), as with any
  undo. Nothing new.
- **Headings** (§23) never arrive in Today (`Today.datesArrived`). The List widget shows them as labels in large and
  skips them in medium.
- **Time zones:** the widget computes Today with the extension's calendar, which is the device's, as the app does.

---

## 5. Effort and order

| # | Piece | Size | Depends on |
|---|---|---|---|
| 0a | **Spike, iPhone:** a free-team build with an empty widget extension and an App Group, on the iPhone 15. Does it sign and install, can both processes read one file, and do the App ID and app limits hold? Also try `LiveActivityIntent` routing (Q2 C) and App Shortcuts without the Siri capability | S | — |
| 0b | **Spike, Mac:** a sandboxed widget extension and an App Group signed (i) as today, ad hoc, and (ii) with an Apple Development certificate, on macOS 27. Does the widget appear in the gallery, and can it read the group? | S | — |
| 1 | TasksCore: `WidgetFeed`, `WidgetInbox`, the nudge name, with tests (the feed against `Today` for a fixed day; the inbox's append and drain under two writers) | M | Q7 |
| 2 | iPhone: the extension target, feed writing in `AppModel`, Today small, medium and large (read-only), deep links and the URL scheme | M | 0a, 1 |
| 3 | Check-off: `SetTaskCompletedIntent`, the overlay, the drain on both apps, the nudge | M | 2 |
| 4 | List widget with `ListEntity` (configuration) | S | 2 |
| 5 | Lock-screen accessories, controls (New Task, Today) | S | 2 |
| 6 | Mac: extension target, sandbox, feed writing in the Mac `AppModel`; the shared views at Mac sizes | S–M (L if signing has to change) | 0b, Q1, 2 |
| 7 | App Shortcuts: `AddTaskIntent`, `ShowTodayIntent`, entities shared with the widget | M | 4 |
| 8 | Later: push-through (Q3 B), Upcoming widget, rendering-mode polish, StandBy | M each | 3 |

**Suggested order:** 0a and 0b together, then **Q1** with their results, then 1 → 2 → 3 on the iPhone (the first thing
the user can hold: a Today widget that checks off), then 4 and 5, then 6 on the Mac, then 7.

---

## 6. The mock-ups

https://claude.ai/artifact/D1JxGqB9hBm5cH1EeLiYRi (Claude Design canvas, private). Data: six open tasks today across
School, Home and Inbox, and one done. The colours are `Theme.rex`'s (Ember `#E6683D` dark, `#B1502F` light; `plan`
blue; danger and attention as in COLOR.md §1).

| Board | Shows |
|---|---|
| MVP widgets, every size | Today small, medium and large, and List medium, at the iPhone's sizes (158, 338 × 158, 338 × 354 pt), dark above and light below |
| iPhone home screen, light / dark | Light: Today medium, and Today small beside app icons. Dark: Today large and List (School) medium |
| iPhone lock screen, light / dark | Inline in the date line, the rectangular Today, the circular gauge and the circular New Task; the two bottom controls (New Task, Today) |
| Mac desktop, light / dark | Today large, medium and small, and List medium, at the Mac's sizes (170, 364 × 170, 364 × 382 pt) |
| Components | Each widget on its own, with Tweaks for dark and Mac sizing |

What they don't show yet: the tinted and clear home-screen styles, the Mac's dimmed desktop rendering, StandBy, and
the empty states.

---

## Sources

- Apple, interactive widgets and where an intent runs:
  [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities),
  [Widgets, Live Activities and controls](https://developer.apple.com/documentation/appintents/widgets-live-activities-and-controls).
- Free-team App Groups, for and against:
  [xtool PR #284](https://github.com/xtool-org/xtool/pull/284) (one group per app on free teams),
  [Plantry PR #23](https://github.com/destromoose/plantry/pull/23) (empty group list; fell back to keychain sharing),
  [Zudo: signing with a free personal team](https://zudo-tauri-wisdom.takazudomodular.com/docs/mobile/ios-signing-free-team/),
  [Expo: free vs paid](https://expo.dev/blog/apple-developer-program-explained-free-vs-paid) (7 days, 3 apps).
- Mac ad hoc signing and group containers:
  [Limitwick #8](https://github.com/frankydzoro/Limitwick/issues/8) (empty widget on macOS 27, ad hoc),
  [little-orbit #84](https://github.com/neo-the-on3/little-orbit/issues/84),
  [widgetkit_macos](https://github.com/hinata-platform/widgetkit_macos) (sandbox and profile requirements).
- These are third-party reports, and they conflict. That's why §5 starts with spikes on the user's own devices.
