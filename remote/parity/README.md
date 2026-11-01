# parity: golden JSON from TasksCore

A small Swift package that depends on `../../app/TasksCore` by path and writes the golden files the TypeScript
port (`remote/src/core/`) is tested against. It only calls TasksCore's public API and never changes anything
under `app/` or `server/`.

```sh
cd remote/parity
mise x swift -- swift run golden            # writes ../test/golden/*.json
mise x swift -- swift run golden <outdir>   # or somewhere else
```

The output is deterministic: a seeded SplitMix64, fixed instants and sorted keys, so two runs give the same bytes.
Run it again after a TasksCore change and diff `remote/test/golden/`.

| File | What |
|------|------|
| `core-fold.json` | Raw log lines and pending op texts, folded: confirmed state, visible state and every view of a `Projection` (fixtures/sync logs, handmade cases, 72 seeded random logs) |
| `inverse.json` | `Inverse.of` for ops of those logs, against the entity just before each op |
| `op-json.json` | Op text in, canonical `jsonData` text out (`null` if it doesn't decode) |
| `day.json` | `Day(containing:calendar:)` around midnights and DST changes |
| `calendar-date.json` | `CalendarDate` parsing, `adding(days:)`, `days(until:)`, `weekday`, `dayNumber` |
| `date-phrase.json` | `DatePhrase.match` over a phrase × reference day × numeric order grid |
| `ordering.json` | `Ordering.place` |

The fractional-index vectors are not copied: read `app/TasksCore/Tests/TasksCoreTests/Resources/fractional-index-vectors.json`
by path. `capture-cli.mjs` (the command-layer goldens) lives here too but is separate from this package.
