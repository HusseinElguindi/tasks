// Code mode on Worker Loader: the 218 CLI scenarios (test/cli-parity.ts) with each script in a Loader isolate, as
// in production. Output, key order and pushed ops must match the CLI's, and so must error positions now.

import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { logEntries, runCase, type Golden } from "../cli-parity.ts";
import { loaderSandbox } from "../../src/codemode.ts";

const fixtures = (env as unknown as { GOLDEN: Fetcher }).GOLDEN;
const golden = (await (await fixtures.fetch("http://golden/cli-scenarios.json")).json()) as Golden;
const entries = logEntries(golden);
const sandbox = loaderSandbox(env.LOADER);

let positioned = 0;

describe("cli-scenarios.json on Worker Loader", () => {
  for (const c of golden.cases) {
    it(c.name, { timeout: 20_000 }, async () => {
      const r = await runCase(golden, entries, c, sandbox, { positions: true });
      expect(r.got).toEqual(r.want);
      expect(JSON.stringify(r.got)).toBe(JSON.stringify(r.want));
      expect(r.ourOps).toEqual(r.theirOps);
      const e = (r.got as { error?: { line?: number; column?: number } }).error;
      if (typeof e?.line === "number" && typeof e.column === "number") positioned++;
    });
  }

  it("compared error positions (line and column) in the cases that have them", () => {
    const want = golden.cases.filter((c) => {
      const e = (c.output as { error?: { line?: number; type?: string } }).error;
      return typeof e?.line === "number" && e.type !== "SyntaxError"; // compared by type only
    });
    expect(positioned).toBe(want.length);
    expect(positioned).toBeGreaterThanOrEqual(60);
  });
});

// No scenario has TypeScript before the error on its line, where stripping types moves the columns. Positions Deno
// 2.9.8 reported for these scripts through the CLI's bridge (its import and `where`), measured 2026-11-01. Lines
// always match. A column can differ after TypeScript-only syntax: Deno's source map has no mapping after a removed
// `as T)`, so it reports an earlier token ("generic": column 18, the "k"); sucrase maps every token, so we report
// the `.a` that threw (29).
describe("error positions in TypeScript, as Deno reports them", () => {
  const cases: [string, string, number, number][] = [
    ["annotated", 'const x: string[] = (null as any).foo.bar;\nreturn x;', 1, 35],
    ["generic", 'type T = { a: number };\nconst m = new Map<string, T>();\nconst v = (m.get("k") as T).a;\nreturn v;', 3, 29], // Deno: 18
    ["call", 'interface Q { text: string }\nconst q: Q = { text: "a" };\nconst r: number = await tasks.find(q as Q);\nreturn r;', 3, 31],
    ["twoOnLine", 'const a: number = 1; const b: string = (undefined as any).length;\nreturn a;', 1, 59],
  ];
  const notFound = async () => ({ error: { type: "NotFound", message: "nope", field: null, candidates: [] } });
  for (const [name, script, line, column] of cases) {
    it(name, async () => {
      const o = await sandbox(script, notFound);
      expect(o.ok).toBe(false);
      expect(o.error).toMatchObject({ line, column });
    });
  }
});
