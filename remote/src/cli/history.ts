// The log grouped into changes, and the derived ids undo works from: a port of TasksCLI/History.swift
// (docs/SDK-PLAN.md §4 "Review", "Undo for a batch").

import { createHash } from "node:crypto";
import { isListOp, isTaskOp, type EntityID, type Op } from "../core/op.ts";
import { AppState, type TaskItem, type TaskList } from "../core/state.ts";
import type { LogEntry } from "../core/wire.ts";
import { CLIError } from "./errors.ts";
import type { EntityChange } from "./render.ts";
import type { Describe } from "./render.ts";
import { charCount } from "./text.ts";

/** A stable id from a key: a lowercase UUIDv8 from SHA-256 (`add --key`, and undo batch ids). */
export function derivedID(seed: string): string {
  const b = createHash("sha256").update(seed, "utf8").digest().subarray(0, 16);
  b[6] = (b[6] & 0x0f) | 0x80;
  b[8] = (b[8] & 0x3f) | 0x80;
  const hex = Buffer.from(b).toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

export interface Group {
  key: string;
  batch: string | null;
  actor: string;
  /** Server time for confirmed ops, the client's `at` for pending ones. */
  time: number;
  confirmed: boolean;
  ops: Op[];
  /** Touched ids in first-touch order. */
  order: EntityID[];
  /** The entity just before the group first touched it (undefined: it didn't exist). */
  beforeTasks: Map<EntityID, TaskItem | undefined>;
  beforeLists: Map<EntityID, TaskList | undefined>;
  afterTasks: Map<EntityID, TaskItem>;
  afterLists: Map<EntityID, TaskList>;
}

export function groupChanges(g: Group): EntityChange[] {
  const out: EntityChange[] = [];
  for (const id of g.order) {
    const a = g.afterTasks.get(id);
    if (a) {
      out.push({ kind: "task", before: g.beforeTasks.get(id), after: a });
      continue;
    }
    const l = g.afterLists.get(id);
    if (l) out.push({ kind: "list", before: g.beforeLists.get(id), after: l });
  }
  return out;
}

export class History {
  groups: Group[] = [];
  private byKey = new Map<string, number>();
  /** Undo batch id → the batch it undoes. */
  private originals = new Map<string, string>();

  constructor(entries: LogEntry[], pending: Op[]) {
    const state = new AppState();
    let lastKey: string | null = null;
    const items: [Op, number, boolean][] = [
      ...entries.map((e): [Op, number, boolean] => [e.op, e.received, true]),
      ...pending.map((o): [Op, number, boolean] => [o, o.at, false]),
    ];
    for (const [op, time, confirmed] of items) {
      let key: string;
      if (op.batch !== undefined) key = "batch:" + op.batch;
      else if (confirmed) {
        // Contiguous entries received together are one request: one change in the app.
        key = lastKey !== null && lastKey.startsWith(`req:${time}:`) ? lastKey : `req:${time}:${this.groups.length}`;
      } else {
        key = lastKey !== null && lastKey.startsWith("local:") ? lastKey : `local:${this.groups.length}`;
      }
      lastKey = key;
      let gi = this.byKey.get(key);
      if (gi === undefined) {
        gi = this.groups.length;
        this.byKey.set(key, gi);
        this.groups.push({
          key, batch: op.batch ?? null, actor: op.actor ?? "app", time, confirmed, ops: [], order: [],
          beforeTasks: new Map(), beforeLists: new Map(), afterTasks: new Map(), afterLists: new Map(),
        });
      }
      const g = this.groups[gi];
      if (!confirmed) g.confirmed = false;
      const id = op.target;
      if (isTaskOp(op.type)) {
        if (!g.beforeTasks.has(id)) {
          g.beforeTasks.set(id, state.tasks.get(id));
          g.order.push(id);
        }
      } else if (isListOp(op.type)) {
        if (!g.beforeLists.has(id)) {
          g.beforeLists.set(id, state.lists.get(id));
          g.order.push(id);
        }
      }
      state.apply(op);
      if (isTaskOp(op.type)) {
        const t = state.tasks.get(id);
        if (t) g.afterTasks.set(id, t);
      }
      if (isListOp(op.type)) {
        const l = state.lists.get(id);
        if (l) g.afterLists.set(id, l);
      }
      g.ops.push(op);
    }
    for (const g of this.groups) if (g.batch !== null) this.originals.set(History.undoID(g.batch), g.batch);
  }

  /** The id of the batch that undoes `batch`: derived, so "is it undone?" needs no stored state. */
  static undoID(batch: string): string {
    return derivedID("undo:" + batch);
  }

  get batches(): Group[] {
    return this.groups.filter((g) => g.batch !== null);
  }

  group(batch: string): Group | undefined {
    const i = this.byKey.get("batch:" + batch);
    return i === undefined ? undefined : this.groups[i];
  }

  isUndone(batch: string): boolean {
    return this.byKey.has("batch:" + History.undoID(batch));
  }

  /** 0 for an ordinary change, 1 for an undo of one, 2 for a redo, …, with the ordinary change at the root. */
  lineage(batch: string): { depth: number; root: string } {
    let d = 0;
    let b = batch;
    for (let o = this.originals.get(b); o !== undefined && d < 64; o = this.originals.get(b)) {
      d += 1;
      b = o;
    }
    return { depth: d, root: b };
  }

  depth(batch: string): number {
    return this.lineage(batch).depth;
  }

  summary(g: Group, d: Describe): string {
    if (g.batch === null) return d.summary(groupChanges(g));
    const { depth, root } = this.lineage(g.batch);
    const original = this.group(root);
    if (depth === 0 || !original) return d.summary(groupChanges(g));
    return (depth % 2 === 1 ? "Undo: " : "Redo: ") + d.summary(groupChanges(original));
  }

  /** A batch by id or unique prefix (4+ characters). */
  resolve(ref: string): Group {
    const r = ref.toLowerCase();
    const g = this.group(r);
    if (g) return g;
    if (charCount(r) < 4) throw new CLIError("NotFound", `No change ${ref}. Use a batch id from tasks log.`, "batch");
    const matches = this.batches.filter((x) => x.batch!.startsWith(r));
    if (matches.length === 1) return matches[0];
    if (matches.length === 0) throw new CLIError("NotFound", `No change ${ref} in the log.`, "batch");
    throw new CLIError("Ambiguous", `${ref} matches ${matches.length} changes.`, "batch", matches.map((x) => x.batch!));
  }
}
