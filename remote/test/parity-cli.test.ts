// The command layer against the real CLI: remote/parity/capture-cli.mjs ran each scenario script with the stock
// `tasks run` against a local server and recorded its output and the ops it pushed. Here the same script runs on a
// replica rebuilt from the same log, and must give the same output and the same ops.
//
// Normalised before comparing: ids the run generated (random in the CLI, placeholders here, matched up by position),
// times from the run's clock (the CLI's wall clock, a fixed `nowBefore` here), and an error's line and column (Deno's
// stack against this sandbox's).

import { describe, expect, it } from "vitest";
import { Context } from "../src/cli/context.ts";
import type { Json } from "../src/cli/render.ts";
import { execute } from "../src/cli/run.ts";
import { dayContaining } from "../src/core/day.ts";
import { opJSON, type Op } from "../src/core/op.ts";
import { Projection } from "../src/core/projection.ts";
import { AppState } from "../src/core/state.ts";
import { decodeEntryLine } from "../src/core/wire.ts";
import { loadGolden } from "./golden.ts";
import { nodeSandbox } from "./sandbox.ts";

interface Case {
  name: string;
  script: string;
  dryRun: boolean;
  /** A case run with TASKS_DATE_ORDER set. */
  dateOrder?: string;
  actor: string;
  from: number;
  to: number;
  nowBefore: number;
  nowAfter: number;
  today: string;
  output: Json;
}

const golden = loadGolden<{ timeZone: string; dateOrder: string; log: string[]; cases: Case[] }>("cli-scenarios.json");

/** Placeholder ids with unique 6-character prefixes, so refs stay 6 characters as the CLI's random ones do. */
const placeholder = (n: number) => `f${n.toString(16).padStart(5, "0")}00-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const isPlaceholder = (s: string) => /^f[0-9a-f]{5}00-0000-4000-8000-[0-9a-f]{12}$/.test(s);

/** Replaces the run's clock values with a marker, in both outputs alike. */
function clockless(v: Json, lo: number, hi: number): Json {
  if (typeof v === "number") return v >= lo && v <= hi ? "<now>" : v;
  if (Array.isArray(v)) return v.map((x) => clockless(x, lo, hi));
  if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, clockless(x, lo, hi)]));
  return v;
}

/** Drops an error's position (Deno's stack vs this sandbox's). */
function positionless(v: Json): Json {
  if (Array.isArray(v)) return v.map(positionless);
  if (v && typeof v === "object") {
    const out: { [k: string]: Json } = {};
    for (const [k, x] of Object.entries(v)) if (k !== "line" && k !== "column") out[k] = positionless(x);
    return out;
  }
  return v;
}

/** Walks both trees together, mapping each placeholder id (and its ref) to the CLI's value in the same place. */
function mapIDs(ours: Json, theirs: Json, map: Map<string, string>, key = ""): void {
  if (typeof ours === "string" && isPlaceholder(ours) && typeof theirs === "string") {
    if (!map.has(ours)) map.set(ours, theirs);
    return;
  }
  if (typeof ours === "string" && key === "ref" && typeof theirs === "string") {
    for (const [p, cli] of map) if (p.startsWith(ours) && cli.startsWith(theirs)) map.set(ours, theirs);
    return;
  }
  if (Array.isArray(ours) && Array.isArray(theirs)) {
    ours.forEach((x, i) => mapIDs(x, theirs[i] ?? null, map, key));
    return;
  }
  if (ours && theirs && typeof ours === "object" && typeof theirs === "object" && !Array.isArray(ours) && !Array.isArray(theirs)) {
    for (const k of Object.keys(ours)) mapIDs(ours[k], theirs[k] ?? null, map, k);
  }
}

function substitute(v: Json, map: Map<string, string>): Json {
  if (typeof v === "string") {
    if (map.has(v)) return map.get(v)!;
    let s = v;
    for (const [a, b] of map) if (s.includes(a)) s = s.split(a).join(b);
    return s;
  }
  if (Array.isArray(v)) return v.map((x) => substitute(x, map));
  if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, substitute(x, map)]));
  return v;
}

const opValue = (op: Op): Json => JSON.parse(opJSON(op));

describe.skipIf(!golden)("cli-scenarios.json", () => {
  const entries = (golden?.log ?? []).map((l) => decodeEntryLine(l)!);
  for (const c of golden?.cases ?? []) {
    // The 10 s limit is real time, as in the CLI.
    it(c.name, { timeout: 20_000 }, async () => {
      const before = entries.slice(0, c.from);
      const projection = new Projection(AppState.replay(before.map((e) => e.op)), [], dayContaining(c.nowBefore, golden!.timeZone));
      let n = 0;
      const clock = { now: () => c.nowBefore, newID: () => placeholder(++n) };
      const ctx = new Context({ projection, entries: () => before, actor: c.actor },
        { clock, timeZone: golden!.timeZone, dateOrder: (c.dateOrder ?? golden!.dateOrder) === "dm" ? "dayFirst" : "monthFirst" });
      let pushed: Op[] = [];
      const out = await execute(c.script, ctx, nodeSandbox, {
        dryRun: c.dryRun,
        commit: async (ops, batch) => {
          pushed = ops.map((o) => ({ ...o, actor: c.actor, batch }));
          return true;
        },
      });
      const theirOps = entries.slice(c.from, c.to).map((e) => opValue(e.op));
      const ourOps = pushed.map(opValue);

      // Ids: the pushed ops line up one to one; the output maps the rest (dry runs, created entities).
      const map = new Map<string, string>();
      mapIDs(ourOps, theirOps, map);
      mapIDs(out as Json, c.output, map);
      const lo = c.nowBefore - 2000;
      const hi = c.nowAfter + 2000;
      const norm = (v: Json) => positionless(clockless(v, lo, hi));
      let want = norm(c.output);
      let got = norm(substitute(out as Json, map));
      const failed = (v: Json) => v && typeof v === "object" && !Array.isArray(v) && v.ok === false;
      const error = (v: Json) => (v as { error?: { type?: string } }).error;
      // A syntax error's text is the parser's (Deno's vs sucrase's): compare its type only.
      if (failed(want) && error(want)?.type === "SyntaxError") {
        want = { ...(want as object), error: { type: "SyntaxError" } } as Json;
        got = failed(got) ? ({ ...(got as object), error: { type: error(got)?.type ?? null } } as Json) : got;
      }
      expect(got).toEqual(want);
      // Key order too: the MCP tool returns this object's JSON text.
      expect(JSON.stringify(got)).toBe(JSON.stringify(want));
      expect(norm(substitute(ourOps, map))).toEqual(norm(theirOps));
    });
  }
});

