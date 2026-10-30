# Build brief: macOS app (SwiftUI)

Read docs/BRIEF.md, docs/SPEC.md (the contract, especially §2–§5, §8 client, §9 performance) and design/DIRECTIONS.md
(the chosen design is **A1 · Split**, Classic style, plus the two A3 pieces it lists). Open the A1 canvas link in
DIRECTIONS.md to see it. Use design/PaneTheme.swift as the theme; add the new Pane components/tokens DIRECTIONS.md lists, derived the same way.

Build in `app/`:
- Put the model, reducer, ordering (fractional index), queries/indexes, persistence (log.jsonl, pending.json, snapshot.json)
  and sync client in a Swift package (e.g. `TasksCore`) with `swift test` coverage for everything §8–§9 lists: reducer conflict cases,
  op/inverse round trips, ordering ties and rebalance, the Today predicate around midnight, the incremental-vs-full-replay randomized test,
  and the performance budget benchmarks (10k tasks / 100k ops).
- The macOS 14+ app target (SwiftUI, NavigationSplitView) depends on that package. Choose the simplest reproducible project setup
  (e.g. XcodeGen or a checked-in .xcodeproj) and say why. Toolchains come from mise (see ~/.claude/CLAUDE.md); install new tools with `mise use -g`, never brew.
- Decode the shared fixtures in `fixtures/sync/` (written by the server agent; they may appear while you work) in tests, so client and server agree on the wire format.
- Order of work: core package + tests first, then the app shell (sidebar, Today, list, detail split), then drag/reorder, quick add, archive, undo,
  then sync wired to a configurable server URL + token (Keychain). Until a server is deployed, test sync against `wrangler dev` in `server/` if it exists, or a stub.
- Performance is a top priority for the user: follow §9 (per-entity observation, maintained indexes, work off the main actor), and measure.

You may use subagents if useful (e.g. one on the core package while you do UI, or a reviewer). Don't commit; leave changes in the working tree.
Don't touch `server/` or Cloudflare. If you need a decision, ask it plainly in this terminal and stop; the coordinator will relay it to the user.
When done, summarize what you built, how to build/run/test it, and anything in the spec or design you think is wrong.

Follow the milestones in docs/SPEC.md §10 (macOS track C1–C5, then the end-to-end check).
