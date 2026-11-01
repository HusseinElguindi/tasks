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
                       │    └─ tasks_run ──▶ LOADER isolate (the script; env: { TASKS: stub }, globalOutbound: null)
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

**3. Code mode on Worker Loader.**
- **The script:** TypeScript is stripped to JS with `sucrase` (types only, small). It is wrapped exactly as the CLI
  wraps it (`export default async () => {\n…\n};`), so a script runs the same in both, and its line numbers match.
- **The isolate:** `env.LOADER.load({ mainModule: "bridge.js", modules, env: { TASKS }, globalOutbound: null })`.
  `TASKS` is `ctx.exports.TasksApi({ props: { run } })`, a loopback entrypoint whose methods call back into the
  Replica DO's fork for that run. The script can reach nothing else.
- **Limits:** the CLI's (10 s, 100 KB result, 200 log lines), with the same result and error shapes
  (`{ok, result, logs, change, synced}` / `{ok: false, error: {type, message, line}}`). `dryRun` returns the diff and
  writes nothing.
- **To check first:** that `worker_loaders` and `ctx.exports` loopbacks work under local `wrangler dev`.

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
binding between the two. `remote/.dev.vars` (gitignored) holds the dummy `SYNC_TOKEN` and `SETUP_SECRET`. Nothing is
created on Cloudflare.

## For later (not run; the coordinator asks the user)

```
cd remote
npx wrangler kv namespace create OAUTH_KV        # then put its id in wrangler.jsonc
npx wrangler secret put SYNC_TOKEN               # the main Worker's API_TOKEN
npx wrangler secret put SETUP_SECRET
npx wrangler deploy
```

The DO migrations ship with that deploy. The main `tasks` Worker isn't touched.

## Risks

- **Two implementations of the reducer and dates.** Parity fixtures guard them, but a later Swift change needs a
  fixture refresh (`pnpm parity`) to show up.
- **The shared replica:** clients take turns through the run lock, so a slow script delays the next one by up to 10 s.
- **Dates:** `Intl` in Workers carries full time zone data. DST edges are covered by the Today fixtures.
