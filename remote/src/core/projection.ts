// Visible state = confirmed state + pending ops, and the views read from it: a port of TasksCore/Projection.swift.
// The app keeps incremental buckets and observable models for SwiftUI; a replica answering one request at a time
// only needs the same answers, so the views are computed from scratch when asked and cached until the next change.

import { datesArrived, dayContains, type Day } from "./day.ts";
import { isListOp, isTaskOp, type EntityID, type Op, type PendingOp } from "./op.ts";
import { orderPrecedes, type OrderedItem } from "./ordering.ts";
import { AppState, applyToList, applyToTask, type TaskItem, type TaskList } from "./state.ts";

/** A position in a view: by `order` (manual), or by a time (completedAt, archivedAt), ties by id. */
interface SortKey {
  order: string;
  time: number;
  id: EntityID;
}

const manual = (order: string, id: EntityID): SortKey => ({ order, time: 0, id });
const ascending = (time: number, id: EntityID): SortKey => ({ order: "", time, id });
const descending = (time: number, id: EntityID): SortKey => ({ order: "", time: -time, id });

function compareKeys(a: SortKey, b: SortKey): number {
  if (a.time !== b.time) return a.time < b.time ? -1 : 1;
  if (orderPrecedes(a.order, a.id, b.order, b.id)) return -1;
  if (orderPrecedes(b.order, b.id, a.order, a.id)) return 1;
  return 0;
}

const sorted = (keys: SortKey[]) => keys.sort(compareKeys);

interface Index {
  open: Map<EntityID, SortKey[]>;
  headings: Map<EntityID, SortKey[]>;
  completed: Map<EntityID, SortKey[]>;
  today: Map<EntityID, SortKey[]>;
  todayDone: SortKey[];
  activeLists: SortKey[];
  archivedLists: SortKey[];
}

export class Projection {
  /** The state reduced from the log `[0, cursor)`. */
  confirmed: AppState;
  /** Local ops not yet seen in the log, oldest first, each with its verbatim JSON. */
  pending: PendingOp[];
  day: Day;

  private taskOverlay = new Map<EntityID, TaskItem>();
  private listOverlay = new Map<EntityID, TaskList>();
  private index: Index | null = null;

  constructor(confirmed: AppState, pending: PendingOp[], day: Day) {
    this.confirmed = confirmed;
    this.pending = [...pending];
    this.day = day;
    this.rebuildOverlay();
  }

  // MARK: Reading

  task(id: EntityID): TaskItem | undefined {
    return this.taskOverlay.get(id) ?? this.confirmed.tasks.get(id);
  }

  list(id: EntityID): TaskList | undefined {
    return this.listOverlay.get(id) ?? this.confirmed.lists.get(id);
  }

  allTaskIDs(): Set<EntityID> {
    return new Set([...this.confirmed.tasks.keys(), ...this.taskOverlay.keys()]);
  }

  allListIDs(): Set<EntityID> {
    return new Set([...this.confirmed.lists.keys(), ...this.listOverlay.keys()]);
  }

  isActive(list: EntityID): boolean {
    const l = this.list(list);
    return l !== undefined && l.archivedAt === null;
  }

  /** The list's rows in order: its open tasks and its headings. */
  openTasks(list: EntityID): EntityID[] {
    return ids(this.idx().open.get(list));
  }

  headings(list: EntityID): EntityID[] {
    return ids(this.idx().headings.get(list));
  }

  /** Open tasks, headings not counted. */
  openTaskCount(list: EntityID): number {
    return this.openTasks(list).length - this.headings(list).length;
  }

  /** Completed tasks, newest first. */
  completedTasks(list: EntityID): EntityID[] {
    return ids(this.idx().completed.get(list));
  }

  /** Open tasks of the list that match the Today predicate's date half, in order. */
  todayTasks(list: EntityID): EntityID[] {
    return ids(this.idx().today.get(list));
  }

  /** Tasks completed today that match Today, by completedAt. */
  todayDone(): EntityID[] {
    return ids(this.idx().todayDone);
  }

  /** Active lists in sidebar order. */
  activeLists(): EntityID[] {
    return ids(this.idx().activeLists);
  }

  /** Archived lists, most recently archived first. */
  archivedLists(): EntityID[] {
    return ids(this.idx().archivedLists);
  }

  orderedActiveLists(): OrderedItem[] {
    return this.idx().activeLists.map((k) => ({ id: k.id, order: k.order }));
  }

  /** The open tasks of a list with their keys, for computing new keys. */
  orderedOpenTasks(list: EntityID): OrderedItem[] {
    return (this.idx().open.get(list) ?? []).map((k) => ({ id: k.id, order: k.order }));
  }

  /** Every non-deleted task of a list, open and completed, by (order, id): a completed task keeps its place. */
  orderedTasksIncludingCompleted(list: EntityID): OrderedItem[] {
    const keys = [...(this.idx().open.get(list) ?? [])];
    for (const k of this.idx().completed.get(list) ?? []) {
      const t = this.task(k.id);
      if (t) keys.push(manual(t.order, t.id));
    }
    sorted(keys);
    return keys.map((k) => ({ id: k.id, order: k.order }));
  }

  /** A heading and the tasks under it, down to the next heading, completed ones included, in order. */
  section(heading: EntityID): EntityID[] {
    const h = this.task(heading);
    if (!h || !h.isHeading || h.deleted) return [];
    const all = this.orderedTasksIncludingCompleted(h.list);
    const i = all.findIndex((x) => x.id === heading);
    if (i < 0) return [heading];
    const out = [heading];
    for (const item of all.slice(i + 1)) {
      if (this.task(item.id)?.isHeading === true) break;
      out.push(item.id);
    }
    return out;
  }

  /** The heading a task sits under in its list, null before the first one. */
  headingOf(id: EntityID): EntityID | null {
    const t = this.task(id);
    if (!t || t.isHeading) return null;
    const key = manual(t.order, t.id);
    const hs = this.idx().headings.get(t.list) ?? [];
    let found: EntityID | null = null;
    for (const h of hs) if (compareKeys(h, key) < 0) found = h.id;
    return found;
  }

  // MARK: Local ops

  perform(ops: PendingOp[]): void {
    for (const p of ops) {
      this.pending.push(p);
      this.applyToOverlay(p.op);
    }
    this.index = null;
  }

  /** A page of log entries: to confirmed, then our confirmed ops leave pending (by id), then visible is rebuilt. */
  confirm(ops: Op[]): void {
    if (ops.length === 0) return;
    for (const op of ops) this.confirmed.apply(op);
    const ids = new Set(ops.map((o) => o.id));
    if (this.pending.some((p) => ids.has(p.op.id))) this.pending = this.pending.filter((p) => !ids.has(p.op.id));
    this.rebuildOverlay();
  }

  /** `invalid_op`: drops the op from pending and rebuilds visible state. */
  reject(opID: string): PendingOp | null {
    const i = this.pending.findIndex((p) => p.op.id === opID);
    if (i < 0) return null;
    const [p] = this.pending.splice(i, 1);
    this.rebuildOverlay();
    return p;
  }

  /** 409 recovery: confirmed restarts empty and every known op becomes pending. */
  recover(queue: PendingOp[]): void {
    this.confirmed = new AppState();
    this.pending = [...queue];
    this.rebuildOverlay();
  }

  setDay(day: Day): void {
    if (day.date === this.day.date && day.start === this.day.start && day.end === this.day.end) return;
    this.day = day;
    this.index = null;
  }

  // MARK: Internals

  private applyToOverlay(op: Op): void {
    if (isTaskOp(op.type)) {
      const r = applyToTask(op, this.task(op.target));
      if (r.applied) this.taskOverlay.set(op.target, r.task!);
    } else if (isListOp(op.type)) {
      const r = applyToList(op, this.list(op.target));
      if (r.applied) this.listOverlay.set(op.target, r.list!);
    }
  }

  private rebuildOverlay(): void {
    this.taskOverlay = new Map();
    this.listOverlay = new Map();
    for (const p of this.pending) this.applyToOverlay(p.op);
    this.index = null;
  }

  private idx(): Index {
    if (this.index) return this.index;
    const day = this.day;
    const index: Index = {
      open: new Map(), headings: new Map(), completed: new Map(), today: new Map(),
      todayDone: [], activeLists: [], archivedLists: [],
    };
    const push = (m: Map<EntityID, SortKey[]>, list: EntityID, k: SortKey) => {
      const a = m.get(list);
      if (a) a.push(k);
      else m.set(list, [k]);
    };
    for (const id of this.allListIDs()) {
      const l = this.list(id);
      if (!l) continue;
      if (l.archivedAt !== null) index.archivedLists.push(descending(l.archivedAt, l.id));
      else index.activeLists.push(manual(l.order, l.id));
    }
    for (const id of this.allTaskIDs()) {
      const t = this.task(id);
      if (!t || t.deleted) continue;
      // A heading is always a row in its list's order, whatever another client wrote on it.
      if (t.isHeading) {
        const k = manual(t.order, t.id);
        push(index.open, t.list, k);
        push(index.headings, t.list, k);
      } else if (t.completedAt !== null) {
        push(index.completed, t.list, descending(t.completedAt, t.id));
        if (dayContains(day, t.completedAt) && datesArrived(t, day.date) && this.isActive(t.list)) {
          index.todayDone.push(ascending(t.completedAt, t.id));
        }
      } else {
        const k = manual(t.order, t.id);
        push(index.open, t.list, k);
        if (datesArrived(t, day.date)) push(index.today, t.list, k);
      }
    }
    for (const m of [index.open, index.headings, index.completed, index.today]) for (const a of m.values()) sorted(a);
    sorted(index.todayDone);
    sorted(index.activeLists);
    sorted(index.archivedLists);
    this.index = index;
    return index;
  }
}

const ids = (keys: SortKey[] | undefined): EntityID[] => (keys ?? []).map((k) => k.id);
