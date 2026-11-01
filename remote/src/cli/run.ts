// A whole code-mode run: the script's outcome shaped into the result the CLI's `tasks run --json` and `tasks mcp`
// return (TasksCLI/Run.swift `execute`). The sandbox that runs the script is passed in: Worker Loader in the Worker,
// a plain function in the tests.

import { answer, type CallResult } from "./commands.ts";
import type { Context } from "./context.ts";
import { utf8Compare } from "../core/ordering.ts";
import type { Json } from "./render.ts";

export const MAX_RESULT_BYTES = 100_000;
export const MAX_LOG_LINES = 200;
export const MAX_OPS = 500;

export interface SandboxOutcome {
  ok: boolean;
  /** The error is the host's own (a timeout, a crash), not the script's: it keeps its key order. */
  hostError?: boolean;
  result?: Json;
  error?: Json;
  logs: string[];
}

/** Runs `source` (the script as written) with `call` as the only way out, and reports how it ended. */
export type Sandbox = (source: string, call: (method: string, args: Json[]) => Promise<CallResult>) => Promise<SandboxOutcome>;

/** How the CLI's bridge wraps a script: a module whose default export is the script's body. */
export const wrapScript = (source: string) => "export default async () => {\n" + source + "\n};\n";

/**
 * The script's result and error reach the CLI's host through Swift's JSON parser, which reads objects with their
 * keys sorted, so they're written back sorted. The `change` the host builds keeps the tasks.d.ts order.
 */
export function sortedKeys(v: Json): Json {
  if (Array.isArray(v)) return v.map(sortedKeys);
  if (v && typeof v === "object") {
    return Object.fromEntries(Object.keys(v).sort(utf8Compare).map((k) => [k, sortedKeys(v[k])]));
  }
  return v;
}

export async function execute(source: string, c: Context, sandbox: Sandbox, o: {
  dryRun: boolean;
  /** Writes the run's ops as one batch and syncs; resolves to whether they're in the log. */
  commit: (ops: Context["ops"], batch: string) => Promise<boolean>;
}): Promise<{ [k: string]: Json }> {
  const outcome = await sandbox(source, async (method, args) => answer(c, method, args));
  let logs = outcome.logs;
  if (logs.length > MAX_LOG_LINES) logs = [...logs.slice(0, MAX_LOG_LINES), `… ${outcome.logs.length - MAX_LOG_LINES} more lines dropped`];
  const failure = (error: Json) => ({ ok: false, error, logs, change: null });
  if (!outcome.ok) return failure(outcome.hostError ? (outcome.error ?? null) : sortedKeys(outcome.error ?? null));
  const result = sortedKeys(outcome.result ?? null);
  const size = new TextEncoder().encode(JSON.stringify(result)).length;
  if (size > MAX_RESULT_BYTES) {
    return failure({ type: "Limit", message: `The result is ${Math.floor(size / 1000)} KB; the limit is 100 KB. Return less (ids, counts).` });
  }
  if (c.ops.length > MAX_OPS) {
    return failure({ type: "Limit", message: `The script made ${c.ops.length} ops; one change is at most 500 (pass --large to split it).` });
  }
  const change = c.ops.length === 0 ? null : c.changeJSON();
  if (o.dryRun) return { ok: true, result, logs, change, dryRun: true, diff: c.diff() };
  const synced = c.ops.length === 0 ? true : await o.commit(c.ops, c.batch);
  return { ok: true, result, logs, change, synced };
}

/** How the bridge prints a console argument. */
export const show = (v: unknown): string => {
  if (typeof v === "string") return v;
  try {
    return JSON.stringify(v);
  } catch {
    return String(v);
  }
};

/** Arguments as the bridge sends them: undefined becomes null, then a JSON round trip. */
export const wireArgs = (args: unknown[]): Json[] => JSON.parse(JSON.stringify(args.map((a) => (a === undefined ? null : a))));

/** A script's error as the bridge reports it: a `tasks` error keeps its type; anything else is its name. */
export function scriptError(e: unknown): { [k: string]: Json } {
  const known = e !== null && typeof e === "object" && "type" in e && "message" in e;
  if (known) {
    const x = e as { type: string; message: string; field?: string | null; candidates?: string[] };
    return { type: x.type, message: x.message, field: x.field ?? null, candidates: x.candidates ?? [] };
  }
  const err = e as { message?: unknown; name?: unknown } | null | undefined;
  const message = String((err && err.message) ?? e);
  const type = /^SyntaxError:|could not be parsed/.test(message) || (err && err.name === "SyntaxError") ? "SyntaxError" : String((err && err.name) || "Error");
  return { type, message: message.replace(/^SyntaxError: /, "") };
}
