# Tasks for macOS

The SwiftUI client from `docs/SPEC.md` (§8–§9) in the A1 · Split design (`design/DIRECTIONS.md`).

| Path | What |
|------|------|
| `TasksCore/` | Swift package: ops and the reducer, fractional index ordering, the Today predicate, the projection (pending overlay, maintained indexes, per-entity `@Observable` models), persistence (`log.jsonl`, `pending.jsonl`, `snapshot.json`, 409 recovery) and the sync client. No UI. |
| `Tasks/` | The macOS 14+ app: views only, rebuilt for v2 from `design/prototype-v2/` (`design/INTERACTIONS-v2.md`). `Theme/` has the prototype's tokens (`TK`) and the AppKit drawing pieces; `Window/` the window state, every action, the menus and the panes' chrome; `TaskList/` and `Sidebar/` are AppKit lists; `Detail/` and `Overlay/` (date popover, notice, tooltip, the drag copy) are SwiftUI with AppKit fields. `Pane/` is the v1 theme, still used by Settings. |
| `project.yml` | XcodeGen spec for `Tasks.xcodeproj` (generated, not checked in). |
| `TasksCore/Sources/TasksCLI/` | `tasks`, the agent CLI (`docs/SDK-PLAN.md`): its own replica of the log on `TasksCore`. See below. |
| `Scripts/e2e.sh` | The end-to-end check against a local `wrangler dev`. |
| `Scripts/e2e-cli.sh` | The same for the CLI alongside a scratch Debug app. |
| `Scripts/install-cli.sh` | Builds `tasks` in release, signs it, and copies it to `~/.local/bin` (`--prefix` to change). |
| `Scripts/make-signing-identity.sh` | Makes the local signing identity once per Mac (see Signing). |
| `Signing.xcconfig` | The signing identity: ad hoc, or the local one once the script has run. |

## Build and run

```sh
mise use -g xcodegen          # once
cd app
xcodegen generate             # writes Tasks.xcodeproj
open Tasks.xcodeproj          # ⌘R; or:
xcodebuild -project Tasks.xcodeproj -scheme Tasks -derivedDataPath .build/DerivedData build
open .build/DerivedData/Build/Products/Debug/Tasks.app
```

Why XcodeGen: the project is ~60 lines of YAML that review and merge like code, with nothing hand-edited in a
`.pbxproj`. The app's sources are a synchronized folder, so adding a file never needs a regeneration; only target
settings do. The app is not sandboxed and has no Apple Developer account (spec §7).

### Signing (keeps Keychain access across builds)

Ad-hoc builds get a new code signature every time, and the Keychain ties "Always Allow" on the sync token to that
signature, so every new build asked again. Builds signed with a stable local identity keep the same designated
requirement, so the token's "Always Allow" sticks. Once per Mac:

```sh
Scripts/make-signing-identity.sh      # makes "Tasks Local Signing" in the login keychain; safe to run again
```

- **What the script makes:** a self-signed code-signing certificate (20 years) and its key in the login keychain.
  - It generates the key in a temporary folder and deletes that copy after importing. The key isn't stored or
    exported anywhere else.
  - It lets `/usr/bin/codesign` use the key without asking.
  - It writes `Signing.local.xcconfig` (not checked in), which `Signing.xcconfig` includes. Without that file, builds
    are ad hoc as before.
  - It needs no password.
- **Trust:** the certificate shows as "not trusted" (`CSSMERR_TP_NOT_TRUSTED`). That doesn't matter: codesign signs
  with it, and the requirement is pinned to the certificate itself. `Scripts/make-signing-identity.sh --trust` marks
  it trusted for code signing. That step is optional, and macOS asks for your password.
- **Check:** `codesign -dr - .build/DerivedData/Build/Products/Release/Tasks.app` should print
  `identifier "com.elguindi.Tasks" and certificate leaf = H"…"`, the same for every build. An ad-hoc build prints a
  `cdhash` instead.
- **After switching:** the first build signed this way asks for the token once more. "Always Allow" then holds for
  later builds.
- **Removing it:** delete the "Tasks Local Signing" certificate and key in Keychain Access, then
  `Signing.local.xcconfig`.
- **Trade-off:** anything running as you can use `codesign` with this identity. So, like the app, it could read the
  sync token without a prompt.

Sync: Settings (⌘,) → Server URL (the Worker's base URL) and Token. The token goes to the login Keychain. Until
both are set the sidebar footer says "Sync off".

Data lives in `~/Library/Application Support/Tasks/`. For testing, `-dataDirectory <path>` points an instance at
another folder, and `-serverURL` / `-syncToken` / `-taskEditing detail|inline` (Settings ▸ Edit tasks) override the
settings without saving them.

## Tests

```sh
cd app/TasksCore
swift test                                                            # everything, ~5 s
swift test -c release -Xswiftc -enable-testing --filter BenchmarkTests  # §9 budgets, enforced in release
```

- Reducer conflict cases, op/inverse round trips, fractional index (against vectors from the npm package), ties,
  rebalance, the drag-to-anchor mapping, the Today predicate around midnight and DST, seeding.
- The randomized rebase test: 2–3 simulated Macs, partial pushes, small pages, ops made while a request is in
  flight, midnight, and (in a second variant) the server restored or wiped at random points; after every sync the
  incremental projection must equal a from-scratch rebuild (visible state, every bucket, placements, models).
- Persistence: snapshot + tail = full replay, bad snapshots fall back, torn tails, write order, a crash after each
  409 recovery step.
- Sync: the shared `fixtures/sync` pairs replayed byte for byte, every row of the error table, backoff, 413,
  size-capped pages, two-Mac convergence, recovery from a wiped, a restored and a healthy server.
- `LiveServerTests` runs against a local `wrangler dev` (skipped unless `TASKS_LIVE_*` are set; refuses non-local
  URLs). See the file for the two phases.

Benchmarks on an M5 Pro (release, 10k tasks / 100k ops): launch from snapshot 22 ms (budget 100), snapshot decode
18 ms (60), local edit 3 µs (1 ms), 1,000 interleaved remote ops 0.9 ms (10), reorder in a 2,000-task list
0.2 ms (1), midnight rebuild 0.5 ms (5), full replay of 100k ops 0.32 s.

## The agent CLI

`tasks` is another replica, like a second Mac: its own files in `~/Library/Application Support/Tasks CLI/<host>/`
(never the app's), the app's `Store` on them, and the same sync. `tasks help` lists every command; `docs/AGENTS.md`
is the guide for agents.

```sh
swift build --package-path TasksCore --product tasks       # debug build: only talks to localhost
Scripts/install-cli.sh                                     # release build on PATH
```

It reads the server from `TASKS_URL` (or a `TASKS_URL=` line in `~/.tasks-sync.env`) and the token from
`TASKS_TOKEN`, then `API_TOKEN` in that file, then the app's Keychain item (only at a terminal). `swift test` runs
its tests (`TasksCLITests`, against an in-memory server); `Scripts/e2e-cli.sh` runs it with a Debug app against
`wrangler dev`.

## Debug-only launch arguments

Compiled out of Release builds.

| Argument | Effect |
|----------|--------|
| `-demoData YES` | Fills an empty data folder with the prototype's seed (`design/prototype-v2/Main.dc.html` dc:457–548), for side-by-side checks. `-demoBulk N` adds a list "Big" with N tasks. |
| `-debugRoute today\|upcoming\|undated\|completed\|trash\|list:<name>`, `-debugSelect <title>`, `-debugDetail YES`, `-debugAdd YES`, `-debugThenRoute …`, `-debugSidebarHidden YES` | Sets up the window. |
| `-snapshotTo <png>` (`-snapshotQuit YES`, `-snapshotDelay`, `-debugWindowSize WxH`) | Renders the window to a PNG. |
| `-snapshotSettings <png>` | Renders Settings (⌘,) to a PNG without opening its window. |
| `-debugScript "<steps>"` | Posts clicks and keys inside the app, then quits (see `Support/DebugScript.swift`). Its `glasssnap:<png>` step renders how much of the Glass ground each pixel covers (alpha), plus a `.txt` of the window and its materials; `act:<action>` runs a window action by name and `act:rows`, `act:menu`, `act:trace` log the four views' rows, menus and motion (`Support/DebugViews.swift`). |
| `-debugRenderTimes <file>` | Logs each task-list render's duration and phases. |
| `-debugMeasureSwitch <file>` | The list-switch benchmark (`Scripts/switch-bench.sh`). |
| `-debugActions '<json>'`, `-debugDumpTo <json>` | Performs actions through the Store, syncs, dumps state, quits (used by `Scripts/e2e.sh`). |
