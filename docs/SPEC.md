# Tasks app — spec (v1)

Status: draft for review. Source of requirements: `docs/BRIEF.md`. Visual design lives in `design/` and is out of scope here.

The guiding rule from the brief is **simplicity**, and the bar for adding anything is high. Each section below says what we build and, where an obvious extension invites more, what we leave out and why.

## 1. Scope

In v1:

- Tasks with a title, Markdown notes, an optional `when` date and an optional `deadline` date.
- Lists. Every task belongs to exactly one list and can be moved. An **Inbox** is created on first launch, and it's an ordinary list.
- **Archiving** lists. That's what "deleting" a list means.
- **Drag-to-reorder** for tasks within a list and for lists in the sidebar.
- A **Today** screen (rollup), a screen per list, and an Archive screen.
- A macOS app, single user, offline-first, synced across the user's Macs through an append-only log on Cloudflare.

Not in v1: iOS, recurring tasks, reminders/notifications, times of day, tags, subtasks, search, attachments, multiple users, hard deletes, and server-side snapshots/compaction. See §11 (Later).

## 2. Data model

### Task

| Field         | Type            | Notes |
|---------------|-----------------|-------|
| `id`          | UUID string     | Generated on the client, lowercase (§5 "Ids"). |
| `list`        | List id         | Required. Changing it is a "move". |
| `order`       | String          | Fractional index key within its list (§3). |
| `title`       | String          | Max 1,000 chars. May be empty. |
| `notes`       | String          | Markdown, max 20,000 chars. Called `description` in the brief; renamed because `description` collides with Swift's `CustomStringConvertible`. |
| `when`        | `CalendarDate?` | "I plan to do this on/after this day." |
| `deadline`    | `CalendarDate?` | "This must be done by this day." |
| `completedAt` | Epoch ms (Int)? | Null = open. Set from the device clock when the user checks it. Completed tasks are kept forever. |
| `deleted`     | Bool            | Default false. Deleting is setting it; undo clears it (§6). |
| `kind`        | `"heading"`?    | Absent: a task. `"heading"`: a heading, a row in its list that groups the tasks under it (`design/INTERACTIONS-v2.md` §23). Set at create and never changed. |

`createdAt` and `updatedAt` are derived on the client from the `at` of the first and last op that touched the task. They are never written as fields.

### List

| Field   | Type        | Notes |
|---------|-------------|-------|
| `id`    | UUID string | Generated on the client, lowercase (§5 "Ids"). |
| `name`  | String      | Max 200 chars. Duplicates allowed. |
| `order` | String      | Fractional index key in the sidebar (§3). |
| `archivedAt` | Epoch ms (Int)? | Null = active. Set when the user archives the list. Lists are never deleted. |
| `notes` | String      | Markdown, max 20,000 chars, shown under the list's title. Empty by default. |

### Inbox: an ordinary list, seeded once

So that a new user can add tasks straight away, the app creates an "Inbox" list. After it's created, nothing in the app treats it differently from any other list. It can be renamed, reordered and archived like the rest.

- **Seeding:** on launch, if the state (confirmed + pending) has no list with the id `00000000-0000-0000-0000-000000000001`, the client performs one op:

  ```
  list.create  id: 00000000-0000-0000-0000-000000000002  target: …0001  set: {name: "Inbox", order: "a0"}
  ```

  That fixed pair of ids is the only constant. It lives in the seeding function, and the reducer, queries and UI never see it.
- **Two Macs launching for the first time** (or a second Mac installed later, even offline): both send the identical op.
  - The server's op-id dedup stores it once.
  - Even without dedup, the second create would be ignored, because the first create wins (§5 rule 1).
  - Either way there's one Inbox. Tasks a second Mac adds to its Inbox while offline land in the same list once synced, because they reference the same list id.
- A renamed or archived Inbox stays that way. The seed is a create, and a create never overwrites an existing list.

### Default list: the top of the sidebar

New tasks created outside a list (Today's `+`, ⌘N in Today) go to the selected task's list when a task is selected, and otherwise to the **first active list in sidebar order**: the default list. A fresh install seeds the Inbox at the top (`order: "a0"`), so the Inbox is the default until the user drags another list above it.

- There's no setting or field, because the default comes from order the user already controls.
- A synced "default list" setting would need a new kind of entity, and an `isDefault` field on lists would need an "exactly one" rule that concurrent edits can break.
- If the default list is archived, the next active list takes over automatically.
- If every list is archived, adding a task asks the user to create a list or unarchive one.
- Today's `+` names its target in its tooltip ("New Task in Inbox ⌘N"), so the rule is discoverable. The sidebar doesn't mark the default.

### Archiving lists

"Deleting" a list archives it, like archiving a finished course along with its tasks.

- **Representation:** one field on the list, `archivedAt`. Its tasks are **not** rewritten. Each task inherits visibility from its list at query time. Archiving and unarchiving are one op each, whatever the list size, and the tasks come back exactly as they were (order, dates, completion).
- **Effect:** an archived list and all its tasks drop out of the sidebar, Today and "Move to…" targets. Everything stays in the log and in state.
- **Undo:** ⌘Z clears `archivedAt`. So does the Unarchive button.
- **Where they're viewed:** an **Archive** item at the bottom of the sidebar, shown only when at least one list is archived. It lists archived lists, most recently archived first, with their archive date. Opening one shows the normal list screen with an "Archived" banner and an Unarchive button. Nothing is read-only, and there are no special editing rules.
- **Concurrency:** a task moved into a list that another Mac archived at the same time is archived with it, and shows up in the Archive. Unarchiving restores the list to its old sidebar spot, by its old key.

### Dates: calendar dates, no times, no time zones

`when` and `deadline` are **calendar dates**, serialized as `"YYYY-MM-DD"`. They are not instants and carry no time zone. A task due `2026-11-03` is due on November 3rd wherever the user happens to be.

- **Today** is the Mac's current local calendar date (`Calendar.current`, `TimeZone.current`). Compare dates as `YYYY-MM-DD` strings or as `DateComponents`, never by converting to `Date` at midnight.
- Travel changes what "today" is, never what a task's dates are.
- The app recomputes Today when the day changes (`NSCalendarDayChanged` / `.significantTimeChangeNotification`) and when it becomes active.
- `completedAt` is the one real instant. It is only shown or compared via its local calendar date.

No validation that `when ≤ deadline`. Either order is harmless.

**Pushback:** datetimes (due at 5pm) mean time zones, notifications and a time picker. Leave them out until someone needs them.

### Notes are Markdown

Notes are stored as a plain Markdown string, so sync and the server don't care about the format.

- One editor shows and edits the source, rendered in place: inline styles, headings, lists, checklists, quotes and code blocks, with each mark (`**`, `#`, …) showing only near the caret. Line breaks are kept. The spec is `design/MARKDOWN.md`.
- The app renders it with its own scanner (TasksCore `Markdown`), not `AttributedString(markdown:)`, which drops the marks and can't map back to the source. No third-party renderer.

## 3. Ordering

The user can drag two things: tasks within a list and lists in the sidebar. Both use the same mechanism. Today has no order of its own; it derives one (§4).

### Representation: fractional index keys

Tasks and lists each have an `order: String`.

- **Sort** by `order` (byte-wise comparison), with ties broken by `id`. Every Mac computes the same order from the same state.
- **Keys** are base-62 strings over `0-9A-Za-z`. Those characters are in ASCII order, so byte comparison is the sort order.
- **Algorithm:** the well-known fractional-indexing scheme (David Greenspan's, as in the `fractional-indexing` npm package).
  - `keyBetween(a, b)` returns a key strictly between `a` and `b`. `nil` means an open end, so `keyBetween(last, nil)` appends.
  - `keysBetween(a, b, n)` returns `n` evenly spaced keys.
  - It's a Swift port of about 100 lines and lives only on the client. The server only checks that the charset is right and the length is ≤ 128.

**Why not integer positions:** moving one item would renumber many, every renumber is an op per item, and two Macs renumbering concurrently conflict on items neither user touched. With a fractional key, a drag changes exactly one field of exactly one item.

### How position changes are expressed

There are no new op types. Position is written through the ordinary `set` patch.

| Action | Op |
|--------|----|
| Create a task | `task.create` with `order = keyBetween(lastInList, nil)`. New tasks go to the bottom. |
| Create a list | `list.create` with `order = keyBetween(lastList, nil)`. |
| Reorder a task within its list | `task.update set {list, order}`, where `order = keyBetween(prev, next)` around the drop point. |
| Move a task to another list | `task.update set {list: target, order: keyBetween(lastInTarget, nil)}`. Triggered by dropping it on a sidebar list or with a "Move to…" command. It lands at the bottom. |
| Reorder a list | `list.update set {order}`. |
| Drag k selected tasks | k keys from `keysBetween(prev, next, k)`, one op each, in one sync request. |
| Create a heading | `task.create` with `kind: "heading"` and the key where it goes (above the selected row, or the bottom). Headings and tasks share the list's keys. |
| Move a heading with its section | The heading and every task under it down to the next heading, completed ones included, get `keysBetween` keys before another heading or at the end: `task.update set {list, order}`, one op each, in one sync request (`design/INTERACTIONS-v2.md` §23). |

**Rule: a task's position change always writes `list` and `order` together, in one op.** Position then behaves like a single value. Concurrent position changes resolve wholly to one of them, and a task never ends up in list B carrying a key computed against list A.

Completing a task doesn't touch `order`. Completed tasks are listed by `completedAt` and keep their key, so uncompleting puts a task back in its old spot.

### Concurrent reorders from two Macs

- **Different items moved:** both moves apply, because each touches only its own key.
- **Same item moved on both:** the later move in the log wins, `list` and `order` together.
- **Both insert at the same spot** (e.g. both add a task at the bottom while offline): the keys come out identical. The `id` tie-break gives both Macs the same order.
- **Inserting between two equal keys:** there's no key strictly between them. The client first re-keys the tied run, giving each item a distinct key between the run's key and the next distinct key above it, and then inserts. This takes a few ops and is rare.
- **Accepted trade-off:** a drag made against a stale view can land slightly off from where the user meant once it's merged with the other Mac's moves. Both Macs still agree on the order, and dragging again fixes it.

### Key growth and rebalancing

- Appending at either end grows keys logarithmically, so keys stay 2–4 characters even for thousands of items.
- Inserting repeatedly at the *same* spot adds about one character per ~6 inserts. Each midpoint halves the gap, and 62 ≈ 2⁶.
- **Rebalance:** when a key the client is about to write would exceed 32 characters, it re-keys that list's open tasks (or the sidebar's active lists) with fresh, short, evenly spaced keys in the same order.
  - That's one update op per item, pushed in one request.
  - It takes ~150 inserts at the exact same spot to trigger, so in practice it almost never runs.
- The server appends a request atomically, so a rebalance lands as one contiguous block of the log. If two Macs rebalance concurrently, the later block wins for every item it touched, and both converge.
- Rebalance skips completed tasks and archived lists. One that comes back (uncompleted or unarchived) after a rebalance sorts by its old key, which may not be its original spot. That's rare, and a drag fixes it.

## 4. Screens

### Today

A task appears in Today when all of these hold:

```
not task.deleted and task.list exists and task.list.archivedAt == nil
and (task.completedAt == nil or localDate(task.completedAt) == today)
and ((task.when != nil and task.when <= today) or (task.deadline != nil and task.deadline <= today))
```

- **Both dates set:** the task shows if *either* date has arrived. A task with `when = Nov 5, deadline = Nov 3` shows on Nov 3.
- **Past `when`:** carries forward every day until done, with no badge. Past `when` doesn't mean late.
- **Overdue:** `deadline < today`, shown with a danger-colored label ("Overdue · 3d"). `deadline == today` gets an attention-colored "Due today". Colors come from `PaneColors.dangerText` / `.attention`.
- **Completed tasks:** stay at the bottom of Today, checked and dimmed, ordered by `completedAt`, for the rest of the local day they were completed. They drop out at midnight. This is part of the predicate, so it needs no UI state.

**Order: derived, no manual order of its own.** Today is grouped by list:

- Groups appear in sidebar order, under the list name.
- Within a group, tasks appear in that list's manual order.
- Overdue and due-today tasks stand out by their badges, not by being sorted to the top.

Dragging within a group reorders the task in its list:

- The new key goes right after the task above it *in the full list*, using `keyBetween(above, above's successor in the list)`.
- If the task is dropped at the top of a group, the key goes right before the task below it instead.
- Dragging across groups isn't allowed in Today. To move a task between lists, drop it on the sidebar.

Why not a separate Today order:

- A `todayOrder` key would need rules for tasks that enter Today with no key, and for stale keys when a task leaves Today and comes back.
- It would also be a second order to sync and rebalance.

Grouping costs nothing and uses an order the user already controls. Sorting Today by date was the earlier draft's approach. It's dropped because it overrides the user's manual order.

Adding from Today (`+`, ⌘N) creates a task with `when = today`, at the bottom of the selected task's list, or of the default list (§2) when no task is selected. The new task opens in the detail pane, whose List row moves it to another list. Nothing is written until its title has text: then one `task.create`. Leaving it untitled writes nothing (`design/INTERACTIONS-v2.md` §6).

### List screens

A list screen shows:

- its name as a large title, and its `notes` under it;
- the list's open tasks and its headings in manual order, draggable; a heading groups the tasks under it, down to
  the next heading, and can be collapsed on this Mac (never synced);
- a collapsed "Completed" section, newest first, kept forever.

Headings never show outside their list: Today, the views and counts leave them out (`design/INTERACTIONS-v2.md` §23).

Each row shows its `when` and `deadline` inline.

### Sidebar

The sidebar, top to bottom:

- **Today**, pinned. It isn't a list and can't be dragged.
- **Active lists** in manual order. They're draggable, and tasks can be dropped onto a list to move them there.
- **Archive**, at the bottom, only when something is archived (§2).

"Delete list" in the UI is labeled **Archive**.

## 5. Sync: the append-only log

### Principles

- **The server is a dumb, ordered log.** It stores ops and hands them back. It never interprets them, so there is exactly one reducer, written in Swift on the client.
- **Log order is the only clock.** Every Mac replays the same ops in the same order through the same deterministic reducer and ends up in the same state. Wall clocks are never used to resolve conflicts.
- **Ops are field patches.** There are no separate `move`/`complete`/`reorder`/`delete`/`archive` ops. A move is `set: {list, order}`, completing is `set: {completedAt}`, deleting a task is `set: {deleted: true}`, and archiving a list is `set: {archivedAt}`.

### Op schema

Every op has the same shape: an envelope, a type, a target id and a `set` patch. `set` is always present; an update that changes nothing sends `{}`.

```jsonc
{
  "id":   "6f1c…",          // op id, client-generated lowercase UUID — the idempotency key
  "at":   1761800000000,    // client wall clock, ms — informational only (createdAt/updatedAt)
  "type": "task.update",    // one of the four types below
  "target": "a83e…",        // task or list id
  "set":  { "list": "c91d…", "order": "a0V" }
}
```

| Type          | `set` keys allowed |
|---------------|--------------------|
| `task.create` | `list`, `order` (both required), `title`, `notes`, `when`, `deadline`, `completedAt`, `kind` |
| `task.update` | any of the above except `kind`, plus `deleted` |
| `list.create` | `name`, `order` (both required), `notes` |
| `list.update` | `name`, `order`, `notes`, `archivedAt` |

`set` semantics: a key that's present overwrites the field (`null` clears it), and a missing key leaves it unchanged.

**Attribution (optional):** the envelope may also carry `actor`, who wrote the op (`"agent:claude-code"`, `"cli"`; absent means the Mac app), and `batch`, an id shared by every op of one change (one CLI command or one code-mode run, `docs/SDK-PLAN.md` §4). The reducer never reads them. They exist for review (`tasks log`) and for undoing a whole change later.

```jsonc
{ "id": "3a7f…", "at": 1761811320000, "type": "task.update", "target": "9f8e…", "set": { "when": "2026-11-06" },
  "actor": "agent:claude-code", "batch": "2c1f…" }
```

**Ids** (op `id`, `target`, `list`) are opaque, case-sensitive strings to the server: `"ABC"` and `"abc"` are different ops for dedup and different entities for the reducer. Clients generate lowercase UUIDs, the form every fixture uses, and store and compare ids as `String`. In Swift that means `UUID().uuidString.lowercased()`, and never round-tripping an id through `UUID`, whose `uuidString` is uppercase. The Inbox seed ids (§2) are all digits, so they're the same either way.

Stored by the server, the log entry adds `seq` (its index) and `received` (server ms).

### Reducer rules (the whole conflict model)

Apply ops in `seq` order:

1. `*.create` on an id that already exists (live or deleted): ignored. The first create wins.
2. `*.update`: each key in `set` overwrites. The last write in log order wins **per field**, so concurrent edits to different fields both survive. (Position is written as `list` + `order` together, see §3.)
3. `*.update` on an unknown id: ignored.
4. `deleted` (tasks) and `archivedAt` (lists) are ordinary fields. The entity stays in state and is only hidden by queries. A concurrent edit on another Mac doesn't touch these fields, so it never brings anything back. Only an explicit `deleted: false` / `archivedAt: null` does (undo, §6; Unarchive).
5. Visibility is decided at query time, not in the reducer. A task is visible only if it isn't deleted and its list exists and isn't archived. So archiving cascades with no per-task ops, and unarchiving brings every task back unchanged.
6. Unknown op types and unknown `set` keys are ignored, so old clients survive new ops. Values with the wrong type are ignored per key.

Known trade-offs, which are acceptable for a personal app:

- An edit made offline on Monday and synced on Wednesday overwrites a Tuesday edit to the same field, because it lands later in the log.
- `notes` is last-writer-wins as a whole string. Two Macs editing the same notes concurrently lose one side.
- The client commits `title`/`notes` edits on end-of-editing (or after a ~1s idle debounce), not per keystroke, so the log doesn't fill with typing.

### Index assignment

`seq` is 0-based and dense. `head` is the number of ops in the log, which is the next `seq` to assign. A client that has synced through `seq = k − 1` stores the cursor `k` and fetches `[k, head)`, exactly as the brief describes. The Durable Object (§7) serializes appends, so assigning `seq` is just `head++` inside a transaction.

Each entry also carries a chain `hash` (§6), so a client can prove its cursor points into the same log the server has.

### API contract

There's exactly one endpoint: `POST /v1/sync`. Pushing and pulling are the same call; a pull is a push with no ops. There is **no `GET /v1/health`**, because a pull with empty `ops` already proves the Worker, the token and the DO all work, so a health route would add a second thing to keep working without telling us anything new.

#### HTTP

| Aspect | Rule |
|--------|------|
| Method | `POST` only. Any other method on `/v1/sync` → `405 method_not_allowed`, with an `Allow: POST` header. |
| Paths | Any other path → `404 not_found`. |
| Auth | `Authorization: Bearer <token>`, compared to the `API_TOKEN` secret in constant time. Missing or wrong → `401 bad_token`. |
| Request body | `Content-Type: application/json`, UTF-8, ≤ 1 MiB (1,048,576 bytes). The server doesn't check `Content-Type`; it just parses the body. Over 1 MiB → `413` (checked against `Content-Length` and again after reading, for bodies sent without one). Not valid UTF-8 or not valid JSON → `400 bad_request`. Request bodies are **never compressed**: pushes are small, and the big transfers are pulls. |
| Response body | Always JSON: `Content-Type: application/json; charset=utf-8`, on success and on error. |
| Compression | Responses are compressed when the request's `Accept-Encoding` allows it. `URLSession` sends `Accept-Encoding: gzip, deflate, br` and decompresses transparently, so the client does nothing. On the server, the Worker sets `Content-Encoding: br` (or `gzip`) on the response, picked from `request.cf.clientAcceptEncoding` (the header as the client sent it, before Cloudflare may rewrite it), falling back to `Accept-Encoding`: `br` if accepted, else `gzip`, else none, honouring `q=0`. Error responses follow the same rule. The Workers runtime compresses the body itself (`encodeBody: "automatic"`, the default), independent of Cloudflare's edge compression settings. Verified on the deployed Worker (S4); a 1,000-entry page of 288 KB goes out as ~48 KB with `br`. |

**Check order.** The Worker does every check that doesn't need the log, so a bad request never reaches the DO:

1. **Worker:** route (`404` / `405`) → auth (`401`) → body size (`413`) → parse the body and check `from`, `base`, `ops` (`400 bad_request`) → op count (`413 too_large` for > 500 ops) → each op (`400 invalid_op`).
2. **DO:** log check (`409`) → append → read.

So a client with a stale cursor and a bad request gets the `400` or `413` it needs to fix, never a `409` that would start a needless recovery.

#### Request

```jsonc
{
  "from": 0,        // integer 0 ≤ from ≤ 2^53 − 1: the client's cursor (next seq it doesn't have)
  "base": null,     // hash of entry from−1 as 64 lowercase hex chars; null if and only if from = 0
  "ops":  []        // 0–500 ops, in the order they were made
}
```

`400 bad_request` for the request itself: a body that isn't a JSON object; `from` that isn't such an integer; `base` that isn't `null` or 64 lowercase hex chars; a `null` `base` with `from > 0` or a non-null one with `from = 0`; `ops` that isn't an array. Unknown top-level keys in the request are ignored.

**Op validation:** the whole request is rejected on the first failure, and nothing is appended. Each op is checked in this order, and the error's `field` names what failed:

| Check | `field` on failure |
|-------|--------------------|
| The op is a JSON object. | `op` |
| `id`: a string of 1–64 characters. | `id` |
| `at`: an integer, 0 ≤ `at` ≤ 2⁵³ − 1. | `at` |
| `type`: one of `task.create`, `task.update`, `list.create`, `list.update`. | `type` |
| `target`: a string of 1–64 characters. | `target` |
| `set`: present, and an object. | `set` |
| `actor`, `batch`: absent, or a string of 1–64 characters. | `actor` / `batch` |
| No envelope keys besides `id`, `at`, `type`, `target`, `set`, `actor`, `batch`. | the extra key, e.g. `seq` |
| Each `set` key, in the order received: allowed for its `type` (§5 op schema), and its value valid (below). | `set.<key>` |
| Required keys on a create: `list` and `order` for a task, `name` and `order` for a list. | `set.<key>` |

**Unknown keys are rejected**, in the envelope and in `set`. Adding a field therefore means deploying the server first, which is fine with one developer, and it catches client bugs early.

`set` values:

| Key | Valid value |
|-----|-------------|
| `list` | string, 1–64 characters |
| `order` | `^[0-9A-Za-z]{1,128}$` |
| `title` | string, ≤ 1,000 |
| `notes` | string, ≤ 20,000 (a task's and a list's) |
| `name` | string, ≤ 200 |
| `when`, `deadline` | `null`, or `"YYYY-MM-DD"` (ASCII digits) that's a real date in the Gregorian calendar, any four-digit year |
| `completedAt`, `archivedAt` | `null`, or an integer 0 ≤ n ≤ 2⁵³ − 1 (epoch ms) |
| `deleted` | boolean |
| `kind` | the string `"heading"` |

- **Lengths** count **UTF-16 code units**: `String.length` in JS, `.utf16.count` in Swift. Both sides then agree exactly.
- **Every string must be well-formed Unicode.** A JSON `\ud800`-style escape can carry an unpaired surrogate; that's rejected (`invalid_op`), because a stored entry a client can't decode would stop every Mac's sync at that `seq` for good. Swift strings can't hold one, so a Swift client never sends it.
- **Duplicate op ids** inside one request: only the first is appended. An op id already in the log is skipped too, whatever its content (dedup is by id only).

**Validation may only loosen, never tighten.** A `409` recovery re-pushes ops that are already in the log, verbatim, and validation runs before dedup. So a rule that rejects an op the log already holds would turn a harmless re-push into `invalid_op`, and the client would move that op to `rejected.jsonl`: the discard the recovery rule forbids. Rolling the Worker back to a version with stricter rules has the same effect. Allowing a new `set` key is a loosening and fine; so was allowing `actor` and `batch`, which is why the Worker must never be rolled back past that change, and so is allowing `kind` on `task.create` and `notes` on `list.create` and `list.update` (headings and a list's text, `design/INTERACTIONS-v2.md` §23; built 2026-10-31 and **not deployed yet**: the Worker must be deployed before any client sends them, and never rolled back past it after). A rule that must tighten needs a migration plan for the ops already stored before it ships.

The server stores each op as `JSON.stringify({id, at, type, target, set, actor, batch})`: top-level keys in that order, `set` keys in the order received. `JSON.stringify` omits an absent `actor` or `batch`, so an op without them is stored as `{id, at, type, target, set}`, exactly as before the keys existed. That exact text is what gets hashed (§6). The client never re-hashes, so this is only a server-internal rule, but the worked examples below are test vectors for it.

#### Success: `200`

```jsonc
{
  "entries": [ { "seq": 0, "received": 1761811261234, "hash": "…", "op": { … } } ],  // a page starting at `from` (below)
  "head": 2,
  "more": false     // true when the page stopped before head
}
```

**Page size.** A page holds the entries from `from` onward, up to 1,000 of them, and stops early once its op text passes 4,000,000 UTF-16 code units. It always holds at least one entry when `from < head`.

- The second bound keeps a page inside the Durable Object's 32 MiB RPC limit. 1,000 entries with near-limit notes (and any non-Latin-1 character, which makes the runtime serialize the string at 2 bytes per unit) would exceed it, and that `from` would fail on every retry.
- Entries average ~250 characters, so in practice pages are full 1,000-entry pages.
- **The client continues from the last returned `seq` + 1**, which is its new cursor, never from `from + 1000`, and loops while `more` is true.

A request's ops are appended contiguously, in the order sent, and before the page is read. So the response includes the client's own just-pushed ops **only when they fall inside the page**. A client more than a page behind gets them on a later page: a new Mac pushing its Inbox seed into a large log, or any `409` recovery. **The client drops a pending op only when its id appears in a returned entry**, never because the request returned `200`.

#### Errors

Every non-200 response has the same body:

```jsonc
{ "error": "invalid_op", "message": "human-readable, for logs only", "index": 1, "field": "set.order" }
// index and field appear only on invalid_op
```

| Status | `error` | Meaning | Client does |
|--------|---------|---------|-------------|
| 400 | `bad_request` | Body isn't UTF-8 JSON or isn't an object, or `from`/`base`/`ops` are missing or invalid (see Request), including a `null` `base` with `from > 0` and a non-null one with `from = 0`. | Client bug. Stop syncing, show "Sync error", log the message. **No retry.** |
| 400 | `invalid_op` | `ops[index]` failed validation at `field`. | Client bug in that one op. Move it from pending to `rejected.jsonl` (kept for debugging), rebuild its entity from confirmed + remaining pending (§9), show a non-blocking "A change couldn't be saved" notice, then **retry immediately** without it. |
| 401 | `bad_token` | Token missing or wrong. | **Stop syncing. No retry loop.** Show a "Check sync token" state in the sidebar footer and in Settings. Pending ops stay queued. Syncing resumes when the token is changed or on ⌘R. |
| 404 | `not_found` | Wrong path. | Misconfigured server URL. Same as `bad_request`: stop, show the error, no retry. |
| 405 | `method_not_allowed` | Not `POST`. | Same as `404`. |
| 409 | `log_mismatch` | `from > head`, or `base` doesn't match the hash at `from − 1`. | **Never discard an op.** Make every known op (confirmed log + pending) pending, delete `snapshot.json`, move `log.jsonl` aside, and **retry immediately** with `from: 0, base: null`. That request can't 409 again. Details: "Recovering from a 409" below. |
| 413 | `too_large` | Body over 1 MiB or more than 500 ops. | Client bug, since the client chunks requests (below). Halve the batch and **retry**. |
| 5xx, timeouts, network errors, non-JSON bodies | `internal` from the Worker; none from the edge | Server or network trouble. An unexpected exception in the Worker is `500 {"error":"internal",…}`; a Cloudflare edge error may be an HTML page. | **Retry** with exponential backoff: 1 s doubling, capped at 1 min. |

**Chunking:** the client sends pending ops in chunks of at most 500 ops and ~900 KB, oldest first, one request at a time. After a long offline stretch, a sync is several requests.

#### Worked examples

These use the test-vector ops below. `opA` seeds the Inbox (§2) and `opB` creates a task in it.

```
opA = {"id":"00000000-0000-0000-0000-000000000002","at":1761811200000,"type":"list.create","target":"00000000-0000-0000-0000-000000000001","set":{"name":"Inbox","order":"a0"}}
opB = {"id":"5b0c6c1e-3f0a-4c8e-9d61-0f4f6f1a2b3c","at":1761811260000,"type":"task.create","target":"9f8e7d6c-5b4a-4321-8fed-cba987654321","set":{"list":"00000000-0000-0000-0000-000000000001","order":"a0","title":"Buy milk","when":"2026-10-30"}}

hash(0) = SHA-256("" + "\n" + opA) = bc2a6e3a4de77a2ce16c4a38c6f4d76237a98434f7d213049e3fd77dde66dacd
hash(1) = SHA-256(hash(0) + "\n" + opB) = 184ceb4c3d11bd53025385963c25f50298c2d652f84d5989941d2ec13a66fd79
```

**1. Push (200).** A fresh Mac pushes two ops to an empty log.

```http
POST /v1/sync HTTP/1.1
Host: tasks.<account>.workers.dev
Authorization: Bearer <token>
Content-Type: application/json
Accept-Encoding: gzip, deflate, br

{"from":0,"base":null,"ops":[opA,opB]}
```

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
Content-Encoding: br

{"entries":[
  {"seq":0,"received":1761811261234,"hash":"bc2a6e3a4de77a2ce16c4a38c6f4d76237a98434f7d213049e3fd77dde66dacd","op":opA},
  {"seq":1,"received":1761811261234,"hash":"184ceb4c3d11bd53025385963c25f50298c2d652f84d5989941d2ec13a66fd79","op":opB}
],"head":2,"more":false}
```

Both entries are the head of the pending queue, so this is the fast path (§9). The client's cursor becomes 2 and its `base` becomes `184ceb4c…`. Sending the same request again returns the same body, because both op ids are deduplicated.

**2. Pull with `more: true` (200).** A second Mac joins when the log has 2,345 entries.

```http
POST /v1/sync HTTP/1.1
Authorization: Bearer <token>
Content-Type: application/json

{"from":0,"base":null,"ops":[]}
```

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8

{"entries":[
  {"seq":0,"received":1761811261234,"hash":"bc2a6e3a…dacd","op":opA},
  {"seq":1,"received":1761811261234,"hash":"184ceb4c…fd79","op":opB},
  … 998 more entries, seq 2–999 …
],"head":2345,"more":true}
```

The client applies the page and continues from its last `seq` + 1: `{"from":1000,"base":"<hash of seq 999>","ops":[]}`. It keeps going until `more` is `false`; here that's a third request starting at `from: 2000`.

**3. Invalid op (400).** The order key contains a space.

```http
POST /v1/sync HTTP/1.1
Authorization: Bearer <token>
Content-Type: application/json

{"from":2,"base":"184ceb4c3d11bd53025385963c25f50298c2d652f84d5989941d2ec13a66fd79","ops":[
  {"id":"7d1e…","at":1761811300000,"type":"task.update","target":"9f8e7d6c-5b4a-4321-8fed-cba987654321","set":{"title":"Buy oat milk"}},
  {"id":"8e2f…","at":1761811301000,"type":"task.update","target":"9f8e7d6c-5b4a-4321-8fed-cba987654321","set":{"list":"00000000-0000-0000-0000-000000000001","order":"a 0"}}
]}
```

```http
HTTP/1.1 400 Bad Request
Content-Type: application/json; charset=utf-8

{"error":"invalid_op","message":"ops[1].set.order must match ^[0-9A-Za-z]{1,128}$","index":1,"field":"set.order"}
```

Nothing was appended, not even `ops[0]`. The client moves `ops[1]` to `rejected.jsonl` and resends the request with only `ops[0]`.

**4. Bad token (401).**

```http
POST /v1/sync HTTP/1.1
Authorization: Bearer wrong-token
Content-Type: application/json

{"from":2,"base":"184ceb4c3d11bd53025385963c25f50298c2d652f84d5989941d2ec13a66fd79","ops":[]}
```

```http
HTTP/1.1 401 Unauthorized
Content-Type: application/json; charset=utf-8

{"error":"bad_token","message":"Missing or invalid bearer token."}
```

The client stops syncing and shows "Check sync token".

**5. Log mismatch (409).** The server log was restored from a backup, then grew to a different entry 1.

```http
POST /v1/sync HTTP/1.1
Authorization: Bearer <token>
Content-Type: application/json

{"from":2,"base":"184ceb4c3d11bd53025385963c25f50298c2d652f84d5989941d2ec13a66fd79","ops":[]}
```

```http
HTTP/1.1 409 Conflict
Content-Type: application/json; charset=utf-8

{"error":"log_mismatch","message":"base does not match the log at seq 1."}
```

The client recovers (below): it moves its log aside and re-pushes every op it knows, here its confirmed `opA` and `opB` (its pending queue is empty).

```http
POST /v1/sync HTTP/1.1
Authorization: Bearer <token>
Content-Type: application/json

{"from":0,"base":null,"ops":[opA,opB]}
```

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8

{"entries":[
  {"seq":0,"received":1761811261234,"hash":"bc2a6e3a4de77a2ce16c4a38c6f4d76237a98434f7d213049e3fd77dde66dacd","op":opA},
  {"seq":1,"received":1761811261234,"hash":"d26a435858c180d340e58ccc240e66e280a27dbb8a68c6581cea8c5e7341448b","op":{…"Buy bread"…}},
  {"seq":2,"received":1761811261234,"hash":"2a34469203cb49eae9ac47f94f152dd5096801d50cd45dccb5682ea889992350","op":opB}
],"head":3,"more":false}
```

The server deduplicates `opA` and appends the missing `opB` at seq 2. The example reuses one task id for both creates, so the reducer ignores `opB` (rule 1) and the task reads "Buy bread" on every Mac; `opB` itself is kept in the log. Real task ids never collide, so in practice the re-appended create brings the task back.

### Client sync loop and offline queue

The client holds:

- **Confirmed state**: the reduced log `[0, cursor)`. On disk it's `log.jsonl` plus a snapshot (§8).
- **Pending queue**: ops created locally and not yet seen in the log, persisted.
- **Visible state**: confirmed state with the pending ops applied on top, kept as a per-entity overlay (optimistic UI, §9).

When the user acts:

1. Build the op(s).
2. Apply them to the overlay. The changed row redraws.
3. Queue the append to `pending.jsonl`.
4. Schedule a sync.

A sync:

1. `POST /v1/sync {from: cursor, base: lastHash, ops: <next chunk of pending, ≤ 500 ops / ~900 KB>}`.
2. Append the returned entries to `log.jsonl` and advance the cursor.
3. Apply them to the confirmed state and drop pending ops whose `id` appeared.
4. Update visible state for the touched ids only (fast path or general path, §9).
5. Loop while `more` is true or pending ops remain unsent.

Errors are handled per the table in the API contract. Only `5xx` and network failures back off (1 s doubling, capped at 1 min). `401`, `404`, `405` and `bad_request` stop syncing until the user acts. `409`, `invalid_op` and `413` retry immediately after their fix.

If the app crashes before `pending.jsonl` is rewritten, the next launch drops pending ops that are already in the log tail (§8). Resending is harmless anyway, because the server dedupes by op id.

### Recovering from a 409: re-push everything

A `409` means the Mac's log and the server's have diverged: the server was wiped, reset or restored from an older backup, or the Mac's own log is damaged. In the first three cases the Macs may hold the only copy of some ops. So the rule is: **a Mac never discards an op it knows.** It re-pushes all of them, and the server's op-id dedup keeps the ones it's missing.

On `409`, the client:

1. Builds the **recovery queue**: every op in `log.jsonl` in `seq` order, then the pending queue in order, keeping the first occurrence of each op id. Log ops are copied as their `op` JSON text verbatim, never decoded and re-encoded, because decoding drops types and keys this client doesn't know (rule 6), and those may come from a newer client on another Mac.
2. Writes it atomically as the new `pending.jsonl`.
3. Deletes `snapshot.json`.
4. Renames `log.jsonl` to `log.jsonl.bak-<epoch ms>`.
5. Resets confirmed state to empty, the cursor to 0 and `base` to `null`, and syncs as usual: `from: 0`, in the normal chunks, until `more` is false and nothing is pending. 100k ops is 200 pushes.

The server needs nothing new. To it these are ordinary pushes:

| Server | Result |
|--------|--------|
| Wiped (head 0) | Nothing is deduplicated. The log is rebuilt from this Mac. |
| Restored to an older point, maybe grown since | Ops it has are deduplicated; the missing ones are appended at head. |
| Fine, but this Mac's log is damaged | Everything is deduplicated. Nothing is appended; the Mac just re-downloads. |

Several Macs recovering at once is fine: each re-pushes its own ops, and whatever another Mac already re-pushed is deduplicated. A `409` in the middle of a recovery (the server changed again) just starts another one from the current log + pending, which still holds every op.

**Automatic, with no prompt.** There's one user, and recovery only ever adds back ops that user made, so a dialog would have one sensible answer. The app stays fully usable while it runs, and new edits queue behind the recovery queue. The sidebar footer shows "Restoring sync · 1,500 of 12,000" (recovery-queue ops confirmed so far, of the total) and goes back to normal when it's done.

**The screen doesn't jump.** With confirmed state empty and everything pending, the overlay (§9) is a replay of the old log + pending, which is exactly what was on screen. As pages come back, each id they target is rebuilt from `confirmed[id]` plus its remaining pending ops, as in the §9 general path, with one difference: **every** id in the page counts as touched, ours included, because our own ops can come back in a different order than the overlay applied them (some were already on the server, behind other Macs' ops). That costs O(page) on a rare path.

**Known effect: last-writer-wins can shift.** Re-appended ops land after anything the server gained since its backup, so where both wrote the same field, the re-appended value now wins. Every Mac still converges on the same state. Acceptable.

**Hash chain:** unchanged. Appended ops get a new `seq` and hash from the server, and the client stores whatever comes back. Nothing is hashed on the client.

**Inbox seeding:** unaffected. The seed's `list.create` is in the log, so it's in the recovery queue and the state (confirmed + pending) still has the Inbox. If it were seeded again anyway, its fixed op id is deduplicated.

**Crash safety** comes from the step order. A crash before step 4 leaves `log.jsonl` in place: launch loads it (from the snapshot, or by full replay if step 3 ran), the next sync `409`s again, and recovery reruns and builds the same queue. Until then, pending also holds ops that are already confirmed. Re-applying a log on top of its own result changes nothing except in odd cases (an update that came before its create in the log), and the recovery corrects those. A crash after step 4 finds no log and no snapshot: confirmed is empty, everything is pending, and the recovery carries on.

**Backups:** the app never reads `log.jsonl.bak-*`, since every op in them is already pending. They're a safety net for bugs in this path. All of them are deleted when a sync ends with `more: false` and nothing pending.

**Deleting the server no longer erases data.** A wiped or deleted-and-redeployed server is rebuilt by the first Mac that syncs. Starting over for real also means deleting each Mac's Application Support data before it syncs again.

### Realtime: polling, no WebSocket

Sync triggers:

- App launch and when the app becomes active.
- ~1s after any local change.
- Every 30s while a window is open.
- ⌘R.
- **The CLI's nudge.** After a `tasks` command (or a `tasks run` script, or an MCP call) pushed ops the server took,
  the CLI posts a Darwin notification (`notify_post`). The app listens for it (`notify_register_dispatch` on the main
  queue) and runs its normal sync, so a CLI change shows in about half a second instead of at the next 30s tick.
  - It carries no data: the changes still come through `/v1/sync`. A read, a `--dry-run`, a `--cached` write or a
    push that didn't reach the server posts nothing; ops queued offline post when a later command pushes them.
  - Debounced in the app: the sync runs 0.5s after the last nudge, and no later than 5s after the first of a burst, so
    a burst of commands is one sync. A nudge during a sync asks for one more pass after it, as any request does.
  - The name: Release builds use `com.elguindi.Tasks.changed`. Debug builds (the "Tasks Dev" app, a `swift build`
    CLI) use `com.elguindi.Tasks.changed.dev.<hash>`, the hash being FNV-1a of the server's origin
    (`scheme://host:port`), so a test run against a `wrangler dev` reaches only Debug apps syncing with that server
    and never the installed app (`SyncNudge` in TasksCore).

**Pushback:** a WebSocket (DO hibernation API) would cut sync latency from up to 30s to near-instant. For one person's Macs, 30s is fine. If it's ever wanted, the socket only needs to send "head is now N" and clients keep using `/v1/sync`, so the protocol doesn't change.

### Compaction and server snapshots: not yet

Rough size: ~200 bytes per op. The performance target of 100k ops (§9) is ~20 MB. DO SQLite storage allows 10 GB.

The client keeps its own snapshot (§8), so launch cost doesn't grow with the log. Only two paths still scale with log length:

- the first sync of a new Mac (100 pages, once);
- the fallback replay.

Server snapshots would mean either running the reducer on the server in TypeScript (two reducers that must agree forever) or trusting client-uploaded snapshots. Revisit them only if a new Mac's first sync becomes measurably slow.

### Deletes

Deleting a task sets `deleted: true`. Lists are never deleted, only archived (§2). Either way the entity stays in state and every op stays in the log forever. Hard deletes are deferred (§11).

## 6. The Git analogy: what we adopt

The design is close to Git, and the mapping is useful. Where it breaks down is where this design gets simpler than Git.

| Git | Here | Difference |
|-----|------|------------|
| commit | op | A field patch on one entity, not a snapshot of a tree. |
| `main` on the remote | the server log | Linear and append-only. Never rewritten, no branches, no merge commits. |
| `git push` | ops in `/v1/sync` | Never rejected as "not a fast-forward". The server appends at head. That's safe because ops are patches addressed by entity id, not diffs against a parent. |
| unpushed local commits | pending queue | — |
| `fetch` + `rebase` | a sync | The rebase never conflicts. Pending ops are replayed *unchanged* on the new head, and the reducer resolves overlaps deterministically (§5). Nothing is rewritten, so nothing needs the user. |
| working tree | in-memory `AppState` | Always derived, never edited directly. |
| tree at a commit | snapshot at a cursor | Client-side in v1 (§8). Server-side deferred. |
| packfiles | — | Not needed. |
| `git log -- <path>` | log filtered by `target` | — |
| `git revert` | an inverse op | Used for undo. |

### Ideas evaluated

**Content-addressed op ids: no.**

- A hash id needs canonical JSON that byte-matches in both Swift and TypeScript (key order, number formatting, Unicode normalization). That's a permanent source of subtle bugs.
- It buys nothing. A client-generated UUID already makes retries idempotent, and TLS already covers transport integrity.

**Parent-hash chain: yes, the minimal form.**

The protocol trusts a bare index ("give me everything after `k`"). If the server log is ever reset, or restored from a Durable Object point-in-time backup, and then grows again, a client's index silently points into a *different* log. The client would apply the wrong ops with no error. The existing `from > head` check only catches the case where the log ends up shorter.

- **Server:** each entry stores `hash = SHA-256(prevHash + "\n" + opText)` as hex, where `opText` is the op JSON exactly as the server stores it and `prevHash` is `""` for `seq 0`.
- **Client:** sends `base`, the hash of its last entry. A mismatch returns `409`, and the client re-pushes every op it knows and resyncs from 0 (§5).
- **Why it's cheap:** the client never computes a hash. It stores the server's hash with each entry and echoes the last one back. So no canonical-JSON rules exist anywhere.
- **Cost:** one column, one hash per append, one comparison per sync, ~65 bytes per op.
- **Not adopted:** clients verifying the whole chain on load. The torn-tail rule (§8) covers the realistic local failure.

**On-disk format: the simplest that works.**

- **Client:** `log.jsonl`, with each line being one server entry *verbatim*: `{"seq","received","hash","op"}`.
  - The file is append-only. At launch only the tail after the snapshot is read (§8).
  - Packed segments (packfiles) are rejected: the snapshot already keeps launch cost off the log's size.
- **Server:** one SQLite table (§7) with `seq` as the primary key and a unique index on `id`.
  - The op is stored as JSON text, never decomposed into columns, because the server never queries inside ops.

**Snapshots / checkpoints: client yes (v1), server no.**

- A snapshot is "the tree at a commit": reduced state plus `(cursor, hash)`, so it's tied to one exact point in the log.
- **Client:** `snapshot.json` is in v1 (§8). Launch loads it and replays only the tail.
- **Server:** snapshots (the equivalent of a shallow clone for a new Mac) stay rejected, because they'd need a second reducer in TypeScript (§5).
- The log stays complete either way. Snapshots are a cache and never replace history.

**Per-task history: free, no UI in v1.**

"`git log -- <task>`" is a scan of `log.jsonl` filtered by `target`, read on demand in the background, because the log isn't held in memory. It needs no index or extra storage. A history view can be added later without any change to the model or storage.

**Undo as a new op: yes. ⌘Z is expected on macOS.**

- Undo is `git revert`: when performing an op, the client records its inverse, `set` with the *previous* values of exactly the keys it wrote. ⌘Z performs that inverse as a new op. Nothing in the log is ever removed.
- The stack lives in `UndoManager`, per session, and isn't synced.
- Undo needs deletes to be reversible. So **delete becomes an ordinary field** (`deleted: true`) instead of a terminal tombstone with its own op type.
- That *removes* two op types (`task.delete`, `list.delete`) and the special "terminal" reducer rule. Lists use `archivedAt` the same way (§2).
- Behavior is unchanged otherwise: concurrent edits don't touch `deleted`, so a delete still sticks unless explicitly undone.
- Undoing an archive restores the list's tasks too (§5 rule 5).
- Undo is last-writer-wins like any write. Undoing an edit that another Mac has since changed overwrites that change. That's acceptable for one user.

**Ordering keys (§3) under all of this:**

- **Keys are just fields in op payloads.** The log, the hash chain and dedup never look at them.
- **Rebase doesn't recompute keys.** A pending move keeps the key it was given, even if the neighbours changed on another Mac. The worst case is a tie (broken by `id`) or a slightly-off position, exactly the concurrent-reorder case in §3. Recomputing keys during rebase would bring back conflict resolution that needs to know the user's intent, which this design avoids on purpose.
- **Undoing a move** restores the old `{list, order}` pair. If a rebalance happened in between, the old key sorts approximately rather than exactly. That's rare, and a drag fixes it.
- **A rebalance** is one contiguous block of ops (one request), like a single big "reformat" commit. It's rare enough that the extra log growth doesn't matter.

### Recommendation

Adopt:

- the linear, server-ordered log as-is;
- a minimal hash chain (server computes, client echoes `base`);
- verbatim JSONL entries on the client;
- one SQLite table on the server;
- delete-as-a-field with undo as inverse ops;
- a client snapshot (§8).

Reject content-addressed ids and packed segments. Defer server snapshots and a history UI.

## 7. Cloudflare architecture

### Choice: one Worker plus one SQLite-backed Durable Object. No D1.

```
macOS app ──HTTPS──▶ Worker (auth, routing) ──RPC──▶ UserLog DO (idFromName("me"))
                                                       └─ SQLite: log table
```

Why a Durable Object instead of D1:

- **Ordering is free.** A DO is single-threaded, so `head++` can't race and no locking or transaction tricks are needed.
- **The log is the database.** There's one table, with no `user_id` column and no shared schema.
- **Room to grow.** The same object can later hold WebSockets (realtime) or an alarm-driven snapshot without changing the architecture. Multiple users would just mean one DO per user.
- D1 would work, but adds a separate database and query surface for no benefit when every query is "read or append the log".

DO storage:

```sql
CREATE TABLE log (
  seq      INTEGER PRIMARY KEY,   -- 0-based, dense, assigned as head
  id       TEXT NOT NULL UNIQUE,  -- client op id (idempotency)
  received INTEGER NOT NULL,      -- server ms
  op       TEXT NOT NULL,         -- JSON.stringify({id, at, type, target, set, actor, batch}), hashed as stored (§5)
  hash     TEXT NOT NULL          -- SHA-256(prev hash + "\n" + op), hex (§6)
);
```

`head` and the last hash are read once on startup and cached in memory. `head` is `MAX(seq) + 1`, read through the primary key (`ORDER BY seq DESC LIMIT 1`). That equals `COUNT(*)`, because `seq` is dense, without scanning the table.

The append never awaits: SHA-256 comes from `node:crypto` (the `nodejs_compat` flag), which is synchronous, and the inserts run in one `transactionSync`. So requests can't interleave inside `sync()`. Web Crypto's `digest()` is async and would open a window between reading `head` and appending. The cached `head` and hash are updated only after the transaction commits.

The Worker has one route, `POST /v1/sync`. The split of work:

- **Worker:** routing, auth, size limits, parsing and op validation (`404`, `405`, `401`, `413`, `400`), then the response encoding.
- **DO, via RPC:** `sync(from, base, ops)`, where each op arrives as its id and its stored text, serialized by the Worker. It does the log check (`409`), the append and the page read, and returns the response body (built by concatenating the stored op text, never re-parsing it) or a mismatch.

The server is written in TypeScript.

The Worker is served from its `*.workers.dev` URL in v1, with no custom domain.

Resources, **deployed 2026-10-30** to `https://tasks.elguindi.workers.dev` with the user's approval (`server/DEPLOY.md`); ask before changing any of them:

- one Worker, `tasks`;
- one DO namespace with a `new_sqlite_classes` migration (`v1`);
- one secret, `API_TOKEN`.

**Redeployed 2026-10-31** with the user's approval: version `a0db0c46-dab4-4eaf-9e02-5b7ab64ffc83`, commit `9728858`,
which accepts the optional `actor` and `batch` envelope keys (§5) for the agent CLI. Nothing else changed: the secret,
the DO and its log were kept (166 entries, untouched by the smoke test, which only pulled). **Never roll the Worker
back past this version** (§5 "Validation may only loosen").

**Redeployed 2026-10-31** with the user's approval: version `d5f33632-50a7-48af-bb9f-0a2128102304`, commit `53dfe22`,
which accepts `kind: "heading"` on `task.create` and `notes` on `list.create`/`list.update` (§2, §5). The secret, the
DO and its log were kept (200 entries, unchanged by the read-only smoke test). **Never roll the Worker back past this
version.**

### Auth: one fixed token

The app is single-user:

- A Worker secret `API_TOKEN` holds a long random token. The Worker compares the `Authorization: Bearer` header to it in constant time.
- The token is pasted once into the app's settings and stored in the Keychain.
- There's no account system and no Apple Developer configuration.

If more users ever matter, the token maps to a user id, the DO is named by that id, and Sign in with Apple can issue tokens. Sync doesn't change.

## 8. macOS client

### Platform

One macOS app target, **macOS 14+**, the minimum `design/PaneTheme.swift` already sets. It uses a `NavigationSplitView` with a sidebar (Today, then the lists). Sync keeps several Macs in step. Nothing here depends on AppKit-only APIs beyond what SwiftUI provides, so an iOS target stays possible later without changing the model or sync.

### Local store: the log, plus a snapshot cache

**Pushback on SwiftData/Core Data:** they would be a second, mutable source of truth next to the log, with their own migration and sync semantics, and every op would have to be mapped into managed objects. The log already *is* the database. A personal task set (~10k tasks) fits in memory.

Files in Application Support:

| File | Contents | Written |
|------|----------|---------|
| `log.jsonl` | Confirmed entries exactly as the server sent them (`seq`, `received`, `hash`, `op`). Append-only. | Appended after each sync that returns entries. |
| `pending.jsonl` | Pending ops. Append-only. | One append per local op. Rewritten atomically after a sync confirms some. |
| `snapshot.json` | `{schema, cursor, hash, logOffset, state}`: the reduced confirmed state at `cursor`. | Debounced after syncs, and on quit (below). |
| `log.jsonl.bak-<ms>` | A log moved aside by a `409` recovery (§5). Never read by the app. | Created on `409`; deleted when the recovery finishes. |

**Pending ops are sent verbatim.** A request carries each pending op as its `pending.jsonl` line, unchanged. For a local op that's its JSON as the client wrote it; for an op recovered from the log (§5) it's the server's text, which may hold keys this client can't decode.

- **The log is the source of truth.** The snapshot is a cache that can always be rebuilt from it.
- **Torn tails:** if a crash leaves the last line of a `.jsonl` file torn, that line is dropped on load. A torn log entry is simply refetched.
- **Write order within a sync:** append to `log.jsonl`, then rewrite `pending.jsonl`, then (later) write the snapshot. So an op that was confirmed but is still in `pending.jsonl` after a crash is always in the log tail after the snapshot. Launch finds it there and drops it from pending.
- **No scans at runtime:** the cursor and `base` are kept in memory (the snapshot's cursor plus the tail length, and the last hash). They're never derived by scanning the log.

### Snapshot (v1)

**Contents:**

- `schema`: a version number. Schema 2 added a task's `kind` and a list's `notes` (§23): a snapshot of another schema
  is dropped and the log replayed.
- `cursor`.
- `hash`: the hash of entry `cursor − 1`.
- `logOffset`: the byte offset in `log.jsonl` where entry `cursor` starts.
- The confirmed `AppState`: every task and list, including deleted and archived ones.

**Format: JSON, using the same `Codable` types.**

- 10k tasks make a ~3–5 MB file, with a decode budget of ≤ 60 ms, off the main thread.
- JSON keeps one serialization of the model, not two to keep in step, and the file stays inspectable.
- **Gate:** a benchmark test decodes a 10k-task fixture. If it misses the budget, the encoding inside `SnapshotStore` is swapped for a hand-written binary format. Nothing else changes, because the snapshot is a cache keyed by `schema`.

**When it's written:**

- After any sync that applied entries, debounced 5 s.
- When the app resigns active or quits.
- It's skipped if the cursor hasn't moved since the last write.
- The snapshot is encoded off the main thread from a value copy of the confirmed state, which is free thanks to copy-on-write.
- It's written atomically: temp file, then rename.

**Launch**, at a cost of O(state + tail) that doesn't depend on log length:

1. Decode `snapshot.json` off the main thread.
2. Seek `log.jsonl` to `logOffset` and read the tail. The first tail line must have `seq == cursor`. Apply the tail entries to the state. The debounce keeps the tail short, usually a handful of entries.
3. Read `pending.jsonl`, drop ops whose `id` appears in the tail and build the pending overlay from the rest (§9).
4. Build the indexes (§9) and show the window.

**Fallback: full replay of `log.jsonl`**, followed by writing a fresh snapshot straight away. It happens when the snapshot is:

- missing;
- undecodable;
- from a different `schema`;
- failing the offset/`seq` check.

Bump `schema` whenever the shape of `AppState` or the reducer's semantics change. The next launch then rebuilds from the log with the new reducer, which is one reason the log stays the source of truth. A full replay of 100k ops takes about a second, and only once.

**On `409`:** recover as in §5 ("Recovering from a 409"): the confirmed log's ops plus pending become the new `pending.jsonl`, then `snapshot.json` is deleted and `log.jsonl` is moved aside, in that order, and the Mac syncs from 0. No op is ever discarded.

### Shape

```
Op               Codable value type matching §5.
AppState         struct { tasks: [ID: Task], lists: [ID: TaskList] }   // confirmed; deleted/archived included
                 mutating func apply(_ op: Op) -> ID?    // the reducer: pure; returns the one id it changed, nil if ignored
FractionalIndex  keyBetween(a, b), keysBetween(a, b, n)  // §3, pure
Store            @MainActor; owns confirmed AppState, cursor, base, pending ops and the projection
                 func perform(_ ops: [Op])                // optimistic; registers inverse ops with UndoManager (§6)
Projection       pending overlay, indexes, model registry (§9)
Ordering         moveOps(task, to: list, after: Task?, before: Task?) -> [Op]   (keys, ties, rebalance)
Seed             seedInboxIfMissing(): run on launch (§2)
SyncClient       POST /v1/sync, backoff, triggers; network and response decoding off the main actor
Persistence      LogFile, PendingFile, SnapshotStore; all file I/O on one background serial queue
```

Views read models and index buckets from the projection and call `store.perform(…)`. Views never touch persistence or the network, never compute keys, and never filter or sort.

Unit tests cover the pure parts with fixed inputs:

- **Reducer:** the conflict cases in §5, and that every op followed by its inverse leaves state unchanged.
- **Rebase:** for random interleavings of local and remote ops, the incremental result equals a full replay (§9).
  - The setup is two or three simulated Macs making random ops and syncing in random orders, with partial pushes and ops created while a request is in flight.
  - After every sync, visible state, indexes and model values must equal a from-scratch replay of `confirmed log + pending`.
- **Snapshot:** loading the snapshot and applying the tail equals a full replay. A corrupt, missing or old-schema snapshot falls back correctly.
- **409 recovery:** against a server that was wiped, restored to an older point (and grown since), or healthy with a damaged client log, the server ends up holding every op id any Mac ever had, and all Macs converge. The rebase test includes restores at random points. A crash after each recovery step still ends there. Unknown keys in recovered log ops are re-pushed byte for byte.
- **Ordering:** ties, rebalance, concurrent moves replayed in both orders.
- **Today predicate:** midnight, both dates set, completed yesterday, list archived.
- **Seeding:** two Macs seeding offline and then syncing in either order end up with one Inbox. A renamed or archived Inbox survives a re-seed.
- **Benchmarks:** see §9.

The theme comes from `PaneTheme.swift`. Screen design follows the design directions in `design/`.

## 9. Performance: view layer, indexes, budget

The goal is that every regular operation costs time proportional to what changed. Nothing copies, re-sorts or re-renders the whole state.

### The property everything rests on

**Every op touches exactly one entity:** its `target`.

- The reducer changes only that entity and returns its id.
- Cross-entity effects (an archived list hides its tasks) are handled by which lists the views iterate (§9 indexes), never by rewriting entities.

That property makes per-entity rebase, per-entity index updates and per-row redraws possible.

### Visible state: confirmed + a pending overlay

- **`confirmed: AppState`:** the state reduced from the log.
- **`overlay: [ID: Entity]`:** for each id that has pending ops, the result of applying those ops, in order, to `confirmed[id]`. It's usually empty or tiny.
- **Visible entity** = `overlay[id] ?? confirmed[id]`.

A **local op** is applied to `overlay[target]`. The changed set is `{target}`.

**After a sync**, the cost is proportional to the new entries, never a copy of the state:

- **Fast path:** the new entries are exactly the head of the pending queue, i.e. our own ops, in order.
  1. Apply them to `confirmed`.
  2. Drop them from pending.
  3. Remove overlay entries for ids with no pending ops left.

  Visible state is untouched, because it already reflects these ops. Nothing redraws. This is the common case when only one Mac is editing.
- **General path:** remote ops are interleaved with ours.
  1. Apply all new entries to `confirmed`.
  2. Drop the confirmed ones from pending.
  3. Let **touched** = ids targeted by the new *remote* entries.
  4. For each touched id: `visible[id] = confirmed[id]`, then re-apply that id's remaining pending ops in order (this is the new `overlay[id]`, or no overlay entry if none remain).
  5. Clear overlay entries for any other id left with no pending ops.

  All other entities, models and index entries are untouched.

The approved rule also listed ids with remaining pending ops in `touched`. Those can be skipped when no remote entry targets them, because their result can't have changed:

- `confirmed[id]` only advanced by our own ops, applied in the same order the overlay already applied them.
- The rebase test (§8) proves the two agree.

**Why remote ops can't be applied directly onto the visible state.** Take "rename T on two Macs":

1. Mac B renames T to "Groceries" and syncs.
2. Mac A, offline, renames T to "Shopping". That rename is pending, and A's screen shows "Shopping".
3. A syncs. The server appends A's op after B's, so the log reads `[B: "Groceries", A: "Shopping"]` and T's final title is **"Shopping"**.

If A applied B's remote op straight onto its visible state, the screen would flip to "Groceries". Then, when A's own op came back confirmed, the fast-path reasoning ("already reflected") would skip it, and A would show "Groceries" while its confirmed state and every other Mac say "Shopping".

Rebuilding T from `confirmed[T]` (= "Shopping") plus A's remaining pending ops (none) gives the right answer. The same holds if A's rename was made while the request was in flight and isn't in this push: `confirmed[T]` = "Groceries", plus the pending "Shopping", shows "Shopping", which is what the log will say once it's pushed.

### Fine-grained observation

**Choice:** one `@Observable final class` per task and per list (`TaskModel`, `ListModel`), held in a registry keyed by id. On top of that, there's one small `@Observable` object per index bucket, holding an `ids` array.

How Observation tracks reads on macOS 14:

- Observation tracks exactly which properties each view body reads.
- A row that reads `model.title` re-renders when that model's title changes, and for nothing else.
- A list screen reads only its bucket's `ids`, so editing a title never touches it. A reorder changes `ids`, so the `ForEach` diff runs, but the bodies of unchanged rows don't.

Rejected alternatives:

- **One `@Observable` store holding `AppState`:** any change invalidates every view that read `state`.
- **`ObservableObject` / `@Published`:** invalidation is per object, so every view observing the store redraws.
- **Value-type rows with `Equatable`:** parent bodies still re-run and diff every row.

Rules:

- **Models are created lazily**, the first time a row asks for one, from the visible entity, and then cached. Launch doesn't allocate 10k objects.
- When an id changes, its cached model is updated by **assigning only fields whose value differs**. Observation notifies on every assignment, even when the new value is equal.
- **Rows:** `ForEach(bucket.ids, id: \.self) { TaskRow(model: registry.task($0)) }` inside a SwiftUI `List`. `List` is lazy (backed by `NSTableView`), so only visible rows exist.

### Maintained indexes

The projection keeps these indexes and updates them from changed ids. No view body filters or sorts.

| Index | Contents | Sorted by |
|-------|----------|-----------|
| `open[list]` | Open, non-deleted tasks of each list (archived lists included) | `(order, id)` |
| `completed[list]` | Completed, non-deleted tasks of each list | `completedAt` desc |
| `today[list]` | Open tasks of each list that match the Today predicate | `(order, id)` |
| `todayDone` | Tasks completed today that match the Today predicate | `completedAt` |
| `activeLists` | Lists with `archivedAt == nil` | `(order, id)` |
| `archivedLists` | Archived lists | `archivedAt` desc |

- **Archiving costs nothing.** The task indexes ignore archive state. Today and the sidebar iterate `activeLists` only, so archiving moves one list between `activeLists` and `archivedLists`. An archived list's screen reads the same `open`/`completed` buckets.
- **One changed task:** compare its old and new placement (which buckets, which sort key). If nothing changed, do nothing. Otherwise remove the id from the old bucket and binary-search-insert it into the new one. That's O(log k) plus a memmove for a bucket of k ids, microseconds even for thousands.
- **Batches** (rebalance, first sync): if a batch touches more than ~1/8 of a bucket, re-sort that bucket once instead.
- **Midnight:** Today membership depends on the date. Incremental updates use the current `today`. When the day changes, `today` and `todayDone` are rebuilt in one pass over open tasks and tasks completed in the last day: O(n), ~1 ms at 10k tasks.
- **The reducer stays pure.** It knows nothing about overlays, indexes or models; it returns the changed id. The projection reads each changed entity before and after and updates the overlay, indexes and models. The rebase test (§8) checks every incremental index against a from-scratch rebuild.

### Main actor vs background

- **On the main actor:** the reducer, overlay, indexes and models. All of it is O(changes).
- **In the background:** network, decoding sync responses, all file I/O and encoding the snapshot.

A local edit never waits on disk. The in-memory change and the redraw happen first, and then the append to `pending.jsonl` is queued. A crash inside that sub-millisecond window can lose one edit, which is accepted.

### Budget

Target: an Apple-silicon Mac with ~10k tasks (mostly completed) and ~100k ops in the log. "App work" means our code on the main actor, excluding SwiftUI layout and rendering.

| Operation | Budget | Why it holds |
|-----------|--------|--------------|
| Launch to data ready | ≤ 100 ms, flat in log length | Snapshot decode ≤ 60 ms off main, short tail, index build ≤ 10 ms, lazy models |
| Local edit (op → visible) | ≤ 1 ms app work; one row redraws | One overlay entry, one index check, changed fields only; disk is async |
| Sync applying N remote ops | ≤ 10 µs per op of app work (≤ 10 ms for 1,000) | Decoding off main; per-entity reduce, rebase and index update |
| Sync confirming only our own ops | ≈ 0; nothing redraws | Fast path |
| Drag reorder | ≤ 1 ms app work; one row moves | One op; one bucket remove + insert |
| Switching lists | ≤ 1 frame (16 ms) to first rows | Bucket already sorted; lazy `List` builds visible rows only |
| Midnight rollover | ≤ 5 ms | One pass to rebuild Today |
| First sync on a new Mac (100k ops) | A few seconds, once | 100 pages; the only O(log) path besides fallback replay |

Enforced by XCTest `measure` benchmarks on a generated 10k-task / 100k-op fixture. A regression fails the build. The benchmarks cover:

- launch from a snapshot;
- a local edit;
- applying 1,000 interleaved remote ops;
- a reorder in a 2,000-task list;
- the midnight rebuild.

## 10. Implementation order

Two tracks, server (S) and macOS (C), run in parallel. Each step ends with something testable, and neither track waits on the other until C4.

**Shared first step: fixtures.**

- The server agent writes the §5 worked examples as JSON files under `fixtures/sync/`: each request, response and error, plus the `opA`/`opB` hash vectors.
- Both tracks test against these files, so they agree on the wire format before either one talks to the other.

### Server

| Step | Build | Testable by |
|------|-------|-------------|
| S1 | Worker skeleton: routing, `404`/`405`, auth (`401`), JSON error bodies. | `vitest` with `@cloudflare/vitest-pool-workers`, running locally. |
| S2 | Parsing and validation: `400 bad_request`, `400 invalid_op` (with `index`/`field`), `413`. | A table-driven test per rule in the validation table, plus the 400/401 fixtures. |
| S3 | The DO: log table, append with dedup, hash chain, page read with `more`, `409`. | The hash vectors (`opA`/`opB` must produce exactly the fixture hashes), the 200 push/pull and 409 fixtures (`05b` is the recovery re-push: one op deduplicated, one appended), idempotent retry, a 2,345-entry pagination test. |
| S4 | Response compression, then **deploy to `*.workers.dev`, only after the user approves**: Worker, DO migration, `API_TOKEN` secret. | `curl` smoke test: a pull from 0, and a `POST` with `curl --compressed -D -` showing `Content-Encoding` (`-I` sends `HEAD`, which gets a `405`). |

Until S4, everything runs locally (`vitest`, `wrangler dev`) and no Cloudflare resources are created.

### macOS

| Step | Build | Testable by |
|------|-------|-------------|
| C1 | Pure core: `Op` Codable, the `AppState` reducer, `FractionalIndex`, the Today predicate, Inbox seeding. | Unit tests: conflict cases (§5), ordering, Today, seeding, and decoding every fixture op. |
| C2 | Projection: pending overlay, fast-path and general-path rebase, indexes, model registry. | The randomized rebase test (§8) and the incremental-vs-rebuilt index check. |
| C3 | Persistence: `log.jsonl`, `pending.jsonl`, the snapshot and its fallback, write ordering, the `409` recovery's file steps (§5). | Snapshot and crash tests, including a crash after each recovery step (§8); launch and edit benchmarks (§9). |
| C4 | `SyncClient`: chunking, the error table, backoff, `409` recovery. | Against `wrangler dev` from S3, or a stub that serves the fixtures: every row of the error table. Recovery against a wiped, a restored and a healthy server (§8). |
| C5 | UI with the Pane theme and `design/`: sidebar, Today, list screens, Archive, drag, ⌘Z, the token setting. | Manual testing plus the remaining §9 benchmarks. |

C1 has a hard dependency: §9's projection relies on the reducer returning the single changed id, so C1 has to provide that before C2 starts.

**End-to-end check (after S4 and C5):** run two app instances against the deployed Worker, then edit, reorder and archive on both, online and offline. The two instances run on one Mac with separate data directories, via a `-dataDirectory <path>` launch argument that exists for testing only. Done means both instances converge, and each matches a fresh third instance that syncs from 0. Then wipe the server log (a fresh local `wrangler dev` state, not the deployed Worker) and check that both instances recover it with nothing lost.

## 11. Later

Deferred on purpose. Each is additive and needs no change to what v1 stores.

- **Hard deletes:** permanently removing deleted tasks and archived lists.
  - The log keeps everything, so a real purge means rewriting history, like `git filter-repo`: rebuild the log without the purged entities, which gives a new hash chain.
  - Every Mac's `base` then mismatches, so each gets a `409`. But `409` recovery (§5) re-pushes every op a Mac knows, which would put the purged ops straight back. A purge therefore needs its own signal, e.g. a distinct error that tells Macs to drop ops for the purged ids before recovering.
  - The other open design work is producing the rewritten log on the server, which needs reduced state there (a server snapshot).
- **Server snapshots / compaction:** for faster first sync on a new Mac (§5, §6).
- **Realtime:** a WebSocket "head is now N" poke from the DO (§5).
- **Per-task history view** (§6).
- ~~**Block Markdown rendering** for notes (§2).~~ Built (`design/MARKDOWN.md`).
- **iOS, multiple users, Sign in with Apple** (§7, §8).

## 12. Open questions

None open. List deletion is resolved as archiving (§2).
