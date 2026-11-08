# Sync server

The append-only op log behind `POST /v1/sync`: one Cloudflare Worker and one SQLite-backed Durable Object
(SPEC §5–§7). TypeScript, no framework, no runtime dependencies. `GET /v1/events` is a WebSocket that says
`{"head":N}` when the log grows, so clients sync at once instead of at their next poll (design/PUSH-SYNC.md).

| File | Role |
|------|------|
| `src/index.ts` | Worker: routing (404/405), bearer auth (401), body size (413), parsing and validation (400), the RPC to the DO (409), response encoding; for `/v1/events`, 405/426/401 and then the upgrade to the DO. |
| `src/validate.ts` | Request parsing and op validation. Pure. Serializes each op as the log stores and hashes it. |
| `src/log.ts` | `UserLog` DO: the `log` table, cached head and last hash, append with dedup and the hash chain in one transaction, page read; the hibernatable sockets and the head poke after an append. |
| `scripts/make-fixtures.mjs` | Writes `../fixtures/sync/` (the shared wire contract). |

## Commands

```sh
pnpm install
pnpm test          # vitest inside workerd (@cloudflare/vitest-plugin), ~2 s
pnpm typecheck
pnpm fixtures      # regenerate ../fixtures/sync after changing the contract
pnpm dev           # wrangler dev on http://localhost:8787, token from .dev.vars
```

`pnpm dev` needs a `.dev.vars` file (git-ignored) with `API_TOKEN=<anything>`. Local dev creates no Cloudflare
resources. Deploying does: see `DEPLOY.md`.

## Choices worth knowing

- **Synchronous hot path.** SHA-256 comes from `node:crypto` (`nodejs_compat`), which is synchronous, so
  `UserLog.sync()` never awaits and requests can't interleave inside it. Web Crypto's `digest()` is async and
  would open a window between reading `head` and appending.
- **The Worker does the per-op work.** Validation and `JSON.stringify` of each op happen in the Worker, which
  scales out. The DO, the serialization point, only hashes, inserts and reads.
- **No re-parsing on read.** The page body is built by concatenating stored op text, so a 1,000-entry pull
  never runs `JSON.parse`/`stringify` over the ops.
- **Head on startup** is `MAX(seq) + 1` through the primary key (O(log n)) rather than `COUNT(*)` (a scan);
  the two are equal because `seq` is dense.
- **Dedup** is `INSERT … ON CONFLICT (id) DO NOTHING`, one statement per op.
- **Pages stop at 1,000 entries or 4M UTF-16 units of op text**, whichever comes first, and always hold at least
  one entry. Without the second bound, 1,000 near-limit notes would exceed the 32 MiB RPC limit and that `from`
  would fail forever. Normal entries are ~250 characters, so in practice pages are exactly 1,000. Clients must
  advance by the entries they receive (`last seq + 1`), never by 1,000.
- **The poke socket hibernates.** `UserLog.fetch` accepts with `ctx.acceptWebSocket` (never `ws.accept()`), so
  the object still sleeps between requests, isn't billed for the time a socket is open, and the sockets stay
  connected. The runtime answers protocol pings without waking it. `sync()` sends `{"head":N}` to
  `ctx.getWebSockets()` after an append that moved head (a pull or a push of only duplicates sends nothing);
  `ws.send` is synchronous, so `sync()` still never awaits. Every writer (the apps, the CLI, the remote MCP
  through its service binding) goes through `sync()`, so every write pokes. A deploy disconnects every socket;
  clients reconnect with backoff and jitter.
