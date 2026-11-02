# Remote MCP: plan

A second Worker, `tasks-mcp`, in `remote/`, that serves the local `tasks mcp`'s two tools (`tasks_types`,
`tasks_run`) over Streamable HTTP to claude.ai and other MCP clients. It is one more replica of the log, like the CLI.
It is written in TypeScript, and nothing existing changes: not `app/`, not `server/`, not the deployed `tasks`
Worker (docs/TASK-remote-mcp.md, "Decision").

Why TypeScript: the Wasm spike (2026-11-01) found that TasksCore doesn't build for WASI. The blockers are `notify`,
`URLSession`, `UndoManager` and `Dispatch`. Even once it builds, any Wasm module that imports `Foundation` is 19 MB
gzipped, against the Worker's 10 MB limit.

## Shape

```
MCP client ──OAuth──▶ tasks-mcp (remote/)
                       ├─ /authorize /token /register   workers-oauth-provider; consent needs a passkey
                       ├─ /mcp                          JSON-RPC: initialize, tools/list, tools/call
                       ├─ Replica DO (SQLite)           log, cursor, pending, folded state; one run at a time
                       │    └─ tasks_run ──▶ LOADER isolate (the script; env: {}, globalOutbound: null),
                       │                     its `tasks` calls → a Host RpcTarget passed to run(host), in the DO
                       └─ SYNC service binding ──▶ tasks Worker, POST /v1/sync (unchanged), Bearer SYNC_TOKEN
```

| Binding / config | What |
|---|---|
| `REPLICA` | Durable Object, SQLite. One instance (`idFromName("main")`), so every client shares one replica |
| `AUTH` | Durable Object, SQLite: passkeys, the registration-closed flag, each client's actor |
| `OAUTH_KV` | KV, required by workers-oauth-provider |
| `LOADER` | `worker_loaders` |
| `SYNC` | `services: [{ binding: "SYNC", service: "tasks" }]` |
| `TIME_ZONE` var | IANA name, default `America/Toronto` (this Mac's zone). Today and every date use it, through `Intl` |
| `DATE_ORDER` var | `md` or `dm` for numeric date phrases, the CLI's `TASKS_DATE_ORDER`. Default `md` |
| `SYNC_TOKEN`, `SETUP_SECRET` | secrets |

## Layout

```
remote/
  package.json  wrangler.jsonc  tsconfig.json  vitest.config.ts  README.md
  tasks.d.ts                 copy of the CLI's; test fails on drift
  src/index.ts               OAuthProvider: /mcp handler, consent and setup pages
  src/mcp.ts                 JSON-RPC, same instructions and tool text as MCP.swift
  src/replica.ts             Replica DO: storage, sync loop, run lock, forks
  src/auth.ts                Auth DO + WebAuthn (passkey) flows
  src/codemode.ts            transpile, Loader isolate, bridge, limits, the TasksApi entrypoint
  src/core/                  the port: op, wire, state (reducer, inverse), ordering, fractional-index,
                             calendar-date, today, date-phrase, projection (views), json (key order)
  src/cli/                   the port: commands (table), intents, refs, output, history (log/undo)
  parity/                    Swift package → golden JSON (below)
  test/                      vitest + @cloudflare/vitest-pool-workers
```

## Phases (stop and report after each)

**1. Core port and parity.**
- **Port these** from TasksCore:
  - `Op`/`Patch` and canonical op JSON (key order, `JSON.stringify` escaping);
  - `LogEntry` and the sync request and response;
  - `Reducer`, `Inverse` and `AppState.replay`;
  - `Ordering` and `FractionalIndex`;
  - `CalendarDate`, `Day`/Today and `DatePhrase`.
- **Projection:** a plain fold. The views (Today, sidebar, list rows, completed, archive, headings and sections) are
  computed on demand. The app's incremental buckets and models are UI-only and stay unported.
- **Left out:** `Persistence`, `Markdown`, `SyncNudge`, Observation, undo through `UndoManager`.
- **From the CLI,** port `Commands` (the table, as far as code mode uses it), `Intents`, `Refs`, `Output` (field
  order) and `History` (undo by batch, the UUIDv8 batch ids, "keep the later edit").

Parity, all generated outside the Swift package:
- **`remote/parity/`:** a Swift package that depends on `../../app/TasksCore` by path. It writes golden JSON:
  - folded state and every view for the `fixtures/sync` logs and for seeded random logs;
  - DatePhrase over a phrase × reference-day × order grid;
  - Today across DST days in `America/Toronto`;
  - the fractional-index vectors (read from TasksCore's test resources by path).
- **The command layer:** the stock `tasks` CLI (a debug `swift build` only talks to localhost) runs scenario scripts
  with `tasks run` against a local `wrangler dev` of `server/`, using a dummy token and a scratch `TASKS_DATA_DIR`.
  Each scenario records its starting log, its result and its ops. The TypeScript side replays the same log and
  script and must produce the same result and ops, with ids and `at` normalised.
- **`tasks.d.ts`:** a test compares `remote/tasks.d.ts` with `app/TasksCore/Tests/TasksCLITests/tasks.d.ts` (the
  golden copy CodeModeTests holds the generator to). A parity script also diffs it against `tasks types`.

**2. Replica DO and sync.**
- **Tables:** `log(seq, received, hash, op)` (verbatim text), `pending(id, json)`, `rejected`, `meta(cursor, base)`,
  and a snapshot row. The fold is rebuilt on wake from the snapshot plus the tail.
- **The sync loop** is `Store.runSync`, ported:
  - 1,000-entry pages;
  - 500-op / 900 KB chunks;
  - `invalid_op` moves the op to `rejected`;
  - 413 halves the chunk;
  - 401, 404, 405 and `bad_request` stop sync;
  - transient errors get a few short retries inside the request, then the run reports `synced: false` and the ops stay
    queued;
  - 409 recovery: every known op becomes pending, from 0, nothing discarded;
  - the alarm retries anything left queued.
- **A run's life,** as in SDK-PLAN §2:
  1. take the run lock (one script at a time);
  2. pull;
  3. build on a fork;
  4. commit with `actor` and `batch`;
  5. push;
  6. report once our ops are back in a page.
- **Test:** `wrangler dev` with a local `server/` and a dummy token. Push, pull, two replicas, then 409 and 413 cases
  (with the server's own fixtures).
- **As built:** the cursor and `base` aren't stored; they're the log's last row (seq + 1, its hash), so they can't
  disagree with it. A 409 recovery is one SQLite transaction, so it has no half-done states (the CLI's files need
  four ordered steps). The Inbox is seeded at the start of each run, as each CLI command's `Store` does. Transient
  retries inside a run wait at most 2 s each (the CLI: 8 s). The Worker tests run the DO in workerd with `SYNC`
  forwarded from Node to `server/` under wrangler's test harness (a fresh log per test) or a real `wrangler dev`.

**3. Code mode on Worker Loader.**
- **The script:** TypeScript is stripped to JS with `sucrase` (types only, small). It is wrapped exactly as the CLI
  wraps it (`export default async () => {\n…\n};`), so a script runs the same in both, and its line numbers match.
- **The isolate:** `env.LOADER.load({ mainModule: "bridge.js", modules, env: {}, globalOutbound: null,
  limits: { cpuMs: 10000 } })`, fresh for each run. The DO calls the bridge's `run(host)` over RPC, where `host` is
  an `RpcTarget` holding that run's fork: every `tasks.*` call and console line lands on it, in the DO's memory, with
  no second request into the DO. The script can reach nothing else. (An `RpcTarget` can't go in `env`:
  DataCloneError. The plan's `ctx.exports` loopback also works locally but needs that second hop.)
- **Limits:** the CLI's (10 s, 100 KB result, 200 log lines), with the same result and error shapes
  (`{ok, result, logs, change, synced}` / `{ok: false, error: {type, message, line, column}}`). `dryRun` returns the
  diff and writes nothing. The 10 s are enforced three ways: a host timer (stops a script that waits), every call
  after the deadline failing with the timeout error, and `limits.cpuMs` (a busy loop, production only).
- **Checked first (2026-11-01), all locally:** Worker Loader under `wrangler dev`, from a Worker and from a DO, and in
  the vitest Workers pool; `globalOutbound: null` blocks `fetch`; stacks read `script.js:line:col`; the SYNC binding
  between two `wrangler dev` sessions (`[connected]`).
- **Caveat, local only: a busy loop isn't stopped.** workerd doesn't enforce `limits.cpuMs` locally, and a script that
  never yields (`while (true) {}`, or a loop of calls that each answer at once) starves the DO's timer and blocks the
  DO until it ends, so `wrangler dev` needs a restart. A script that waits is stopped at 10 s as in the CLI. Scripts
  come from the model, so this is an accident, not an attack; in production `limits.cpuMs` should stop it, which the
  post-deploy check below verifies. If it doesn't, the fallback is deadline checks inserted into every loop and
  function when the TypeScript is stripped (about half a day).
- **Error positions:** sucrase's source map takes them back to the TypeScript, as Deno does, so all 62 positioned
  errors in the CLI scenarios match. Lines always match; a column can differ after TypeScript-only syntax on the same
  line, where Deno's map is coarser (it can point at an earlier token).
- **Until phase 4,** `/mcp` takes `Authorization: Bearer <DEV_TOKEN>` (a local-only secret; unset means closed) and
  writes as `agent:dev`.

**4. OAuth and the passkey.**
- **OAuth:** `@cloudflare/workers-oauth-provider` serves `/mcp` as its API route, plus dynamic client registration.
- **Consent page:** shows the client's name and redirect URI and needs a passkey assertion (`@simplewebauthn/server`).
  The grant's props carry `actor = "agent:" + slug(client name)`, for example `agent:claude-ai`, which is 1–64
  characters and shown on the page.
- **Setup:** `/setup` with `SETUP_SECRET` registers the first passkey. After that, registration is closed in the Auth
  DO, and setup refuses.
- **Test:** register, consent, token and an `/mcp` call, all locally, with a virtual authenticator in the tests.

## Local dev

`server/` runs unchanged under its own `wrangler dev` with `--var API_TOKEN:<dummy>` and `--persist-to` a folder in
`remote/.wrangler/`. `tasks-mcp` runs in a second `wrangler dev`, and the dev registry resolves the `SYNC` service
binding between the two. `remote/.dev.vars` (gitignored) holds the dummy `SYNC_TOKEN`, `DEV_TOKEN` (phase 3) and
`SETUP_SECRET` (phase 4). `pnpm smoke` (`remote/scripts/dev-smoke.mjs`) runs exactly that, with dummy tokens and
scratch state, then MCP over HTTP: a write, a read, an error, and the server's log. Nothing is created on Cloudflare.

## For later (not run; the coordinator asks the user)

```
cd remote
npx wrangler kv namespace create OAUTH_KV        # then put its id in wrangler.jsonc
npx wrangler secret put SYNC_TOKEN               # the main Worker's API_TOKEN
npx wrangler secret put SETUP_SECRET
npx wrangler deploy
```

The DO migrations ship with that deploy. The main `tasks` Worker isn't touched. `DEV_TOKEN` is never set in
production.

**After the deploy: check that `limits.cpuMs` stops a busy loop** (it can't be checked locally). From a connected
MCP client, run `tasks_run` with `while (true) {}`. Expect, within about 10–15 s,
`{ok: false, error: {type: "Limit", message: "The script ran longer than 10 s, so it was stopped."}}`, and then a
`tasks_run` of `return 1` answering at once (the replica isn't stuck). It writes nothing. If the first call hangs or
the second waits, the replica is blocked: switch to the loop-guard fallback (phase 3, "Caveat").

## Risks

- **Two implementations of the reducer and dates.** Parity fixtures guard them, but a later Swift change needs a
  fixture refresh (`pnpm parity`) to show up.
- **The shared replica:** clients take turns through the run lock, so a slow script delays the next one by up to 10 s.
- **A busy loop:** locally it blocks the replica until `wrangler dev` restarts; in production `limits.cpuMs` should
  stop it at 10 s (the post-deploy check). Unverified until then.
- **Dates:** `Intl` in Workers carries full time zone data. DST edges are covered by the Today fixtures.
