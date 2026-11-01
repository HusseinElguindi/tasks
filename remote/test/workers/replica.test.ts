// The Replica DO against local copies of the unchanged server/ (test/workers/servers.ts): push, pull, two replicas,
// offline and the alarm, 409 recovery, 413, invalid_op and the stop errors (with the server's own fixture
// responses), dry runs, undo, the run lock, and a wake from the snapshot plus the tail.

import { evictDurableObject, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { AppState } from "../../src/core/state.ts";
import { decodeEntryLine } from "../../src/core/wire.ts";
import type { Replica } from "../../src/replica.ts";
import f03 from "../../../fixtures/sync/03-invalid-op.json";
import f04 from "../../../fixtures/sync/04-bad-token.json";
import f05 from "../../../fixtures/sync/05-log-mismatch.json";
import f07 from "../../../fixtures/sync/07-bad-request.json";
import f08 from "../../../fixtures/sync/08-too-many-ops.json";
import f09 from "../../../fixtures/sync/09-not-found.json";
import log2345 from "../../../fixtures/sync/log-2345.jsonl?raw";
import { control, freshServer, replica, run, serverLog, status, sync } from "./helpers.ts";

const INBOX_OP = "00000000-0000-0000-0000-000000000002";
const fault = (f: { response: { status: number; body: unknown } }, extra: Record<string, unknown> = {}) =>
  ({ status: f.response.status, body: JSON.stringify(f.response.body), ...extra });
const unavailable = (times: number) => ({ status: 503, body: "Service Unavailable", times });

type Out = { [k: string]: unknown };
const batchOf = (out: Out) => (out.change as { batch: string }).batch;
const titles = async (stub: ReturnType<typeof replica>) =>
  (await run(stub, async (tasks) => (await tasks.find({})).map((t: { title: string }) => t.title).sort())).result;
const alarmAt = (stub: ReturnType<typeof replica>) => runInDurableObject(stub, (_: Replica, s) => s.storage.getAlarm());

describe("push and pull", () => {
  it("a run pushes its ops with the actor and one batch, and reports them synced", async () => {
    await freshServer();
    const a = replica("push-1");
    const out = await run(a, async (tasks) => {
      await tasks.add({ title: "Buy milk" });
      await tasks.add({ title: "Call mum", when: "today" });
      return "done";
    });
    expect(out).toMatchObject({ ok: true, result: "done", synced: true, change: { summary: "New 2 Tasks" } });
    const log = await serverLog();
    // The Inbox seed (the same op every replica sends, no actor), then the run's two ops in one batch.
    expect(log.map((e) => e.op.type)).toEqual(["list.create", "task.create", "task.create"]);
    expect(log[0].op).toMatchObject({ id: INBOX_OP, set: { name: "Inbox", order: "a0" } });
    expect(log[0].op.actor).toBeUndefined();
    for (const e of log.slice(1)) expect(e.op).toMatchObject({ actor: "agent:test", batch: batchOf(out) });
    expect(await status(a)).toMatchObject({ cursor: 3, pending: 0, log: 3, rejected: 0, syncState: { kind: "idle" } });
    expect(await alarmAt(a)).toBeNull();
    expect((await control({ take: true })).seen.every((s) => s.status === 200)).toBe(true);
  });

  it("two replicas see each other's changes, and the Inbox is stored once", async () => {
    await freshServer();
    const a = replica("two-a");
    const b = replica("two-b");
    const added = await run(a, async (tasks) => (await tasks.add({ title: "From A" })).id, { actor: "agent:a" });
    expect(added).toMatchObject({ ok: true, synced: true });
    const done = await run(b, async (tasks) => {
      const [t] = await tasks.find({ text: "From A" });
      await tasks.complete(t.id);
      return t.id;
    }, { actor: "agent:b" });
    expect(done).toMatchObject({ ok: true, result: added.result, synced: true });
    const seen = await run(a, async (tasks) => (await tasks.task(added.result as string)).done, { actor: "agent:a" });
    expect(seen).toMatchObject({ ok: true, result: true });
    const log = await serverLog();
    expect(log.filter((e) => e.op.id === INBOX_OP)).toHaveLength(1);
    expect(log.map((e) => e.op.actor ?? null)).toEqual([null, "agent:a", "agent:b"]);
    expect(await status(a)).toMatchObject({ cursor: 3, pending: 0 });
    expect(await status(b)).toMatchObject({ cursor: 3, pending: 0 });
  });

  it("another device's ops show up in the next run", async () => {
    await freshServer();
    const a = replica("other-device");
    await run(a, async (tasks) => tasks.add({ title: "Mine" }));
    const log = await serverLog();
    const list = log[0].op.target;
    const r = await sync(log.length, log[log.length - 1].hash, [
      { id: crypto.randomUUID(), at: Date.now(), type: "task.create", target: crypto.randomUUID(), set: { list, order: "a5", title: "From the Mac" } },
    ]);
    expect(r.status).toBe(200);
    expect(await titles(a)).toEqual(["From the Mac", "Mine"]);
  });

  it("a dry run writes nothing", async () => {
    await freshServer();
    const a = replica("dry");
    await run(a, async (tasks) => tasks.add({ title: "Keep" }));
    const before = (await serverLog()).length;
    const out = await run(a, async (tasks) => {
      await tasks.add({ title: "Draft" });
      return 1;
    }, { dryRun: true });
    expect(out).toMatchObject({ ok: true, dryRun: true, change: { summary: 'New Task "Draft" in Inbox' } });
    expect(out.diff).toEqual(expect.arrayContaining([expect.stringContaining("Draft")]));
    expect((await serverLog()).length).toBe(before);
    expect(await status(a)).toMatchObject({ pending: 0 });
    expect(await titles(a)).toEqual(["Keep"]);
  });

  it("a script that throws writes nothing", async () => {
    await freshServer();
    const a = replica("throws");
    await run(a, async () => 0);
    const before = (await serverLog()).length;
    const out = await run(a, async (tasks) => {
      await tasks.add({ title: "Half" });
      throw new Error("nope");
    });
    expect(out).toEqual({ ok: false, error: { message: "nope", type: "Error" }, logs: [], change: null });
    expect((await serverLog()).length).toBe(before);
    expect(await status(a)).toMatchObject({ pending: 0 });
  });

  it("undo is a new batch that restores the touched keys, from the replica's log", async () => {
    await freshServer();
    const a = replica("undo");
    const added = await run(a, async (tasks) => (await tasks.add({ title: "Buy milk" })).id);
    const renamed = await run(a, async (tasks) => tasks.rename(added.result, "Buy oat milk"));
    const undone = await run(a, async (tasks) => tasks.undo(batchOf(renamed)));
    expect(undone).toMatchObject({ ok: true, synced: true, change: { summary: 'Undo: Rename Task to "Buy oat milk"' } });
    expect(batchOf(undone)).not.toBe(batchOf(renamed));
    const last = (await serverLog()).at(-1)!;
    expect(last.op).toMatchObject({ type: "task.update", target: added.result, set: { title: "Buy milk" }, batch: batchOf(undone) });
    expect(await titles(a)).toEqual(["Buy milk"]);
  });

  it("runs take turns: each sees the one before it", async () => {
    await freshServer();
    const a = replica("lock");
    const slow = async (tasks: { add: (t: object) => Promise<unknown>; find: (q: object) => Promise<unknown[]> }, title: string) => {
      const before = (await tasks.find({})).length;
      await new Promise((r) => setTimeout(r, 50));
      await tasks.add({ title });
      return before;
    };
    const [one, two] = await Promise.all([run(a, (t) => slow(t, "one")), run(a, (t) => slow(t, "two"))]);
    expect([one.result, two.result].sort()).toEqual([0, 1]);
    expect(batchOf(one)).not.toBe(batchOf(two));
    expect(await titles(a)).toEqual(["one", "two"]);
  });

  it("works the same against a real `wrangler dev` of server/", async () => {
    await freshServer("wrangler");
    const a = replica("wrangler-a");
    const b = replica("wrangler-b");
    const out = await run(a, async (tasks) => (await tasks.add({ title: "Over wrangler dev" })).id);
    expect(out).toMatchObject({ ok: true, synced: true });
    expect(await titles(b)).toEqual(["Over wrangler dev"]);
    expect((await serverLog()).map((e) => e.op.type)).toEqual(["list.create", "task.create"]);
  }, 180_000);
});

describe("offline", () => {
  it("a run that can't reach the server keeps its ops and reports synced: false; the alarm pushes them", async () => {
    await freshServer();
    const a = replica("offline");
    // The pull and the commit each try four times (three retries). The last one fails in the handler, which
    // Miniflare answers as a bare 500.
    await control({ inject: [unavailable(7), { status: 0, body: "", drop: true }] });
    const out = await run(a, async (tasks) => (await tasks.add({ title: "Offline" })).title);
    expect(out).toMatchObject({ ok: true, result: "Offline", synced: false });
    expect(await status(a)).toMatchObject({ pending: 2, cursor: 0, syncState: { kind: "retrying", reason: "HTTP 500" } });
    expect(await alarmAt(a)).not.toBeNull();
    expect(await serverLog()).toEqual([]);
    expect(await runDurableObjectAlarm(a)).toBe(true);
    expect(await status(a)).toMatchObject({ pending: 0, cursor: 2, syncState: { kind: "idle" } });
    expect(await alarmAt(a)).toBeNull();
    expect((await serverLog()).map((e) => e.op.type)).toEqual(["list.create", "task.create"]);
  });

  it("the next run pushes what's queued before it runs, and sees it", async () => {
    await freshServer();
    const a = replica("offline-next");
    await control({ inject: [unavailable(8)] });
    expect(await run(a, async (tasks) => tasks.add({ title: "Queued" }))).toMatchObject({ ok: true, synced: false });
    const next = await run(a, async (tasks) => (await tasks.find({})).length);
    expect(next).toMatchObject({ ok: true, result: 1, synced: true });
    expect(await status(a)).toMatchObject({ pending: 0, cursor: 2 });
  });

  it("an alarm that still can't reach the server backs off", async () => {
    await freshServer();
    const a = replica("offline-backoff");
    await control({ inject: [unavailable(9)] });
    await run(a, async (tasks) => tasks.add({ title: "Later" }));
    const first = (await alarmAt(a))!;
    const t0 = Date.now();
    expect(await runDurableObjectAlarm(a)).toBe(true);
    const second = (await alarmAt(a))!;
    // 4 + 4 failures took the backoff to 256 s, capped at 60 s.
    expect(second - t0).toBeGreaterThanOrEqual(59_000);
    expect(first).toBeLessThan(second);
    expect(await status(a)).toMatchObject({ pending: 2, syncState: { kind: "retrying" } });
    expect(await runDurableObjectAlarm(a)).toBe(true);
    expect(await status(a)).toMatchObject({ pending: 0 });
  });
});

describe("the error table, with the server's fixture responses", () => {
  it("401 stops the run before the script, with nothing scheduled", async () => {
    await freshServer();
    const a = replica("401");
    await control({ inject: [fault(f04)] });
    let ran = false;
    const out = await run(a, async () => { ran = true; });
    expect(out).toEqual({ ok: false, error: { type: "Sync", message: "The server rejected the token (SYNC_TOKEN)." }, logs: [], change: null });
    expect(ran).toBe(false);
    expect(await alarmAt(a)).toBeNull();
    expect(await run(a, async () => 1)).toMatchObject({ ok: true, synced: true });
  });

  it("404 and bad_request stop sync with the server's message", async () => {
    await freshServer();
    const a = replica("404");
    await control({ inject: [fault(f09)] });
    expect(await run(a, async () => 1)).toMatchObject({ ok: false, error: { type: "Sync", message: "Sync stopped: No such path: /v1/push." } });
    await control({ inject: [fault(f07)] });
    expect(await run(a, async () => 1)).toMatchObject({ ok: false, error: { type: "Sync", message: "Sync stopped: base must not be null when from > 0." } });
    expect(await run(a, async () => 1)).toMatchObject({ ok: true });
  });

  it("invalid_op moves that op to rejected and sends the rest", async () => {
    await freshServer();
    const a = replica("invalid");
    await run(a, async () => 0);
    // ops[1] of the next push.
    await control({ inject: [fault(f03, { onPush: true })] });
    const out = await run(a, async (tasks) => {
      await tasks.add({ title: "Good" });
      await tasks.add({ title: "Rejected" });
    });
    expect(out).toEqual({
      ok: false,
      error: { type: "Sync", message: "The server rejected a change (it's in the replica's rejected table). This is a bug in tasks-mcp." },
      logs: [], change: null,
    });
    expect(await status(a)).toMatchObject({ pending: 0, rejected: 1 });
    expect(await titles(a)).toEqual(["Good"]);
    expect((await serverLog()).map((e) => e.op.set.title ?? null)).toEqual([null, "Good"]);
  });

  it("413 halves the chunk until it fits", async () => {
    await freshServer();
    const a = replica("413");
    await run(a, async () => 0);
    await control({ take: true, inject: [fault(f08, { onPush: true })] });
    const out = await run(a, async (tasks) => {
      for (const title of ["a", "b", "c"]) await tasks.add({ title });
    });
    expect(out).toMatchObject({ ok: true, synced: true });
    const seen = (await control({ take: true })).seen;
    expect(seen.map((s) => [s.ops, s.status])).toEqual([[0, 200], [3, 413], [1, 200], [1, 200], [1, 200]]);
    expect(await titles(a)).toEqual(["a", "b", "c"]);
  });

  it("413 on a single op stops sync; the op stays queued for the next run", async () => {
    await freshServer();
    const a = replica("413-one");
    await run(a, async () => 0);
    await control({ inject: [fault(f08, { onPush: true })] });
    const out = await run(a, async (tasks) => tasks.add({ title: "Big" }));
    expect(out).toMatchObject({ ok: false, error: { type: "Sync", message: "Sync stopped: A change is too large to sync." } });
    expect(await status(a)).toMatchObject({ pending: 1 });
    expect(await alarmAt(a)).toBeNull();
    expect(await run(a, async () => 1)).toMatchObject({ ok: true, synced: true });
    expect(await titles(a)).toEqual(["Big"]);
  });
});

describe("409 recovery: every known op becomes pending, from 0, nothing discarded", () => {
  it("a server that lost its log (restored, or new) gets the whole log back", async () => {
    await freshServer();
    const a = replica("409-lost");
    await run(a, async (tasks) => {
      await tasks.add({ title: "One" });
      await tasks.add({ title: "Two" });
    });
    const before = await serverLog();
    await freshServer(); // empty: our cursor is past its head
    expect(await run(a, async (tasks) => (await tasks.find({})).length)).toMatchObject({ ok: true, result: 2, synced: true });
    const after = await serverLog();
    expect(after.map((e) => e.op)).toEqual(before.map((e) => e.op));
    expect(after.map((e) => e.hash)).toEqual(before.map((e) => e.hash));
    expect(await status(a)).toMatchObject({ cursor: 3, pending: 0, recovering: false, log: 3 });
  });

  it("a log that diverged is merged: theirs, then ours", async () => {
    await freshServer();
    const a = replica("409-diverged");
    await run(a, async (tasks) => {
      await tasks.add({ title: "Ours 1" });
      await tasks.add({ title: "Ours 2" });
    });
    await freshServer();
    const b = replica("409-other");
    await run(b, async (tasks) => {
      await tasks.add({ title: "Theirs 1" });
      await tasks.add({ title: "Theirs 2" });
    }, { actor: "agent:other" });
    // Same length, different hashes: a's base doesn't match.
    expect(await titles(a)).toEqual(["Ours 1", "Ours 2", "Theirs 1", "Theirs 2"]);
    const log = await serverLog();
    expect(log.map((e) => e.op.set.title ?? e.op.set.name)).toEqual(["Inbox", "Theirs 1", "Theirs 2", "Ours 1", "Ours 2"]);
    expect(await status(a)).toMatchObject({ cursor: 5, pending: 0, recovering: false });
  });

  it("a page that doesn't continue our log is treated as a 409", async () => {
    await freshServer();
    const a = replica("409-gap");
    await run(a, async (tasks) => tasks.add({ title: "Kept" }));
    const stray = (await serverLog())[1];
    await control({ inject: [{ status: 200, body: JSON.stringify({ entries: [{ ...stray, seq: 7 }], head: 8, more: false }) }] });
    expect(await run(a, async (tasks) => (await tasks.find({})).length)).toMatchObject({ ok: true, result: 1 });
    expect(await status(a)).toMatchObject({ cursor: 2, pending: 0, recovering: false });
  });

  it("a log that keeps changing stops after three recoveries, and the next run finishes it", async () => {
    await freshServer();
    const a = replica("409-loop");
    await run(a, async (tasks) => tasks.add({ title: "Survivor" }));
    await control({ inject: [fault(f05, { times: 4 })] });
    expect(await run(a, async () => 1)).toMatchObject({ ok: false, error: { type: "Sync", message: "Sync stopped: The server's log keeps changing." } });
    expect(await status(a)).toMatchObject({ recovering: true, cursor: 0, pending: 2, log: 0 });
    expect(await titles(a)).toEqual(["Survivor"]);
    expect(await status(a)).toMatchObject({ recovering: false, cursor: 2, pending: 0, log: 2 });
    expect(await serverLog()).toHaveLength(2);
  });

  it("a recovery survives the replica being evicted midway", async () => {
    await freshServer();
    const a = replica("409-evicted");
    await run(a, async (tasks) => tasks.add({ title: "Persisted" }));
    await control({ inject: [fault(f05, { times: 4 })] });
    await run(a, async () => 1);
    await evictDurableObject(a);
    expect(await status(a)).toMatchObject({ recovering: true, pending: 2, cursor: 0 });
    expect(await titles(a)).toEqual(["Persisted"]);
    expect(await status(a)).toMatchObject({ recovering: false, pending: 0, cursor: 2 });
  });
});

describe("the 2,345-entry log (fixtures/sync)", () => {
  const entries = log2345.split("\n").filter(Boolean).map((l) => JSON.parse(l) as { seq: number; hash: string; op: Record<string, unknown> });

  /** Pushes the fixture log's ops into the current server, 500 at a time. */
  async function seedServer() {
    let base: string | null = null;
    for (let i = 0; i < entries.length; i += 500) {
      const r = await sync(i, base, entries.slice(i, i + 500).map((e) => e.op));
      expect(r.status).toBe(200);
      base = r.body.entries.length > 0 ? r.body.entries[r.body.entries.length - 1].hash : base;
    }
    return serverLog();
  }

  const confirmed = (stub: ReturnType<typeof replica>) => runInDurableObject(stub, (r: Replica) => {
    const p = (r as unknown as { engine: { projection: { confirmed: AppState } } }).engine.projection.confirmed;
    return { tasks: Object.fromEntries(p.tasks), lists: Object.fromEntries(p.lists) };
  });

  it("pulls in pages of 1,000, wakes from the snapshot plus the tail, and folds like a full replay", async () => {
    await freshServer();
    const log = await seedServer();
    expect(log.map((e) => e.hash)).toEqual(entries.map((e) => e.hash)); // the same chain as the fixture
    const a = replica("big");
    await control({ take: true });
    const first = await run(a, async (tasks) => ({ lists: await tasks.lists(), found: (await tasks.find({})).length }));
    expect(first).toMatchObject({ ok: true, synced: true });
    expect((await control({ take: true })).seen.map((s) => s.from)).toEqual([0, 1000, 2000]);
    expect(await status(a)).toMatchObject({ cursor: 2345, log: 2345, pending: 0, snapshot: 2345 });

    // Another device adds three ops: the tail after the snapshot.
    const list = entries[0].op.target as string;
    const ops = ["x", "y", "z"].map((title, i) => ({ id: crypto.randomUUID(), at: Date.now(), type: "task.create", target: crypto.randomUUID(), set: { list, order: `b${i}`, title } }));
    expect((await sync(2345, log.at(-1)!.hash, ops)).status).toBe(200);
    const second = await run(a, async (tasks) => ({ lists: await tasks.lists(), found: (await tasks.find({})).length }));
    expect(await status(a)).toMatchObject({ cursor: 2348, snapshot: 2345 });
    const before = await confirmed(a);

    await evictDurableObject(a);
    expect(await status(a)).toMatchObject({ cursor: 2348, log: 2348, snapshot: 2345, pending: 0 });
    expect(await confirmed(a)).toEqual(before);
    const replay = AppState.replay([...(await serverLog())].map((e) => decodeEntryLine(JSON.stringify(e))!.op));
    expect(before).toEqual({ tasks: Object.fromEntries(replay.tasks), lists: Object.fromEntries(replay.lists) });
    const third = await run(a, async (tasks) => ({ lists: await tasks.lists(), found: (await tasks.find({})).length }));
    expect(third.result).toEqual(second.result);
    expect((second.result as { found: number }).found).toBe((first.result as { found: number }).found + 3);
  });
});
