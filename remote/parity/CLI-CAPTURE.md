# CLI capture: golden code-mode behaviour

`capture-cli.mjs` runs the stock `tasks` CLI against a local server and writes
`remote/test/golden/cli-scenarios.json`. The TypeScript port replays each case's starting log and script, and its
result and pushed ops must match. Ids and timestamps get normalised.

## Run

```sh
cd remote/parity
node capture-cli.mjs                     # Node 24, no dependencies; about 30 s
node capture-cli.mjs --scratch DIR --out FILE --date-order md|dm --no-build --anytime
```

It needs `mise` (for swift 6.4.2 and deno), and `server/node_modules` (`pnpm install` in `server/`). It refuses to start
within 10 minutes after or 25 minutes before local midnight, because every case has to fall on the same day. `--anytime`
overrides that. If the day changes during a run, nothing is written. It's safe to run again: each run starts from an
empty server and empty replicas.

What it does:

1. `mise x swift -- swift build --product tasks` in `app/TasksCore`. This is a debug build, so it only talks to
   localhost, and the script checks that it does.
2. `npx wrangler dev --ip 127.0.0.1 --port <free> --var API_TOKEN:dummy-local-token --persist-to <scratch>/state` in
   `server/`, with `WRANGLER_SEND_METRICS=false`. It waits for `POST /v1/sync` to answer, and kills the process group
   at the end.
3. Seeds the state with plain CLI commands as actor `cli`: 9 lists (3 deleted, including a deleted "Work" next to a
   live one, and "Old Projects" with two tasks deleted before it), headings with sections, When and Deadline dates
   around today, tasks done today, deleted tasks,
   Markdown notes, and two ids that share the prefix `abcd`. Two "completed earlier" updates are pushed straight to
   the server, with no actor or batch, the way the Mac app sends them, because the CLI can only complete "now".
4. Runs each case as `tasks run --json [--dry-run] <file>` with actor `agent:parity`. That prints the JSON the MCP
   tool returns: the script checks `tasks mcp` against it for one read and for one dry-run error. After each case it
   pulls the server log from its cursor and checks the hash chain.

## The file

`{generatedAt, timeZone, dateOrder, actor, cli, entities, typesMatchDts, mcpCheck, warnings, seed, log, cases}`

- `log`: every entry line exactly as the server sent it (`{"seq","received","hash","op"}`). The hash check proves the
  op text is byte-identical.
- `cases[i]`: `{name, script, dryRun, actor, [dateOrder], [prep], from, to, nowBefore, nowAfter, today, exitCode,
  output, [outputText], [stderr]}`.
  - A case starts from `log[0..from)`.
  - Its pushed ops are `log[from..to)`.
  - `prep` holds plain CLI commands run just before the case, with their own `from`/`to`. One is the conflicting
    rename by actor `cli`, from a second replica.
  - `outputText` is the raw stdout, kept only where `JSON.stringify(output)` would differ from it (Swift writes
    `1e-07`).
- `entities`: names to ids for the seeded lists, tasks and headings.
- `warnings`: cases whose outcome wasn't what the scenario intended. It should be empty.

Expected differences between two runs: ids, refs, times, and one sidebar order. "Old Projects" and "Reading" end up
with the same order key, and the tie is broken by id.

## What it never touches

- Every CLI call gets an explicit environment and nothing else:
  - `TASKS_URL` (the local server);
  - `TASKS_TOKEN=dummy-local-token`;
  - `TASKS_DATA_DIR` and `HOME`/`TMPDIR` under the scratch dir;
  - `TASKS_ENV_FILE` (a path that doesn't exist; checked before every call);
  - `TASKS_ACTOR`, `TASKS_DENO` and `TASKS_DATE_ORDER`.
- So the CLI never reads `~/.tasks-sync.env`, never reads the Keychain (stdin isn't a TTY, and a token is set), and
  never writes the real replica in `~/Library/Application Support/Tasks CLI`.
- No Cloudflare account: `wrangler dev` runs locally, and `CLOUDFLARE_*`/`CF_*` variables are stripped from its
  environment. There are no deploys.
- `app/` and `server/` aren't edited. The build writes the gitignored `app/TasksCore/.build`, and wrangler writes the
  gitignored `server/.wrangler`.
- The Tasks app and its data aren't touched. A debug CLI's sync nudge only reaches debug apps on the same local server.
- Writes go only to the scratch dir (default `$TMPDIR/tasks-parity-cli`, or `PARITY_SCRATCH`) and to `--out`.
