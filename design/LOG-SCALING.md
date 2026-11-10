# How the change log scales for long-time users

A design study, not a plan to build (the user, 2026-11-08: "ok yea forget diffs. I like trimming and truncation. let's
not implement it but let's think about it from a scaling perspective if we get users who use for a long time.").
"Trimming" here means compaction and checkpoints; "truncation" means compression on disk and on the wire. Per-note
diffs are out.

Measured on a copy of the user's `log.jsonl` and `snapshot.json` on 2026-11-08. Cloudflare limits are from
developers.cloudflare.com (Durable Objects limits and pricing, Workers limits), read the same day.

## 0. The short version

- Nothing hurts today, and nothing will for about a year at the user's pace.
- Client disk is never the problem. The first walls are elsewhere:
  1. **The remote MCP's undo** holds the whole log in memory. It runs out of the 128 MB isolate at roughly 140k ops:
     about 2.5 years at the user's pace, 6 months for a 5× user.
  2. **A 409 recovery on the Workers Free plan.** Rebuilding a wiped server writes every op again, and Free allows
     100,000 rows written a day across the account. Past ~50k ops (about 11 months) a recovery takes more than a day.
     It still finishes; it just waits for the daily reset.
  3. **A new device's first sync** passes a minute at around 250k ops (4–5 years for the user, about a year at 5×).
  4. **The fallback full replay** (after a snapshot schema bump, a 409, or a bad snapshot) reads the whole log into
     memory at once. On an iPhone that becomes a memory risk somewhere past ~500k ops.
- Recommended order: (1) stream the log instead of holding it, in the MCP's undo and in the full replay; no format
  change. (2) An additive server checkpoint for new devices, with the full log kept on the server. (3) Client-side
  compaction last, if ever. Tombstone expiry only as a user-facing Trash rule. Compression on disk isn't worth it;
  on the wire it's already done for downloads.

## 1. How it works today

### The pieces

| Replica | Where | Holds | Reads old ops when |
|---|---|---|---|
| Sync server | `server/`, one `UserLog` DO (`idFromName("me")`), SQLite | `log(seq, id UNIQUE, received, op, hash)`: every op since seq 0, verbatim | A pull from an old `from` (a new device, a 409 resync) |
| Mac app | `~/Library/Application Support/Tasks/` | `log.jsonl` (server entries verbatim), `snapshot.json` (state at a cursor + byte offset), `pending.jsonl` | Fallback replay only |
| iPhone app | Same `TasksCore` and files, in the app's container | Same | Same |
| CLI | `~/Library/Application Support/Tasks CLI/<host>/`, its own replica | Same files, a second full copy on the Mac | `tasks log`, `tasks undo`/`redo`, `tasks show --history`: each call reads and decodes the whole log (`Persistence.readEntries`) |
| Remote MCP | `remote/`, one `Replica` DO (`idFromName("main")`), SQLite | `log`, `pending`, `rejected`, `snapshot` (rewritten every 1,000 entries) | Wake folds snapshot + tail; `undo` builds `History` from every entry, cached in memory (`SqlReplicaStorage.entries`) |

### The protocol

- `POST /v1/sync {from, base, ops}`. The server checks `base` against the hash at `from − 1` (409 on mismatch),
  appends with dedup by op id, and returns up to 1,000 entries (or 4M UTF-16 units) from `from`, br/gzip-compressed.
- `seq` is dense and 0-based. A client's cursor is a count; `base` is the hash of its last entry. The chain is
  `hash = SHA-256(prevHash + "\n" + opText)`. Clients never compute hashes, only echo them.
- Launch on the Mac and iPhone: decode the snapshot, seek `log.jsonl` to `logOffset`, replay the short tail. Cost is
  O(state + tail), flat in log length.

### Conflicts

- Log order is the only clock. Rule 1: first create wins. Rule 2: per-field last writer wins. Rule 3: an update to
  an unknown id is ignored. Rule 6: unknown types and keys are ignored, so old clients survive new ops.
- **Notes** are one field: the whole string, last writer wins. Two devices editing the same note concurrently lose one
  side. Each commit (end of editing or a ~1 s idle) writes the whole note again, which is why notes are 24% of the
  bytes.
- Delete and archive are fields (`deleted`, `archivedAt`), so deleted things stay in state and every op stays in the
  log.

### Who needs old ops, and why

| Need | Old ops? | Why |
|---|---|---|
| Today's state on a device that has a snapshot | No | Snapshot + tail |
| Undo on the Mac and iPhone (⌘Z, the Undo notice) | No | `UndoManager` holds inverse ops made at perform time, per session |
| Restore from Trash, Put Back, restoring a list | No | `deleted`/`archivedAt` are fields in state; the snapshot keeps deleted entities |
| CLI/MCP `undo <batch>` and `redo` | **Yes**, back to that batch | The state just before the batch, and every later op, to skip keys edited since |
| `tasks log`, `tasks show --history` | **Yes**, all | History and attribution (`actor`, `batch`) exist only in ops |
| A new device's first sync | **Yes**, all | There is no server snapshot; it pulls from 0 |
| A snapshot schema bump (an app update) | **Yes**, all | The new reducer rebuilds state from the log. This is also how an old client's state picks up fields it couldn't read before (schema 2 added `kind` and list `notes` this way) |
| 409 recovery | **Yes**, all | "A Mac never discards an op it knows": the clients are the server's backup. A wiped or rolled-back server is rebuilt from their logs |
| The server's cursor model | **Yes**, the hash at any client's cursor | `base` must match `hash(from − 1)`; `from` indexes a dense seq |

## 2. Growth

### Measured (1,293 entries over 8.2 days, 2026-10-30 to 11-08)

- 157 ops/day, 57.8 KB/day, 377 B per line. Since Nov 1 the pace is lower (112 ops/day, 42 KB/day); the first two
  days include setting up. The projections use the higher figure.
- Envelope (`seq`, `received`, `hash`) is 117 B per line, 31% of the file. The hash alone is 64 B.
- By bytes: moves (`{list, order}`) 32%, notes updates 22%, completes 9%, `when` 8%, creates 15%.
- Notes updates: 211 ops, 24% of bytes, average 561 B, max 5.3 KB. Note values: median 42, p90 252, max 4,864 chars.
- **Superseded:** 64% of ops and 58% of bytes are fully overwritten by later writes. The live ops are 199 KB of 476 KB.
- **Trash:** 40 of 130 tasks are deleted or in a deleted list, and 9 of 17 lists are deleted. Ops on trashed things:
  35% of ops, 29% of bytes.
- Snapshot: 64 KB, 503 B per task. New tasks: 5.5 a day since Nov 1 (15.8 a day overall).
- Actors: the app 1,081, `agent:claude-code` 190, `agent:claude` 18, `agent:muse` 4.
- Per op in SQLite (same schema, 50k synthetic rows): the server 458 B (the `id` unique index included), the MCP
  replica 369 B.
- In memory: a decoded entry is ~610 B of JS heap; `History` adds ~150 B per op.

### Compression of the same data

| Data | gzip-6 | brotli-4 | brotli-11 | zstd-3 | zstd-19 | xz-9 |
|---|---|---|---|---|---|---|
| `log.jsonl` (476 KB) | 3.5× | 4.0× | 4.7× | 3.9× | 4.4× | 4.5× |
| `snapshot.json` (64 KB) | 3.1× | 3.0× | 3.7× | 3.0× | 3.3× | 3.4× |
| Op text only, no envelope | 4.6× | 5.3× | 6.4× | 5.0× | 5.8× | 6.0× |

- A first sync's pages at brotli-4 come to 3.9×. The server already sets `Content-Encoding: br` or gzip, so
  **downloads are already compressed on the wire.** Pushes are not compressed.
- 64 KB zstd frames (an append-friendly on-disk layout) keep 3.5×.
- One 510 B notes line compressed alone shrinks only to ~375 B, so compressing each op or each row is pointless.
  Compression only pays over many ops.

### Projections

1× is the measured 157 ops/day (57k ops a year). 5× is a heavy user at 785 ops/day; 3× sits in between, at 60% of
the 5× figures. Tasks grow at ~6 a day at 1× and ~30 at 5×. Time assumes 0.15–0.4 s per 1,000-entry page.

| | 1× · 1 y | 1× · 3 y | 1× · 5 y | 5× · 1 y | 5× · 3 y | 5× · 5 y |
|---|---|---|---|---|---|---|
| Ops | 57k | 172k | 287k | 287k | 860k | 1.43M |
| Client `log.jsonl` (×2 on a Mac with the CLI) | 22 MB | 65 MB | 108 MB | 108 MB | 324 MB | 540 MB |
| `snapshot.json` (grows with tasks, not ops) | 1.1 MB | 3.3 MB | 5.5 MB | 5.5 MB | 17 MB | 28 MB |
| Server DO | 26 MB | 79 MB | 131 MB | 131 MB | 394 MB | 657 MB |
| Server + MCP replica on Cloudflare | 47 MB | 142 MB | 237 MB | 237 MB | 711 MB | 1.19 GB |
| New device: download (br) | 5.5 MB | 17 MB | 28 MB | 28 MB | 83 MB | 138 MB |
| New device: pages / time | 57 / 9–23 s | 172 / 26–69 s | 287 / 43–115 s | 287 / 43–115 s | 860 / 2–6 min | 1,430 / 4–10 min |
| Launch from snapshot (grows with tasks; 22 ms per 10k on an M5 Pro) | ~5 ms | ~15 ms | ~25 ms | ~25 ms | ~75 ms | ~120 ms |
| Fallback full replay (M5 Pro; iPhone slower) | 0.2 s | 0.55 s | 0.9 s | 0.9 s | 2.8 s | 4.6 s |
| Fallback peak memory (file + decoded entries) | ~60 MB | ~170 MB | ~280 MB | ~280 MB | ~850 MB | ~1.4 GB |
| MCP `undo` memory (decoded log + History) | ~45 MB | ~130 MB ✗ | ~220 MB ✗ | ~220 MB ✗ | ✗ | ✗ |
| Rows written to rebuild a wiped server (Free: 100k/day) | 57–115k | 172–344k | 287–574k | 287–574k | 0.9–1.7M | 1.4–2.9M |

The memory and launch figures are estimates from the measured per-entry costs, not runs at that size.

### Where each starts to hurt

- **Client disk:** never really. 540 MB on a phone is visible in iPhone Storage but not a failure. The Mac keeps two
  copies (the app and the CLI).
- **Snapshot size:** grows with tasks, not ops; completed and deleted tasks pile up. At ~30k tasks (5× · 3 y) the
  decode passes its 60 ms budget (18 ms per 10k tasks today), launch passes 100 ms at ~45k tasks, and T8 finding 2 (the snapshot rewritten after every sync) becomes ~17 MB per edit
  if it isn't fixed first.
- **Server storage:** fine everywhere on Paid (10 GB per DO, $0.20/GB-month past 5 GB). On Free: 5 GB per account,
  and the limits FAQ says 1 GB per DO on Free (the limits table says 10 GB without a plan split). 5× · 5 y puts the
  server DO at 657 MB; it would reach 1 GB around year 7–8 at 5×. When it's full, writes fail with `SQLITE_FULL`.
- **Rows read** (Free: 5M/day): a first sync reads every row once, fine to 5M ops. The MCP's `undo` reads every row
  per call when its cache is cold.
- **Rows written** (Free: 100k/day per account, deletes count, and D1's rule, which DO billing follows, adds a row per
  index update): ordinary use is under 2k/day even at 5×. A **409 recovery** writes every op again, once per row plus
  its `id` index, and the MCP replica's own recovery writes its pending queue and log again on the same account. Past
  ~50k ops a recovery on Free spans more than a day: writes fail with an error, the client backs off (at most 60 s)
  and finishes after the 00:00 UTC reset. Nothing is lost, but sync is stuck "Restoring" for days.
- **MCP memory (128 MB per isolate):** `undo` decodes and caches the whole log, then builds `History` over it. It fails
  past ~140k ops: 2.5 years at 1×, 6 months at 5×. This is the first real wall.
- **Fallback replay:** `Persistence.loadOnQueue` reads the whole file into one `Data` and decodes every entry before
  folding. On a Mac that's seconds at worst. On an iPhone, jetsam limits sit around 1.5–3 GB depending on the model,
  so past ~500k ops a schema-bump launch could be killed. That launch is also when the user has just updated the app.
- **CLI history:** `tasks log`/`undo`/`show --history` re-read the whole log per call: ~1 s at 1× · 5 y, ~5 s at 5×.
- **New device first sync:** a minute or more past ~250k ops, ~10 minutes at 5× · 5 y. On an iPhone it has to finish
  in the foreground (or across launches; it resumes from the cursor).
- **Request limits:** a DO's 1,000 req/s and 30 s CPU per request are far away. The Free Worker's 10 ms CPU per request
  is the tightest: the Worker parses and validates up to 500 ops per push, which a 409 recovery does in bulk.

## 3. Options

### 3a. Client-only compaction: drop superseded ops below the snapshot

Two forms:

- **Prefix truncation:** once a snapshot is written, drop `log.jsonl` before `logOffset`. The snapshot becomes the
  base, not a cache.
- **Live-ops filter:** keep, in their original order and byte for byte, only the ops that still hold a winning value
  (the first create of each entity, and each op that is the last writer of at least one field). Measured: 42% of the
  bytes remain.

| | |
|---|---|
| Changes | `TasksCore` `Persistence` only (Mac, iPhone, CLI). The server, protocol and wire don't change. |
| User loses | With prefix truncation: CLI history and undo before the snapshot; schema bumps can't rebuild from the log, so every reducer or model change needs a snapshot migration in code. With the filter: history of superseded edits ("what was this note last week"). |
| 409 recovery | Weakened. A truncated client can't help rebuild a wiped server. A filtered one can: re-pushing the live ops in order rebuilds the same state, but a restored server loses the superseded history. |
| Compatibility | Local only. An old app version opening a truncated log sees a snapshot whose offset no longer matches, falls back to replay, and gets an empty or partial state. So the snapshot needs a new schema number and a "log starts at seq N" marker, and old versions must refuse it. |
| Risk | Medium. Prefix truncation turns a cache into the source of truth. The filter has to copy the reducer's rules 1–3 and 6 exactly: a last write that the reducer ignores (a wrong-typed value, an update before its create) must not cost the earlier value it masks. |
| Gain | Client disk, the fallback replay, CLI history time. It does nothing for the server, new devices or the MCP. |

Client disk is the cheapest resource here, so this buys the least.

### 3b. Server checkpoint for new devices

The server keeps the whole log and adds a checkpoint: state at some `seq` (every ~10k ops, say), with that seq's
hash. A new device pulls the checkpoint plus the tail instead of the whole log.

| | |
|---|---|
| Changes | Server: a `checkpoint` table and a way to fetch it (a new route, or `from: "checkpoint"`). Protocol: a client that knows about it asks for it when its cursor is 0; the cursor and hash then start at the checkpoint's seq, so `from`/`base` keep working unchanged. Client: start from a checkpoint (as from a snapshot, but with no log behind it). |
| Building it | The SPEC (§5) rejected this because it needed a second reducer in TypeScript. That reducer now exists: `remote/src/core/state.ts`, held to the Swift by the parity suite. Or, reducer-free: the checkpoint is the live-ops filter (3a) run on the server, so it stays a list of verbatim ops, and any client version replays it with its own reducer, unknown keys included. |
| User loses | Nothing. The full log stays on the server. A new device has no local history before the checkpoint; `tasks log` there could fetch older pages on demand. |
| Compatibility | Additive. Old clients never ask and pull from 0 as now. A checkpoint built from state (not ops) must record its reducer version, and a newer client falls back to the full log if the checkpoint is older than its reducer. The verbatim-ops form avoids that. |
| Risk | Low to medium. A wrong checkpoint gives a new device wrong state while every other device is right. Check it: build the checkpoint and fold the full log in the test suite and compare, as the parity suite does. |
| Gain | New-device time and download shrink to the live state plus the tail: at the user's live-op rate, ~40% of the log. With tombstone expiry (3c) much less. A wiped-and-rebuilt server needs nothing new. |

### 3c. Tombstone expiry

Deleted tasks, deleted lists and their tasks are removed for good after N days in Trash ("Empty Trash", or an
automatic 30-day rule).

| | |
|---|---|
| Changes | A real purge: SPEC §11 "Hard deletes". The log is rewritten without the purged entities, which gives a new hash chain, and every device gets a 409. Recovery would then re-push the purged ops, so the purge needs its own signal (a "purged ids" list the server sends, which clients drop from the log and pending before recovering). Server, protocol and every client change. |
| Lighter form | Expire only from checkpoints and snapshots (3b, 3a): drop trashed entities from the checkpoint and keep their ops in the server log. Nothing is rewritten; Trash still works on devices that have the ops. |
| User loses | Restore from Trash after N days, and history and undo for anything purged. That's the expected Trash deal on Apple platforms, but it's a product decision. |
| Compatibility | The hard form breaks every client that doesn't know the purge signal: an old client's 409 recovery re-pushes the purged ops. All clients would need updating before the first purge. |
| Risk | High for the hard form (a history rewrite across devices), low for the checkpoint-only form. |
| Gain | 29% of the log bytes and 31% of tasks today, more over years. It's the only option that shrinks the snapshot and the live state, which nothing else touches. |

### 3d. Compression

| Where | Change | Gain | Risk |
|---|---|---|---|
| Downloads (server → client) | None: already br or gzip | 3.9× | – |
| Uploads (client → server) | Clients send `Content-Encoding: gzip`; the Worker inflates before the 1 MiB check | 3.5–4× on pushes, which only matters for 409 recovery and the MCP's bulk runs | Low. Old clients keep sending plain; the Worker accepts both. A zip bomb needs a cap on the inflated size. |
| Client disk | `log.jsonl` in zstd or LZFSE frames of ~64 KB; the snapshot compressed whole | 3.5× and 3× | Medium for little: the offset seek becomes "find the frame", torn-tail recovery becomes torn-frame recovery, and the file is no longer greppable. Old app versions can't read it, so it needs a new file name and a one-way migration. |
| Server storage | Compress op text per row | ~1.3× (one op alone barely compresses) | It breaks "hashed as stored" unless the hash stays over the plain text. Not worth it. |
| The hash | Store and send it shorter (16 bytes of SHA-256 in base64 is 22 chars) | 42 B per line, 11% of the log | Protocol change for 11%. Not worth it on its own; fold it in if the format ever changes for another reason. |

Compression scales everything by a constant. It postpones the walls by a factor of 3–4 and moves none of them.

### 3e. Limits on history and undo depth

| | |
|---|---|
| Changes | CLI and MCP only: `undo` and `redo` reach batches from the last N days (30, say) or the last N changes; `tasks log` shows a window by default. Undo replays from the nearest snapshot before the window instead of from seq 0. The MCP replica keeps a few snapshots (it already writes one every 1,000 entries) and streams rows instead of caching them all. |
| User loses | Undoing an agent's change from more than N days ago through the CLI or MCP. The app's ⌘Z and Undo notices are per session and unaffected. A full read of older history can stay available on the Mac, where memory isn't tight. |
| Compatibility | No format or protocol change. |
| Risk | Low. |
| Gain | Removes the first wall (the MCP's 128 MB) and the CLI's per-call full read. |

### Summary

| Option | Changes | User loses | Compatibility | Risk | Fixes |
|---|---|---|---|---|---|
| 3a Client compaction | `TasksCore` files | Old history (truncation) or superseded edits (filter); weaker 409 recovery | New snapshot schema; old versions must refuse it | Medium | Client disk, fallback replay |
| 3b Server checkpoint | Server table + fetch; clients start from it | Nothing | Additive; old clients pull from 0 | Low–medium | New-device sync |
| 3c Tombstone expiry | Hard: log rewrite + purge signal everywhere. Light: checkpoints only | Trash restore after N days | Hard: every client first. Light: additive | High / low | Live state and snapshot size, plus the above |
| 3d Compression | Uploads: Worker + clients. Disk: new file format | Nothing (greppable files) | Uploads additive; disk one-way | Low / medium | Constant 3–4× on bytes |
| 3e History/undo limits | CLI + MCP only | Agent undo older than N days | None | Low | MCP memory, CLI history time |

## 4. Recommendation and triggers

Also mine, adjacent to the options: **stream the full replay.** Fold `log.jsonl` line by line instead of reading it
all and decoding every entry first. It's a `TasksCore`-only change with no format change, and it takes the iPhone's
fallback memory from O(log) to O(state).

| Step | What | Trigger |
|---|---|---|
| 0 | Nothing. Keep measuring: add the log's entry count and byte size to `tasks status` so the triggers below can be read off. | Now |
| 1 | **3e + streaming:** the MCP's `undo` streams rows and replays from a snapshot before the batch; undo and redo reach back N days in the CLI and MCP; the full replay streams. | The log passes **100k ops** (about 1.7 years at the user's pace), or the first time an MCP `undo` fails with an out-of-memory error. |
| 1b | **Plan or upload compression for 409 recovery:** either Workers Paid ($5/month: 50M rows written a month, 10 GB per DO) or accept multi-day recovery on Free. Compressed uploads don't change the row count, so they help bytes, not this limit. | The log passes **50k ops** (about 11 months), if the account is still on Free. It's the user's call. |
| 2 | **3b, verbatim-ops form:** a server checkpoint, every ~10k ops, of the live ops; the full log stays. Use it to bootstrap new devices. | A new device's first sync measures over **30 s**, or the log passes **250k ops**. |
| 3 | **3c, light form:** leave trashed entities older than N days out of the checkpoint and out of new devices' snapshots. Hard deletes only if the user wants a real "Empty Trash". | The snapshot passes **5 MB** (~10k tasks), or the user asks for Empty Trash. |
| 4 | **3a**, the live-ops filter, on iPhone only. | `log.jsonl` on an iPhone passes ~250 MB, or the fallback replay passes ~2 s there after step 1. |

Not recommended: on-disk compression of `log.jsonl` (3–4× on the cheapest resource, at the cost of the simple file),
compressing server rows, and prefix truncation on the client (it turns the snapshot into the source of truth and ends
the log's role as the place a new reducer rebuilds from).

One SPEC claim to update when any of this is built: §5 "Compaction and server snapshots: not yet" says server
snapshots need a second reducer. Since the remote MCP, that reducer exists and is parity-tested, and the verbatim-ops
checkpoint needs no reducer at all.
