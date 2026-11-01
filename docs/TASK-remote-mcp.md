# Task: a remote MCP server, as a separate Worker, with TasksCore in Wasm

## What the user decided (2026-11-01)
- **Code mode:** the same two tools as the local `tasks mcp` (`tasks_types`, `tasks_run`). The model writes one script
  per request, and it runs in a **Dynamic Worker Loader** isolate. The user is on the paid plan and says the Loader
  is ready to use.
- **Approve new clients with a passkey** (WebAuthn) on the OAuth consent page.
- **Read and write.**
- **Keep it separate from the current server: a different Worker.**
- **Try the Swift WebAssembly path:** TasksCore compiled to Wasm, so the reducer, the projection and the date logic
  have one implementation.
- "Really just the fastest way to get started, and decoupled."

## The shape: the remote MCP is another replica
The CLI is already a replica: it pulls the log over `POST /v1/sync`, folds it with TasksCore, and pushes new ops
with an `actor` and a `batch`. The remote MCP does exactly the same, but it runs on Cloudflare. **The existing
Worker, UserLog DO and app don't change at all.**

```
claude.ai / other MCP clients ──OAuth──▶ tasks-mcp Worker (new, its own wrangler project in remote/)
                                           ├─ /mcp  Streamable HTTP (MCP)
                                           ├─ /authorize /token /register (workers-oauth-provider; consent = passkey)
                                           ├─ Replica DO (new): the log cursor, the folded state, held via TasksCore.wasm
                                           ├─ tasks_run → Worker Loader isolate (the script; its only binding is the API)
                                           └─ sync: POST /v1/sync to the existing Worker, using a service binding or
                                              HTTPS, with the sync token as a secret
```

- Each OAuth client gets its own token, and its name becomes the op `actor` (for example `agent:claude-ai`).
  The `batch` id makes one script one undo, as it is locally.
- The SDK plan's write rules apply as the CLI applies them, such as "keep the later edit" (`docs/SDK-PLAN.md`).
- Today and dates need the user's time zone. Make it a config variable.

## Phase 0: the Wasm spike (do this first; it decides the rest)
1. Compile `app/TasksCore` (the library, not TasksCLI) to Wasm with the Swift SDK for WASI. The toolchain comes from
   mise (`swift 6.4.2` is installed there). Install a matching Wasm SDK with `swift sdk install`. Never use brew.
2. Find what doesn't build on WASI: Foundation pieces, Calendar or TimeZone, hashing (the hash chain), and the
   networking in `SyncClient`. Prefer small seams over forks: move platform-only code behind `#if`, or leave it
   out of a `TasksCoreWasm` target. Don't break the macOS build or its tests.
3. Expose a thin C-ABI or JSON-in/JSON-out surface: apply ops and return the projection; run a query; build ops for
   an intent. Run it in a Worker with `wrangler dev`, against an exported copy of the log, or the fixtures in
   `fixtures/`.
4. Measure the compressed size against the Worker limit, the cold start, and the fold time for the real log.
5. **Stop and report** with the numbers and a go/no-go for Wasm. If it's a no-go, say what the fallback would cost
   (a TypeScript reducer with shared golden fixtures). Don't switch to the fallback on your own.

## Phase 1 and on (after the coordinator says go)
Write `docs/REMOTE-MCP-PLAN.md`, then build in `remote/`. Cover:
- the Replica DO;
- sync with the main Worker;
- the code-mode runner on Worker Loader, reusing the CLI's `tasks.d.ts` and command table as the API contract;
- OAuth with workers-oauth-provider;
- passkey registration. Bootstrap the first passkey with a one-time setup secret, and close registration after it.

Everything runs locally under `wrangler dev` with a local copy of the main server.

## Rules
- **No Cloudflare changes without asking.** Don't create Workers, DOs, KV or secrets, and don't deploy. When you're
  ready, write the exact commands in your report and the coordinator will ask the user. Never touch the live
  server or the deployed main Worker. Never roll anything back.
- Never print or commit the sync token (`~/.tasks-sync.env`). Use a dummy token with the local server.
- Don't touch the installed app, its data, or Rex.
- Per-path commits only (`git commit -m … -- <paths>`), ending with `Co-Authored-By: Claude Opus 5.5
  <noreply@anthropic.com>`. Never `git add -A`. Never push.
- Compact yourself between phases if context passes about 45%.

## Update from the user: stop before changing TasksCore
If anything in TasksCore doesn't compile for WASI, **stop before changing any TasksCore source**: no `#if`, no new
target, no moved code. Report what fails and why, with the file and line for each, the options you see, and what
each would cost. The user will decide. Building the stock package and inspecting the errors is fine. Editing it is
not, until they say so.

## Decision (the user, 2026-11-01): the TypeScript path, and nothing existing changes
"just do the typescript path. i dont want to change what we have."

- **Nothing existing changes.** That means `app/` (TasksCore, TasksCLI, the app), `server/` and the deployed main
  Worker. The remote MCP is new code only.
- **Where the code goes:** `remote/`, a new pnpm and wrangler project next to `server/`. It has its own
  `wrangler.jsonc` with `"name": "tasks-mcp"`, its own `package.json`, tests and README. Wasm and Swift aren't used.
- **How there are two Workers:** each wrangler project deploys as its own Worker on the same account. `tasks-mcp`
  reaches the main Worker through a **service binding** (`services: [{ binding: "SYNC", service: "<main worker
  name>" }]`). It calls the unchanged `POST /v1/sync` over that binding, with the sync token as a `tasks-mcp`
  secret. No public hop is needed, and the main Worker doesn't know or care.
- **The port:** port the reducer, projection, ordering and fractional index, CalendarDate, Today and DatePhrase to
  TypeScript under `remote/src/core/`. Also port the CLI's command layer (Intents, Commands, Refs) as far as code
  mode needs it.
- **The contract:** the CLI's `tasks.d.ts` stays the API contract. Copy it into `remote/`, with a test that fails if
  the copy drifts from the CLI's generated file.
- **Parity:** generate golden fixtures from Swift **without changing the Swift package**:
  - use a small separate Swift package in `remote/parity/` that depends on `../../app/TasksCore` by path;
  - or drive the installed-style `tasks` CLI against a scratch data folder.

  The TypeScript tests must match those fixtures and the existing `fixtures/`.

**Next:** write `docs/REMOTE-MCP-PLAN.md` (keep it short), then build phase by phase, all local under `wrangler dev`.
Run a local copy of the main server from `server/` with a dummy token for the service binding. The phases are:
1. core port and parity;
2. the Replica DO and sync;
3. code mode on Worker Loader;
4. OAuth and the passkey.

Stop after the plan and after each phase with a short report. The Cloudflare rules above still hold: ask before
creating or deploying anything.
