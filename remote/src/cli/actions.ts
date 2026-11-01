// The user's actions as ops, on a fork: a port of TasksCore/Store+Actions.swift. A run builds its change on a Fork
// (a second projection over the replica's state); the ops it queues are the change (docs/SDK-PLAN.md §4 "Forks").

import type { CalendarDate } from "../core/calendar-date.ts";
import { HEADING, pendingOf, type EntityID, type Op, type Patch } from "../core/op.ts";
import { Ordering, type Anchor } from "../core/ordering.ts";
import type { Projection } from "../core/projection.ts";
import { clamp } from "./text.ts";

export const MAX_TITLE = 1_000;
export const MAX_NOTES = 20_000;
export const MAX_NAME = 200;

export interface Clock {
  /** Epoch ms. */
  now(): number;
  /** A lowercase UUID string. */
  newID(): string;
}

export class Fork {
  /** The ops this fork queued, oldest first. */
  readonly made: Op[] = [];

  constructor(readonly projection: Projection, readonly clock: Clock) {}

  /** Applies ops to the fork's projection and queues them. False if there were none. */
  perform(ops: Op[]): boolean {
    if (ops.length === 0) return false;
    this.projection.perform(ops.map(pendingOf));
    this.made.push(...ops);
    return true;
  }

  private get p() {
    return this.projection;
  }

  newID(): string {
    return this.clock.newID();
  }

  /** New tasks created outside a list go to the first active list in sidebar order. */
  get defaultListID(): EntityID | undefined {
    return this.p.activeLists()[0];
  }

  private taskOp(id: EntityID, set: Patch): Op {
    return { id: this.newID(), at: this.clock.now(), type: "task.update", target: id, set };
  }

  private listOp(id: EntityID, set: Patch): Op {
    return { id: this.newID(), at: this.clock.now(), type: "list.update", target: id, set };
  }

  // MARK: Tasks

  createTask(o: { id?: EntityID; title: string; notes?: string; list?: EntityID; anchor?: Anchor; when?: CalendarDate | null; deadline?: CalendarDate | null }): EntityID | null {
    return this.create(o.id, o.title, o.notes ?? "", o.list, o.anchor ?? "bottom", undefined, o.when ?? null, o.deadline ?? null);
  }

  createHeading(o: { id?: EntityID; title: string; notes?: string; list: EntityID; anchor?: Anchor }): EntityID | null {
    return this.create(o.id, o.title, o.notes ?? "", o.list, o.anchor ?? "bottom", HEADING, null, null);
  }

  private create(id: EntityID | undefined, title: string, notes: string, list: EntityID | undefined, anchor: Anchor,
                 kind: string | undefined, when: CalendarDate | null, deadline: CalendarDate | null): EntityID | null {
    const listID = list ?? this.defaultListID;
    if (listID === undefined) return null;
    const taskID = id ?? this.newID();
    const keys = Ordering.place([taskID], anchor, this.p.orderedOpenTasks(listID));
    const ops = keys.filter((k) => k.id !== taskID).map((k) => this.taskOp(k.id, { list: listID, order: k.order }));
    const set: Patch = { list: listID, order: keys.find((k) => k.id === taskID)!.order, title: clamp(title, MAX_TITLE), notes: clamp(notes, MAX_NOTES) };
    if (when !== null) set.when = when;
    if (deadline !== null) set.deadline = deadline;
    if (kind !== undefined) set.kind = kind;
    ops.push({ id: this.newID(), at: this.clock.now(), type: "task.create", target: taskID, set });
    this.perform(ops);
    return taskID;
  }

  setTitle(id: EntityID, title: string): boolean {
    const t = this.p.task(id);
    const v = clamp(title, MAX_TITLE);
    if (!t || t.title === v) return false;
    return this.perform([this.taskOp(id, { title: v })]);
  }

  setNotes(id: EntityID, notes: string): boolean {
    const t = this.p.task(id);
    const v = clamp(notes, MAX_NOTES);
    if (!t || t.notes === v) return false;
    return this.perform([this.taskOp(id, { notes: v })]);
  }

  setWhen(ids: EntityID[], date: CalendarDate | null): boolean {
    const ops = ids.filter((id) => {
      const t = this.p.task(id);
      return t !== undefined && !t.isHeading && t.when !== date;
    }).map((id) => this.taskOp(id, { when: date }));
    return this.perform(ops);
  }

  setDeadline(ids: EntityID[], date: CalendarDate | null): boolean {
    const ops = ids.filter((id) => {
      const t = this.p.task(id);
      return t !== undefined && !t.isHeading && t.deadline !== date;
    }).map((id) => this.taskOp(id, { deadline: date }));
    return this.perform(ops);
  }

  /** Checks or unchecks; headings are skipped. Completing doesn't touch `order`. */
  toggleComplete(ids: EntityID[]): boolean {
    const tasks = ids.map((id) => this.p.task(id)).filter((t) => t !== undefined && !t.isHeading).map((t) => t!);
    const complete = tasks.some((t) => t.completedAt === null);
    const now = this.clock.now();
    const ops = tasks.filter((t) => (t.completedAt === null) === complete).map((t) => this.taskOp(t.id, { completedAt: complete ? now : null }));
    return this.perform(ops);
  }

  delete(ids: EntityID[]): boolean {
    const ops = ids.filter((id) => this.p.task(id)?.deleted === false).map((id) => this.taskOp(id, { deleted: true }));
    return this.perform(ops);
  }

  /** "Move to…": the tasks land at the bottom of `list`, in the given order. Headings stay in their list. */
  move(ids: EntityID[], list: EntityID): boolean {
    const moving = ids.filter((id) => {
      const t = this.p.task(id);
      return t !== undefined && !t.isHeading && t.list !== list;
    });
    if (moving.length === 0) return false;
    const placed = Ordering.append(moving, this.p.orderedOpenTasks(list));
    return this.perform(placed.map((k) => this.taskOp(k.id, { list, order: k.order })));
  }

  /** A drag within a list: `list` and `order` together, plus any re-keyed neighbours. */
  reorder(ids: EntityID[], list: EntityID, anchor: Anchor): boolean {
    if (ids.length === 0) return false;
    const placed = Ordering.place(ids, anchor, this.p.orderedOpenTasks(list));
    const ops = placed.filter((k) => {
      const t = this.p.task(k.id);
      return t !== undefined && (t.order !== k.order || t.list !== list);
    }).map((k) => this.taskOp(k.id, { list, order: k.order }));
    return this.perform(ops);
  }

  /** Moves a heading with its section: the heading and every task under it, completed ones included. */
  moveSection(heading: EntityID, anchor: Anchor): boolean {
    const h = this.p.task(heading);
    if (!h || !h.isHeading || h.deleted) return false;
    const section = this.p.section(heading);
    const placed = Ordering.place(section, anchor, this.p.orderedTasksIncludingCompleted(h.list));
    const ops = placed.filter((k) => {
      const t = this.p.task(k.id);
      return t !== undefined && (t.order !== k.order || t.list !== h.list);
    }).map((k) => this.taskOp(k.id, { list: h.list, order: k.order }));
    return this.perform(ops);
  }

  // MARK: Lists

  createList(name: string, id?: EntityID): EntityID {
    const listID = id ?? this.newID();
    const order = Ordering.append([listID], this.p.orderedActiveLists()).find((k) => k.id === listID)!.order;
    this.perform([{ id: this.newID(), at: this.clock.now(), type: "list.create", target: listID, set: { order, name: clamp(name, MAX_NAME) } }]);
    return listID;
  }

  renameList(id: EntityID, name: string): boolean {
    const v = clamp(name, MAX_NAME);
    const l = this.p.list(id);
    if (!l || l.name === v) return false;
    return this.perform([this.listOp(id, { name: v })]);
  }

  setListNotes(id: EntityID, notes: string): boolean {
    const v = clamp(notes, MAX_NOTES);
    const l = this.p.list(id);
    if (!l || l.notes === v) return false;
    return this.perform([this.listOp(id, { notes: v })]);
  }

  /** "Delete list" is archiving: one op; its tasks are untouched. */
  archive(id: EntityID): boolean {
    if ((this.p.list(id)?.archivedAt ?? null) !== null) return false;
    return this.perform([this.listOp(id, { archivedAt: this.clock.now() })]);
  }

  /** Back to its old sidebar spot, by its old key. */
  unarchive(id: EntityID): boolean {
    if ((this.p.list(id)?.archivedAt ?? null) === null) return false;
    return this.perform([this.listOp(id, { archivedAt: null })]);
  }

  reorderLists(ids: EntityID[], anchor: Anchor): boolean {
    const placed = Ordering.place(ids, anchor, this.p.orderedActiveLists());
    const ops = placed.filter((k) => {
      const l = this.p.list(k.id);
      return l !== undefined && l.order !== k.order;
    }).map((k) => this.listOp(k.id, { order: k.order }));
    return this.perform(ops);
  }
}
