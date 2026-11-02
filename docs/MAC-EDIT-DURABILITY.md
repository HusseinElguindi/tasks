# Mac edit durability (2026-11-02)

The question (docs/TASK-mac-edit-durability.md): can the Mac lose an in-progress edit, as iOS could? **Yes, in
three ways.** ⌘Q, logout and restart lose any field that is being edited. Closing the window loses every
rename-in-place field. Sync arriving while a field is open gets its change reverted, even if the user typed nothing.
Nothing is debounced: every field writes one op when its session ends, so a crash loses everything typed since the
session began. Once an op is committed it reaches the disk reliably.

**Status: fixed in `app/Tasks` (fixes 1–3 below, approved by the user 2026-11-02; fix 4 skipped).** "The fix" at the end
says what changed and shows the same cases again. The rule is now in design/INTERACTIONS-v2.md §7, When an edit is
written. Everything up to "The fix" is the investigation as it was, before the change.

## How each field commits

| Field | Text lives in | Becomes an op when |
|---|---|---|
| Detail title, existing task | the `InlineField` (`Detail/TitleField.swift`) | its field editor ends (`onEnd` → `finish()`, :36, :177), or the view leaves its window (`viewWillMove(toWindow: nil)`, :100) |
| New task (draft) | `WindowState.draft` (`WindowActions.setDraftTitle`, :353) | the same `finish()` → `commitDraft()` (:359): one `task.create` |
| Notes: detail pane, list notes, heading notes | the `NotesTextView` (`Detail/NotesView.swift`) | `resignFirstResponder` (:44) or `viewWillMove(toWindow: nil)` (:50) → `endEditing()` (:650): one `task.update`/`list.update` |
| Task rename in the list (Edit tasks: Inline), new heading, heading rename, list title in the list pane, list rename and new list in the sidebar | `WindowState.rename.text` (`setRenameText`, WindowActions.swift:426) | the field's `controlTextDidEndEditing` (`Theme/InlineField.swift:107`) → `commitRename()` (WindowActions.swift:433), or an action that calls `endEdits()` (:136). The sidebar defers the commit a turn (`SidebarView.swift:565`). None of these fields has a `viewWillMove` hook. |

The date popover's typed phrase is the only other text field. It is a picker, not content, and is left out here.

Persistence: `Store.perform` hands each op to `Persistence.appendPending` (Store.swift:168). That queues a
`write(2)` on a serial utility queue (Persistence.swift:52, :280–285), so the op reaches the kernel within
microseconds. `didResignActive` and `willTerminate` both call `persistNow()` (AppModel.swift:221–225,
Store.swift:215), which writes the snapshot and waits for the queue (`flush`, Persistence.swift:393). Nothing
calls `fsync`/`F_FULLFSYNC`, and the `.atomic` rewrites (:257, :302) don't either.

## Results

Unless a row says "code", each result was observed with the Debug build (`Tasks Dev`) on scratch data directories. The
test typed through `-debugScript` and then read `pending.jsonl`. ⌘Q is the script's own `NSApp.terminate`. Logout is
a quit Apple event sent to that process (`NSRunningApplication.terminate`). Close is an Accessibility press on that
window's close button. Sync ran against a local `wrangler dev` with the Debug `tasks` CLI as the other replica.

| Field | ⌘Q, logout, restart | Close window | Switch app | Sleep | Crash / `kill -9` | Sync changes it mid-edit |
|---|---|---|---|---|---|---|
| Detail title (existing) | **Lost** (ran ⌘Q and logout) | Safe | Kept in memory (code) | Safe (code) | **Lost since session began** | **Remote change reverted**, typed or not |
| New task (draft) | **Lost**: no task is created | Safe | Kept in memory (code) | Safe (code) | **Lost** | n/a (new id) |
| Detail notes | **Lost** | Safe | Kept in memory (code) | Safe (code) | **Lost since session began** | **Remote change reverted** |
| List / heading notes (list pane) | **Lost** (code: same view as the detail notes) | Safe (code) | Kept in memory (code) | Safe (code) | **Lost since session began** | **Remote change reverted** (code) |
| Inline task rename | **Lost** | **Lost** | Kept in memory (code) | Safe (code) | **Lost** | **Remote change reverted** |
| New heading / heading rename | **Lost** | **Lost** | Kept in memory (code) | Safe (code) | **Lost** | Reverted (code: same path) |
| List title rename (list pane) | **Lost** | **Lost** | Kept in memory (code) | Safe (code) | **Lost** | Reverted (code: same path) |
| Sidebar list rename / new list | **Lost** | **Lost** | Kept in memory (code) | Safe (code) | **Lost** | **Remote change reverted** |
| Any committed op | Safe: flushed in `willTerminate` | Safe | Safe: flushed on resign | Safe | Safe once written: present 1.5 s after commit; lost only in the µs before the queued write | — |

Evidence for each column:

- **⌘Q / logout.** AppKit's terminate never ends editing or takes views out of their windows. The responder chain
  never changes, so no hook fires. The flush in `willTerminate` writes only ops that were already committed. Each
  field above was edited and then quit, and none left an op. Ending the edit first (`act:commit`) and then quitting
  leaves the op. A quit Apple event to the same process behaves the same way. The app turns on neither sudden nor
  automatic termination (no Info.plist keys and no API calls), so logout and restart take this terminate path rather
  than a SIGKILL.
- **Close.** Removing the window runs the `viewWillMove(toWindow: nil)` hooks of the title and notes views, so
  they commit. The rename fields are torn down with their `WindowState`, and their pending `rename` goes with them.
  The app keeps running after the window closes (verified), but that text is gone.
- **Switching apps and sleep.** Neither event ends the field editor. The resign observer persists only committed ops.
  The text survives as long as the process does, so it is lost if the Mac then quits, logs out or loses power.
- **Crash.** No field writes before its session ends, so the whole session is lost, not a debounce window.
- **Sync mid-edit.** While a session is open the field ignores model updates (TitleField.swift:124,
  NotesView.swift:584, the reused rename fields at TaskListView.swift:925 and :986). At the end it compares the field's text
  with the model's current value, not with the value the session started from (TitleField.swift:194,
  NotesView.swift:665/:669, WindowActions.swift:438/:446/:452/:466). After a remote change those differ even if the
  user typed nothing, so the stale text is written back. Observed: the caret sat in a title, the CLI renamed the task
  to "Remote1", the app synced (its row showed "Remote1"), then the edit ended. The server ended at "T1". The same
  happened for notes, where the history shows `agent:check Edit Notes` followed by `app Edit Notes`, for the inline
  rename and for the sidebar list rename. When the user did type, their text wins over the concurrent remote edit,
  as last-writer-wins would. In code only: if the task is deleted remotely mid-edit, the title or notes edit is
  dropped silently (`!t.deleted`).

## Recommended fixes (smallest first, all in `app/Tasks`; none touch TasksCore)

1. **Revert on sync (the worst one: it loses other devices' edits with no input).** Commit only if the text differs
   from where the session started. `TitleFieldView.Session.original` and the notes `session.original` already exist;
   compare against them in `finish()` and `endEditing()`. Add an `original` to `WindowState.Rename`, set it in
   `startRename`, `startListRename` and similar, and compare against it in `commitRename`. A few lines.
2. **⌘Q, logout, restart.** Before `persistNow()` in the `willTerminate` observer (AppModel.swift:224), run
   `WindowActions.endEdits()` for each open window. That needs a weak list of the live `WindowState`s. Call
   `commitRename` directly, because the sidebar's deferred `onEnd` would run too late. `endEdits` already
   resigns the field editor, which commits the title, draft and notes.
3. **Close window.** Call the same `endEdits()` when the window closes (`NSWindow.willCloseNotification` for that
   window, or `viewWillMove(toWindow: nil)` on the three rename fields, as `TitleFieldView` has).
4. **Optional: crash after switching away.** On `didResignActive`, write the open field's text as an op without
   ending the session, and move the session's `original` to it. The caret stays, the iOS `.inactive` fix gets its
   Mac counterpart, and a crash or power loss then loses only what was typed since the app was last frontmost. It
   costs a second undo step ("Edit Notes") per session that spans a switch. I'd do 1–3 now and this one only if that
   trade is acceptable.

Durability below the app (no `fsync` of `pending.jsonl`) can lose the last few seconds on a kernel panic or power
cut. Ops sync about 1 s after they're made, so I don't recommend a TasksCore change for it.

## The fix (2026-11-02)

All of it is in `app/Tasks`. TasksCore is unchanged.

- **Sync revert (fix 1).** `Window/EditSession.swift` has the rule for every field: write only if the text differs
  from where the session began, and from the model's value now. The detail title (`TitleFieldView.finish`) and the
  notes (`NotesField.Coordinator.endEditing`) compare against the `original` their sessions already kept.
  `WindowState.Rename` gains `original`, set by `startRename`, `startListRename`, `startHeadingRename` and
  `startTitleRename`, and `commitRename` compares against it. When nothing is written, the title and the notes show
  the model's value, which may be one that synced in. Esc on an existing title puts back the model's title rather
  than the session's original.
- **Quit, logout, restart (fix 2).** `WindowState.windows` is a weak list of the main windows' states. The
  `willTerminate` observer (AppModel.swift) calls `WindowActions.endAllEdits(store:)`, which runs `endEdits()` in
  each window, before `persistNow()`.
- **Close window (fix 3).** `MainLayout` runs `endEdits()` on its window's `NSWindow.willCloseNotification`
  (RootView.swift).
- **Tests.** `TasksTests/EditSessionTests.swift` (8 cases) covers the rule, and `EditSession.swift` is compiled into
  the logic-test bundle (project.yml).

The same cases, re-run with the Debug build the same way as above (own data directories, `-debugScript`, a quit
Apple event, an Accessibility close, and `wrangler dev` on 127.0.0.1:8791 with a throwaway token and the Debug CLI):

| Case | Before | After |
|---|---|---|
| ⌘Q mid-edit: detail title, new task, detail notes, inline rename, new heading, new list, sidebar list rename, list title | nothing written | each writes its op (`task.update`, `task.create`, `task.update` notes, `task.update`, heading `task.create`, `list.create`, `list.update` ×2) |
| ⌘Q with the caret in the title and then the notes, nothing typed | nothing | nothing (no spurious op) |
| Quit Apple event (logout / restart) mid-edit, detail title | nothing written | `task.update` "AlphaXYZ" |
| Close window mid-edit: the four rename fields and a new heading or list | lost | each writes its op. The title, notes and new task still do. |
| Sync renames T1 while the caret sits in its title, untouched | server back to "T1" | server keeps "Remote1", and the field shows "Remote1" |
| The same for notes, the inline rename, the sidebar list rename and the list's large title | reverted | the remote value stays (notes history: no `app` write) |
| Typed "Y" into T2 while a remote rename arrived | "T2Y" | "T2Y" (typed text still wins) |
| Esc on a title after a remote rename | field showed the stale title | field shows "Remote6", nothing written |

Builds and tests: Debug and Release build into `app/.build/DerivedData`. `xcodebuild test` passes the app's logic
tests (16, the 8 new ones included). `swift test` in TasksCore passes 176 tests (1 skipped, the live-server one) and
the CLI's 36.

Still not covered, by decision: a crash, `kill -9` or power loss while a field is open loses that session, and
switching apps doesn't write the open field (fix 4, skipped).
