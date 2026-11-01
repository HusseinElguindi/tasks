// The core port against the fixtures that already exist: fixtures/sync (the wire contract, shared with the server
// and the Swift FixtureTests) and TasksCore's fractional-index vectors (generated from the npm package).

import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { decodeOp, opJSON } from "../src/core/op.ts";
import { FractionalIndex } from "../src/core/ordering.ts";
import { AppState } from "../src/core/state.ts";
import { classify, decodeEntryLine, syncBody } from "../src/core/wire.ts";

const root = join(import.meta.dirname, "..", "..");
const fixtureDir = join(root, "fixtures", "sync");

interface Fixture {
  name: string;
  setup: { log: unknown[] };
  request: { body: unknown };
  response: { status: number; body: unknown };
}

const fixtures: Fixture[] = readdirSync(fixtureDir)
  .filter((f) => /^\d.*\.json$/.test(f))
  .map((f) => JSON.parse(readFileSync(join(fixtureDir, f), "utf8")));

const expectedKind: Record<number, string> = { 200: "page", 401: "badToken", 404: "misconfigured", 405: "misconfigured", 409: "logMismatch", 413: "tooLarge" };

describe("fixtures/sync", () => {
  it("has fixtures", () => expect(fixtures.length).toBeGreaterThan(10));

  for (const f of fixtures) {
    it(`${f.name}: classifies the response`, () => {
      const outcome = classify(f.response.status, JSON.stringify(f.response.body));
      const want = f.response.status === 400
        ? ((f.response.body as { error: string }).error === "invalid_op" ? "invalidOp" : "badRequest")
        : expectedKind[f.response.status];
      expect(outcome.kind).toBe(want);
      if (outcome.kind === "page") {
        const body = f.response.body as { entries: unknown[]; head: number; more: boolean };
        expect(outcome.page.entries.length).toBe(body.entries.length);
        expect(outcome.page.head).toBe(body.head);
        expect(outcome.page.more).toBe(body.more);
        // The stored text is the server's bytes.
        outcome.page.entries.forEach((e, i) => expect(e.json).toBe(JSON.stringify(body.entries[i])));
      }
    });

    it(`${f.name}: the request body is what this client would send`, () => {
      const body = f.request.body as { from?: unknown; base?: unknown; ops?: unknown[] };
      if (typeof body !== "object" || body === null || !Array.isArray(body.ops) || typeof body.from !== "number") return;
      const ops = body.ops.map(decodeOp);
      if (ops.some((o) => o === null)) return; // a deliberately malformed request
      const ours = syncBody(body.from, (body.base as string | null) ?? null, ops.map((o) => opJSON(o!)));
      // Equal as JSON; equal as text when the fixture's set keys are in canonical order.
      expect(JSON.parse(ours)).toEqual(JSON.parse(JSON.stringify(body)));
    });
  }
});

describe("log-2345.jsonl", () => {
  const lines = readFileSync(join(fixtureDir, "log-2345.jsonl"), "utf8").split("\n").filter(Boolean);

  it("decodes every line and folds", () => {
    const entries = lines.map(decodeEntryLine);
    expect(entries.every((e) => e !== null)).toBe(true);
    entries.forEach((e, i) => expect(e!.seq).toBe(i));
    const t0 = performance.now();
    const state = AppState.replay(entries.map((e) => e!.op));
    const ms = performance.now() - t0;
    expect(state.tasks.size + state.lists.size).toBeGreaterThan(0);
    console.log(`fold ${lines.length} entries: ${ms.toFixed(1)} ms, ${state.tasks.size} tasks, ${state.lists.size} lists`);
  });

  it("canonical op text round-trips the server's op text", () => {
    for (const line of lines) {
      const raw = JSON.parse(line);
      const op = decodeOp(raw.op);
      expect(op).not.toBeNull();
      expect(JSON.parse(opJSON(op!))).toEqual(raw.op);
    }
  });
});

describe("fractional-index vectors", () => {
  const v = JSON.parse(readFileSync(join(root, "app/TasksCore/Tests/TasksCoreTests/Resources/fractional-index-vectors.json"), "utf8")) as {
    between: [string | null, string | null, string][];
    nBetween: [string | null, string | null, number, string[]][];
    errors: [string | null, string | null][];
  };

  it("keyBetween", () => {
    for (const [a, b, want] of v.between) expect(FractionalIndex.keyBetween(a, b)).toBe(want);
  });

  it("keysBetween", () => {
    for (const [a, b, n, want] of v.nBetween) expect(FractionalIndex.keysBetween(a, b, n)).toEqual(want);
  });

  it("errors", () => {
    for (const [a, b] of v.errors) expect(() => FractionalIndex.keyBetween(a, b)).toThrow();
  });
});
