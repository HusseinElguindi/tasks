# Tasks SDK, CLI and code mode: plan

Status: plan for review, 2026-10-31. Brief: `docs/TASK-sdk-plan.md`. Nothing here is built yet; two throwaway spikes
settled the sandbox questions (§7).

The end goal is agents using Tasks. Every agent interface here is a thin front end on one TypeScript SDK, and the SDK
is just another replica of the log, like a second Mac. The server stays a dumb log. The one change it needs is two
optional, ignored-by-the-reducer envelope keys, `actor` and `batch`.

## Summary

- **One TypeScript package, `sdk/`, with no runtime dependencies.** It's a port of the pure half of `TasksCore` (the
  reducer, inverse ops, ordering, fractional keys, calendar dates, typed date phrases, Today) plus a sync client that
  follows SPEC §5 exactly, plus an intent API that mirrors `Store+Actions.swift` one to one.
- **Identical to the app by fixtures.** `fixtures/core/` holds input/expected cases that the Swift tests write and both
  suites check, the way `fixtures/sync/` already works for the wire format. A read-only `tasks verify` also replays the
  Mac's own `log.jsonl` with the TypeScript reducer and diffs it against the Mac's `snapshot.json`.
- **Three front ends, built in this order:**
  - **The `tasks` CLI**, for agents with a shell and for people. One command is one undoable change, `--json` prints
    the same objects the SDK returns, and short refs work like Git's.
  - **Local code mode, `tasks run`.** The model writes a TypeScript script against `tasks.d.ts`. It runs in a Deno
    child process with no permissions, and its API calls go back to the CLI over stdio. One run is one change: atomic,
    previewable with `--dry-run`, and undoable.
  - **Remote code mode, optional and later.** The same API runs on our Worker through the Dynamic Worker Loader, for
    agents with no shell (Claude on the web or a phone). It's exposed as a two-tool MCP server.
- **One change is one batch: one sync request, appended atomically, undone as a unit.** That covers "move these 5
  tasks".
- **Attribution and review come from the log alone.** Each op an agent writes carries `actor` and `batch`.
  `tasks log` groups the log by batch, and `tasks undo <batch>` reverts one from any replica. No local journal is
  needed.

## 1. What the SDK is

### Another replica of the log

```
 Mac app (Swift TasksCore)  ──┐
 Mac app on another Mac     ──┼──  POST /v1/sync  ──▶  Worker ──▶ UserLog DO (the log)
 tasks CLI (sdk/, own data) ──┤
 code-mode runner (later)   ──┘   (runner: a replica in its own DO, calling UserLog over RPC)
```

The SDK does what a Mac does:

1. pull the log;
2. reduce it with the same rules;
3. show a read model (Today, lists, tasks);
4. turn intents into ops, apply them optimistically, and push them.

The protocol stays the same apart from those two keys. The SDK talks to the server only through `POST /v1/sync`. It keeps its own cursor,
`base`, pending queue and files, and never reads or writes the Mac app's data directory (except `tasks verify`, which
only reads it).

### Language: TypeScript

| Option | For | Against |
|---|---|---|
| **TypeScript port + shared fixtures (recommended)** | It's what agents and code mode write. It runs in Node, Deno, Bun and Workers, so one implementation serves the CLI, the sandbox and a Worker runner. It's the server's language. `fractional-indexing` is originally JS, and the date grammar was ported to Swift from the JS prototype. | It's a second reducer, the cost SPEC §5 avoided. Fixtures pay that cost down (§2). |
| Reuse Swift `TasksCore` (a Swift CLI) | No drift at all on this Mac. | macOS-only (`platforms: [.macOS(.v14)]`, Foundation and `@MainActor` throughout). It can't run in a sandbox the model writes code for, or in a Worker. Code mode would still need TypeScript. |
| Swift compiled to WASM, called from JS | One reducer. | A large Foundation-in-WASM binary, an exotic toolchain, and a debugging story nobody wants. It fails the simplicity rule. |
| A spec only, each client on its own | Nothing shared to maintain. | Drift shows up as an agent seeing a different Today than the user. Fixtures cost little more and catch it. |

The SPEC's objection to a second reducer was about running one on the *server* for snapshots. Once agents need a
typed TypeScript API, a TypeScript reducer exists either way. The work is keeping it equal to Swift (§2), and after
that, where it runs is a free choice.

### What's in `sdk/`

```
sdk/
  core/         pure, no I/O, runs anywhere
    op.ts         Op, Patch, per-key lenient decoding (SPEC §5 rule 6)
    reducer.ts    apply(state, op) → changed id; replay
    inverse.ts    the undo op of an op, given the entity before it
    fraction.ts   fractional-indexing 3.2.0, vendored with its MIT notice (the algorithm Swift ports)
    ordering.ts   place(moving, anchor, items): ties, tied-run re-keying, rebalance (Ordering.swift)
    dates.ts      CalendarDate, Day, DatePhrase.parse/match, DateLabel (DatePhrase.swift, Today.swift)
    views.ts      today(), sidebar(), list(), archive(): the app's orders and predicates
  replica.ts    confirmed log + pending + the §5 sync loop and error table, 409 recovery; Storage interface
  storage/      dir.ts (log.jsonl, pending.jsonl, rejected.jsonl, like the Mac's files), memory.ts
  tasks.ts      the API: refs, intents → ops, batches, dry-run, undo, log
  cli.ts        the `tasks` command
  run/          tasks.d.ts (what the model sees), host.ts, sandbox.ts (code mode, §7)
  test/         deno test: conformance (fixtures/core), sync (fixtures/sync + wrangler dev), CLI
```

`core/` and `replica.ts` use only `fetch`, `crypto.randomUUID` and `crypto.subtle`, so the same files can later run
inside the Worker. Only `storage/dir.ts` and `cli.ts` touch the file system.

**Runtime: Deno** (open decision 1).

- It runs TypeScript with no build step and `deno compile` makes one binary.
- `deno test` and `deno fmt` are built in, and with no npm dependencies there's no lockfile churn.
- Its permission flags can confine the CLI itself:
  - network only to the server's host;
  - file access only to its state directory and the token file.
- It's already the code-mode sandbox (§7).

Node would also work, but then the CLI needs a build step and still spawns Deno for `tasks run`.

## 2. Staying identical to the app

### What has to match

| Must be identical (an agent sees what the user sees) | Must be compatible (any valid answer works) |
|---|---|
| Reducer results, including `createdAt` / `updatedAt` | The exact keys `place()` picks, as long as they sort right |
| Inverse ops | Rebalance thresholds |
| The Today predicate, groups and the orders of every view (`(order, id)`, `completedAt` desc, `archivedAt` desc, done today ascending) | Text labels in CLI output |
| What a typed date phrase means for a given today and numeric order | |
| That every op the SDK builds passes the server's validation | |

Using the same fractional-indexing algorithm and porting `Ordering.place` line for line makes the second column match
anyway. It just isn't what correctness rests on.

### Shared conformance fixtures: `fixtures/core/`

This works like `fixtures/sync/`: the reference side writes the expected outputs once, they're checked in, and both
suites assert against them. **Swift is the reference,** because the app is what the user looks at.

| File | Case shape | Source of cases |
|---|---|---|
| `reducer.json` | `{ops[], expected: {tasks, lists}}` | SPEC §5 rules 1–6, the conflict cases in `ReducerTests.swift`, and wrong-typed values dropped per key (`completedAt: -1`, `when: "2026-02-30"`, unknown keys and types) |
| `reducer-random.json` | 200 seeded random op sequences and their final states | A Swift generator. The TypeScript side only replays them, so the two sides never need matching PRNGs |
| `inverse.json` | `{before, op, inverse}` | `Inverse.of`, including create → `deleted: true` / `archivedAt` |
| `fraction.json` | the existing `fractional-index-vectors.json`, moved here | npm `fractional-indexing` 3.2.0 |
| `ordering.json` | `{items, moving, anchor, expected}` | `OrderingTests.swift`: ties, tied runs, rebalance at 32 characters |
| `dates.json` | `{text, today, order, parse, match}` | Every case in `DatePhraseTests.swift`, plus month ends and year bounds |
| `views.json` | `{state, now, timeZone, today, sidebar, lists, archive}` | Today edge cases from `TodayTests.swift`: midnight, both dates set, completed yesterday, archived list, a DST change (America/Toronto on 2026-11-01) |
| `actions.json` | `{state, now, ids[], call, expected ops[]}` | One case per `Store+Actions` function. Ids and the clock are injected, so the ops are exact |

- **Regenerating:** `TASKS_WRITE_FIXTURES=1 swift test --filter Conformance` writes the `expected` fields from Swift.
  Plain `swift test` and `deno test` check them.
- **Drift:** a Swift change that alters behavior updates the fixtures in the same commit. The TypeScript suite then
  fails until it's ported, and that failure is the point.
- **Valid ops:** an SDK test imports `server/src/validate.ts` and runs every op the SDK builds through
  `parseSyncRequest`. That's a test-only import, so the server stays dependency-free.

### Checking against real data, offline: `tasks verify`

`tasks verify --app-data <dir>` reads the Mac app's `log.jsonl` and `snapshot.json`, read-only. It replays the log up to
the snapshot's cursor with the TypeScript reducer and diffs the result against the snapshot's state. That runs the port
against every op the user has ever made, with no network and no server. Run it after each port change and before each
SDK release.

## 3. The replica: sync, offline, concurrency

### Files and one command's life

State lives in `~/Library/Application Support/tasks-cli/<host>/`, or `$XDG_STATE_HOME/tasks/<host>/` on Linux.

- **It's keyed by server URL** because a replica's 409 recovery pushes every op it knows to whatever server it's
  talking to. If the same files were pointed first at `wrangler dev` and then at the live Worker, recovery would copy
  dev ops into the real log, or the other way round. A new URL means a new, empty replica.
- **The files** are `log.jsonl` (server entries verbatim), `pending.jsonl` (ops verbatim), `rejected.jsonl`, and
  `log.jsonl.bak-<ms>` during a recovery. That's the Mac's layout and its write order (SPEC §8).
- **No snapshot at first.** Replaying the log costs ~1 s at 100k ops (SPEC §8), and today's log is far smaller. Port
  `snapshot.json`, the same scheme as the Mac's, once a command measurably takes over ~200 ms.

A command:

1. Take the directory lock (`state.lock`, created with `O_EXCL`; wait up to 5 s; stale after 30 s if its pid is gone).
   Agents often run several commands at once.
2. Load the log and pending, and pull. A `--cached` command skips the pull.
3. Resolve refs and build the change against the fresh state (§4).
4. Append the ops to `pending.jsonl`, then push.
5. Report success only once each op id has come back in a returned page (SPEC §5).

A read is one request and a write is two. Building a write against fresh state matters for agents ("complete
everything due today" has to see today's tasks), so the pull before it is worth the round trip.

### Pending ops and offline

- Writes are durable before the push: they're in `pending.jsonl`, sent verbatim and deduplicated by op id. A retry or a
  crash never duplicates a write.
- **Offline:** the write applies locally and stays queued, and the command exits 75 (`EX_TEMPFAIL`): applied, not yet
  in the log. The next command pushes the queue first, before its own pull. `tasks status` shows the queue and the
  last error.
- **Chunks never split a batch.** A batch of ≤ 500 ops always goes in one request. The server appends a request
  contiguously and all-or-nothing (validation rejects the whole request), so a batch lands atomically.
- **The error table is SPEC §5's:**
  - `401`, `404`, `405` and `bad_request` stop with a clear message (exit 1).
  - `invalid_op` moves the op to `rejected.jsonl` and fails the command. The SDK validates first, so this means a bug.
  - `413` halves the chunk, but never below one batch.
  - `5xx` and network failures retry three times with backoff, then exit 75.

### 409 recovery

The SDK implements SPEC §5's recovery as written:

- every op in the log and in pending becomes pending, copied verbatim;
- the log is moved aside;
- the replica resyncs from 0.

A short-lived in-memory replica (a test, a one-off run) "knows" only what it pulled plus its own pending. It re-pushes
exactly that, which is conformant and harmless.

### Running alongside the Mac app

They're independent replicas, so this is the two-Macs case the protocol already handles.

- **Latency:** an agent's change shows on the Mac at its next sync: within 30 s while a window is open, at once on ⌘R
  or when the app becomes active. If that feels slow once agents are in daily use, it's the trigger to build SPEC §11's
  "head is now N" poke.
- **Conflicts:** the last write in log order wins, per field. The one that bites is `notes`, which is last-writer-wins
  as a whole string. An agent appending to notes while the user edits the same notes on a Mac loses one side. The CLI
  pulls just before it writes, which keeps that window small, and undo restores the agent's side.
- **Mac edits the agent can't see:** the agent never sees a Mac's pending, unpushed edits. The Mac pushes about 1 s
  after a change, so this only matters for an offline Mac.
- **No seeding:** the SDK never seeds the Inbox. A read command that writes would be a surprise, and the app seeds on
  launch anyway.

### "Today" depends on a time zone

- **Local:** `today` is the host's local date, computed with `Intl` in the host's time zone. The start and end of a
  day (for "completed today") are found the same way, which is where DST matters, so `views.json` covers it.
- **In a Worker:** the clock runs in UTC. The remote runner (§7) needs the user's zone, either as a `TIME_ZONE` var or
  passed in with each run.

## 4. The API surface

### Conventions

- **One schema everywhere.** The SDK returns plain JSON objects. `--json` prints exactly those objects, and a
  code-mode script sees exactly those objects.
- **Refs.** Anything that takes a task or list accepts:
  - its full id;
  - a unique id prefix of at least 4 characters, which is how Git refs work;
  - for lists, a name, case-insensitive, matched among active lists first and then archived ones.

  Output shows each id's shortest unique prefix, at least 6 characters, as `ref`. **Refs fail closed:** a missing or
  ambiguous ref is an error that lists the candidates, and the SDK never guesses. Duplicate list names are allowed, so
  they need a prefix.
- **Ids are stable.** An id is chosen once, at create, and never changes.
  - `add --id <id>` lets the caller pick it.
  - `add --key <text>` derives it: a UUIDv8 from SHA-256 of the key, lowercase. The create op's id is derived from the
    key too.
  - So repeating `tasks add "Pay rent" --key rent-2026-11` changes nothing: the SDK sees the task exists and returns
    it. Two replicas racing offline also leave one task (SPEC §5 rule 1, plus op-id dedup).
- **Dates.** A `DateInput` is `"YYYY-MM-DD"`, `null` to clear, or any text the app's date field reads ("fri",
  "next week", "3d", "nov 9", "the 9th").
  - Text resolves exactly as the popover's Return does (`DatePhrase.match`, INTERACTIONS-v2 §11) against the replica's
    today. Numeric dates use the locale's order, or `TASKS_DATE_ORDER=md|dm`.
  - Every result echoes the resolved date, and `tasks.date(text)` resolves one without writing.
  - Text that reads as no date is an error.
- **Places.** A place is `top`, `bottom`, `up`, `down`, `{after: ref}` or `{before: ref}`, the anchors of
  `Ordering.Anchor`.
  - `up` and `down` are ⌥⌘↑ and ⌥⌘↓, one slot among the open tasks of the task's list.
  - An anchor in another list moves the task there. "After X" is the full-list rule that drags in a Today group already
    use (SPEC §4).
- **Multi-select** is passing several refs. They apply as one batch, in the order given.
- **Validation is the server's, done first.** Limits are counted in UTF-16 units. The SDK fails with a message naming
  the limit rather than clamping silently as the app's fields do. A title must be non-empty after trimming (the app
  never writes an untitled task). A list name can't be empty.
- **No-ops write nothing,** as the Store's guards do (`t.title != title` and the rest). That makes every command except
  `toggle` idempotent:
  - completing a done task, or setting a date it already has, writes nothing;
  - moving a task to the list it's in writes nothing;
  - placing a task where it already is writes nothing, because `keyBetween` is deterministic.
- **A write returns a `Change`:** `{batch, summary, tasks, lists, synced}`, with the entities after the change.
  - `summary` uses the app's undo names (INTERACTIONS-v2 §9: "Complete 3 Tasks", "Move 3 Tasks", "Remove When") with
    the target added ("Move 3 Tasks to School").
  - Creates return the new entity instead.

### Every UI operation

Refs below are made up. In code mode, `tasks` is the API object and every call is awaited (§7).

**Tasks**

| UI operation (INTERACTIONS-v2) | SDK call | CLI | Code mode |
|---|---|---|---|
| New task in a list: ⌘N, the header +, double-click empty space (§6) | `add({title, list})`. It lands at the bottom of the list's open tasks | `tasks add "Buy milk" --list Groceries` | `await tasks.add({ title: "Buy milk", list: "Groceries" })` |
| New task from Today: When = today, in the default list (SPEC §2) | `add({title, when: "today"})`. With no `list`, the first active list | `tasks add "Call mum" --today` | `await tasks.add({ title: "Call mum", when: "today" })` |
| New task from a Today group's + | `add({title, list, when: "today"})` | `tasks add "Essay" --list School --today` | `await tasks.add({ title: "Essay", list: "School", when: "today" })` |
| New task with notes and dates, then edited in the detail pane | `add({title, notes, when, deadline, place})` | `tasks add "Trip" --deadline "nov 9" --notes - < notes.md` | `await tasks.add({ title: "Trip", deadline: "nov 9", notes })` |
| Rename (detail title, or in the row) | `rename(task, title)` | `tasks rename 3f9a2c "Buy oat milk"` | `await tasks.rename(t.id, "Buy oat milk")` |
| Edit notes (Markdown) | `setNotes(task, markdown)` | `tasks notes 3f9a2c -` (from stdin); `--append TEXT` | `await tasks.setNotes(t.id, t.notes + "\n- [ ] call back")` |
| Complete (checkbox, Space, ⌘K, menu) | `complete(tasks)` | `tasks done 3f9a2c 77b0e1` | `await tasks.complete(ids)` |
| Mark as not done | `uncomplete(tasks)` | `tasks undone 3f9a2c` | `await tasks.uncomplete(ids)` |
| ⌘K on a selection: completes all unless all are done, then uncompletes all | `toggle(tasks)` | `tasks toggle 3f9a2c 77b0e1` | `await tasks.toggle(ids)` |
| Set When: popover, typed phrase, quick picks, ⌘T, menu (§11) | `setWhen(tasks, date)` | `tasks when fri 3f9a2c 77b0e1`; `tasks when today …` | `await tasks.setWhen(ids, "next week")` |
| Remove When (Clear, ⌫, ×, menu) | `setWhen(tasks, null)` | `tasks when none 3f9a2c` | `await tasks.setWhen(ids, null)` |
| Set or remove Deadline | `setDeadline(tasks, date \| null)` | `tasks deadline "nov 9" 3f9a2c`; `tasks deadline none …` | `await tasks.setDeadline(t.id, "2026-11-09")` |
| Drag onto Today (sets When = today, the task stays in its list) | `setWhen(tasks, "today")` | `tasks when today 3f9a2c` | `await tasks.setWhen(ids, "today")` |
| Delete: ⌘⌫, menu, trash (§9) | `delete(tasks)` | `tasks delete 3f9a2c 77b0e1` | `await tasks.delete(ids)` |
| Undo / redo (⌘Z / ⇧⌘Z) | `undo(batch?)`, `redo()` | `tasks undo [batch]`, `tasks redo` | `await tasks.undo(change.batch)` |
| Move to another list: ⇧⌘M, menu, detail List pop-up, drop on a sidebar list (§10) | `move(tasks, {list})`. They land at the bottom, in the order given | `tasks move 3f9a2c 77b0e1 --to School` | `await tasks.move(ids, { list: "School" })` |
| Reorder in a list (drag, §14) | `move(tasks, {place: {after}})`, also `{before}`, `top`, `bottom` | `tasks move 3f9a2c --after 77b0e1`; `--top` | `await tasks.move(t.id, { place: "top" })` |
| Move up / down (⌥⌘↑ ⌥⌘↓) | `move(tasks, {place: "up"})` | `tasks move 3f9a2c --up` | `await tasks.move(t.id, { place: "down" })` |
| Reorder in a Today group | The same as a list reorder. The anchor is relative to the full list (SPEC §4) | `tasks move 3f9a2c --before 9c1d0f` | `await tasks.move(a, { place: { before: b } })` |
| Move into another list at a spot (two gestures in the app) | `move(tasks, {list, place})` | `tasks move 3f9a2c --to School --top` | `await tasks.move(t.id, { list: "School", place: "top" })` |

**Lists**

| UI operation | SDK call | CLI | Code mode |
|---|---|---|---|
| New list: ⇧⌘N, the Lists +, the sidebar menu (§12) | `addList(name, place?)`. It goes at the bottom of the sidebar | `tasks list add School` | `await tasks.addList("School")` |
| Rename a list | `renameList(list, name)` | `tasks list rename School "School 2026"` | `await tasks.renameList("School", "School 2026")` |
| Reorder lists: drag, ⌥⌘↑ ⌥⌘↓, Move Up / Down | `moveList(list, place)` | `tasks list move School --after Work`; `--up` | `await tasks.moveList("School", "top")` |
| Archive ("delete list") | `archiveList(list)` | `tasks list archive School` | `await tasks.archiveList("School")` |
| Unarchive (button, menu) | `unarchiveList(list)` | `tasks list unarchive School` | `await tasks.unarchiveList("School")` |

**Views**

| UI view | SDK call | CLI | Code mode |
|---|---|---|---|
| Today: groups in sidebar order, then Completed today (§13) | `today()` → `{date, groups: [{list, tasks}], done}` | `tasks today` | `const { groups } = await tasks.today()` |
| The sidebar with its counts | `lists()`. Active lists in order, each with `open` | `tasks lists` | `await tasks.lists()` |
| A list: open tasks in order, then Completed newest first | `list(list)` → `{list, open, completed}` | `tasks ls School`; `--done` adds Completed | `(await tasks.list("School")).open` |
| The Archive group: archived lists, newest first | `archive()` | `tasks archive` | `await tasks.archive()` |
| An archived list ("Archived Oct 28", still editable) | `list(list)`. `list.archivedAt` is set | `tasks ls School` (shows the banner line) | as a list |
| The detail pane: fields, raw notes, Created / Completed | `task(task)` | `tasks show 3f9a2c` | `await tasks.task(id)` |
| Sync now (⌘R) | `sync()` | `tasks sync` | (each run syncs) |

Moving into an archived list is refused with "School is archived; unarchive it first". The app never offers archived
lists as targets (§10), and a task moved there would quietly vanish from view. Adding a task to an archived list works,
as it does in the app.

**Not covered, on purpose:** selection, focus, navigation ("Show in School", ⌘1–⌘9), type-to-select, the sidebar
toggle, and the UserDefaults settings (Edit tasks, Theme, Glass). They're the app's local state and none of them is in
the log.

### Beyond the UI (agents need these)

| Need | SDK | CLI |
|---|---|---|
| Find a task without knowing its list (read-only; the app has no search) | `find({text, list, done, deleted})` | `tasks find milk` |
| Bring back a deleted task when there's no undo stack (`deleted: false`) | `restore(tasks)` | `tasks restore 3f9a2c` |
| What changed, and who did it (§5) | `log({since, actor, limit})` | `tasks log --actor 'agent:*' --since 2h` |
| One task's history (`git log -- <task>`, SPEC §6) | `log({task})` | `tasks show 3f9a2c --history` |
| Resolve a date phrase without writing | `date(text)` | `tasks date "next fri"` |
| Sync state, pending queue, actor, server | `status()` | `tasks status` |

## 5. Batches, attribution, review and undo

### One change, one batch

A batch is one SDK call (or one `tasks.batch(fn)` block), one CLI command, or one code-mode run. All of its ops carry
the same `batch` id and go in one request.

- **≤ 500 ops:** one request, so the server appends it contiguously and all-or-nothing.
- **More than that** (a bulk import) needs `--large`. It's split across requests, still under one `batch` id, so it's
  still undone as one unit, but it isn't atomic on the wire.
- **A code-mode run that throws writes nothing.** Its ops are pushed only once the script returns.

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
- **Storage:** the stored text becomes `JSON.stringify({id, at, type, target, set, actor, batch})`. `JSON.stringify`
  omits `undefined`, so every existing op's text, and therefore every hash and every fixture, is byte-for-byte
  unchanged. New fixture: `11-push-with-actor.json`.
- **Backward compatible:**
  - the Mac decodes ops with a keyed container, so it ignores both keys;
  - it copies log ops verbatim in a 409 recovery, so they survive;
  - its `PendingOp` resends text verbatim.

  The app needs no change.
- **Order of rollout:** today's server rejects unknown envelope keys, so the server change is deployed before the SDK
  writes anything (phase 2 comes before phase 3). Like any loosening, the server must **never be rolled back past it**:
  a 409 re-push of an agent op would then be `invalid_op` and get discarded (SPEC §5 "Validation may only loosen").
- **Who sets `actor`:**
  - the CLI uses `--actor`, else `TASKS_ACTOR`, else `agent:claude-code` when `CLAUDECODE=1` is set, else `cli`;
  - `tasks run` defaults to `agent`;
  - the remote runner uses `agent:<token name>`.

  The client declares it, which is enough for one user. Agent tokens (§9) are about being able to revoke access, not
  about proving who wrote what.

**Pushback, the server stamping the token's name instead:** that can't be forged, but it changes the entry format, and
it attributes ops wrongly after a recovery (whoever re-pushes gets credited). It's worth doing only if there are ever
other users.

### Review: `tasks log`

`tasks log` reads the replica's log and pending, newest first:

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

`undo(batch)` works from the log alone, on any replica.

1. Find the batch's ops in the log and in pending.
2. For each touched entity, rebuild it from the log as it was just before the batch's first op on it.
3. Write the inverse, as `Inverse.of` does: the touched keys go back to their earlier values. A created task gets
   `deleted: true`, and a created list gets `archivedAt`.

Two more rules make it safe hours later:

- **Conflicts.** A key someone has changed since the batch (its value is no longer what the batch wrote) is skipped
  and reported: "kept the later edit to the title of 3f9a2c". `--force` overwrites anyway. The app's ⌘Z is
  last-writer-wins, which is right for an undo pressed straight away and wrong for one made the next day.
- **Deterministic ids.** The undo batch's id is derived from the original's (a UUIDv8 of `"undo:" + batch`), and its op
  ids are derived from that. Then:
  - two agents undoing the same batch produce the same op ids, and the server keeps one;
  - "is this batch undone?" is "does its undo batch exist in the log?", so the answer needs no stored state;
  - `tasks undo` with no argument undoes this actor's newest batch that is neither undone nor itself an undo, and
    repeating it walks back further;
  - `tasks redo` undoes the newest undo.

Undo is itself a batch, with an actor, so it shows in `tasks log`. The app's own ⌘Z stack is unchanged and never sees
agent batches. A Mac "Undo agent change" or a history view can come later, built on the same two keys.

### Preview: `--dry-run`

Every write takes `dryRun`. It builds the change against a copy of the state and returns the `Change` and a diff
without queueing anything:

```
~ 3f9a2c "Buy milk"      when: — → 2026-11-06 (Fri)
~ 77b0e1 "Call dentist"  list: Inbox → School (bottom)
```

`tasks run --dry-run` runs the whole script against a fork: its reads see its own writes, nothing is pushed, and the
output is the combined diff. To commit, run it again without the flag. The diff was computed against a state that can
move, but a stale preview is the same accepted trade-off as a stale drag (SPEC §3).

## 6. The CLI

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
tasks undo [<batch>] [--force]  |  redo  |  sync  |  status  |  date <text>  |  verify --app-data <dir>
tasks run [<file>|-] [--dry-run]  |  types
global: --json  --ids  --dry-run  --cached  --offline  --actor A  --server URL  --large
```

`tasks help <command>` and `tasks --help` are written for a model reading them cold: one line per command, then one
example each.

### Output and exit codes

- **Text by default.** It reads like the app: chips as the rows show them ("Overdue · 2d", "Due today", "Fri"), the
  6-character ref first, and a closing line naming the batch and how to undo it.
- **`--json`** prints the SDK's objects: an array for lists of things, an object otherwise. **`--ids`** prints one id
  per line, for pipes.
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
  generated once and persisted before the push, so a retried command never double-applies.

## 7. Code mode

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

What we take from Cloudflare's design, and what we don't:

- **We take:**
  - the model gets TypeScript declarations with doc comments and one tool that runs code;
  - the sandbox has no network, and its only capability is the API binding;
  - `console.log` output comes back with the result.
- **We don't take:** `@cloudflare/codemode`'s rule that scripts must be JavaScript ("do NOT use TypeScript syntax").
  Locally, Deno runs TypeScript as written. Remotely, the runner strips the types first (below), so the same script
  works in both places.

### Local: `tasks run`

```
tasks run (Deno, holds the replica and token)
   │  spawns: deno run --no-prompt --no-remote --deny-import --v8-flags=--max-old-space-size=128 sandbox.ts
   │          (no --allow-* flags, empty env, empty cwd)
   │  stdin  → the script, then replies   {id, result | error}
   │  stdout ← calls {id, method, args}, then {done, result | error}
   ▼
sandbox.ts: `tasks` is a Proxy whose methods are those calls;
            the script is imported from a data: URL, so its TypeScript runs as written
```

**Spike (throwaway, not committed; Deno 2.9.8).** In the child:

- reading a file, reading env, `fetch` and spawning a process each threw `NotCapable`;
- stdin and stdout worked;
- `import("data:application/typescript;base64,…")` loaded and ran a typed script with no permission (the docs only
  promise that for Workers);
- a Node host served `tasks.today()` and `tasks.complete([...])` over the pipe;
- a whole run took ~50 ms.

**One hole to close before this ships: remote imports.**

- Deno 2 gates module imports with a separate `import` permission. `deno run --help` (2.9.8) gives its default as
  `deno.land`, `jsr.io`, `esm.sh`, `raw.esm.sh`, `cdn.jsdelivr.net`, `raw.githubusercontent.com` and
  `gist.githubusercontent.com`.
- So a no-flags script could leak task data in an `import("https://…?d=…")` URL.
- The child therefore also gets `--no-remote --deny-import`, an empty environment and an empty working directory.
- A phase-4 test checks that a remote import fails. The probe that would have shown today's default needs the network,
  so it wasn't run here.
- Deno's docs ask for "more than one layer of defense". The second layer is the API itself: it's the script's only
  effect, and everything it does is undoable.

So:

- **The token never enters the sandbox,** and the script can't touch files or the network. It can only call the API,
  and every effect the API has is undoable.
- **The host runs the whole script against one working state.** Reads see earlier writes, the writes collect into one
  batch, and the batch is pushed once at the end, as one request.
- **Limits:**
  - 10 s of wall time, after which the host kills the child and writes nothing;
  - 128 MB of heap;
  - 500 ops (more needs `--large`);
  - a 100 KB result and 200 log lines.
- **`console.log` is captured,** for the result's `logs`.
- **Errors come back with the script's line and column,** because a `data:` module keeps its own line numbers. API
  errors are typed: `NotFound`, `Ambiguous` (with candidates), `Invalid` (with the field), `NoActiveList`, `Limit`.
  An unknown method gets "no `tasks.compelte`; did you mean `complete`?".

The result is one JSON object:

```jsonc
{ "ok": true, "result": <what the script returned>, "logs": ["…"],
  "change": { "batch": "2c1f9e…", "summary": "Set When: Sun, Nov 1 (4)", "tasks": [ … ] }, "synced": true }
{ "ok": false, "error": { "type": "Ambiguous", "message": "\"Work\" matches 2 lists: 4be1c0, 9a77f2", "line": 3 },
  "logs": [], "change": null }
```

### What the model sees: `tasks.d.ts`

`tasks types` prints it, and its first line points to `tasks run`. It's about 1,500 tokens. It's hand-written for the
model, short and with comments, and a type test checks that the SDK implements it.

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

### Remote, later: on our Worker

This is for agents with no shell and no token on the machine: Claude on the web or a phone, cloud agents.

```
MCP client ──▶ Worker /mcp (tools: tasks_types, tasks_run) ──▶ Runner DO (a replica: SDK core + its own SQLite)
                                                                   │ RPC: UserLog.sync(cursor, base, ops)
                                                                   │ env.LOADER.get(…): the script, with
                                                                   ▼   env.tasks = an RPC stub, globalOutbound: null
                                                               Dynamic Worker (the script)
```

- **The runner is just another replica,** so the log DO stays exactly as dumb as it is now. It lives in its own DO, keeps
  its reduced state hot in memory with a copy in its own storage, and syncs by calling `UserLog.sync()` over RPC. No
  token is involved, and the protocol is the same.
- **The script runs in a Dynamic Worker:**
  - its network is blocked (`globalOutbound: null`);
  - its only capability is `env.tasks`, an RPC stub into the runner;
  - its actor comes in through the stub's `props`, so a script can't claim to be someone else.
- **Spike (throwaway, local `wrangler dev`, wrangler 4.156):** the dynamic worker's `fetch()` threw "not permitted to
  access the internet". `ctx.exports.TasksApi({ props: { actor } })` passed an RPC stub whose methods ran in the parent
  with `props.actor` set. `console.log` could be captured. No Cloudflare resources were touched. Cloudflare notes that
  Miniflare is not a security boundary, so this spike showed the wiring works, not the isolation.
- **What the platform gives** (as of 2026-10, sources in §13):
  - **Availability:** open beta since 2026-03-24, Workers Paid only.
  - **Cost:**
    - 1,000 Dynamic Workers a month are included, then $0.002 per unique Worker per day, plus normal request and CPU
      pricing.
    - A different script is a different Worker, so every run counts.
    - Personal use stays inside the free 1,000.
  - **Code:** modules must be JavaScript. The runner strips the types first (esbuild, as `@cloudflare/worker-bundler`
    does).
  - **Limits:**
    - `limits: { cpuMs, subRequests }` per run;
    - memory and wall time aren't documented, so the runner enforces its own 10 s with a race, as
      `@cloudflare/codemode`'s executor does;
    - a DO can run at most 10 Dynamic Workers at once, which is plenty here.
  - **Off the shelf:** `@cloudflare/codemode`'s `DynamicWorkerExecutor` (0.5.x, experimental) does the load, timeout
    and log capture. Our own version is about 60 lines, and owning it keeps the server free of dependencies.
- **Before building it:** confirm the account is on Workers Paid, and set `TIME_ZONE`.
- **New resources:** a `worker_loaders` binding, a second DO class with its migration, and an MCP route. Each one needs
  the user's go-ahead (BRIEF rules).

## 8. CLI, code mode or MCP: what each is good at

| | CLI | Code mode (`tasks run`, or remote) | MCP with one tool per operation |
|---|---|---|---|
| Context cost | Nothing until the model runs `tasks --help` (~1k tokens) | `tasks.d.ts`, ~1.5k tokens, read once | ~25 tool schemas, ~4–6k tokens, in every request |
| Round trips for "reschedule every overdue task outside Work" | 2 (`find … --ids \| tasks when tomorrow -`) | 1 | 1 + one per task |
| Atomic multi-step change | Within one command | The whole script | No; each call is its own change |
| Logic (filters, loops, conditions) | Shell and `jq` | Real code, typed | In the model's head, through its context |
| Who it serves | Any agent with a shell (Claude Code), and people | Shell agents (local); any MCP client (remote) | MCP clients |
| Debugging | Run the same command yourself | Rerun the script with `--dry-run` | Read the transcripts |
| Cost to build | Medium (the CLI is most of the SDK's surface) | Small on top of the CLI (sandbox + d.ts) | Small, but a second surface to keep equal to the UI |

**Recommendation:**

- **CLI first.** Claude Code on this Mac is the first agent, and the CLI is also the human and debugging surface.
- **Code mode next,** for anything that's more than one command.
- **MCP only as a wrapper around code mode,** with two tools:
  - `tasks_types` returns the d.ts;
  - `tasks_run` takes a script and returns the result object.

  That's a ~50-line stdio server over `tasks run` for desktop clients, and later the remote `/mcp`. **Pushback, one
  tool per UI operation:** it's the expensive pattern code mode exists to replace, and it would be a third surface to
  keep equal to the app.

## 9. Tokens

- **Now: share the one token, locally.** The CLI reads `TASKS_URL` and `TASKS_TOKEN` from the environment, or else
  `~/.tasks-sync.env` (`API_TOKEN`, plus a `TASKS_URL` line).
  - There's no default URL, so a dev setup can't hit the live log by accident.
  - The token is never printed (`tasks status` says "token: set, from ~/.tasks-sync.env") and never reaches a code-mode
    script.
  - A local agent with a shell could read that file anyway, so a separate token on this Mac would add little.
- **Later, when anything runs off this Mac:** named, revocable tokens.
  - One secret, `AGENT_TOKENS`: JSON `{"<name>": {"sha256": "<hex>", "write": true}}`.
  - The Worker checks `API_TOKEN` as it does now, then the SHA-256 of the presented token against the entries.
  - The name becomes the default actor.
  - A read-only token pushing any ops gets `403 read_only` (a new error code, never seen by today's clients).
  - Revoking one is removing its entry and running `wrangler secret put`, a Cloudflare change, so it's the user's.

  **Pushback, tokens kept in the DO behind an admin API:** that's more surface than one person needs. A secret is
  versioned with deploys and already requires the user's hand.

## 10. Server changes

| When | Change | Size |
|---|---|---|
| With the CLI (phase 2) | `actor` and `batch` envelope keys (§5): `validate.ts`, one fixture, SPEC §5's tables. Deploy with the user's approval | ~15 lines |
| Remote code mode (phase 5, optional) | `AGENT_TOKENS` (§9), the Runner DO, the `worker_loaders` binding, `/mcp` | A new module, ~300 lines |

**Not proposed:**

- A read-model endpoint (`GET /v1/tasks`). Replicas reduce locally, and the runner reduces in its own DO. A server
  read model would be the server-side reducer and snapshot that SPEC §5 deferred, for no gain.
- A WebSocket. SPEC §11 still holds, unless agent latency on the Mac starts to bother the user (§3).

## 11. Build order

Each phase ends with something testable, like SPEC §10.

| Phase | Build | Done when |
|---|---|---|
| 1. Core | `sdk/core/` port. `fixtures/core/` with the Swift `ConformanceTests` that write and check them (test-only additions in `app/TasksCore/Tests`). `tasks verify`. | `swift test` and `deno test` pass the same fixtures, and `tasks verify` matches the Mac's real snapshot |
| 2. Server keys | `actor`/`batch` (§5), the new fixture, SPEC update. It can run alongside phase 1. Deploy only after the user approves | Server tests are green, every old fixture is byte-identical, and the deploy is smoke-tested |
| 3. Replica + CLI | `replica.ts` (sync loop, error table, 409 recovery), `storage/dir.ts`, the lock, `tasks.ts` (refs, intents, batches, dry-run, undo, log), `cli.ts` with every command in §6 | Every `fixtures/sync` row and the recovery cases against `wrangler dev` (wiped, restored, healthy). Then the CLI and a scratch Mac instance on the same `wrangler dev`, both editing, online and offline: both converge and match a fresh replica |
| 4. Local code mode | `tasks.d.ts`, `tasks types`, `tasks run` (host + sandbox), the two-tool stdio MCP server, and a short `docs/AGENTS.md` that teaches an agent the CLI and `tasks run` | A scripted agent task ("reschedule overdue outside Work") runs as one batch, `--dry-run` matches the real run, `tasks undo` reverts it, and an over-limit script writes nothing |
| 5. Remote (optional) | Agent tokens, the Runner DO, the Worker Loader, `/mcp` | The same scripted task from a remote MCP client. Only with the user's approval of each new Cloudflare resource |

Later: the Mac app shows who changed what (a history view, an "agent" mark) and can undo an agent batch, using the same
two keys.

## 12. Open decisions

1. **The SDK and CLI runtime.** *Recommend Deno:* TypeScript with no build, a single binary, built-in tests, the
   permission model for both the CLI and the sandbox, and no npm dependencies. The alternative is Node 24 with a build
   step, still spawning Deno for `tasks run`.
2. **Attribution.** *Recommend client-declared `actor` + `batch` on the envelope (§5):* tiny, backward compatible, and
   enough for review and undo. The alternative is the server stamping the token name, which can't be forged but is
   wrong after a recovery and changes the entry format.
3. **Do agent writes apply at once?** *Recommend yes, with the change summary and an undo command in every result,*
   and `--dry-run` when the agent or the user wants a preview. Preview-first by default doubles every agent's turns,
   and nothing an agent can do is irreversible: deletes are a field and lists only archive. The one permanent effect is
   log growth, and the per-run op limit bounds it.
4. **Agent undo conflicts.** *Recommend skipping keys changed since the batch, and saying so* (`--force` overrides). The
   alternative is the app's last-writer-wins ⌘Z, which can wipe a day-later user edit.
5. **Tokens.** *Recommend sharing the one token for local use now,* and named, revocable agent tokens (one secret)
   only when something runs off this Mac.
6. **MCP.** *Recommend only a two-tool wrapper around code mode* (`tasks_types`, `tasks_run`), stdio first. Not one tool
   per operation.
7. **Remote code mode (phase 5).** *Recommend deferring it* until an agent without a shell needs Tasks. When it's
   needed, build it as a Runner DO replica with the Dynamic Worker Loader, after checking the Loader's availability and
   cost on the account.
8. **Typed dates in the CLI.** *Recommend the popover's reading* (`DatePhrase.match`, what Return sets), always echoing
   the resolved date. The alternative is strict `parse` only, safer for an agent's typos but unlike the app ("next"
   alone is Next Week in the app).

## 13. Research notes

These were checked in primary sources on 2026-10-31. Anything not confirmed is marked.

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

**Dynamic Worker Loader**

- **Status:** open beta for Workers Paid since 2026-03-24.
  https://developers.cloudflare.com/changelog/post/2026-03-24-dynamic-workers-open-beta/
  - GA is unconfirmed: there's no announcement, though the docs no longer show a beta badge.
- **Pricing:** creation has been billed since 2026-05-26. https://developers.cloudflare.com/dynamic-workers/pricing/
  - 1,000 Dynamic Workers a month are included, then $0.002 per unique Worker per day.
  - `load()` counts every call. `get(id)` counts once per id, and the code for an id must be identical.
- **API:** `get(id, cb)` and `load(code)`; a `WorkerCode` is `{compatibilityDate, mainModule, modules, env,
  globalOutbound, limits, …}`. https://developers.cloudflare.com/dynamic-workers/api-reference/
  - Modules are JavaScript, with no TypeScript and no build step.
    https://developers.cloudflare.com/dynamic-workers/getting-started/
  - An RPC binding is passed as `env: { X: ctx.exports.Api({ props }) }`; the methods read `this.ctx.props`.
    https://developers.cloudflare.com/dynamic-workers/usage/bindings/
  - `globalOutbound: null` makes `fetch` and `connect` throw while bindings still work.
    https://developers.cloudflare.com/dynamic-workers/usage/egress-control/
- **Limits:** `limits: { cpuMs, subRequests }`. A request can run at most 4 Dynamic Workers at once and a DO at most 10;
  memory and wall time aren't documented. https://developers.cloudflare.com/dynamic-workers/platform/limits/
- **Local dev:** it works in `wrangler dev`, as the spike above confirmed. "Miniflare is not a security boundary for
  untrusted code."

**`@cloudflare/codemode`**

- 0.5.x, experimental, rewritten on 2026-02-20 to be runtime-agnostic.
  https://developers.cloudflare.com/changelog/post/2026-02-20-codemode-sdk-rewrite/
- `DynamicWorkerExecutor` returns `{result, error?, logs?}` and uses a `Promise.race` timeout.
- Its default prompt tells the model to write JavaScript only.
  https://developers.cloudflare.com/agents/model-context-protocol/codemode/

**Local sandboxes**

- **Deno:** with no flags, code can't touch files, the network, env or subprocesses. `--no-prompt` stops it prompting
  on a TTY, and the docs advise more than one layer of defense. https://docs.deno.com/runtime/fundamentals/security/
  - Per-Worker permissions still need `--unstable-worker-options`, which is why the plan uses a child process instead.
  - That `data:` imports need no permission is documented only for Workers. The spike confirmed it for `import()`.
  - The default allow-list for remote imports is the hole closed in §7.
- **`quickjs-emscripten`** is an in-process alternative: memory, stack and deadline limits, and only one pending async
  call at a time. It's JavaScript-only and unaudited. A Deno child is simpler and runs TypeScript.
- **Node's `vm`** is not a sandbox: "The `node:vm` module is not a security mechanism. Do not use it to run untrusted
  code." https://nodejs.org/api/vm.html
