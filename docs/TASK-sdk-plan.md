# Task: plan a code SDK for Tasks, so agents can use it

The user's words: "lets start a new xhigh session to plan a code sdk for this. the end goal is to have agents using this. I want to explore code mode and cli based interfaces. all the ui operations should be supported."

**This is planning only.** Write the plan. Small throwaway spikes are fine if they settle a question, but build nothing for real yet.

## Context

- **Product and model:** read `docs/BRIEF.md` and `docs/SPEC.md`, all of it.
  - The model and ops are in §1–3.
  - Sync is in §5: `POST /v1/sync {from, base, ops}`, an append-only, hash-chained log.
  - The Git analogy and undo as inverse ops are in §6.
  - The server is in §7.
- **Server code:** `server/`, in particular `src/validate.ts` for the op schema.
- **Fixtures:** `fixtures/sync/`.
- **Swift client** (the reducer, projection and fractional ordering): `app/TasksCore/`.
- **What the UI can do** is in `design/INTERACTIONS-v2.md` and `docs/TASK-v2-feedback.md`. "All the UI operations" means everything a person can do in the app:
  - create, edit, complete and uncomplete tasks;
  - delete with undo;
  - move tasks between lists and reorder them, including relative placement ("after X", "top");
  - set and clear when and deadline dates, including typed phrases like "fri" and "3d";
  - Markdown notes;
  - create, rename, reorder, archive and unarchive lists;
  - Today and the list views, the completed tasks, and the archive;
  - multi-select operations.
- **The live server is https://tasks.elguindi.workers.dev,** with a single fixed token in `~/.tasks-sync.env`.
  - Never print the token or put it in the repo.
  - Don't run against the live server. Use `wrangler dev` (the `server/` README) for any spike.

## Explore

1. **SDK shape.**
   - **Language or languages:** TypeScript is the natural fit for agents and for Cloudflare. Weigh it against reusing the Swift `TasksCore`, or a shared spec with conformance fixtures.
   - **What the SDK is:** a client of the log. It pulls the log, replays it with the same reducer, gives a typed read model (Today, lists, tasks), and turns intents into ops it pushes.
   - **Staying identical to the app:** how the SDK's reducer, ordering and date logic stay identical to Swift's (shared fixtures, a conformance suite).
   - **Offline and concurrency:** pending ops, the 409 recovery, and running alongside the Mac app.
2. **Code mode.** Agents write code against a typed API instead of making many tool calls. Cloudflare has published on this; look it up.
   - Where would the code run? Options: a Worker isolate or Dynamic Worker Loader on our own Worker; Deno; a local sandbox.
   - What the API surface and its types look like for the model.
   - How results and errors come back.
   - Safety: limits, a dry-run or preview, and every agent write being undoable.
3. **The CLI.** A `tasks` command for agents and humans:
   - commands that cover every UI operation;
   - `--json` output;
   - stable ids and short refs;
   - piping, and idempotency.
   - Compare it with code mode, and with an MCP server as a third option, for agent use.
4. **Agent concerns.**
   - **Attribution:** which ops came from an agent, and should the op carry an `actor` or `source` field? A schema change is allowed, but it must stay loose and backward compatible.
   - **Review:** a log or "what changed" view, and an undo for an agent's batch.
   - **Tokens:** whether agents get their own scoped or revocable tokens or share the single one.
   - **Atomic batches:** "move these 5 tasks" as one undoable unit.
5. **Server changes,** if any: new endpoints such as a read model, a code-mode runner or agent tokens, kept minimal and in the spirit of the spec.

## Output

`docs/SDK-PLAN.md` covers:
- the recommended architecture;
- the API surface: every UI operation mapped to an SDK call, a CLI command and a code-mode example;
- what each interface is good at;
- phased build order;
- open decisions for the user, each with a recommendation.

Keep it as simple as the rest of the project.

Commit per path, never `git add -A`, never push. End commit messages with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Don't touch `app/` or `server/` code. You may use subagents, for example for research.

When the plan is ready, report a short summary and the open decisions to the coordinator.
