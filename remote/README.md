# tasks-mcp

The remote MCP server: a second Worker, separate from `server/`, that is one more replica of the log, like the CLI.
The plan is in `docs/REMOTE-MCP-PLAN.md`.

So far (phase 1) this is the TypeScript port of what a replica needs, checked against the Swift:

- `src/core/`: TasksCore's ops and their canonical JSON, the wire format and error table, the reducer and inverse
  ops, ordering and fractional keys (the `fractional-indexing` package TasksCore's port came from), calendar dates,
  Today in an IANA zone, DatePhrase, and the projection's views.
- `src/cli/`: the CLI's code-mode layer: the command table, argument decoding, refs, intents on a fork, undo, the
  Change and diff text, and the run result.
- `tasks.d.ts`: the CLI's API contract, copied. A test fails if it drifts from the CLI's, or if the command table
  here stops generating it byte for byte.

```sh
pnpm install
pnpm test        # Node; the fixtures, the contract, and parity with the Swift
pnpm typecheck
pnpm parity      # regenerate test/golden (Swift goldens, then a CLI capture against a local server), gzipped
```

Parity comes from two generators that never change `app/` or `server/`:

- `parity/` (Swift, depends on `../../app/TasksCore` by path): folds, views, Day, dates, DatePhrase, ordering,
  op JSON, inverses. See `parity/README.md`.
- `parity/capture-cli.mjs`: 218 scenario scripts run through the stock `tasks run --json` against a local
  `wrangler dev` of `server/` with a dummy token, with their outputs and pushed ops. See `parity/CLI-CAPTURE.md`.

Config the Worker will read: `TIME_ZONE` (IANA, default `America/Toronto`) and `DATE_ORDER` (`md` or `dm`).
