# Revise the SDK plan: Swift core, no remote

The user accepted every recommendation in `docs/SDK-PLAN.md` §12, with two changes:

1. **No remote, at all.** Drop phase 5, the Runner DO, the Worker Loader, `/mcp` on the Worker and agent tokens. Everything runs on this Mac.
2. **The core is Swift, not a TypeScript port.** The user asked: "if we already implemented the client in swift, why can't we make the core in swift?"
   - The coordinator's reasoning: without remote, TypeScript was only needed inside the code-mode sandbox. But the sandbox's `tasks.*` calls already go back to the host over stdio, so the host can be a Swift CLI built on `TasksCore`.
   - That leaves one reducer, so no port and no drift. Sync, the error table, 409 recovery, ordering and dates are reused as they are.

## Rewrite `docs/SDK-PLAN.md` for this

- **The CLI is a Swift executable target, `tasks`.**
  - It goes in the `app/TasksCore` package, or a sibling package that depends on it; pick the simpler one.
  - It is its own replica, with its own data directory, and never shares the Mac app's files.
  - Say what `TasksCore` needs factored for a CLI: `@MainActor`, the `@Observable` models, anything else app-only. Keep the split minimal, and keep the app's performance budgets intact.
- **Code mode:**
  - Deno is the sandbox only: no permissions, running a tiny JS bridge that sends each `tasks.*` call over stdio to the Swift host.
  - `tasks.d.ts` is generated from the command and intent table so it can't drift.
  - Keep `--dry-run`, one run as one batch, and the limits.
  - Keep the two-tool MCP server (stdio, local) and `docs/AGENTS.md`.
- **Drop** the TypeScript `sdk/` tree, `fixtures/core/`, the conformance suite and `tasks verify`. Keep anything still useful.
- **Keep all the accepted decisions:**
  - `actor` and `batch` on the envelope;
  - agent writes apply at once, with a summary and an undo;
  - undo skips keys changed since, with `--force`;
  - the shared token, read from the Keychain item or `~/.tasks-sync.env`, never printed;
  - the two-tool MCP;
  - typed dates read the way the date popover reads them, with the resolved date echoed.
- **Mention the Mac app issue you found** (changing the server URL replays every op into the new server) as a separate item. Don't fix it here.
- **Update the build order:**
  1. The server keys (deploy only with the user's approval).
  2. The Swift CLI: every UI operation, `--json`, refs, batches, undo, log and dry-run, tested against `wrangler dev` alongside a scratch Mac instance.
  3. Code mode: the bridge, `tasks.d.ts`, `tasks run`, MCP and `AGENTS.md`.

Commit per path with the co-author line, then report a short summary of what changed. Don't start building until the coordinator says so.
