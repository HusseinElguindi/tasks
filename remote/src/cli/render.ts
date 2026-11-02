// JSON for tasks and lists, change summaries in the app's undo vocabulary, and dry-run diff lines.
// Port of TasksCLI/Output.swift (the JSON encoders, Describe); the CLI's text rows aren't needed by code mode.

import type { CalendarDate } from "../core/calendar-date.ts";
import { DateLabel } from "../core/date-phrase.ts";
import { HEADING, type EntityID } from "../core/op.ts";
import type { Projection } from "../core/projection.ts";
import type { TaskItem, TaskList } from "../core/state.ts";
import { RefIndex } from "./refs.ts";
import { charCount, charPrefix } from "./text.ts";

export type Json = null | boolean | number | string | Json[] | { [key: string]: Json };

export interface TaskJSON {
  id: string;
  ref: string;
  kind?: "heading";
  list: string;
  listName: string;
  title: string;
  notes: string;
  when: CalendarDate | null;
  deadline: CalendarDate | null;
  done: boolean;
  completedAt: number | null;
  deleted: boolean;
  listDeleted?: true;
  createdAt: number;
  updatedAt: number;
}

export interface ListJSON {
  id: string;
  ref: string;
  name: string;
  notes: string;
  archivedAt: number | null;
  open: number;
}

/** Renders entities against one projection (the replica's, or a fork's). */
export class Render {
  readonly taskRefs: RefIndex;
  readonly listRefs: RefIndex;

  constructor(readonly p: Projection) {
    this.taskRefs = new RefIndex(p.allTaskIDs());
    this.listRefs = new RefIndex(p.allListIDs());
  }

  listName(id: EntityID): string {
    return this.p.list(id)?.name ?? "(missing list)";
  }

  /** `kind` is there only on a heading, and `listDeleted` only in a deleted list, so a task's JSON is otherwise what it
   *  was before either. */
  task(t: TaskItem): TaskJSON {
    const out: TaskJSON = { id: t.id, ref: this.taskRefs.ref(t.id) } as TaskJSON;
    if (t.isHeading) out.kind = HEADING;
    Object.assign(out, {
      list: t.list, listName: this.listName(t.list), title: t.title, notes: t.notes, when: t.when, deadline: t.deadline,
      done: t.completedAt !== null, completedAt: t.completedAt, deleted: t.deleted,
    });
    if (this.p.isDeleted(t.list)) out.listDeleted = true;
    Object.assign(out, { createdAt: t.createdAt, updatedAt: t.updatedAt });
    return out;
  }

  list(l: TaskList): ListJSON {
    return { id: l.id, ref: this.listRefs.ref(l.id), name: l.name, notes: l.notes, archivedAt: l.archivedAt, open: this.p.openTaskCount(l.id) };
  }

  tasks(ids: EntityID[]): TaskItem[] {
    return ids.map((id) => this.p.task(id)).filter((t): t is TaskItem => t !== undefined);
  }
}

/** What changed for one entity, between two states. */
export type EntityChange =
  | { kind: "task"; before: TaskItem | undefined; after: TaskItem }
  | { kind: "list"; before: TaskList | undefined; after: TaskList };

const KINDS = ["newTask", "delete", "restore", "complete", "uncomplete", "move", "when", "removeWhen", "deadline",
  "removeDeadline", "rename", "notes", "reorder", "newList", "renameList", "listNotes", "deleteList", "restoreList", "moveList"] as const;
type Kind = (typeof KINDS)[number];

/** Summaries in the app's undo vocabulary (INTERACTIONS-v2 §9): "Move 3 Tasks to School", "Set When: Fri, Nov 6 on …". */
export class Describe {
  constructor(readonly listName: (id: EntityID) => string, readonly today: CalendarDate) {}

  static of(p: Projection): Describe {
    return new Describe((id) => p.list(id)?.name ?? "(missing list)", p.day.date);
  }

  summary(changes: EntityChange[]): string {
    const groups = new Map<Kind, EntityChange[]>();
    for (const c of changes) {
      for (const k of this.kinds(c)) {
        const g = groups.get(k);
        if (g) g.push(c);
        else groups.set(k, [c]);
      }
    }
    // Re-keyed neighbours (ties, a rebalance) are noise next to any other change.
    if (groups.size > 1) groups.delete("reorder");
    const parts = KINDS.filter((k) => groups.has(k)).map((k) => this.phrase(k, groups.get(k)!));
    if (parts.length === 0) return "No change";
    return parts.length > 2 ? parts.slice(0, 2).join("; ") + "; …" : parts.join("; ");
  }

  private kinds(c: EntityChange): Kind[] {
    if (c.kind === "task") {
      const { before: b, after: a } = c;
      if (!b) return ["newTask"];
      const k: Kind[] = [];
      if (!b.deleted && a.deleted) k.push("delete");
      if (b.deleted && !a.deleted) k.push("restore");
      if (b.completedAt === null && a.completedAt !== null) k.push("complete");
      if (b.completedAt !== null && a.completedAt === null) k.push("uncomplete");
      if (b.list !== a.list) k.push("move");
      else if (b.order !== a.order) k.push("reorder");
      if (b.when !== a.when) k.push(a.when === null ? "removeWhen" : "when");
      if (b.deadline !== a.deadline) k.push(a.deadline === null ? "removeDeadline" : "deadline");
      if (b.title !== a.title) k.push("rename");
      if (b.notes !== a.notes) k.push("notes");
      return k;
    }
    const { before: b, after: a } = c;
    if (!b) return ["newList"];
    const k: Kind[] = [];
    if (b.name !== a.name) k.push("renameList");
    if (b.notes !== a.notes) k.push("listNotes");
    if (b.archivedAt === null && a.archivedAt !== null) k.push("deleteList");
    if (b.archivedAt !== null && a.archivedAt === null) k.push("restoreList");
    if (b.order !== a.order) k.push("moveList");
    return k;
  }

  private phrase(k: Kind, cs: EntityChange[]): string {
    const tasks = cs.flatMap((c) => (c.kind === "task" ? [c.after] : []));
    const lists = cs.flatMap((c) => (c.kind === "list" ? [c.after] : []));
    const n = tasks.length;
    const headings = tasks.filter((t) => t.isHeading);
    const q = (s: string) => this.quote(s);
    const one = (verb: string) => {
      if (n === 1) return `${verb}${headings.length === 0 ? "" : " Heading"} ${q(tasks[0].title)}`;
      return headings.length === 0 ? `${verb} ${n} Tasks` : `${verb} ${n} Items`;
    };
    const dated = (name: string, d: (t: TaskItem) => CalendarDate | null) => {
      const dates = new Set(tasks.map(d).filter((x): x is string => x !== null));
      const label = dates.size === 1 ? ": " + DateLabel.long([...dates][0], this.today) : "";
      return n === 1 ? `${name}${label} on ${q(tasks[0].title)}` : `${name}${label} (${n} tasks)`;
    };
    const listQuote = lists.length > 0 ? q(lists[0].name) : "";
    switch (k) {
      case "newTask":
        if (n === 1) return `New ${headings.length === 0 ? "Task" : "Heading"} ${q(tasks[0].title)} in ${this.listName(tasks[0].list)}`;
        return headings.length === 0 ? `New ${n} Tasks` : `New ${n} Items`;
      case "delete": return one("Delete");
      case "restore": return one("Restore");
      case "complete": return one("Complete");
      case "uncomplete": return n === 1 ? `Mark Not Done ${q(tasks[0].title)}` : `Mark ${n} Tasks Not Done`;
      case "move": {
        const targets = new Set(tasks.map((t) => t.list));
        const to = targets.size === 1 ? ` to ${this.listName([...targets][0])}` : "";
        return one("Move") + to;
      }
      case "reorder":
        // A section moves as its heading and its tasks: one "Move Heading".
        if (headings.length === 1) return `Move Heading ${q(headings[0].title)}`;
        return one("Reorder");
      case "when": return dated("Set When", (t) => t.when);
      case "removeWhen": return n === 1 ? `Remove When from ${q(tasks[0].title)}` : `Remove When (${n} tasks)`;
      case "deadline": return dated("Set Deadline", (t) => t.deadline);
      case "removeDeadline": return n === 1 ? `Remove Deadline from ${q(tasks[0].title)}` : `Remove Deadline (${n} tasks)`;
      case "rename":
        return n === 1 ? `Rename ${headings.length === 0 ? "Task" : "Heading"} to ${q(tasks[0].title)}` : `Rename ${n} Tasks`;
      case "notes": return n === 1 ? `Edit Notes on ${q(tasks[0].title)}` : `Edit Notes (${n} tasks)`;
      case "newList": return lists.length === 1 ? `New List ${listQuote}` : `New ${lists.length} Lists`;
      case "renameList": return lists.length === 1 ? `Rename List to ${listQuote}` : `Rename ${lists.length} Lists`;
      case "listNotes": return lists.length === 1 ? `Edit List Notes on ${listQuote}` : `Edit List Notes (${lists.length} lists)`;
      case "deleteList": return lists.length === 1 ? `Delete List ${listQuote}` : `Delete ${lists.length} Lists`;
      case "restoreList": return lists.length === 1 ? `Restore List ${listQuote}` : `Restore ${lists.length} Lists`;
      case "moveList": return lists.length === 1 ? `Move List ${listQuote}` : `Move ${lists.length} Lists`;
    }
  }

  /** Titles over 28 characters end in …, as the app's notices do. */
  quote(s: string): string {
    const t = s === "" ? "(untitled)" : s;
    return '"' + (charCount(t) > 28 ? charPrefix(t, 27) + "…" : t) + '"';
  }

  /** Dry-run lines: `+ 3f9a2c "Buy milk"  in Groceries`, `~ 3f9a2c "Buy milk"  when: — → 2026-11-06 (Fri)`. */
  diff(changes: EntityChange[], refs: Render): string[] {
    const out: string[] = [];
    for (const c of changes) {
      if (c.kind === "task") {
        const { before: b, after: a } = c;
        const head = `${b ? "~" : "+"} ${refs.taskRefs.ref(a.id)} ${this.quote(a.title)}`;
        const fields = this.taskFields(b, a);
        if (fields.length > 0) out.push(head + "  " + fields.join("; "));
      } else {
        const { before: b, after: a } = c;
        const head = `${b ? "~" : "+"} list ${refs.listRefs.ref(a.id)} ${this.quote(a.name)}`;
        const f: string[] = [];
        if (!b) f.push("new list");
        if (b && b.name !== a.name) f.push(`name: ${this.quote(b.name)} → ${this.quote(a.name)}`);
        if (b && b.notes !== a.notes) f.push("notes edited");
        if (!b && a.notes !== "") f.push("notes");
        if ((b?.archivedAt ?? null) !== a.archivedAt) f.push(a.archivedAt === null ? "restored" : "deleted");
        if (b && b.order !== a.order) f.push("sidebar position");
        if (f.length > 0) out.push(head + "  " + f.join("; "));
      }
    }
    return out;
  }

  private taskFields(b: TaskItem | undefined, a: TaskItem): string[] {
    const d = (x: CalendarDate | null) => (x === null ? "—" : `${x} (${DateLabel.whenChip(x, this.today)})`);
    if (!b) {
      const f = [a.isHeading ? `heading in ${this.listName(a.list)}` : `in ${this.listName(a.list)}`];
      if (a.when !== null) f.push(`when ${d(a.when)}`);
      if (a.deadline !== null) f.push(`deadline ${d(a.deadline)}`);
      if (a.notes !== "") f.push("notes");
      return f;
    }
    const f: string[] = [];
    if (b.list !== a.list) f.push(`list: ${this.listName(b.list)} → ${this.listName(a.list)}`);
    else if (b.order !== a.order) f.push("position");
    if (b.title !== a.title) f.push(`title: ${this.quote(b.title)} → ${this.quote(a.title)}`);
    if (b.notes !== a.notes) f.push("notes edited");
    if (b.when !== a.when) f.push(`when: ${d(b.when)} → ${d(a.when)}`);
    if (b.deadline !== a.deadline) f.push(`deadline: ${d(b.deadline)} → ${d(a.deadline)}`);
    if ((b.completedAt === null) !== (a.completedAt === null)) f.push(a.completedAt === null ? "not done" : "done");
    if (b.deleted !== a.deleted) f.push(a.deleted ? "deleted" : "restored");
    return f;
  }
}
