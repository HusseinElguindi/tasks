// Entities, the reducer and inverse ops: a port of TasksCore/AppState.swift (spec §5, "the whole conflict model").

import type { CalendarDate } from "./calendar-date.ts";
import { HEADING, type EntityID, type Op, type Patch } from "./op.ts";

export interface TaskItem {
  id: EntityID;
  list: EntityID;
  /** Fractional index key within its list. */
  order: string;
  title: string;
  /** Markdown. */
  notes: string;
  /** Set by `task.create`'s `kind: "heading"` and never changed. */
  isHeading: boolean;
  when: CalendarDate | null;
  deadline: CalendarDate | null;
  /** Epoch ms; null = open. */
  completedAt: number | null;
  deleted: boolean;
  /** The `at` of the first and last op that touched the task. */
  createdAt: number;
  updatedAt: number;
}

export interface TaskList {
  id: EntityID;
  name: string;
  order: string;
  notes: string;
  /** Epoch ms; null = active. */
  archivedAt: number | null;
  createdAt: number;
  updatedAt: number;
}

/** `task.create`: `list` and `order` are required; only create keys are read. */
export function taskCreating(op: Op): TaskItem | null {
  const s = op.set;
  if (s.list === undefined || s.order === undefined) return null;
  return {
    id: op.target,
    list: s.list,
    order: s.order,
    title: s.title ?? "",
    notes: s.notes ?? "",
    isHeading: s.kind === HEADING,
    when: s.when ?? null,
    deadline: s.deadline ?? null,
    completedAt: s.completedAt ?? null,
    deleted: false,
    createdAt: op.at,
    updatedAt: op.at,
  };
}

export function listCreating(op: Op): TaskList | null {
  const s = op.set;
  if (s.name === undefined || s.order === undefined) return null;
  return { id: op.target, name: s.name, order: s.order, notes: s.notes ?? "", archivedAt: null, createdAt: op.at, updatedAt: op.at };
}

/** `task.update`: each present key overwrites (rule 2). Returns a new object. */
export function taskUpdated(t: TaskItem, p: Patch, at: number): TaskItem {
  const n = { ...t };
  if (p.list !== undefined) n.list = p.list;
  if (p.order !== undefined) n.order = p.order;
  if (p.title !== undefined) n.title = p.title;
  if (p.notes !== undefined) n.notes = p.notes;
  if (p.when !== undefined) n.when = p.when;
  if (p.deadline !== undefined) n.deadline = p.deadline;
  if (p.completedAt !== undefined) n.completedAt = p.completedAt;
  if (p.deleted !== undefined) n.deleted = p.deleted;
  n.updatedAt = at;
  return n;
}

export function listUpdated(l: TaskList, p: Patch, at: number): TaskList {
  const n = { ...l };
  if (p.name !== undefined) n.name = p.name;
  if (p.order !== undefined) n.order = p.order;
  if (p.notes !== undefined) n.notes = p.notes;
  if (p.archivedAt !== undefined) n.archivedAt = p.archivedAt;
  n.updatedAt = at;
  return n;
}

/** `Reducer.apply` for a task slot: the entity after `op`, and whether the op took effect. */
export function applyToTask(op: Op, task: TaskItem | undefined): { task: TaskItem | undefined; applied: boolean } {
  if (op.type === "task.create") {
    // Rule 1: a create on an id that already exists (live or deleted) is ignored.
    if (task !== undefined) return { task, applied: false };
    const created = taskCreating(op);
    return created ? { task: created, applied: true } : { task, applied: false };
  }
  if (op.type === "task.update") {
    // Rule 3: an update on an unknown id is ignored.
    if (task === undefined) return { task, applied: false };
    return { task: taskUpdated(task, op.set, op.at), applied: true };
  }
  return { task, applied: false };
}

export function applyToList(op: Op, list: TaskList | undefined): { list: TaskList | undefined; applied: boolean } {
  if (op.type === "list.create") {
    if (list !== undefined) return { list, applied: false };
    const created = listCreating(op);
    return created ? { list: created, applied: true } : { list, applied: false };
  }
  if (op.type === "list.update") {
    if (list === undefined) return { list, applied: false };
    return { list: listUpdated(list, op.set, op.at), applied: true };
  }
  return { list, applied: false };
}

/** The confirmed state: every task and list reduced from the log, deleted and archived ones included. */
export class AppState {
  tasks = new Map<EntityID, TaskItem>();
  lists = new Map<EntityID, TaskList>();

  clone(): AppState {
    const s = new AppState();
    s.tasks = new Map(this.tasks);
    s.lists = new Map(this.lists);
    return s;
  }

  /** The reducer. Returns the id it changed, null if the op was ignored. */
  apply(op: Op): EntityID | null {
    switch (op.type) {
      case "task.create":
      case "task.update": {
        const r = applyToTask(op, this.tasks.get(op.target));
        if (!r.applied) return null;
        this.tasks.set(op.target, r.task!);
        return op.target;
      }
      case "list.create":
      case "list.update": {
        const r = applyToList(op, this.lists.get(op.target));
        if (!r.applied) return null;
        this.lists.set(op.target, r.list!);
        return op.target;
      }
      default:
        return null;
    }
  }

  static replay(ops: Iterable<Op>): AppState {
    const s = new AppState();
    for (const op of ops) s.apply(op);
    return s;
  }
}

/** Inverse ops (undo as `git revert`). */
export const Inverse = {
  /** The op that undoes `op` given the visible task before it, or null if `op` would have no effect. */
  ofTask(op: Op, before: TaskItem | undefined, id: string, at: number): Op | null {
    if (op.type === "task.create") {
      if (before !== undefined || taskCreating(op) === null) return null;
      return { id, at, type: "task.update", target: op.target, set: { deleted: true } };
    }
    if (op.type === "task.update") {
      if (before === undefined) return null;
      const s = op.set;
      const p: Patch = {};
      if (s.list !== undefined) p.list = before.list;
      if (s.order !== undefined) p.order = before.order;
      if (s.title !== undefined) p.title = before.title;
      if (s.notes !== undefined) p.notes = before.notes;
      if (s.when !== undefined) p.when = before.when;
      if (s.deadline !== undefined) p.deadline = before.deadline;
      if (s.completedAt !== undefined) p.completedAt = before.completedAt;
      if (s.deleted !== undefined) p.deleted = before.deleted;
      return { id, at, type: "task.update", target: op.target, set: p };
    }
    return null;
  },

  /** Undoing a list create archives it: lists are never deleted. */
  ofList(op: Op, before: TaskList | undefined, id: string, at: number): Op | null {
    if (op.type === "list.create") {
      if (before !== undefined || listCreating(op) === null) return null;
      return { id, at, type: "list.update", target: op.target, set: { archivedAt: at } };
    }
    if (op.type === "list.update") {
      if (before === undefined) return null;
      const s = op.set;
      const p: Patch = {};
      if (s.name !== undefined) p.name = before.name;
      if (s.order !== undefined) p.order = before.order;
      if (s.notes !== undefined) p.notes = before.notes;
      if (s.archivedAt !== undefined) p.archivedAt = before.archivedAt;
      return { id, at, type: "list.update", target: op.target, set: p };
    }
    return null;
  },
};
