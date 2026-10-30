// S3: the UserLog DO: append with dedup, hash chain, page read with `more`, 409 (SPEC §5–§7).
import { evictDurableObject, runInDurableObject } from "cloudflare:test";
import { describe, expect, it, vi } from "vitest";
import {
  INBOX, logStub, NOW, ok, opText, pullAll, seed, sha256, sync, taskUpdate, TASK, type Entry, type Op,
} from "./helpers";

const opA: Op = { id: "00000000-0000-0000-0000-000000000002", at: 1761811200000, type: "list.create", target: INBOX, set: { name: "Inbox", order: "a0" } };
const opB: Op = { id: "5b0c6c1e-3f0a-4c8e-9d61-0f4f6f1a2b3c", at: 1761811260000, type: "task.create", target: TASK, set: { list: INBOX, order: "a0", title: "Buy milk", when: "2026-10-30" } };
const HASH_0 = "bc2a6e3a4de77a2ce16c4a38c6f4d76237a98434f7d213049e3fd77dde66dacd";
const HASH_1 = "184ceb4c3d11bd53025385963c25f50298c2d652f84d5989941d2ec13a66fd79";

/** Checks seq is dense from `from` and every hash chains from its predecessor. */
function expectChain(entries: Entry[], from = 0, prev = "") {
  entries.forEach((e, i) => {
    expect(e.seq).toBe(from + i);
    expect(e.hash).toBe(sha256(prev + "\n" + opText(e.op)));
    prev = e.hash;
  });
}

const rows = () =>
  runInDurableObject(logStub(), (_, state) => state.storage.sql.exec("SELECT seq, id, received, op, hash FROM log ORDER BY seq").toArray());

describe("hash chain", () => {
  it("produces the SPEC §5 test vectors", async () => {
    const page = await ok(0, null, [opA, opB]);
    expect(page.entries.map((e) => e.hash)).toEqual([HASH_0, HASH_1]);
  });

  it("stores and hashes the op as JSON.stringify({id, at, type, target, set}), set keys in received order", async () => {
    const raw = `{"from":0,"base":null,"ops":[ {"set": {"order":"a1", "list":"l", "title":"t"}, "target":"t1", "type":"task.create", "at":5, "id":"o1"} ]}`;
    const res = await sync(raw);
    const text = '{"id":"o1","at":5,"type":"task.create","target":"t1","set":{"order":"a1","list":"l","title":"t"}}';
    expect((await rows())[0].op).toBe(text);
    expect(res.body.entries[0].hash).toBe(sha256("\n" + text));
  });

  it("hashes non-ASCII text as UTF-8", async () => {
    const op = taskUpdate({ title: "Café ☕ 😀", notes: "line 1\nline \"2\"" });
    const page = await ok(0, null, [op]);
    expect(page.entries[0].hash).toBe(sha256("\n" + opText(op)));
    expect(page.entries[0].op).toEqual(op);
  });

  it("chains across requests and across DO restarts", async () => {
    let page = await ok(0, null, [opA]);
    await evictDurableObject(logStub());
    page = await ok(1, HASH_0, [opB]);
    expect(page.entries[0].hash).toBe(HASH_1);
    await evictDurableObject(logStub());
    const third = taskUpdate();
    page = await ok(2, HASH_1, [third]);
    expectChain(await pullAll());
  });

  it("stores the table exactly as SPEC §7 describes", async () => {
    await ok(0, null, [opA]);
    const sql = await runInDurableObject(logStub(), (_, state) =>
      state.storage.sql.exec<{ sql: string }>("SELECT sql FROM sqlite_master WHERE name = 'log'").one().sql,
    );
    expect(sql.replace(/\s+/g, " ")).toBe(
      "CREATE TABLE log ( seq INTEGER PRIMARY KEY, id TEXT NOT NULL UNIQUE, received INTEGER NOT NULL, op TEXT NOT NULL, hash TEXT NOT NULL )",
    );
    expect(await rows()).toEqual([{ seq: 0, id: opA.id, received: NOW, op: opText(opA), hash: HASH_0 }]);
  });
});

describe("append", () => {
  it("returns the client's own ops, after everything it didn't have", async () => {
    const theirs = [taskUpdate(), taskUpdate(), taskUpdate()];
    const mine = [taskUpdate(), taskUpdate()];
    await ok(0, null, theirs);
    const page = await ok(0, null, mine);
    expect(page.entries.map((e) => e.op)).toEqual([...theirs, ...mine]);
    expect(page).toMatchObject({ head: 5, more: false });
    expectChain(page.entries);
  });

  it("appends a request's ops contiguously, in the order sent", async () => {
    const a = [taskUpdate(), taskUpdate(), taskUpdate()];
    const b = [taskUpdate(), taskUpdate()];
    const c = [taskUpdate(), taskUpdate(), taskUpdate(), taskUpdate()];
    const [ra, rb, rc] = await Promise.all([ok(0, null, a), ok(0, null, b), ok(0, null, c)]);
    const log = await pullAll();
    expect(log).toHaveLength(9);
    for (const [res, ops] of [[ra, a], [rb, b], [rc, c]] as const) {
      const start = log.findIndex((e) => e.op.id === ops[0].id);
      expect(log.slice(start, start + ops.length).map((e) => e.op)).toEqual(ops);
      expect(res.entries.slice(-ops.length).map((e) => e.op)).toEqual(ops); // the page ends with them
    }
    expectChain(log);
  });

  it("stamps every entry of one request with the same received time", async () => {
    await ok(0, null, [taskUpdate(), taskUpdate()]);
    vi.setSystemTime(NOW + 5000);
    const page = await ok(0, null, [taskUpdate()]);
    expect(page.entries.map((e) => e.received)).toEqual([NOW, NOW, NOW + 5000]);
  });

  it("a pull appends nothing", async () => {
    await ok(0, null, [opA, opB]);
    const page = await ok(2, HASH_1);
    expect(page).toEqual({ entries: [], head: 2, more: false });
    expect(await rows()).toHaveLength(2);
  });

  it("from = head returns only the new ops", async () => {
    await ok(0, null, [opA, opB]);
    const op = taskUpdate();
    const page = await ok(2, HASH_1, [op]);
    expect(page.entries.map((e) => [e.seq, e.op])).toEqual([[2, op]]);
    expect(page.head).toBe(3);
  });
});

describe("idempotency", () => {
  it("a retried request returns the same body and appends nothing", async () => {
    const body = { from: 0, base: null, ops: [opA, opB] };
    const first = await sync(body);
    vi.setSystemTime(NOW + 60_000);
    const again = await sync(body);
    expect(again).toEqual(first);
    expect(await rows()).toHaveLength(2);
  });

  it("a retry from a later cursor skips the ops already in the log", async () => {
    await ok(0, null, [opA, opB]);
    const op = taskUpdate();
    const page = await ok(2, HASH_1, [opB, op, opA]);
    expect(page.entries.map((e) => [e.seq, e.op.id])).toEqual([[2, op.id]]);
    expectChain(await pullAll());
  });

  it("keeps only the first of duplicate ids in one request", async () => {
    const x = taskUpdate({ title: "first" });
    const y = taskUpdate();
    const page = await ok(0, null, [x, { ...x, set: { title: "second" } }, y, x]);
    expect(page.entries.map((e) => e.op)).toEqual([x, y]);
    expectChain(page.entries);
  });

  it("dedups by id only, even when the content differs", async () => {
    await ok(0, null, [opA]);
    const page = await ok(1, HASH_0, [{ ...opA, set: { name: "Other", order: "b0" } }]);
    expect(page).toEqual({ entries: [], head: 1, more: false });
  });

  it("is case-sensitive about ids", async () => {
    const op = taskUpdate({}, { id: "abc" });
    await ok(0, null, [op, { ...op, id: "ABC" }]);
    expect(await rows()).toHaveLength(2);
  });
});

describe("409 log_mismatch", () => {
  it("from past head", async () => {
    await ok(0, null, [opA, opB]);
    const res = await sync({ from: 3, base: HASH_1, ops: [taskUpdate()] });
    expect(res).toEqual({ status: 409, body: { error: "log_mismatch", message: "from 3 is past head 2." } });
    expect(await rows()).toHaveLength(2);
  });

  it("from past head of an empty log", async () => {
    const res = await sync({ from: 1, base: HASH_0, ops: [] });
    expect(res).toEqual({ status: 409, body: { error: "log_mismatch", message: "from 1 is past head 0." } });
  });

  it("base mismatch at head (the cached hash)", async () => {
    await ok(0, null, [opA, opB]);
    const res = await sync({ from: 2, base: HASH_0, ops: [taskUpdate()] });
    expect(res).toEqual({ status: 409, body: { error: "log_mismatch", message: "base does not match the log at seq 1." } });
    expect(await rows()).toHaveLength(2);
  });

  it("base mismatch behind head (read from storage)", async () => {
    await ok(0, null, [opA, opB, taskUpdate()]);
    const res = await sync({ from: 2, base: HASH_0, ops: [] });
    expect(res).toEqual({ status: 409, body: { error: "log_mismatch", message: "base does not match the log at seq 1." } });
  });

  it("matching base behind head is fine", async () => {
    const third = taskUpdate();
    await ok(0, null, [opA, opB, third]);
    const page = await ok(1, HASH_0);
    expect(page.entries.map((e) => e.op)).toEqual([opB, third]);
  });

  it("after a restart, the cached hash is reloaded from storage", async () => {
    await ok(0, null, [opA, opB]);
    await evictDurableObject(logStub());
    expect((await sync({ from: 2, base: HASH_0, ops: [] })).status).toBe(409);
    expect((await sync({ from: 2, base: HASH_1, ops: [] })).status).toBe(200);
  });

  it("from 0 never 409s, whatever the log holds", async () => {
    await ok(0, null, [opA, opB]);
    const op = taskUpdate();
    const page = await ok(0, null, [op]);
    expect(page.entries.map((e) => e.op)).toEqual([opA, opB, op]);
  });
});

describe("pagination", () => {
  // 2,345 entries, as in SPEC example 2.
  const ops = [opA, opB, ...Array.from({ length: 2343 }, (_, i) => taskUpdate({ title: `edit ${i + 2}` }))];

  it("pages of 1,000 with more, in seq order", async () => {
    await seed(ops);
    const p1 = await ok(0, null);
    expect(p1.entries).toHaveLength(1000);
    expect(p1).toMatchObject({ head: 2345, more: true });
    expectChain(p1.entries);

    const p2 = await ok(1000, p1.entries[999].hash);
    expect(p2.entries.map((e) => e.seq)).toEqual(Array.from({ length: 1000 }, (_, i) => 1000 + i));
    expect(p2).toMatchObject({ head: 2345, more: true });

    const p3 = await ok(2000, p2.entries[999].hash);
    expect(p3.entries).toHaveLength(345);
    expect(p3).toMatchObject({ head: 2345, more: false });

    const all = [...p1.entries, ...p2.entries, ...p3.entries];
    expect(all.map((e) => e.op)).toEqual(ops);
    expectChain(all);
  });

  it("more is false exactly when the page reaches head", async () => {
    await seed(ops);
    const log = await pullAll();
    const at = (from: number) => ok(from, log[from - 1].hash);
    expect(await at(1344)).toMatchObject({ more: true, head: 2345 });
    expect((await at(1345)).entries).toHaveLength(1000);
    expect(await at(1345)).toMatchObject({ more: false });
    expect(await at(2345)).toEqual({ entries: [], head: 2345, more: false });
  });

  it("a push from far behind lands at head, beyond the page", async () => {
    await seed(ops);
    const mine = [taskUpdate(), taskUpdate()];
    const p1 = await ok(0, null, mine);
    expect(p1).toMatchObject({ head: 2347, more: true });
    expect(p1.entries).toHaveLength(1000);
    const log = await pullAll();
    expect(log.slice(-2).map((e) => [e.seq, e.op])).toEqual([[2345, mine[0]], [2346, mine[1]]]);
    expectChain(log);
  });

  it("an empty log", async () => {
    expect(await ok(0, null)).toEqual({ entries: [], head: 0, more: false });
  });
});
