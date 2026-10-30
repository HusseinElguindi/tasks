# Build brief: server (Cloudflare Worker + Durable Object)

Read docs/BRIEF.md and docs/SPEC.md (the contract; §5 sync, §6 hash chain, §7 Cloudflare). Build the server in `server/`.

- TypeScript Worker + one SQLite-backed Durable Object, exactly as §7 describes. Keep it small; no frameworks.
- Toolchain comes from mise (see ~/.claude/CLAUDE.md): node/pnpm already installed; add wrangler as a local dev dependency.
- Tests: use `@cloudflare/vitest-pool-workers` (or equivalent) to run against the real workerd runtime locally. Cover every rule in §5–§7:
  validation (each 400 case), 401, 409 on from/base mismatch, idempotent retries (duplicate op ids), contiguous appends,
  hash chain values, pagination (`more`), and ordering of the response.
- Write the canonical request/response pairs from the spec's examples to `fixtures/sync/` as JSON files, and test the server against them.
  The macOS agent decodes the same fixtures, so they are the shared contract. If the spec is ambiguous, ask (see below), don't guess.
- `wrangler dev` locally is fine. **Do NOT run anything that creates or changes Cloudflare resources** (deploy, secret put, login, etc.).
  When the server is ready to deploy, stop and write the exact commands needed in `server/DEPLOY.md`, then ask in this terminal.
- Performance matters to the user: keep the DO hot path lean (cached head/last hash, prepared statements, one transaction per request).

You may use subagents if useful (e.g. a reviewer for your tests vs. the spec). Commit as you go (see the coordinator message): stage only your own paths, never `git add -A`; do not push.
If you need a decision, ask it plainly in this terminal and stop; the coordinator will relay it to the user.
When done, summarize what you built, how to run the tests, and anything in the spec you think is wrong.

Follow the milestones in docs/SPEC.md §10 (server track S1–S4).
