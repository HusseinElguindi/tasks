// Code mode on Worker Loader: the sandbox a tasks_run script runs in, matching the CLI's (TasksCLI/Run.swift). The
// CLI runs the script in a Deno child with no permissions; here it is a fresh isolate per run with no network
// (`globalOutbound: null`) and an empty env. Its one capability is the `Host` below, passed as an RPC argument:
// every `tasks.*` call lands on it, in the Replica DO, and is answered from this run's fork.
//
// TypeScript is stripped by sucrase. The script is wrapped exactly as the CLI wraps it, and error positions go back
// through sucrase's source map to the TypeScript, as Deno reports them, so `line` and `column` match the CLI's.
//
// Limits: 10 s, as the CLI. A host timer stops a script that waits; every call after the deadline fails; and
// `limits.cpuMs` stops a busy loop, in production only. Locally a busy loop (`while (true) {}`) blocks the DO until
// it ends: workerd doesn't enforce CPU limits, and the spin starves the timer (docs/REMOTE-MCP-PLAN.md).

import { RpcTarget } from "cloudflare:workers";
import { transform } from "sucrase";
import type { CallResult } from "./cli/commands.ts";
import type { Json } from "./cli/render.ts";
import { wrapScript, type Sandbox, type SandboxOutcome } from "./cli/run.ts";

/** The CLI's TASKS_RUN_TIMEOUT default. */
export const TIMEOUT_MS = 10_000;
const COMPATIBILITY_DATE = "2026-08-15";

const timeoutError = () => ({ type: "Limit", message: `The script ran longer than ${TIMEOUT_MS / 1000} s, so it was stopped.` });

/**
 * The bridge, the isolate's main module: the CLI's bridge.js with stdio replaced by RPC to `host`. `tasks` and
 * `console` behave the same: calls are awaited JSON round trips, an error keeps its type and the call site's stack,
 * console lines are joined the same way, and the result goes through JSON.
 */
export const BRIDGE = String.raw`
import { WorkerEntrypoint } from "cloudflare:workers";
export default class Bridge extends WorkerEntrypoint {
  async run(host) {
    const sent = [];
    const show = (v) => (typeof v === "string" ? v : (() => { try { return JSON.stringify(v); } catch { return String(v); } })());
    for (const k of ["log", "info", "warn", "error", "debug"]) {
      console[k] = (...a) => { sent.push(host.log(a.map(show).join(" ")).catch(() => {})); };
    }
    // The call site's stack, taken now: an error that comes back later only has the bridge's frames.
    const call = (method, args) => {
      const site = new Error().stack;
      return host.call(method, JSON.parse(JSON.stringify(args.map((a) => (a === undefined ? null : a))))).then((r) => {
        if (r.error) {
          const e = new Error(r.error.message);
          e.name = r.error.type;
          Object.assign(e, r.error, { site });
          throw e;
        }
        return r.result;
      });
    };
    globalThis.tasks = new Proxy({}, {
      get: (_, name) => (typeof name !== "string" || name === "then" ? undefined : (...args) => call(name, args)),
    });
    const where = (e) => {
      const m = /script\.js:(\d+):(\d+)/.exec(String(e && e.site) + " " + String(e && e.stack) + " " + String(e && e.message));
      return m ? { at: [Number(m[1]), Number(m[2])] } : {};
    };
    let out;
    try {
      const mod = await import("./script.js");
      const result = await mod.default();
      out = { ok: true, result: result === undefined ? null : JSON.parse(JSON.stringify(result) ?? "null") };
    } catch (e) {
      const known = e && typeof e === "object" && "type" in e && "message" in e;
      out = { ok: false, ...where(e), error: known
        ? { type: e.type, message: e.message, field: e.field ?? null, candidates: e.candidates ?? [] }
        : { type: /^SyntaxError:|could not be parsed/.test(String(e && e.message)) ? "SyntaxError" : (e && e.name) || "Error",
            message: String((e && e.message) ?? e).replace(/^SyntaxError: /, "") } };
    }
    await Promise.all(sent);
    return out;
  }
}
`;

/** What the script reaches: its `tasks` calls and console lines, for one run. Closed once the run is over. */
export class Host extends RpcTarget {
  readonly lines: string[] = [];
  closed = false;

  constructor(private readonly answer: (method: string, args: Json[]) => Promise<CallResult>, readonly deadline: number) {
    super();
  }

  log(line: string): void {
    if (!this.closed) this.lines.push(String(line));
  }

  async call(method: string, args: Json[]): Promise<CallResult> {
    if (this.closed || Date.now() > this.deadline) return { error: timeoutError() };
    return this.answer(String(method), Array.isArray(args) ? args : []);
  }
}

// MARK: Source positions

/** One generated line's segments: [generated column, original line, original column], all 0-based. */
type Line = [number, number, number][];

const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/** Decodes a source map's `mappings` (one source, no names). */
export function decodeMappings(mappings: string): Line[] {
  const lines: Line[] = [];
  let srcLine = 0;
  let srcCol = 0;
  for (const text of mappings.split(";")) {
    const line: Line = [];
    let genCol = 0;
    for (const seg of text.split(",")) {
      if (!seg) continue;
      const v: number[] = [];
      let value = 0;
      let shift = 0;
      for (const ch of seg) {
        const d = B64.indexOf(ch);
        value += (d & 31) << shift;
        if (d & 32) shift += 5;
        else {
          v.push(value & 1 ? -(value >>> 1) : value >>> 1);
          value = 0;
          shift = 0;
        }
      }
      genCol += v[0];
      if (v.length >= 4) {
        srcLine += v[2];
        srcCol += v[3];
        line.push([genCol, srcLine, srcCol]);
      }
    }
    lines.push(line);
  }
  return lines;
}

/** A 1-based position in the generated JS → the same position in the TypeScript it came from. */
export function originalPosition(map: Line[], line: number, column: number): { line: number; column: number } {
  const segs = map[line - 1] ?? [];
  let best: [number, number, number] | undefined;
  for (const s of segs) if (s[0] <= column - 1) best = s;
  if (!best) return { line, column };
  return { line: best[1] + 1, column: best[2] + 1 + (column - 1 - best[0]) };
}

// MARK: The sandbox

function compile(source: string): { js: string; map: Line[] } {
  const r = transform(wrapScript(source), {
    transforms: ["typescript"],
    disableESTransforms: true,
    filePath: "script.ts",
    sourceMapOptions: { compiledFilename: "script.js" },
  });
  return { js: r.code, map: decodeMappings(r.sourceMap!.mappings) };
}

/** Why the isolate itself failed (not the script's own error). */
function hostFailure(e: unknown): Json {
  const message = e instanceof Error ? e.message : String(e);
  if (/cpu|time limit|exceeded.*time/i.test(message)) return timeoutError();
  if (/memory/i.test(message)) return { type: "Limit", message: "The script stopped: it ran out of memory (128 MB)." };
  return { type: "Limit", message: `The script stopped: ${message}` };
}

interface BridgeOutcome {
  ok: boolean;
  result?: Json;
  error?: { [k: string]: Json };
  at?: [number, number];
}

export function loaderSandbox(loader: WorkerLoader, timeoutMs = TIMEOUT_MS): Sandbox {
  return async (source, answer) => {
    let compiled: { js: string; map: Line[] };
    try {
      compiled = compile(source);
    } catch (e) {
      return { ok: false, error: { type: "SyntaxError", message: e instanceof Error ? e.message : String(e) }, logs: [] };
    }
    const host = new Host(answer, Date.now() + timeoutMs);
    const timedOut = (): SandboxOutcome => ({ ok: false, hostError: true, error: timeoutError(), logs: [...host.lines] });
    let timer: ReturnType<typeof setTimeout> | undefined;
    const timeout = new Promise<"timeout">((resolve) => {
      timer = setTimeout(() => resolve("timeout"), timeoutMs);
    });
    try {
      const worker = loader.load({
        compatibilityDate: COMPATIBILITY_DATE,
        mainModule: "bridge.js",
        modules: { "bridge.js": BRIDGE, "script.js": compiled.js },
        env: {},
        globalOutbound: null,
        limits: { cpuMs: timeoutMs },
      });
      const entry = worker.getEntrypoint() as unknown as { run(host: Host): Promise<BridgeOutcome> };
      const ran = entry.run(host).then((o) => ({ o }), (e: unknown) => ({ e }));
      const first = await Promise.race([ran, timeout]);
      // A spin can starve the timer; past the deadline it's a timeout whatever the script did.
      if (first === "timeout" || Date.now() > host.deadline) return timedOut();
      if ("e" in first) {
        const msg = first.e instanceof Error ? first.e.message : String(first.e);
        if (/SyntaxError/.test(msg)) return { ok: false, error: { type: "SyntaxError", message: msg.replace(/^.*?SyntaxError: /, "") }, logs: [...host.lines] };
        return { ok: false, hostError: true, error: hostFailure(first.e), logs: [...host.lines] };
      }
      const o = first.o;
      if (o.ok) return { ok: true, result: o.result ?? null, logs: [...host.lines] };
      let error = o.error ?? null;
      if (error && o.at) {
        const p = originalPosition(compiled.map, o.at[0], o.at[1]);
        error = { ...error, line: p.line - 1, column: p.column };
      }
      return { ok: false, error, logs: [...host.lines] };
    } finally {
      clearTimeout(timer);
      host.closed = true;
    }
  };
}
