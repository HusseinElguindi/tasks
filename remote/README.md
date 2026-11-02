# tasks-mcp

The remote MCP server: a second Worker, separate from `server/`, that is one more replica of the log, like the CLI.
The plan is in `docs/REMOTE-MCP-PLAN.md`.

It is: the TypeScript port of what a replica needs, checked against the Swift; the Replica Durable Object that syncs
it with the main Worker; `/mcp`, the local `tasks mcp`'s two tools with each script on Worker Loader; and OAuth in
front of it, where the owner approves each client with a passkey. Deploying is in `docs/REMOTE-MCP-PLAN.md`
("For later").

- `src/core/`: TasksCore's ops and their canonical JSON, the wire format and error table, the reducer and inverse
  ops, ordering and fractional keys (the `fractional-indexing` package TasksCore's port came from), calendar dates,
  Today in an IANA zone, DatePhrase, and the projection's views.
- `src/cli/`: the CLI's code-mode layer: the command table, argument decoding, refs, intents on a fork, undo, the
  Change and diff text, and the run result.
- `tasks.d.ts`: the CLI's API contract, copied. A test fails if it drifts from the CLI's, or if the command table
  here stops generating it byte for byte.
- `src/replica.ts`, `src/replica/`: the Replica DO. One instance for every client, in SQLite: the log (each op's
  text verbatim), pending, rejected, and a snapshot of the folded state (rewritten every 1,000 entries; a wake folds
  the log after it). `engine.ts` is `Store.runSync` and the CLI's `Session` ported: 1,000-entry pages, 500-op and
  900 KB chunks, `invalid_op` to rejected, 413 halves the chunk, 409 recovers (every known op pending, from 0), 401,
  404, 405 and `bad_request` stop. A run takes the lock, seeds the Inbox if it's missing, pulls, runs on a fork,
  commits with the client's actor and one batch, pushes, and reports `synced`. Transient failures get three
  retries of at most 2 s inside a run; then the run reports `synced: false`, the ops stay queued, and the alarm
  retries them (1 s doubling to 60 s).
- `src/codemode.ts`: code mode on Worker Loader. A fresh isolate per run, no network, empty env; the DO passes it a
  `Host` (an `RpcTarget`) that answers its `tasks.*` calls from the run's fork. TypeScript is stripped by sucrase and
  error positions mapped back through its source map. The CLI's limits: 10 s (a host timer, a deadline on every call,
  and `limits.cpuMs` in production; locally a busy loop isn't stopped, see the plan), 100 KB, 200 log lines, 500 ops.
- `src/mcp.ts`: MCP over Streamable HTTP (JSON replies, no SSE): `initialize`, `ping`, `tools/list`, `tools/call`
  with the same instructions, tool text and replies as MCP.swift (a test reads MCP.swift).
- `src/index.ts`, `src/auth.ts`, `src/pages.ts`: OAuth 2.1 (`@cloudflare/workers-oauth-provider`): `/register` (DCR)
  and Client ID Metadata Documents, `/authorize` (consent), `/token`, the discovery metadata, and `/mcp` as the
  protected route. `/setup` takes `SETUP_SECRET` once to make the owner's passkey (`@simplewebauthn/server`), then
  closes. Consent needs that passkey. Each client writes as `agent:<its domain or name>`, e.g. `agent:claude-ai`.

```sh
pnpm install
pnpm test           # both suites below
pnpm test:node      # the fixtures, the contract, and parity with the Swift
pnpm test:workers   # in workerd: the Replica DO and sync, the CLI scenarios on Worker Loader, /mcp, OAuth + passkey
pnpm typecheck
pnpm smoke          # server/ and tasks-mcp under two wrangler devs: passkey, OAuth, then MCP (dummy secrets)
pnpm parity         # regenerate test/golden (Swift goldens, then a CLI capture against a local server), gzipped
```

The Worker tests' `SYNC` binding is a function in Node (`test/workers/servers.ts`) that forwards to the unchanged
`server/` with a dummy token: wrangler's test harness on `server/wrangler.jsonc` (a fresh, empty log whenever a test
asks), or one real `wrangler dev` of `server/`. It can also answer with the server's own fixture responses
(`fixtures/sync`), to drive the 401, 404, 400, 409, 413 and `invalid_op` paths. Nothing touches Cloudflare.

`remote/.dev.vars` (gitignored) holds dummy `SYNC_TOKEN` and `SETUP_SECRET` values for local runs. In a browser,
open `http://localhost:8787/setup` (not 127.0.0.1: a passkey can't be made for an IP address).

Parity comes from two generators that never change `app/` or `server/`:

- `parity/` (Swift, depends on `../../app/TasksCore` by path): folds, views, Day, dates, DatePhrase, ordering,
  op JSON, inverses. See `parity/README.md`.
- `parity/capture-cli.mjs`: 240 scenario scripts run through the stock `tasks run --json` against a local
  `wrangler dev` of `server/` with a dummy token, with their outputs and pushed ops. See `parity/CLI-CAPTURE.md`.

Config (`wrangler.jsonc`): `TIME_ZONE` (IANA, default `America/Toronto`), `DATE_ORDER` (`md` or `dm`), the `SYNC`
service binding to the main Worker (`tasks`), and the `SYNC_TOKEN` secret (the main Worker's `API_TOKEN`).
