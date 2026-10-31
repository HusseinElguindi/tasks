// S2: parsing and validation (SPEC §5 "Request"): 400 bad_request, 400 invalid_op, 413.
import { describe, expect, it } from "vitest";
import { listCreate, listUpdate, ok, post, pullAll, sync, taskCreate, taskUpdate, type Op } from "./helpers";

const omit = (op: Op, key: string) => Object.fromEntries(Object.entries(op).filter(([k]) => k !== key));
const withSet = (op: Op, set: Record<string, unknown>) => ({ ...op, set });
const s = (n: number) => "x".repeat(n);
const HASH = "a".repeat(64);

describe("400 bad_request", () => {
  it.each([
    ["empty body", ""],
    ["not JSON", "{from: 0}"],
    ["truncated JSON", '{"from":0,"base":null,"ops":['],
    ["trailing garbage", '{"from":0,"base":null,"ops":[]} x'],
  ])("%s", async (_, raw) => {
    const res = await post(raw);
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: "bad_request", message: "Body is not valid JSON." });
  });

  it("invalid UTF-8", async () => {
    const bytes = new Uint8Array([...new TextEncoder().encode('{"from":0,"base":null,"ops":[],"x":"'), 0xff, 0x22, 0x7d]);
    const res = await post(bytes);
    expect(res.status).toBe(400);
    expect(await res.json()).toMatchObject({ error: "bad_request", message: "Body is not valid UTF-8." });
  });

  it.each([
    ["body is an array", []],
    ["body is null", null],
    ["body is a string", "hi"],
    ["body is a number", 1],
    ["from missing", { base: null, ops: [] }],
    ["from negative", { from: -1, base: null, ops: [] }],
    ["from fractional", { from: 0.5, base: null, ops: [] }],
    ["from a string", { from: "0", base: null, ops: [] }],
    ["from null", { from: null, base: null, ops: [] }],
    ["from beyond 2^53", { from: 2 ** 53, base: HASH, ops: [] }],
    ["base missing", { from: 0, ops: [] }],
    ["base a number", { from: 1, base: 1, ops: [] }],
    ["base uppercase hex", { from: 1, base: "A".repeat(64), ops: [] }],
    ["base 63 chars", { from: 1, base: "a".repeat(63), ops: [] }],
    ["base 65 chars", { from: 1, base: "a".repeat(65), ops: [] }],
    ["base not hex", { from: 1, base: "g".repeat(64), ops: [] }],
    ["base null with from > 0", { from: 1, base: null, ops: [] }],
    ["base set with from = 0", { from: 0, base: HASH, ops: [] }],
    ["ops missing", { from: 0, base: null }],
    ["ops null", { from: 0, base: null, ops: null }],
    ["ops an object", { from: 0, base: null, ops: {} }],
    ["ops a string", { from: 0, base: null, ops: "[]" }],
  ])("%s", async (_, body) => {
    const res = await sync(body);
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("bad_request");
    expect(Object.keys(res.body)).toEqual(["error", "message"]);
  });

  it("ignores unknown top-level keys", async () => {
    expect((await sync({ from: 0, base: null, ops: [], extra: 1 })).status).toBe(200);
  });
});

describe("400 invalid_op", () => {
  const tc = taskCreate();
  const tu = taskUpdate();
  const lc = listCreate();
  const lu = listUpdate();

  // [case, bad op, field]
  const cases: [string, unknown, string][] = [
    ["op is a string", "op", "op"],
    ["op is null", null, "op"],
    ["op is an array", [], "op"],
    ["id missing", omit(tu, "id"), "id"],
    ["id empty", { ...tu, id: "" }, "id"],
    ["id 65 chars", { ...tu, id: s(65) }, "id"],
    ["id a number", { ...tu, id: 1 }, "id"],
    ["id a lone surrogate", { ...tu, id: "a\ud800" }, "id"],
    ["at missing", omit(tu, "at"), "at"],
    ["at negative", { ...tu, at: -1 }, "at"],
    ["at fractional", { ...tu, at: 1.5 }, "at"],
    ["at a string", { ...tu, at: "1" }, "at"],
    ["at null", { ...tu, at: null }, "at"],
    ["at beyond 2^53", { ...tu, at: 2 ** 53 }, "at"],
    ["type missing", omit(tu, "type"), "type"],
    ["type unknown", { ...tu, type: "task.delete" }, "type"],
    ["type wrong case", { ...tu, type: "Task.Update" }, "type"],
    ["type an Object.prototype key", { ...tu, type: "toString" }, "type"],
    ["target missing", omit(tu, "target"), "target"],
    ["target empty", { ...tu, target: "" }, "target"],
    ["target 65 chars", { ...tu, target: s(65) }, "target"],
    ["set missing", omit(tu, "set"), "set"],
    ["set null", { ...tu, set: null }, "set"],
    ["set an array", { ...tu, set: [] }, "set"],
    ["set a string", { ...tu, set: "{}" }, "set"],
    ["unknown envelope key", { ...tu, seq: 3 }, "seq"],
    ["unknown envelope key next to actor", { ...tu, actor: "cli", seq: 3 }, "seq"],
    ["actor empty", { ...tu, actor: "" }, "actor"],
    ["actor 65 chars", { ...tu, actor: s(65) }, "actor"],
    ["actor null", { ...tu, actor: null }, "actor"],
    ["actor a number", { ...tu, actor: 1 }, "actor"],
    ["actor a lone surrogate", { ...tu, actor: "agent:\ud800" }, "actor"],
    ["batch empty", { ...tu, batch: "" }, "batch"],
    ["batch 65 chars", { ...tu, batch: s(65) }, "batch"],
    ["batch null", { ...tu, batch: null }, "batch"],
    ["batch an object", { ...tu, batch: {} }, "batch"],

    // Keys allowed per type.
    ["unknown set key", withSet(tu, { color: "red" }), "set.color"],
    ["__proto__ set key", { ...tu, set: JSON.parse('{"__proto__":{}}') }, "set.__proto__"],
    ["deleted on task.create", withSet(tc, { ...tc.set, deleted: true }), "set.deleted"],
    ["name on task.update", withSet(tu, { name: "n" }), "set.name"],
    ["archivedAt on task.update", withSet(tu, { archivedAt: 1 }), "set.archivedAt"],
    ["title on list.create", withSet(lc, { ...lc.set, title: "t" }), "set.title"],
    ["archivedAt on list.create", withSet(lc, { ...lc.set, archivedAt: 1 }), "set.archivedAt"],
    ["list on list.update", withSet(lu, { list: "x" }), "set.list"],
    ["deleted on list.update", withSet(lu, { deleted: true }), "set.deleted"],
    ["kind on task.update (set once, at create)", withSet(tu, { kind: "heading" }), "set.kind"],
    ["kind on list.create", withSet(lc, { ...lc.set, kind: "heading" }), "set.kind"],
    ["kind on list.update", withSet(lu, { kind: "heading" }), "set.kind"],
    ["notes on list.update next to an unknown key", withSet(lu, { notes: "n", color: "red" }), "set.color"],

    // Required keys on creates.
    ["task.create without list", withSet(tc, { order: "a0" }), "set.list"],
    ["task.create without order", withSet(tc, { list: "l" }), "set.order"],
    ["list.create without name", withSet(lc, { order: "a0" }), "set.name"],
    ["list.create without order", withSet(lc, { name: "n" }), "set.order"],

    // Values.
    ["list empty", withSet(tu, { list: "" }), "set.list"],
    ["list 65 chars", withSet(tu, { list: s(65) }), "set.list"],
    ["list null", withSet(tu, { list: null }), "set.list"],
    ["order empty", withSet(tu, { order: "" }), "set.order"],
    ["order with a space", withSet(tu, { order: "a 0" }), "set.order"],
    ["order with a dash", withSet(tu, { order: "a-0" }), "set.order"],
    ["order non-ASCII", withSet(tu, { order: "aé" }), "set.order"],
    ["order 129 chars", withSet(tu, { order: "a".repeat(129) }), "set.order"],
    ["order a number", withSet(tu, { order: 1 }), "set.order"],
    ["order null", withSet(tu, { order: null }), "set.order"],
    ["order with a trailing newline", withSet(tu, { order: "a0\n" }), "set.order"],
    ["title 1001 chars", withSet(tu, { title: s(1001) }), "set.title"],
    ["title 1001 UTF-16 units", withSet(tu, { title: "😀".repeat(500) + "x" }), "set.title"],
    ["title null", withSet(tu, { title: null }), "set.title"],
    ["title a number", withSet(tu, { title: 1 }), "set.title"],
    ["title a lone surrogate", withSet(tu, { title: "\udc00" }), "set.title"],
    ["notes 20001 chars", withSet(tu, { notes: s(20001) }), "set.notes"],
    ["notes null", withSet(tu, { notes: null }), "set.notes"],
    ["kind another value", withSet(tc, { ...tc.set, kind: "section" }), "set.kind"],
    ["kind wrong case", withSet(tc, { ...tc.set, kind: "Heading" }), "set.kind"],
    ["kind empty", withSet(tc, { ...tc.set, kind: "" }), "set.kind"],
    ["kind null", withSet(tc, { ...tc.set, kind: null }), "set.kind"],
    ["kind true", withSet(tc, { ...tc.set, kind: true }), "set.kind"],
    ["kind an array", withSet(tc, { ...tc.set, kind: ["heading"] }), "set.kind"],
    ["list notes 20001 chars on list.create", withSet(lc, { ...lc.set, notes: s(20001) }), "set.notes"],
    ["list notes 20001 chars on list.update", withSet(lu, { notes: s(20001) }), "set.notes"],
    ["list notes 20001 UTF-16 units", withSet(lu, { notes: "😀".repeat(10000) + "x" }), "set.notes"],
    ["list notes null", withSet(lu, { notes: null }), "set.notes"],
    ["list notes a number", withSet(lu, { notes: 1 }), "set.notes"],
    ["list notes a lone surrogate", withSet(lu, { notes: "a\ud800b" }), "set.notes"],
    ["name 201 chars", withSet(lu, { name: s(201) }), "set.name"],
    ["name null", withSet(lu, { name: null }), "set.name"],
    ["when not a date", withSet(tu, { when: "tomorrow" }), "set.when"],
    ["when with a time", withSet(tu, { when: "2026-10-30T00:00:00Z" }), "set.when"],
    ["when unpadded", withSet(tu, { when: "2026-1-5" }), "set.when"],
    ["when month 13", withSet(tu, { when: "2026-13-01" }), "set.when"],
    ["when month 00", withSet(tu, { when: "2026-00-01" }), "set.when"],
    ["when day 00", withSet(tu, { when: "2026-10-00" }), "set.when"],
    ["when Oct 32", withSet(tu, { when: "2026-10-32" }), "set.when"],
    ["when Nov 31", withSet(tu, { when: "2026-11-31" }), "set.when"],
    ["when Feb 29 in a common year", withSet(tu, { when: "2026-02-29" }), "set.when"],
    ["when Feb 29 in 1900", withSet(tu, { when: "1900-02-29" }), "set.when"],
    ["when a number", withSet(tu, { when: 20261030 }), "set.when"],
    ["when non-ASCII digits", withSet(tu, { when: "٢٠٢٦-10-30" }), "set.when"],
    ["deadline Feb 30", withSet(tu, { deadline: "2028-02-30" }), "set.deadline"],
    ["deadline empty", withSet(tu, { deadline: "" }), "set.deadline"],
    ["completedAt negative", withSet(tu, { completedAt: -1 }), "set.completedAt"],
    ["completedAt fractional", withSet(tu, { completedAt: 1.5 }), "set.completedAt"],
    ["completedAt a string", withSet(tu, { completedAt: "1" }), "set.completedAt"],
    ["completedAt false", withSet(tu, { completedAt: false }), "set.completedAt"],
    ["archivedAt negative", withSet(lu, { archivedAt: -5 }), "set.archivedAt"],
    ["archivedAt a date string", withSet(lu, { archivedAt: "2026-10-30" }), "set.archivedAt"],
    ["deleted null", withSet(tu, { deleted: null }), "set.deleted"],
    ["deleted a number", withSet(tu, { deleted: 1 }), "set.deleted"],
    ["deleted a string", withSet(tu, { deleted: "true" }), "set.deleted"],
  ];

  it.each(cases)("%s", async (_, bad, field) => {
    const res = await sync({ from: 0, base: null, ops: [taskUpdate(), bad, taskUpdate()] });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: "invalid_op", message: expect.stringMatching(/^ops\[1\]/), index: 1, field });
    expect(Object.keys(res.body)).toEqual(["error", "message", "index", "field"]);
    // The whole request is rejected: nothing is appended, not even ops[0].
    expect(await pullAll()).toEqual([]);
  });

  it("reports the first failing op", async () => {
    const res = await sync({ from: 0, base: null, ops: [taskUpdate(), taskUpdate(), { id: "" }, { at: -1 }] });
    expect(res.body).toMatchObject({ index: 2, field: "id" });
  });

  it("checks envelope fields in order id, at, type, target, set, actor, batch, unknown keys, then set keys, then required keys", async () => {
    const first = async (op: unknown) => (await sync({ from: 0, base: null, ops: [op] })).body.field;
    expect(await first({})).toBe("id");
    expect(await first({ id: "x" })).toBe("at");
    expect(await first({ id: "x", at: 0 })).toBe("type");
    expect(await first({ id: "x", at: 0, type: "task.create" })).toBe("target");
    expect(await first({ id: "x", at: 0, type: "task.create", target: "t" })).toBe("set");
    expect(await first({ id: "x", at: 0, type: "task.create", target: "t", set: null, actor: "" })).toBe("set");
    expect(await first({ id: "x", at: 0, type: "task.create", target: "t", set: { title: 1 }, actor: "", batch: "" })).toBe("actor");
    expect(await first({ id: "x", at: 0, type: "task.create", target: "t", set: { title: 1 }, batch: "", seq: 1 })).toBe("batch");
    expect(await first({ id: "x", at: 0, type: "task.create", target: "t", set: { title: 1 }, seq: 1 })).toBe("seq");
    expect(await first({ id: "x", at: 0, type: "task.create", target: "t", set: { title: 1, bad: 1 } })).toBe("set.title");
    expect(await first({ id: "x", at: 0, type: "task.create", target: "t", set: { title: "t" } })).toBe("set.list");
  });

  it("formats the message as in SPEC example 3", async () => {
    const res = await sync({ from: 0, base: null, ops: [taskUpdate(), taskUpdate({ order: "a 0" })] });
    expect(res.body.message).toBe("ops[1].set.order must match ^[0-9A-Za-z]{1,128}$");
  });
});

describe("valid ops", () => {
  const accepted: [string, Op][] = [
    ["id and target of 64 chars", taskUpdate({ title: "t" }, { id: s(64), target: s(64) })],
    ["id of 1 char", taskUpdate({ title: "t" }, { id: "x" })],
    ["at 0", taskUpdate({ title: "t" }, { at: 0 })],
    ["at 2^53 - 1", taskUpdate({ title: "t" }, { at: 2 ** 53 - 1 })],
    ["empty set on an update", taskUpdate({})],
    ["update of an unknown id", taskUpdate({ title: "t" }, { target: "nobody" })],
    ["every task.create key", taskCreate({ title: "t", notes: "n", when: "2026-10-30", deadline: null, completedAt: 1 })],
    ["every task.update key", taskUpdate({ list: "l", order: "Zz", title: "", notes: "", when: null, deadline: "2026-12-31", completedAt: null, deleted: false })],
    ["every list.update key", listUpdate({ name: "", order: "a0", notes: "", archivedAt: null })],
    ["a heading: task.create with kind", taskCreate({ title: "Labs", notes: "Mondays, 2:30", kind: "heading" })],
    ["a heading with only list, order and kind", taskCreate({ kind: "heading" })],
    ["list.create with notes", listCreate({ notes: "A course.\n- [ ] read the syllabus" })],
    ["list notes of 20000 chars", listUpdate({ notes: s(20000) })],
    ["list notes of 20000 UTF-16 units", listUpdate({ notes: "😀".repeat(10000) })],
    ["Markdown and emoji in list notes", listUpdate({ notes: "## Exams\n**Dec 14** · PAC 8 😀" })],
    ["list of 64 chars", taskUpdate({ list: s(64) })],
    ["order of all 62 chars", taskUpdate({ order: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz" })],
    ["order of 128 chars", taskUpdate({ order: "z".repeat(128) })],
    ["title of 1000 chars", taskUpdate({ title: s(1000) })],
    ["title of 1000 UTF-16 units", taskUpdate({ title: "😀".repeat(500) })],
    ["notes of 20000 chars", taskUpdate({ notes: s(20000) })],
    ["name of 200 chars", listUpdate({ name: s(200) })],
    ["Feb 29 in a leap year", taskUpdate({ when: "2028-02-29" })],
    ["Feb 29 in 2000", taskUpdate({ deadline: "2000-02-29" })],
    ["Dec 31", taskUpdate({ when: "2026-12-31" })],
    ["year 0001", taskUpdate({ when: "0001-01-01" })],
    ["completedAt 0", taskUpdate({ completedAt: 0 })],
    ["archivedAt", listUpdate({ archivedAt: 1761811200000 })],
    ["deleted true", taskUpdate({ deleted: true })],
    ["Markdown and emoji in notes", taskUpdate({ notes: "**bold** _it_ `code` [l](https://x) 😀\nline 2" })],
  ];

  it.each(accepted)("%s", async (_, op) => {
    const page = await ok(0, null, [op]);
    expect(page.entries.map((e) => e.op)).toEqual([op]);
  });

  it.each([
    ["actor and batch", { actor: "agent:claude-code", batch: "2c1f9e0a-0000-4000-8000-000000000001" }],
    ["actor and batch of 1 and 64 chars", { actor: "a", batch: s(64) }],
    ["actor only", { actor: "cli" }],
    ["batch only", { batch: "b" }],
  ])("%s", async (_, keys) => {
    const op = { ...taskUpdate({ title: "t" }), ...keys };
    const page = await ok(0, null, [op]);
    expect(page.entries.map((e) => e.op)).toEqual([op]);
  });

  it("stores actor and batch after set, in that order, whatever order they're sent in", async () => {
    const op = taskUpdate({ title: "t" });
    const res = await post({ from: 0, base: null, ops: [{ batch: "b1", actor: "cli", ...op }] });
    const text = await res.text();
    const { id, at, type, target, set } = op;
    expect(text).toContain(`"op":${JSON.stringify({ id, at, type, target, set })}`.slice(0, -1) + ',"actor":"cli","batch":"b1"}');
  });
});

describe("413 too_large", () => {
  it("more than 500 ops", async () => {
    const res = await sync({ from: 0, base: null, ops: Array.from({ length: 501 }, () => taskUpdate()) });
    expect(res.status).toBe(413);
    expect(res.body).toEqual({ error: "too_large", message: "At most 500 ops per request; got 501." });
    expect(await pullAll()).toEqual([]);
  });

  it("exactly 500 ops is fine", async () => {
    expect((await ok(0, null, Array.from({ length: 500 }, () => taskUpdate()))).head).toBe(500);
  });

  it("a body over 1 MiB", async () => {
    const body = JSON.stringify({ from: 0, base: null, ops: [] });
    const res = await post(body + " ".repeat((1 << 20) - body.length + 1));
    expect(res.status).toBe(413);
    expect(await res.json()).toMatchObject({ error: "too_large" });
  });

  it("a body of exactly 1 MiB is fine", async () => {
    const body = JSON.stringify({ from: 0, base: null, ops: [] });
    expect((await post(body + " ".repeat((1 << 20) - body.length))).status).toBe(200);
  });

  it("counts bytes, not characters", async () => {
    const body = JSON.stringify({ from: 0, base: null, ops: [], pad: "" });
    const res = await post(body.replace('""', `"${"é".repeat((1 << 19) - 10)}"`)); // ~1 MiB of UTF-8 in 512Ki chars
    expect(res.status).toBe(413);
  });
});
