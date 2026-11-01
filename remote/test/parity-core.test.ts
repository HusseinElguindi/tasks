// The core port against golden files generated from the Swift TasksCore (remote/parity, `swift run golden`).

import { describe, expect, it } from "vitest";
import { daysUntil, offsetDays, parseCalendarDate, weekday } from "../src/core/calendar-date.ts";
import { DatePhrase } from "../src/core/date-phrase.ts";
import { dayContaining } from "../src/core/day.ts";
import { decodeOp, opJSON, pendingFromJSON } from "../src/core/op.ts";
import { Ordering, type Anchor, type OrderedItem } from "../src/core/ordering.ts";
import { Projection } from "../src/core/projection.ts";
import { AppState, Inverse, type TaskItem, type TaskList } from "../src/core/state.ts";
import { decodeEntryLine } from "../src/core/wire.ts";

import { loadGolden as load } from "./golden.ts";
const toObject = <V>(m: Map<string, V>) => Object.fromEntries([...m.entries()].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
const sortKeys = <V>(o: Record<string, V>) => Object.fromEntries(Object.entries(o).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));

interface FoldCase {
  name: string;
  entries: string[];
  pending: string[];
  now: number;
  timeZone: string;
  expect: {
    tasks: Record<string, TaskItem>;
    lists: Record<string, TaskList>;
    visibleTasks: Record<string, TaskItem>;
    visibleLists: Record<string, TaskList>;
    views: {
      day: { date: string; start: number; end: number };
      activeLists: string[];
      archivedLists: string[];
      todayDone: string[];
      lists: Record<string, { open: string[]; headings: string[]; openCount: number; completed: string[]; today: string[]; orderedIncludingCompleted: string[] }>;
      sections: Record<string, string[]>;
      headingOf: Record<string, string | null>;
    };
  };
}

const fold = load<{ cases: FoldCase[] }>("core-fold.json");
describe.skipIf(!fold)("core-fold.json", () => {
  for (const c of fold?.cases ?? []) {
    it(c.name, () => {
      const entries = c.entries.map((l) => decodeEntryLine(l)).filter((e) => e !== null).sort((a, b) => a!.seq - b!.seq);
      const confirmed = AppState.replay(entries.map((e) => e!.op));
      expect(toObject(confirmed.tasks)).toEqual(sortKeys(c.expect.tasks));
      expect(toObject(confirmed.lists)).toEqual(sortKeys(c.expect.lists));
      const pending = c.pending.map(pendingFromJSON).filter((p) => p !== null).map((p) => p!);
      const p = new Projection(confirmed, pending, dayContaining(c.now, c.timeZone));
      const vt = new Map<string, TaskItem>();
      for (const id of p.allTaskIDs()) vt.set(id, p.task(id)!);
      const vl = new Map<string, TaskList>();
      for (const id of p.allListIDs()) vl.set(id, p.list(id)!);
      expect(toObject(vt)).toEqual(sortKeys(c.expect.visibleTasks));
      expect(toObject(vl)).toEqual(sortKeys(c.expect.visibleLists));
      const v = c.expect.views;
      expect(p.day).toEqual(v.day);
      expect(p.activeLists()).toEqual(v.activeLists);
      expect(p.archivedLists()).toEqual(v.archivedLists);
      expect(p.todayDone()).toEqual(v.todayDone);
      for (const [id, want] of Object.entries(v.lists)) {
        expect({
          open: p.openTasks(id), headings: p.headings(id), openCount: p.openTaskCount(id), completed: p.completedTasks(id),
          today: p.todayTasks(id), orderedIncludingCompleted: p.orderedTasksIncludingCompleted(id).map((x) => x.id),
        }, `list ${id}`).toEqual(want);
      }
      for (const [id, want] of Object.entries(v.sections)) expect(p.section(id), `section ${id}`).toEqual(want);
      for (const [id, want] of Object.entries(v.headingOf)) expect(p.headingOf(id), `headingOf ${id}`).toEqual(want);
    });
  }
});

const day = load<{ cases: { now: number; timeZone: string; expect: { date: string; start: number; end: number } }[] }>("day.json");
describe.skipIf(!day)("day.json", () => {
  it("every case", () => {
    for (const c of day?.cases ?? []) expect(dayContaining(c.now, c.timeZone), `${c.timeZone} ${c.now}`).toEqual(c.expect);
  });
});

const cal = load<{ parse: [string, boolean][]; add: [string, number, string][]; until: [string, string, number][]; weekday: [string, number][] }>("calendar-date.json");
describe.skipIf(!cal)("calendar-date.json", () => {
  it("parse", () => { for (const [s, ok] of cal!.parse) expect(parseCalendarDate(s) !== null, JSON.stringify(s)).toBe(ok); });
  it("add", () => { for (const [d, n, want] of cal!.add) expect(offsetDays(d, n), `${d} + ${n}`).toBe(want); });
  it("until", () => { for (const [a, b, n] of cal!.until) expect(daysUntil(a, b), `${a} → ${b}`).toBe(n); });
  it("weekday", () => { for (const [d, n] of cal!.weekday) expect(weekday(d), d).toBe(n); });
});

const phrases = load<{ cases: { text: string; today: string; order: "md" | "dm"; expect: string | null }[] }>("date-phrase.json");
describe.skipIf(!phrases)("date-phrase.json", () => {
  it("every case", () => {
    const wrong: string[] = [];
    for (const c of phrases?.cases ?? []) {
      const got = DatePhrase.match(c.text, c.today, c.order === "dm" ? "dayFirst" : "monthFirst");
      if (got !== c.expect) wrong.push(`${JSON.stringify(c.text)} on ${c.today} (${c.order}): got ${got}, want ${c.expect}`);
    }
    expect(wrong.slice(0, 20)).toEqual([]);
  });
});

const ordering = load<{ cases: { items: OrderedItem[]; moving: string[]; anchor: Anchor; expect: OrderedItem[] }[] }>("ordering.json");
describe.skipIf(!ordering)("ordering.json", () => {
  it("every case", () => {
    for (const [i, c] of (ordering?.cases ?? []).entries()) expect(Ordering.place(c.moving, c.anchor, c.items), `case ${i}`).toEqual(c.expect);
  });
});

const opJSONCases = load<{ cases: { input: string; canonical: string | null }[] }>("op-json.json");
describe.skipIf(!opJSONCases)("op-json.json", () => {
  it("every case", () => {
    for (const c of opJSONCases?.cases ?? []) {
      let raw: unknown;
      try {
        raw = JSON.parse(c.input);
      } catch {
        raw = undefined;
      }
      const op = raw === undefined ? null : decodeOp(raw);
      expect(op === null ? null : opJSON(op), c.input).toBe(c.canonical);
    }
  });
});

const inverse = load<{ cases: { op: string; before: TaskItem | TaskList | null; kind: "task" | "list"; id: string; at: number; expect: string | null }[] }>("inverse.json");
describe.skipIf(!inverse)("inverse.json", () => {
  it("every case", () => {
    for (const c of inverse?.cases ?? []) {
      const op = decodeOp(JSON.parse(c.op))!;
      const before = c.before ?? undefined;
      const got = c.kind === "task" ? Inverse.ofTask(op, before as TaskItem | undefined, c.id, c.at) : Inverse.ofList(op, before as TaskList | undefined, c.id, c.at);
      expect(got === null ? null : opJSON(got), c.op).toBe(c.expect);
    }
  });
});
