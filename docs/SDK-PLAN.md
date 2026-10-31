# Tasks agent CLI and code mode: plan

Status: revised plan, 2026-10-31. Briefs: `docs/TASK-sdk-plan.md`, then `docs/TASK-sdk-plan-swift.md`. The user
accepted every recommendation of the first version (`c54b00a`) with two changes: everything runs on this Mac, and the
core is Swift, not a TypeScript port. Nothing here is built yet; three throwaway spikes settled the open technical
questions (§1, §6).

The end goal is agents using Tasks. Every agent interface here is a front end on one Swift executable, `tasks`, built
on the app's own `TasksCore`. It's just another replica of the log, like a second Mac, so the reducer, the sync loop,
the error table, 409 recovery, ordering, dates and Today are the app's code, not a copy of it. The server stays a dumb
log. The one change it needs is two optional envelope keys that the reducer ignores, `actor` and `batch`.

## Summary

- **One Swift executable, `tasks`, a new target in `app/TasksCore`.** It links `TasksCore` and drives the same `Store`
  the app does, on its own data directory. A spike showed `Store` runs unchanged in a command-line binary. `TasksCore`
  needs four small additions (§1), none of them on the app's hot paths.
- **No port, so no drift.** There is one reducer. What the app shows, the CLI computes with the same code: Today, the
  orders of every view, what "fri" means.
- **Two front ends, built in this order:**
  - **The `tasks` CLI**, for agents with a shell and for people. Every UI operation is a command, one command is one
    undoable change, `--json` prints the same objects code mode returns, and short refs work like Git's.
  - **Code mode, `tasks run`.** The model writes a TypeScript script against `tasks.d.ts`. It runs in a Deno child
    process with no permissions, where a ~40-line JS bridge sends each `tasks.*` call over stdio to the Swift host.
    One run is one change: atomic, previewable with `--dry-run`, and undoable. `tasks mcp` wraps it as a two-tool
    local MCP server.
- **One table drives every surface.** A single Swift table of commands (names, parameters, types, docs) produces the
  argument parser, `tasks help`, the code-mode dispatch and `tasks.d.ts`, so they can't drift apart.
- **One change is one batch: one sync request, appended atomically, undone as a unit.** That covers "move these 5
  tasks".
- **Attribution and review come from the log alone.** Each op the CLI writes carries `actor` and `batch`. `tasks log`
  groups the log by batch, and `tasks undo <batch>` reverts one. No local journal is needed.

## 1. What the CLI is

### Another replica of the log

```
 Mac app (TasksCore)              ──┐
 Mac app on another Mac           ──┼──  POST /v1/sync  ──▶  Worker ──▶ UserLog DO (the log)
 tasks CLI (TasksCore, own files) ──┘
        ▲  stdio
 Deno child (code mode: bridge.js + the script, no permissions)
```

A command does what the app does:

1. load its files;
2. pull the log;
3. turn intents into ops with `Store+Actions`, apply them optimistically;
4. push them.

It talks to the server only through `POST /v1/sync`. It keeps its own cursor, `base`, pending queue and files, and never
reads or writes the app's data directories (`Tasks`, `Tasks Dev`).

### Why Swift now

The first plan chose TypeScript because a TypeScript reducer would exist either way: the code-mode sandbox and a
remote Worker runner both needed one. With remote dropped, nothing inside the sandbox needs a reducer, because its
`tasks.*` calls already went back to the host over stdio. So the host can be Swift and the reducer stays single. That
removes the port, the `fixtures/core/` conformance suite and `tasks verify`, which were the main costs of the first
plan. What's left in JavaScript is the bridge and the generated `tasks.d.ts`.

The trade-off is that the CLI is macOS-only, like the app. Everything runs on this Mac, so that costs nothing now.

### Where it lives

It's a new executable target in the existing package, not a sibling package. That means one `Package.swift`, one build
directory, and `swift test` covering both. The app's Xcode project keeps depending on the `TasksCore` library product
only, so the app build doesn't change.

```swift
products: [
    .library(name: "TasksCore", targets: ["TasksCore"]),
    .executable(name: "tasks", targets: ["TasksCLI"]),
],
targets: [
    .target(name: "TasksCore"),
    .executableTarget(name: "TasksCLI", dependencies: ["TasksCore"]),
    .testTarget(name: "TasksCoreTests", dependencies: ["TasksCore"], resources: [.copy("Resources")]),
    .testTarget(name: "TasksCLITests", dependencies: ["TasksCLI"]),
]
```

```
app/TasksCore/Sources/TasksCLI/
  main.swift       parse argv with the table, run one command, exit
  Commands.swift   the table: every command and intent, its parameters, types, docs and run function (§3)
  Replica.swift    data directory, lock, URL and token, pull → build → push, exit codes (§2, §8)
  Refs.swift       ids, prefixes, list names; fail closed
  Intents.swift    intents → Store+Actions on a fork, validation, Change and summaries, dry-run (§3, §4)
  History.swift    log grouping, undo and redo of a batch (§4)
  Output.swift     text and JSON, and the TypeScript declarations of the JSON types (§6)
  Run.swift        tasks run: the Deno child, the embedded bridge.js, the RPC loop, limits (§6)
  MCP.swift        tasks mcp: the two-tool stdio server (§6)
```

- **No dependencies.** Argument parsing is ~150 lines over the command table rather than swift-argument-parser. The
  table has to exist anyway for `tasks.d.ts`, and the package stays dependency-free like the rest of the project
  (Xcode would otherwise resolve the dependency for the app too).
- **Install:** `app/Scripts/install-cli.sh` builds release, signs the binary with the "Tasks Local Signing" identity
  (`Scripts/make-signing-identity.sh`, see the app README), and copies it to `~/.local/bin/tasks` (`--prefix` to
  change). The stable signature is what keeps the Keychain's "Always Allow" across rebuilds (§8).

### What `TasksCore` needs for a CLI

Less than expected. **`@MainActor`, `@Observable` and `UndoManager` need no change:**

- A command-line `main.swift` runs on the main actor (Swift 6 top-level code), and an async `main` services the main
  queue. So `Store`, `Projection` and the models run exactly as they do in the app.
- Observation is in the standard library, not SwiftUI. Its registrars cost a few allocations that nobody observes.
- `UndoManager` is Foundation and an optional parameter. The CLI passes none; its own undo works from the log (§4).
- The timers (the ~1 s sync debounce, the 5 s snapshot) are plain `Task`s. The CLI calls `cancelScheduledSync()`,
  `await sync()` and `persistNow()` itself, and all three are public today.

**Spike (throwaway, in the scratchpad, not committed):**

- A release executable depended on `TasksCore` by path, with a top-level `main.swift` that called `Store.open` on a
  temp directory, then `createList`, `createTask`, `setWhen` with `DatePhrase.match("fri", …)`, and `persistNow()`.
- It compiled under Swift 6 with no isolation errors and no `TasksCore` change.
- It seeded the Inbox and ran in 6 ms, or 0.11 s for the whole process.
- A second run reloaded the snapshot plus the pending ops.

**The four additions.** All of them are off the app's paths, or byte-identical for the app:

| Change | Why | Size |
|---|---|---|
| `Op.actor` and `Op.batch`, optional strings. Decoded leniently like every other key; `jsonData` writes them after `set`, only when set | Attribution (§4). The app never sets them, so its op text, pending file and request bodies stay byte-identical | ~15 lines + `WireTests` |
| `Store.attribution: Attribution?` (`actor`, `batch`). `perform` stamps it on every op it queues | One command or run is one batch, however many actions it calls. It's `nil` in the app | ~5 lines |
| `Persistence.readEntries() -> [LogEntry]`, the confirmed log parsed | `tasks log`, `undo <batch>` and `show --history`. Only those commands call it | ~5 lines |
| A public memberwise `LoadedState.init` | Forking a `Store` from in-memory state, for dry-run and code mode (§4) | ~10 lines |

**Performance:** launch, the projection and every action are unchanged. The only shared cost is the `Op` decoder
looking up two absent keys per op during a full replay. `BenchmarkTests` (the 100k-op replay and the per-change
budgets) run before and after the `Op` change, and it ships only if they stay within budget.

**Where the CLI deliberately differs,** in its own target:

- **Validation fails instead of clamping.** `Store+Actions` clamps titles, notes and names to the server's limits,
  because a text field can't fail. The CLI checks the limits first (in UTF-16 units) and errors with the limit named,
  so the clamp never fires. A title or list name that's empty after trimming is refused.
- **Inbox seeding stays.** `Store.init` seeds the Inbox when it's missing. On a fresh CLI replica that queues the same
  fixed-id op every Mac sends, and the server dedups it by op id. The first command on a new replica therefore pushes
  one no-op, which is harmless, so no flag is needed. (The first plan said the SDK would never seed.)

## 2. The replica: sync, offline, concurrency

### Files

State lives in `~/Library/Application Support/Tasks CLI/<host>[:<port>]/`. It's the app's own `Persistence` layout,
written by the app's code: `log.jsonl`, `pending.jsonl`, `snapshot.json`, `rejected.jsonl`, and `log.jsonl.bak-<ms>`
during a recovery.

There's one directory per server URL, because a replica's 409 recovery pushes every op it knows to whatever server
it's talking to. If one replica were pointed first at `wrangler dev` and then at the live Worker, recovery would copy
dev ops into the real log. The Mac app has this problem today (§10).

### One command's life

1. **Lock** the directory: `flock` on `<dir>/lock`, waiting up to 15 s (a code-mode run can hold it for 10 s). Agents
   often run several commands at once. The kernel releases the lock when a process dies, so there's no stale-lock
   logic.
2. **Open** the `Store` (snapshot plus tail), set `config`, cancel the scheduled sync and `await sync()`. That pulls,
   and pushes anything an earlier command left queued. `--cached` skips this step.
3. **Build** the change on a fork against the fresh state (§4), resolving refs first.
4. **Commit:** `perform` the fork's ops on the real `Store` with `attribution` set. Then `persistNow()`, so they're in
   `pending.jsonl` before anything goes out, then `await sync()`.
5. **Report** success only once every op id has come back in a returned page, so none of ours is left in
   `projection.pending` (SPEC §5).

A read is one request and a write is two. Building a write against fresh state matters for agents ("complete
everything due today" has to see today's tasks), so the pull before it is worth the round trip.

### The error table and recovery are the app's

`Store.runSync` already implements SPEC §5:

- paging, and chunks of up to 500 ops and ~900 KB;
- `invalid_op` moving the op to `rejected.jsonl`;
- 413 halving the chunk;
- 401, 404, 405 and `bad_request` stopping;
- backoff for transient errors;
- the 409 recovery, with its backups.

The CLI only maps the outcome to an exit code:

| After the push | Exit |
|---|---|
| `syncState` is `idle` and none of our ops is pending | `0` |
| `retrying` (5xx or network): the CLI waits out the `Store`'s own backoff up to 3 times (~7 s), then gives up | `75` (`EX_TEMPFAIL`): applied locally and queued, not yet in the log |
| `checkToken` (401) | `1`: "the server rejected the token" |
| `failed` (404, 405, `bad_request`, a change too large) | `1`, with the `Store`'s message |
| `notice` set by an `invalid_op` | `1`, naming the field. The CLI validates first, so this means a bug |

- **Queued ops are durable** and sent verbatim, deduplicated by op id, so a retry or a crash never duplicates a write.
  The next command pushes them before its own pull. `tasks status` shows the queue and the last error.
- **A batch normally goes in one request.** Step 2 empties the queue first, so a batch of ≤ 500 ops and ≤ 900 KB is
  one chunk, and the server appends it contiguously and all-or-nothing. Offline, queued batches can share or straddle
  chunks, which is the same as the app.

### Running alongside the Mac app

They're independent replicas, so this is the two-Macs case the protocol already handles.

- **Latency:** an agent's change shows on the Mac at its next sync: within 30 s while a window is open, and at once on
  ⌘R or when the app becomes active. If that feels slow once agents are in daily use, it's the trigger to build SPEC
  §11's "head is now N" poke.
- **Conflicts:** the last write in log order wins, per field. The one that bites is `notes`, which is last-writer-wins
  as a whole string. An agent appending to notes while the user edits the same notes on a Mac loses one side. The CLI
  pulls just before it writes, which keeps that window small, and undo restores the agent's side.
- **Mac edits the agent can't see:** the agent never sees a Mac's pending, unpushed edits. The Mac pushes about 1 s
  after a change, so this only matters for an offline Mac.

### Today

The CLI uses `StoreClock.system`, the app's clock with `Calendar.autoupdatingCurrent`. So Today, "completed today" and
DST changes are the app's own computation on the same Mac, with nothing to configure.

## 3. The API surface

### One table

`Commands.swift` holds one entry per command, for example:

```swift
Command("when <date|none> <task>…", method: "setWhen",
        doc: "Set When. A date, a phrase the date field reads (\"fri\", \"next week\"), or none to clear.",
        params: [.init("tasks", .refs), .init("date", .dateInput)],
        returns: .change) { ctx, args in try ctx.setWhen(args.refs("tasks"), args.date("date")) }
```

Each entry produces:

- the argument parser and usage errors;
- `tasks help` and `tasks help <command>`;
- the code-mode method, with its argument decoding and validation;
- its signature in `tasks.d.ts`, with `doc` as the comment.

The JSON types (`Task`, `List`, `Change`, `Today`) are `Encodable` structs in `Output.swift`, with their TypeScript
declarations next to them. A test encodes each one and checks its keys against the declaration, and a golden
`tasks.d.ts` in `TasksCLITests` makes any change show up in review.

### Conventions

- **One schema everywhere.** `--json` prints exactly the objects a code-mode script receives.
- **Refs.** Anything that takes a task or list accepts:
  - its full id;
  - a unique id prefix of at least 4 characters, which is how Git refs work;
  - for lists, a name, case-insensitive, matched among active lists first and then archived ones.

  Output shows each id's shortest unique prefix, at least 6 characters, as `ref`. **Refs fail closed:** a missing or
  ambiguous ref is an error that lists the candidates, and the CLI never guesses. Duplicate list names are allowed, so
  they need a prefix.
- **Ids are stable.** An id is chosen once, at create, and never changes.
  - `add --id <id>` lets the caller pick it (`createTask(id:)`, as the app's new-task draft does).
  - `add --key <text>` derives it: a lowercase UUIDv8 from SHA-256 of the key.
  - So repeating `tasks add "Pay rent" --key rent-2026-11` changes nothing: the CLI sees the task exists and returns
    it. Two replicas racing offline also leave one task (SPEC §5 rule 1: the first create wins).
- **Dates.** A `DateInput` is `"YYYY-MM-DD"`, `null` (`none` on the command line) to clear, or any text the app's date
  field reads ("fri", "next week", "3d", "nov 9", "the 9th").
  - Text resolves with `DatePhrase.match` against the replica's today, exactly as the popover's Return does
    (INTERACTIONS-v2 §11). Numeric dates use `DatePhrase.numericOrder(for: .current)`, or `TASKS_DATE_ORDER=md|dm`.
  - Every result echoes the resolved date, and `tasks date <text>` resolves one without writing.
  - Text that reads as no date is an error.
- **Places.** A place is `top`, `bottom`, `up`, `down`, `{after: ref}` or `{before: ref}`, the anchors of
  `Ordering.Anchor`.
  - `up` and `down` are ⌥⌘↑ and ⌥⌘↓, one slot among the open tasks of the task's list: `.before` the previous task, or
    `.after` the next one.
  - An anchor in another list moves the task there. "After X" is the full-list rule that drags in a Today group already
    use (SPEC §4).
- **Multi-select** is passing several refs. They apply as one batch, in the order given.
- **No-ops write nothing,** because the `Store+Actions` guards already skip them (`t.title != title` and the rest).
  That makes every command except `toggle` idempotent:
  - completing a done task, or setting a date it already has, writes nothing;
  - moving a task to the list it's in writes nothing;
  - placing a task where it already is writes nothing, because `keyBetween` is deterministic.
- **A write returns a `Change`:** `{batch, summary, tasks, lists, synced}`, with the entities after the change.
  - `summary` uses the app's undo names (INTERACTIONS-v2 §9: "Complete 3 Tasks", "Move 3 Tasks", "Remove When") with
    the target added ("Move 3 Tasks to School").
  - Creates return the new entity instead.
- **Text output reads like the app.** Chips come from `DateLabel.whenChip` and `deadlineChip`, the same functions the
  rows use.

### Every UI operation

Refs below are made up. In code mode, `tasks` is the API object and every call is awaited (§6). The last column is
the `TasksCore` code each one runs.

**Tasks**

| UI operation (INTERACTIONS-v2) | CLI | Code mode | `TasksCore` |
|---|---|---|---|
| New task in a list: ⌘N, the header +, double-click empty space (§6) | `tasks add "Buy milk" --list Groceries` | `await tasks.add({ title: "Buy milk", list: "Groceries" })` | `createTask(in:)`, at the bottom of the list's open tasks |
| New task from Today: When = today, in the default list (SPEC §2) | `tasks add "Call mum" --today` | `await tasks.add({ title: "Call mum", when: "today" })` | `createTask(when:)`; no list means `defaultListID` |
| New task from a Today group's + | `tasks add "Essay" --list School --today` | `await tasks.add({ title: "Essay", list: "School", when: "today" })` | `createTask(in:when:)` |
| New task with notes and dates, then edited in the detail pane | `tasks add "Trip" --deadline "nov 9" --notes - < notes.md` | `await tasks.add({ title: "Trip", deadline: "nov 9", notes })` | `createTask(notes:when:deadline:)`; a place adds a `reorder` in the same batch |
| Rename (detail title, or in the row) | `tasks rename 3f9a2c "Buy oat milk"` | `await tasks.rename(t.id, "Buy oat milk")` | `setTitle` |
| Edit notes (Markdown) | `tasks notes 3f9a2c -` (from stdin); `--append TEXT` | `await tasks.setNotes(t.id, t.notes + "\n- [ ] call back")` | `setNotes` |
| Complete (checkbox, Space, ⌘K, menu) | `tasks done 3f9a2c 77b0e1` | `await tasks.complete(ids)` | `toggleComplete` on the open ones |
| Mark as not done | `tasks undone 3f9a2c` | `await tasks.uncomplete(ids)` | `toggleComplete` on the done ones |
| ⌘K on a selection: completes all unless all are done, then uncompletes all | `tasks toggle 3f9a2c 77b0e1` | `await tasks.toggle(ids)` | `toggleComplete` |
| Set When: popover, typed phrase, quick picks, ⌘T, menu (§11) | `tasks when fri 3f9a2c 77b0e1` | `await tasks.setWhen(ids, "next week")` | `DatePhrase.match`, then `setWhen` |
| Remove When (Clear, ⌫, ×, menu) | `tasks when none 3f9a2c` | `await tasks.setWhen(ids, null)` | `setWhen(nil)` |
| Set or remove Deadline | `tasks deadline "nov 9" 3f9a2c`; `tasks deadline none …` | `await tasks.setDeadline(t.id, "2026-11-09")` | `setDeadline` |
| Drag onto Today (sets When = today, the task stays in its list) | `tasks when today 3f9a2c` | `await tasks.setWhen(ids, "today")` | `setWhen` |
| Delete: ⌘⌫, menu, trash (§9) | `tasks delete 3f9a2c 77b0e1` | `await tasks.delete(ids)` | `delete` |
| Undo / redo (⌘Z / ⇧⌘Z) | `tasks undo [batch]`, `tasks redo` | `await tasks.undo(change.batch)` | `Inverse.of` over the log (§4) |
| Move to another list: ⇧⌘M, menu, detail List pop-up, drop on a sidebar list (§10) | `tasks move 3f9a2c 77b0e1 --to School` | `await tasks.move(ids, { list: "School" })` | `move(to:)`: they land at the bottom, in the order given |
| Reorder in a list (drag, §14) | `tasks move 3f9a2c --after 77b0e1`; `--top` | `await tasks.move(t.id, { place: "top" })` | `reorder(in:at:)` |
| Move up / down (⌥⌘↑ ⌥⌘↓) | `tasks move 3f9a2c --up` | `await tasks.move(t.id, { place: "down" })` | `reorder`, anchored on the neighbour |
| Reorder in a Today group | `tasks move 3f9a2c --before 9c1d0f` | `await tasks.move(a, { place: { before: b } })` | `reorder`, with the anchor relative to the full list (SPEC §4) |
| Move into another list at a spot (two gestures in the app) | `tasks move 3f9a2c --to School --top` | `await tasks.move(t.id, { list: "School", place: "top" })` | `reorder(in: School, at:)`, writing `list` and `order` together |

**Lists**

| UI operation | CLI | Code mode | `TasksCore` |
|---|---|---|---|
| New list: ⇧⌘N, the Lists +, the sidebar menu (§12) | `tasks list add School` | `await tasks.addList("School")` | `createList`, at the bottom of the sidebar; a place adds `reorderLists` |
| Rename a list | `tasks list rename School "School 2026"` | `await tasks.renameList("School", "School 2026")` | `rename(list:to:)` |
| Reorder lists: drag, ⌥⌘↑ ⌥⌘↓, Move Up / Down | `tasks list move School --after Work`; `--up` | `await tasks.moveList("School", "top")` | `reorderLists` |
| Archive ("delete list") | `tasks list archive School` | `await tasks.archiveList("School")` | `archive(list:)` |
| Unarchive (button, menu) | `tasks list unarchive School` | `await tasks.unarchiveList("School")` | `unarchive(list:)` |

**Views**

| UI view | CLI | Code mode | `TasksCore` |
|---|---|---|---|
| Today: groups in sidebar order, then Completed today (§13) | `tasks today` | `const { groups } = await tasks.today()` | `activeLists`, `todayTasks(in:)`, `todayDone` |
| The sidebar with its counts | `tasks lists` | `await tasks.lists()` | `activeLists`, `openTasks(in:).count` |
| A list: open tasks in order, then Completed newest first | `tasks ls School`; `--done` adds Completed | `(await tasks.list("School")).open` | `openTasks(in:)`, `completedTasks(in:)` |
| The Archive group: archived lists, newest first | `tasks archive` | `await tasks.archive()` | `archivedLists` |
| An archived list ("Archived Oct 28", still editable) | `tasks ls School` (shows the banner line) | as a list; `list.archivedAt` is set | as a list |
| The detail pane: fields, raw notes, Created / Completed | `tasks show 3f9a2c` | `await tasks.task(id)` | `projection.task` |
| Sync now (⌘R) | `tasks sync` | (each run syncs) | `sync()` |

Moving into an archived list is refused with "School is archived; unarchive it first". The app never offers archived
lists as targets (§10), and a task moved there would quietly vanish from view. Adding a task to an archived list works,
as it does in the app.

**Not covered, on purpose:** selection, focus, navigation ("Show in School", ⌘1–⌘9), type-to-select, the sidebar
toggle, and the UserDefaults settings (Edit tasks, Theme, Glass). They're the app's local state and none of them is in
the log.

### Beyond the UI (agents need these)

| Need | CLI | Code mode |
|---|---|---|
| Find a task without knowing its list (read-only; the app has no search) | `tasks find milk` | `tasks.find({ text, list, done })` |
| Bring back a deleted task when there's no undo stack (`deleted: false`) | `tasks restore 3f9a2c` | `tasks.restore(ids)` |
| What changed, and who did it (§4) | `tasks log --actor 'agent:*' --since 2h` | — |
| One task's history (`git log -- <task>`, SPEC §6) | `tasks show 3f9a2c --history` | — |
| Resolve a date phrase without writing | `tasks date "next fri"` | `tasks.date(text)` |
| Sync state, pending queue, actor, server | `tasks status` | — |

## 4. Batches, attribution, review and undo

### One change, one batch

A batch is one CLI command or one code-mode run. All of its ops carry the same `batch` id and go in one request.

- **≤ 500 ops:** one request, so the server appends it contiguously and all-or-nothing.
- **More than that** (a bulk import) needs `--large`. The `Store` chunks it across requests, still under one `batch`
  id, so it's still undone as one unit, but it isn't atomic on the wire.

### Forks: dry-run, code mode, and nothing written on error

Every write is built on a fork: a second `Store` made from the real one's in-memory state. The fork gets a
`LoadedState` from `projection.confirmed`, `cursor`, `base` and `projection.pending`, a scratch `Persistence` in a temp
directory, and no `config`, so it never syncs. The intents run on the fork, so reads see earlier writes. At the end,
the ops the fork queued are the change:

- **commit:** `perform` them on the real `Store`, verbatim (ids and timestamps kept), then push (§2);
- **`--dry-run`:** print the `Change` and the diff, and discard the fork;
- **an error anywhere** (a bad ref halfway through a script, a throw, a limit): discard the fork, so nothing is
  written.

That gives a plain command, `--dry-run` and `tasks run` one code path. The summary and diff come from comparing the
touched entities on the fork and on the real `Store`.

### The schema change: `actor` and `batch` on the envelope

```jsonc
{ "id": "…", "at": 1761900000000, "type": "task.update", "target": "…", "set": { "when": "2026-11-06" },
  "actor": "agent:claude-code",   // optional: who wrote it. Absent = the Mac app
  "batch": "2c1f9e0a-…" }         // optional: the change it belongs to
```

- **Envelope, not `set`.** These aren't entity fields, and the reducer never reads them (rule 6 already ignores
  anything unknown).
- **Validation** is the same as ids: a string of 1–64 characters, with `field` `actor` / `batch` on failure. That's a
  loosening, which SPEC §5 allows. Every other unknown envelope key is still rejected.
- **Storage:** the server's stored text becomes `JSON.stringify({id, at, type, target, set, actor, batch})`.
  `JSON.stringify` omits `undefined`, so every existing op's text, and therefore every hash and every fixture, is
  byte-for-byte unchanged. New fixture: `11-push-with-actor.json`, checked by the server tests and by the Swift
  `FixtureTests`.
- **In Swift,** `Op` gains the two optional fields and `jsonData` writes them after `set` (§1), matching that key
  order.
- **Backward compatible:**
  - the app's behavior doesn't change: it gets the fields through `TasksCore` and never sets them;
  - an older app build ignores them, because it decodes ops with a keyed container;
  - in a 409 recovery, log ops are copied verbatim, so the keys survive;
  - `PendingOp` resends text verbatim.
- **Order of rollout:** today's server rejects unknown envelope keys, so the server change is deployed before the CLI
  writes to the live log (phase 1 before phase 2). Like any loosening, the server must **never be rolled back past
  it**: a 409 re-push of an agent op would then be `invalid_op` and get discarded (SPEC §5 "Validation may only
  loosen").
- **Who sets `actor`:** `--actor`, else `TASKS_ACTOR`, else `agent:claude-code` when `CLAUDECODE=1` is set, else
  `cli`. `tasks run` and `tasks mcp` use the same chain, and an MCP client can set its own in its server config
  (`claude mcp add tasks -e TASKS_ACTOR=agent:claude-desktop -- tasks mcp`).

The client declares the actor, which is enough for one user.

**Pushback, the server stamping the token's name instead:** that can't be forged, but it needs a token per writer,
changes the entry format, and attributes ops wrongly after a recovery (whoever re-pushes gets credited). It's worth
doing only if there are ever other users.

### Review: `tasks log`

`tasks log` reads `Persistence.readEntries()` and the pending ops, newest first:

- it groups ops by `batch`;
- ops with no batch, from the app, are grouped by their request: contiguous `seq` with the same `received`;
- each group shows its actor, time and summary;
- the summary is computed by diffing the state before and after the group, using the same summary names as `Change`.

```
2c1f9e  agent:claude-code  10:42  Move 3 Tasks to School      tasks undo 2c1f9e
77ab01  agent:claude-code  10:41  Set When: Fri, Nov 6 (2)    tasks undo 77ab01
—       app                10:30  Complete "Pay rent"
```

`--json` gives each group's ops and per-entity before/after. Filters: `--actor` (glob), `--since`, `--batch`, `--task`.

### Undo for a batch

`undo(batch)` works from the log alone.

1. Find the batch's ops in the log and in pending.
2. For each touched entity, rebuild it as it was just before the batch's first op on it, by replaying the earlier
   entries with `Reducer.apply`.
3. Write the inverse with `Inverse.of`: the touched keys go back to their earlier values. A created task gets
   `deleted: true`, and a created list gets `archivedAt`.

Two more rules make it safe hours later:

- **Conflicts.** A key someone has changed since the batch (its value is no longer what the batch wrote) is skipped
  and reported: "kept the later edit to the title of 3f9a2c". `--force` overwrites anyway. The app's ⌘Z is
  last-writer-wins, which is right for an undo pressed straight away and wrong for one made the next day.
- **A derived batch id.** The undo batch's id is a UUIDv8 of `"undo:" + batch`. Then:
  - "is this batch undone?" means "does its undo batch exist in the log or pending?", so the answer needs no stored
    state, and a second undo of the same batch is refused ("already undone by 5e0c71");
  - `tasks undo` with no argument undoes this actor's newest batch that is neither undone nor itself an undo, and
    repeating it walks back further;
  - `tasks redo` undoes the newest undo.

Undo is itself a batch, with an actor, so it shows in `tasks log`. The app's own ⌘Z stack is unchanged and never sees
agent batches. A Mac "Undo agent change" or a history view can come later, built on the same two keys.

### Preview: `--dry-run`

Every write takes `--dry-run`. It runs on a fork as usual and prints the `Change` and a diff instead of committing:

```
~ 3f9a2c "Buy milk"      when: — → 2026-11-06 (Fri)
~ 77b0e1 "Call dentist"  list: Inbox → School (bottom)
```

`tasks run --dry-run` runs the whole script that way, and the output is the combined diff. To commit, run it again
without the flag. The diff was computed against a state that can move, but a stale preview is the same accepted
trade-off as a stale drag (SPEC §3).

## 5. The CLI

### Commands

```
tasks today | lists | ls [<list>] [--done] | archive | show <task> [--history] | find <text> | log [filters]
tasks add <title> [--list L] [--today] [--when D] [--deadline D] [--notes TEXT|-] [--top|--after R|--before R]
                  [--id ID | --key K]
tasks rename <task> <title>          tasks notes <task> <TEXT|-> [--append]
tasks done|undone|toggle <task>…     tasks when|deadline <date|none> <task>…
tasks move <task>… [--to L] [--top|--bottom|--up|--down|--after R|--before R]
tasks delete|restore <task>…
tasks list add <name> [place]  |  rename <list> <name>  |  move <list> <place>  |  archive|unarchive <list>
tasks undo [<batch>] [--force]  |  redo  |  sync  |  status  |  date <text>
tasks run [<file>|-] [--dry-run]  |  types  |  mcp
global: --json  --ids  --dry-run  --cached  --actor A  --server URL  --large
```

`tasks help <command>` and `tasks --help` come from the table and are written for a model reading them cold: one line
per command, then one example each.

### Output and exit codes

- **Text by default.** It reads like the app: chips as the rows show them ("Overdue · 2d", "Due today", "Fri"), the
  6-character ref first, and a closing line naming the batch and how to undo it.
- **`--json`** prints the same objects code mode returns: an array for lists of things, an object otherwise.
  **`--ids`** prints one id per line, for pipes.
- **stdout is only data.** Warnings and progress go to stderr.
- **Exit codes:**
  - `0`: done, and confirmed in the server's log;
  - `75`: applied locally but not yet in the log (offline, or the server is unreachable); a read was served from the
    cache;
  - `1`: an error, and nothing was written; the message says why, and for a bad ref it lists the candidates;
  - `2`: usage.

```
$ tasks today
Today · Sat, Oct 31
Inbox
  ○ 3f9a2c  Buy milk          Overdue · 2d
  ○ 77b0e1  Call dentist      Due today
School
  ○ 9c1d0f  Essay draft       ⚑ Mon
Completed
  ● 1a2b3c  Pay rent          Inbox

$ tasks find dentist --ids | tasks when tomorrow -
Set When: Sun, Nov 1 on "Call dentist" · undo: tasks undo 5e0c71
```

### Piping and idempotency

- **Refs from stdin:** `-` in a ref position reads them, one per line. `--ids` output feeds straight in:
  `tasks ls Inbox --ids | tasks move - --to Someday`.
- **One command, one batch,** however many refs it gets from stdin.
- **Idempotency:** every command is safe to repeat except `toggle`, and `add` is safe with `--key`. Op ids are
  generated once and persisted before the push, so a retried push never double-applies.

## 6. Code mode

### Why

The idea, in Cloudflare's code-mode posts and Anthropic's "code execution with MCP": models are better at writing
code against a typed API than at chaining tool calls. Every intermediate result of a tool chain passes through the
model's context, and every call costs a turn.

In Tasks, "push every overdue task to tomorrow except the ones in Work" is:

- as tool calls: a read, a filter in the model's head, then one call per task;
- in code mode: one script, one turn, one atomic batch, and only the summary comes back.

The published numbers are large because their APIs are large:

- Cloudflare's whole API went from ~1.17M tokens to ~1,000;
- Anthropic's example went from 150k tokens to 2k;
- programmatic tool calling saves 37%.

Our API is ~25 calls, so the token saving is smaller. The win here is fewer turns and one atomic batch. Sources are in
§13.

We take from Cloudflare's design: TypeScript declarations with doc comments and one tool that runs code, a sandbox
whose only capability is the API, and `console.log` output returned with the result. We don't take
`@cloudflare/codemode`'s rule that scripts must be JavaScript, because Deno runs TypeScript as written.

### `tasks run`: a Swift host and a JS bridge

```
tasks run (Swift: holds the lock, the replica, the token and the fork)
   │  spawns: deno run --no-prompt --no-remote --deny-import --no-config --no-lock
   │                   --v8-flags=--max-old-space-size=128 bridge.js
   │          (no --allow-* flags, empty environment, cwd = a fresh empty 0700 temp dir)
   │  child stdin  ← the script, then replies          {id, result | error}
   │  child stdout → calls {id, method, args}, logs {log}, then {done, result | error}
   ▼
bridge.js (~40 lines): `tasks` is a Proxy whose methods are those calls; console.* becomes {log} lines;
                       the script is imported from a data: URL, so its TypeScript runs as written
```

- **The host is the CLI itself.** Each call is looked up in the command table, its arguments are decoded and
  validated, and it runs the same intent function the CLI command runs, on the run's fork. The reply is the same JSON
  `--json` prints.
- **Deno doesn't type-check.** `deno run` strips types without checking them, so the types are documentation for the
  model. The host validates every argument against the table and returns `Invalid` with the field.
- **`bridge.js` is a string literal in `Run.swift`,** not a bundle resource, so the binary can be copied anywhere. It's
  written into the run's temp directory and deleted afterwards. It's never run with `deno eval`, which takes no
  permission flags and runs with full access.
- **Finding Deno:** `TASKS_DENO`, else `deno` on PATH (mise's shim). If it's missing, `tasks run` says "tasks run needs
  Deno: mise use -g deno". Only code mode needs it.

**Spikes (throwaway, in the scratchpad, not committed; Deno 2.9.8):**

- In the no-flags child, reading a file, reading env, `fetch` and spawning a process each threw `NotCapable`. Stdin and
  stdout worked.
- `import("data:application/typescript;base64,…")` loaded and ran a typed script with no permission (the docs only
  promise that for Workers).
- A host process served `tasks.today()` and `tasks.complete([...])` over the pipe, and a whole run took ~50 ms.
- Run again today under `env -i` from an empty working directory, with `--no-remote --deny-import --no-config
  --no-lock`: the typed `data:` import ran, and file, env and subprocess access (by absolute path) each threw
  `NotCapable`.

**The remote-import hole, closed:**

- Deno 2 gates module imports with a separate `import` permission. `deno run --help` (2.9.8) gives its default as
  `deno.land`, `jsr.io`, `esm.sh`, `raw.esm.sh`, `cdn.jsdelivr.net`, `raw.githubusercontent.com` and
  `gist.githubusercontent.com`.
- So a no-flags script could leak task data in an `import("https://…?d=…")` URL.
- The child therefore gets `--no-remote --deny-import`, an empty environment and an empty working directory.
- A phase-3 test checks that a remote import fails. The probe that would show today's default needs the network, so it
  wasn't run during planning.
- Deno's docs ask for "more than one layer of defense". The second layer is the API itself: it's the script's only
  effect, and everything it does is undoable.

So:

- **The token never enters the sandbox,** and the script can't touch files or the network. It can only call the API.
- **The whole script runs on one fork** (§4). Reads see earlier writes, the writes collect into one batch, and the
  batch is committed and pushed once, after the script returns.
- **Limits:**
  - 10 s of wall time, after which the host kills the child and writes nothing;
  - 128 MB of heap;
  - 500 ops (more needs `--large`);
  - a 100 KB result and 200 log lines.
- **Errors come back with the script's line and column,** because a `data:` module keeps its own line numbers. API
  errors are typed: `NotFound`, `Ambiguous` (with candidates), `Invalid` (with the field), `NoActiveList`, `Limit`.
  An unknown method gets "no `tasks.compelte`; did you mean `complete`?", from the table.

The result is one JSON object:

```jsonc
{ "ok": true, "result": <what the script returned>, "logs": ["…"],
  "change": { "batch": "2c1f9e…", "summary": "Set When: Sun, Nov 1 (4)", "tasks": [ … ] }, "synced": true }
{ "ok": false, "error": { "type": "Ambiguous", "message": "\"Work\" matches 2 lists: 4be1c0, 9a77f2", "line": 3 },
  "logs": [], "change": null }
```

### What the model sees: `tasks.d.ts`

`tasks types` prints it, generated from the command table (§3), and its first line points to `tasks run`. It's about
1,500 tokens. Its shape:

```ts
/** A day, "YYYY-MM-DD", no time or zone. Compares correctly as a string. */
type CalendarDate = string;
/** "YYYY-MM-DD", or what the app's date field reads: "today", "fri", "next week", "3d", "nov 9". null clears. */
type DateInput = string | null;
/** An id, a unique id prefix (4+ chars), or for lists a name. */
type Ref = string;
type Place = "top" | "bottom" | "up" | "down" | { after: Ref } | { before: Ref };

interface Task { id: string; ref: string; list: string; listName: string; title: string; notes: string /* Markdown */;
  when: CalendarDate | null; deadline: CalendarDate | null; done: boolean; completedAt: number | null;
  deleted: boolean; createdAt: number; updatedAt: number }
interface List { id: string; ref: string; name: string; archivedAt: number | null; open: number }
interface Change { batch: string; summary: string; tasks: Task[]; lists: List[] }

declare const tasks: {
  today(): Promise<{ date: CalendarDate; groups: { list: List; tasks: Task[] }[]; done: Task[] }>;
  lists(): Promise<List[]>;                       // the sidebar, in order
  list(list: Ref): Promise<{ list: List; open: Task[]; completed: Task[] }>;
  archive(): Promise<List[]>;
  task(task: Ref): Promise<Task>;
  find(q: { text?: string; list?: Ref; done?: boolean }): Promise<Task[]>;
  date(text: string): Promise<CalendarDate | null>;

  add(t: { title: string; list?: Ref; notes?: string; when?: DateInput; deadline?: DateInput; place?: Place;
           key?: string /* same key, same task: safe to repeat */ }): Promise<Task>;
  rename(task: Ref, title: string): Promise<Change>;
  setNotes(task: Ref, markdown: string): Promise<Change>;
  complete(tasks: Ref | Ref[]): Promise<Change>;
  uncomplete(tasks: Ref | Ref[]): Promise<Change>;
  toggle(tasks: Ref | Ref[]): Promise<Change>;
  setWhen(tasks: Ref | Ref[], date: DateInput): Promise<Change>;
  setDeadline(tasks: Ref | Ref[], date: DateInput): Promise<Change>;
  move(tasks: Ref | Ref[], to: { list?: Ref; place?: Place }): Promise<Change>;
  delete(tasks: Ref | Ref[]): Promise<Change>;
  restore(tasks: Ref | Ref[]): Promise<Change>;
  addList(name: string, place?: Place): Promise<List>;
  renameList(list: Ref, name: string): Promise<Change>;
  moveList(list: Ref, place: Place): Promise<Change>;
  archiveList(list: Ref): Promise<Change>;
  unarchiveList(list: Ref): Promise<Change>;
  undo(batch: string): Promise<Change>;
};
// The whole script is one change: it's written when the script returns, and nothing is written if it throws.
```

An example run:

```ts
const { date, groups } = await tasks.today();
const late = groups.filter((g) => g.list.name !== "Work").flatMap((g) => g.tasks)
  .filter((t) => t.deadline !== null && t.deadline < date);
await tasks.setWhen(late.map((t) => t.id), "tomorrow");
return late.map((t) => t.title);
```

### MCP: `tasks mcp`

`tasks mcp` is a local stdio MCP server (JSON-RPC `initialize`, `tools/list`, `tools/call`, ~120 lines of Swift) with two
tools:

- `tasks_types` returns `tasks.d.ts`;
- `tasks_run` takes a script and an optional `dryRun`, and returns the result object above.

It calls the same code as `tasks run`, in-process. It's for MCP clients on this Mac without a shell (Claude Desktop),
registered with `claude mcp add tasks -- tasks mcp` or the client's config.

### `docs/AGENTS.md`

A short page that teaches an agent the CLI and `tasks run`: refs, dates, `--json`, exit code 75, batches and undo, and
when to reach for a script. Its command list is checked against the table by a test.

## 7. CLI, code mode or MCP: what each is good at

| | CLI | Code mode (`tasks run`, `tasks mcp`) | MCP with one tool per operation |
|---|---|---|---|
| Context cost | Nothing until the model runs `tasks --help` (~1k tokens) | `tasks.d.ts`, ~1.5k tokens, read once | ~25 tool schemas, ~4–6k tokens, in every request |
| Round trips for "reschedule every overdue task outside Work" | 2 (`find … --ids \| tasks when tomorrow -`) | 1 | 1 + one per task |
| Atomic multi-step change | Within one command | The whole script | No; each call is its own change |
| Logic (filters, loops, conditions) | Shell and `jq` | Real code, typed | In the model's head, through its context |
| Who it serves | Any agent with a shell (Claude Code), and people | Shell agents (`tasks run`); local MCP clients (`tasks mcp`) | MCP clients |
| Debugging | Run the same command yourself | Rerun the script with `--dry-run` | Read the transcripts |
| Cost to build | Medium: it's most of the surface | Small on top of the CLI: the bridge, the generated d.ts, ~120 lines of MCP | Small, but a third surface to keep equal to the UI |

**Decided:**

- **CLI first.** Claude Code on this Mac is the first agent, and the CLI is also the human and debugging surface.
- **Code mode next,** for anything that's more than one command.
- **MCP only as a two-tool wrapper around code mode,** not one tool per UI operation. That's the expensive pattern
  code mode exists to replace, and it would be a third surface to keep equal to the app.

## 8. The token and the server URL

- **URL:** `TASKS_URL`, else a `TASKS_URL=` line in `~/.tasks-sync.env`. Today that file holds only `API_TOKEN`, so the
  user adds the line once (`--server` overrides both).
  - There's no default URL, so a dev setup can't hit the live log by accident.
  - Debug builds of the CLI, like Debug builds of the app, only talk to `127.0.0.1` or `localhost` unless
    `TASKS_ALLOW_REMOTE=1` is set.
- **Token:** the one shared token, read from, in order:
  1. `TASKS_TOKEN`;
  2. `API_TOKEN` in `~/.tasks-sync.env`;
  3. the app's Keychain item: service `com.elguindi.Tasks.sync`, account `API_TOKEN` (`AppModel.swift`).

  The Keychain comes last because a new binary's first read shows a Keychain dialog, and an agent can't click it, so
  the command would hang. Once the user clicks Always Allow, the stable signing identity (§1) keeps that across
  rebuilds.
- **Never printed:** `tasks status` says "token: set, from ~/.tasks-sync.env". The token never reaches a code-mode
  script either: the child has an empty environment and no read access.
- **No agent tokens.** Nothing runs off this Mac, and a local agent with a shell could read the file anyway, so a
  separate token here would add little.

## 9. Server changes

| When | Change | Size |
|---|---|---|
| Phase 1 | `actor` and `batch` envelope keys (§4): `validate.ts`, the stored-text order, fixture `11-push-with-actor.json`, SPEC §5's tables. Deploy only with the user's approval | ~15 lines |

**Not proposed:**

- A read-model endpoint (`GET /v1/tasks`). Replicas reduce locally; a server read model would be the server-side
  reducer and snapshot that SPEC §5 deferred, for no gain.
- A WebSocket. SPEC §11 still holds, unless agent latency on the Mac starts to bother the user (§2).
- Anything remote: an MCP endpoint on the Worker, the Dynamic Worker Loader, agent tokens. The first version's design
  for those is in `c54b00a` if it's ever wanted.

## 10. A Mac app issue found along the way (not fixed here)

**Changing the app's server URL replays every op into the new server.**

- Setting `Store.config` syncs at once with the old server's `cursor` and `base`.
- The new server's log doesn't match, so it answers 409, and `recoverFrom409` re-pushes every op this Mac knows. That's
  right for a wiped server, and it's what SPEC §5 asks for.
- But if the new URL is a different server (live to `wrangler dev`, or back), it copies one log into the other.
- Debug builds limit the damage: they have their own data directory and only talk to local servers unless
  `allowRemoteServer` is set. A Release app pointed at a dev server and back would still mix the two logs.

Possible fixes, for whoever schedules it: key the data directory by server URL, as the CLI does (§2), or start a fresh
replica when the URL changes and the log isn't empty, asking first. The CLI isn't affected.

## 11. Build order

Each phase ends with something testable, like SPEC §10.

| Phase | Build | Done when |
|---|---|---|
| 1. Server keys | `actor` and `batch` (§4), fixture 11, the SPEC update. Deploy only after the user approves | Server tests are green, every old fixture is byte-identical, and the deploy is smoke-tested |
| 2. The Swift CLI | The four `TasksCore` additions (§1), with `WireTests` and a `BenchmarkTests` comparison. `TasksCLI`: the replica, lock, URL and token, the command table, every UI operation in §3, refs, `--json`/`--ids`, batches, forks and `--dry-run`, `log`, `undo`/`redo`. `TasksCLITests`. `install-cli.sh` | Unit tests on temp directories with a fake transport, as `SyncTests` does. Then `Scripts/e2e-cli.sh` against `wrangler dev` (running phase 1's code), alongside a scratch Debug app instance (`-dataDirectory`, as `e2e.sh` does): both edit, online and offline, both converge and match a fresh replica, a wiped server recovers, and `tasks undo` reverts an agent batch while keeping a later app edit |
| 3. Code mode | `bridge.js`, `tasks.d.ts` from the table, `tasks types`, `tasks run`, `tasks mcp`, `docs/AGENTS.md` | A scripted agent task ("reschedule overdue outside Work") runs as one batch, `--dry-run` matches the real run, and `tasks undo` reverts it. Over-limit and throwing scripts write nothing. A remote import, file, env, network and subprocess access all fail in the child. Claude Code runs the same task through `tasks mcp` |

Phase 2 can be built and tested against `wrangler dev` as soon as phase 1 is merged locally. Using the CLI on the live
log needs phase 1 deployed.

Later: the Mac app shows who changed what (a history view, an "agent" mark) and can undo an agent batch, using the same
two keys.

## 12. Decisions

**Accepted** (the first version's recommendations, with the two changes from `docs/TASK-sdk-plan-swift.md`):

1. **The core is Swift.** The CLI is built on `TasksCore`; Deno is only the code-mode sandbox.
2. **Attribution:** the client declares `actor` and `batch` on the envelope (§4).
3. **Agent writes apply at once,** with the change summary and an undo command in every result, and `--dry-run` on
   request.
4. **Agent undo skips keys changed since the batch** and says so; `--force` overrides.
5. **Tokens:** the one shared token, from the environment, `~/.tasks-sync.env` or the app's Keychain item, never
   printed (§8).
6. **MCP:** only the two-tool wrapper around code mode, local and stdio.
7. **No remote,** at all.
8. **Typed dates** read the way the date popover reads them on Return, with the resolved date echoed.

**Made in this revision, flag if you disagree:**

- The CLI is a target in the existing `TasksCore` package rather than a sibling package (§1).
- No dependencies: hand-written argument parsing over the command table (§1).
- The CLI keeps the app's Inbox seeding, since it's a server-side no-op (§1).
- Every write runs on a fork and commits at the end, so a plain command, `--dry-run` and `tasks run` share one path
  (§4).
- Debug CLI builds only talk to local servers unless told otherwise, like the app (§8).

**Open:**

1. **Where the token is read first.** *Recommend the environment, then `~/.tasks-sync.env`, then the Keychain,*
   because the Keychain's first-use dialog would hang an agent's command. The alternative is the Keychain first, which
   is better for a secret at rest, but every newly signed binary needs one click before agents can use it.

## 13. Research notes

These were checked in primary sources on 2026-10-31.

**Code mode**

- **Cloudflare, "Code Mode: the better way to use MCP,"** 2025-09-26, https://blog.cloudflare.com/code-mode/
  - LLMs are better at writing code that calls an API than at calling tools.
  - MCP schemas become TypeScript interfaces with doc comments, and the model gets one run-code tool.
  - Results come back through `console.log`.
- **Cloudflare, "Code Mode: give agents an entire API in 1,000 tokens,"** 2026-02-20,
  https://blog.cloudflare.com/code-mode-mcp/
  - The Cloudflare API MCP server has only two tools, `search` and `execute`.
  - It covers 2,500+ endpoints in ~1,000 tokens, against ~1.17M without code mode.
- **Cloudflare, "Sandboxing AI agents, 100x faster" (Dynamic Workers),** 2026-03-24,
  https://blog.cloudflare.com/dynamic-workers/
  - It says TypeScript interfaces are cheaper than OpenAPI.
- **Cloudflare, MCP server portals,** 2026-04-14, https://blog.cloudflare.com/enterprise-mcp
  - 52 tools at ~9,400 tokens became 2 tools at ~600.
- **Anthropic, "Code execution with MCP,"** 2025-11-04, https://www.anthropic.com/engineering/code-execution-with-mcp
  - Tools are shown as files the agent browses, and the code runs in a sandbox you provide.
  - The example goes from 150k tokens to 2k.
- **Anthropic, "Advanced tool use,"** 2025-11-24, https://www.anthropic.com/engineering/advanced-tool-use
  - Programmatic tool calling cut tokens 37%, and intermediate results stay out of context.
  - It runs Python in Anthropic's container, and the docs say `allowed_callers` is not a security boundary.

**Local sandboxes**

- **Deno:** with no flags, code can't touch files, the network, env or subprocesses. `--no-prompt` stops it prompting
  on a TTY, and the docs advise more than one layer of defense. https://docs.deno.com/runtime/fundamentals/security/
  - Per-Worker permissions still need `--unstable-worker-options`, which is why the plan uses a child process instead.
  - That `data:` imports need no permission is documented only for Workers. The spikes confirmed it for `import()`.
  - The default allow-list for remote imports is the hole closed in §6.
  - `deno eval --help` (2.9.8) lists no permission flags; the bridge is always run as a file with `deno run`.
- **`quickjs-emscripten`** is an in-process alternative: memory, stack and deadline limits, and only one pending async
  call at a time. It's JavaScript-only and unaudited. A Deno child is simpler and runs TypeScript.
- **Node's `vm`** is not a sandbox: "The `node:vm` module is not a security mechanism. Do not use it to run untrusted
  code." https://nodejs.org/api/vm.html

The Dynamic Worker Loader and `@cloudflare/codemode` notes, which only mattered for remote code mode, are in the first
version (`c54b00a`).
