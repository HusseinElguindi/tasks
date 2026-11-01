// The API contract: remote/tasks.d.ts is the CLI's, and the TypeScript command table generates exactly it.
// Plus a smoke run of the command layer on the 2,345-entry fixture log.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { declarations, SHAPE_KEYS } from "../src/cli/commands.ts";
import { Context } from "../src/cli/context.ts";
import { execute } from "../src/cli/run.ts";
import { dayContaining } from "../src/core/day.ts";
import { Projection } from "../src/core/projection.ts";
import { AppState } from "../src/core/state.ts";
import { decodeEntryLine, type LogEntry } from "../src/core/wire.ts";
import { nodeSandbox } from "./sandbox.ts";

const root = join(import.meta.dirname, "..", "..");
const ours = readFileSync(join(import.meta.dirname, "..", "tasks.d.ts"), "utf8");
const cli = readFileSync(join(root, "app/TasksCore/Tests/TasksCLITests/tasks.d.ts"), "utf8");

describe("tasks.d.ts", () => {
  it("is the CLI's copy, unchanged", () => expect(ours).toBe(cli));
  it("is what the TypeScript command table generates", () => expect(declarations()).toBe(ours));
});

function replicaFrom(entries: LogEntry[], now: number) {
  const confirmed = AppState.replay(entries.map((e) => e.op));
  const projection = new Projection(confirmed, [], dayContaining(now, "America/Toronto"));
  return { projection, entries: () => entries, actor: "agent:test" };
}

describe("a run on the fixture log", () => {
  const entries = readFileSync(join(root, "fixtures/sync/log-2345.jsonl"), "utf8").split("\n").filter(Boolean).map((l) => decodeEntryLine(l)!);
  const now = Date.UTC(2026, 10, 1, 17);
  let n = 0;
  const clock = { now: () => now, newID: () => `00000000-0000-4000-8000-${String(++n).padStart(12, "0")}` };

  it("reads, writes and reports the change", async () => {
    const c = new Context(replicaFrom(entries, now), { clock, timeZone: "America/Toronto", dateOrder: "monthFirst" });
    const out = await execute(`
      const lists = await tasks.lists();
      const t = await tasks.add({ title: "Buy milk", list: lists[0].id, when: "tomorrow" });
      await tasks.complete(t.id);
      const again = await tasks.task(t.ref);
      console.log("done", again.done);
      return { lists: lists.length, done: again.done, keys: Object.keys(again) };
    `, c, nodeSandbox, { dryRun: true, commit: async () => true });
    expect(out.ok).toBe(true);
    const result = out.result as { lists: number; done: boolean; keys: string[] };
    expect(result.done).toBe(true);
    expect(result.keys).toEqual(SHAPE_KEYS.task.filter((k) => k !== "kind"));
    expect(out.logs).toEqual(["done true"]);
    expect(Object.keys(out)).toEqual(["ok", "result", "logs", "change", "dryRun", "diff"]);
    const change = out.change as { summary: string; tasks: unknown[]; batch: string };
    expect(change.batch).toBe(c.batch);
    expect(change.summary).toMatch(/^New Task "Buy milk"/);
    expect(c.ops.map((o) => o.type)).toEqual(["task.create", "task.update"]);
  });

  it("reports a bad ref with its type and writes nothing", async () => {
    const c = new Context(replicaFrom(entries, now), { clock, timeZone: "America/Toronto", dateOrder: "monthFirst" });
    const out = await execute(`await tasks.add({ title: "x" }); await tasks.complete("zzzzzzzz");`, c, nodeSandbox,
      { dryRun: false, commit: async () => { throw new Error("must not commit"); } });
    expect(out).toMatchObject({ ok: false, error: { type: "NotFound", field: "task" }, change: null });
  });
});
