// One code-mode run: the replica's state, the fork its writes are built on, its batch id, and every intent and view.
// A port of TasksCLI/Intents.swift (Context) and the undo half of History.swift.

import { parseCalendarDate, type CalendarDate } from "../core/calendar-date.ts";
import { DatePhrase, type NumericOrder } from "../core/date-phrase.ts";
import { dayContaining } from "../core/day.ts";
import { isListOp, isTaskOp, type EntityID, type Op, type Patch } from "../core/op.ts";
import { orderPrecedes, type Anchor } from "../core/ordering.ts";
import { Projection } from "../core/projection.ts";
import type { TaskItem, TaskList } from "../core/state.ts";
import type { LogEntry } from "../core/wire.ts";
import { Fork, type Clock } from "./actions.ts";
import { CLIError } from "./errors.ts";
import { History, derivedID, groupChanges } from "./history.ts";
import { Describe, Render, type EntityChange, type Json, type ListJSON, type TaskJSON } from "./render.ts";
import { RefIndex, Resolver, deletedListHint, quotedName } from "./refs.ts";
import { charCount, trimWhitespaces, trimWhitespacesAndNewlines, containsFolded } from "./text.ts";

/** Where a task or list goes (`Ordering.Anchor`, plus up and down). */
export type Place = "top" | "bottom" | "up" | "down" | { after: string } | { before: string };

/** A date argument: absent (undefined), cleared (null), or a day. */
export type DateArg = { value: CalendarDate | null } | undefined;

/** What a run reads from its replica. */
export interface ReplicaState {
  /** The replica's projection: confirmed + its pending ops, as of the pull before the run. */
  projection: Projection;
  /** The whole log, for undo. */
  entries(): LogEntry[];
  actor: string;
}

export interface RunOptions {
  clock: Clock;
  timeZone: string;
  dateOrder: NumericOrder;
}

export class Context {
  /** Every op of this run carries it. An undo uses the id derived from what it undoes. */
  batch: string;
  private batchFixed = false;
  private fork: Fork | null = null;
  /** Undo: later edits it kept rather than overwrite. */
  skipped: string[] = [];
  /** Undo: "Undo: Move 3 Tasks to School" rather than a description of the inverse ops. */
  summaryOverride: string | null = null;

  constructor(readonly replica: ReplicaState, readonly options: RunOptions) {
    this.batch = options.clock.newID();
  }

  get clock() {
    return this.options.clock;
  }

  /** What reads see: the fork once anything has been written (a script reads its own writes), else the replica. */
  get p(): Projection {
    return this.fork?.projection ?? this.replica.projection;
  }

  get resolve(): Resolver {
    return new Resolver(this.p);
  }

  get today(): CalendarDate {
    return this.p.day.date;
  }

  writable(): Fork {
    if (this.fork) return this.fork;
    const base = this.replica.projection;
    const p = new Projection(base.confirmed.clone(), base.pending, dayContaining(this.clock.now(), this.options.timeZone));
    this.fork = new Fork(p, this.clock);
    return this.fork;
  }

  /** The ops this run has made, oldest first. */
  get ops(): Op[] {
    return this.fork?.made ?? [];
  }

  /** Pins the batch id (an undo). Only before anything else is written, and only once. */
  fixBatch(id: string): void {
    if (this.ops.length > 0 || this.batchFixed) throw CLIError.invalid("An undo must be the only change in a command or run.");
    this.batch = id;
    this.batchFixed = true;
  }

  requireUnfixed(): void {
    if (this.batchFixed) throw CLIError.invalid("An undo must be the only change in a command or run.");
  }

  // MARK: The change

  /** Entities the ops from `from` touched, in first-touch order, before this run (the replica) and after (`view`). */
  changes(from = 0, view?: Projection): EntityChange[] {
    const before = this.replica.projection;
    const after = view ?? this.p;
    const seenTasks = new Set<string>();
    const seenLists = new Set<string>();
    const out: EntityChange[] = [];
    for (const op of this.ops.slice(from)) {
      if (isTaskOp(op.type)) {
        if (seenTasks.has(op.target)) continue;
        seenTasks.add(op.target);
        const a = after.task(op.target);
        if (a) out.push({ kind: "task", before: before.task(op.target), after: a });
      } else if (isListOp(op.type)) {
        if (seenLists.has(op.target)) continue;
        seenLists.add(op.target);
        const a = after.list(op.target);
        if (a) out.push({ kind: "list", before: before.list(op.target), after: a });
      }
    }
    return out;
  }

  summary(cs: EntityChange[], p: Projection): string {
    if (this.summaryOverride !== null && cs.length > 0) return this.summaryOverride;
    return Describe.of(p).summary(cs);
  }

  /** A `Change`: the batch, a summary in the app's undo names, and the entities after it. */
  changeJSON(from = 0, view?: Projection): { [k: string]: Json } {
    const v = view ?? this.p;
    const cs = this.changes(from, v);
    const r = new Render(v);
    const out: { [k: string]: Json } = {
      batch: this.ops.length > from ? this.batch : null,
      summary: this.summary(cs, v),
      tasks: cs.flatMap((c) => (c.kind === "task" ? [r.task(c.after) as unknown as Json] : [])),
      lists: cs.flatMap((c) => (c.kind === "list" ? [r.list(c.after) as unknown as Json] : [])),
    };
    if (this.skipped.length > 0) out.skipped = [...this.skipped];
    return out;
  }

  diff(): string[] {
    const p = this.p;
    return Describe.of(p).diff(this.changes(), new Render(p));
  }

  // MARK: Arguments

  date(v: Json | undefined, field: string): DateArg {
    if (v === undefined) return undefined;
    if (v === null) return { value: null };
    if (typeof v !== "string") throw CLIError.invalid(`${field} must be a date, a phrase like "fri", or null.`, field);
    const text = trimWhitespaces(v);
    if (["none", "null", "clear"].includes(text.toLowerCase())) return { value: null };
    const d = this.resolveDate(text);
    if (d === null) {
      throw CLIError.invalid(`"${text}" isn't a date (try 2026-11-06, today, tomorrow, fri, next week, 3d, nov 9).`, field);
    }
    return { value: d };
  }

  /** What the date field reads on Return, or an exact YYYY-MM-DD. */
  resolveDate(text: string): CalendarDate | null {
    return parseCalendarDate(text) ?? DatePhrase.match(text, this.today, this.options.dateOrder);
  }

  place(v: Json | undefined, field = "place"): Place | null {
    if (v === undefined || v === null) return null;
    if (typeof v === "string" && (v === "top" || v === "bottom" || v === "up" || v === "down")) return v;
    if (typeof v === "object" && !Array.isArray(v)) {
      if (typeof v.after === "string") return { after: v.after };
      if (typeof v.before === "string") return { before: v.before };
    }
    throw CLIError.invalid(`${field} must be "top", "bottom", "up", "down", {after: ref} or {before: ref}.`, field);
  }

  static text(s: string, field: string, max: number, nonEmpty: boolean): string {
    if (nonEmpty && trimWhitespacesAndNewlines(s) === "") throw CLIError.invalid(`${field} can't be empty.`, field);
    if (s.length > max) {
      throw new CLIError("Limit", `${field} is ${s.length} characters; the limit is ${max} (UTF-16 units).`, field);
    }
    return s;
  }

  // MARK: Intents (every UI operation, on the fork)

  add(o: { title: string; list?: string; notes?: string; when: DateArg; deadline: DateArg; place: Place | null; id?: string; key?: string }): TaskItem {
    this.requireUnfixed();
    const title = Context.text(o.title, "title", 1000, true);
    const notes = Context.text(o.notes ?? "", "notes", 20000, false);
    if (o.id !== undefined && o.key !== undefined) throw CLIError.invalid("Pass id or key, not both.", "key");
    if (o.id !== undefined && (o.id.length < 1 || o.id.length > 64)) throw CLIError.invalid("An id is 1 to 64 characters.", "id");
    const taskID = o.id ?? (o.key !== undefined ? derivedID("key:" + o.key) : undefined);
    // Same id, same task: repeating an add with a key writes nothing.
    if (taskID !== undefined) {
      const existing = this.p.task(taskID);
      if (existing) return existing;
    }
    const r = this.resolve;
    let anchorTask: TaskItem | undefined;
    const place = o.place;
    if (place === "up" || place === "down") throw CLIError.invalid("A new task can't move up or down.", "place");
    if (place !== null && typeof place === "object") {
      anchorTask = r.task("after" in place ? place.after : place.before);
      if (anchorTask.completedAt !== null) throw CLIError.invalid("Place it next to an open task.", "place");
    }
    const explicit = o.list !== undefined ? r.list(o.list) : undefined;
    if (explicit && anchorTask && anchorTask.list !== explicit.id) {
      throw CLIError.invalid(`The place is in ${this.p.list(anchorTask.list)?.name ?? "another list"}, not ${explicit.name}.`, "place");
    }
    const s = this.writable();
    const listID = explicit?.id ?? anchorTask?.list ?? s.defaultListID;
    if (listID === undefined) throw new CLIError("NoActiveList", "There's no active list to add to. Add one with tasks list add NAME.");
    if (explicit) this.refuseDeleted(explicit, "list");
    const newID = s.createTask({ id: taskID, title, notes, list: listID, when: o.when?.value ?? null, deadline: o.deadline?.value ?? null });
    if (newID === null) throw new CLIError("NoActiveList", "There's no active list to add to.");
    if (place !== null && place !== "bottom") s.reorder([newID], listID, this.anchor(place, anchorTask));
    return s.projection.task(newID)!;
  }

  private anchor(place: Place, task: TaskItem | undefined): Anchor {
    if (place === "top") return "top";
    if (typeof place === "object") return "after" in place ? { after: task!.id } : { before: task!.id };
    return "bottom";
  }

  rename(ref: string, title: string): void {
    this.requireUnfixed();
    const v = Context.text(title, "title", 1000, true);
    const t = this.resolve.task(ref);
    this.writable().setTitle(t.id, v);
  }

  setNotes(ref: string, notes: string, append: boolean): void {
    this.requireUnfixed();
    const t = this.resolve.task(ref);
    let text = notes;
    if (append && t.notes !== "") text = t.notes + (t.notes.endsWith("\n") ? "" : "\n") + notes;
    text = Context.text(text, "notes", 20000, false);
    this.writable().setNotes(t.id, text);
  }

  /** Completing, dates and Move to don't apply to a heading: name it and write nothing. */
  refuseHeadings(tasks: TaskItem[], field = "tasks"): void {
    const h = tasks.find((t) => t.isHeading);
    if (h) {
      throw CLIError.invalid(`${h.title === "" ? "(untitled)" : h.title} is a heading; headings have no completion or dates and stay in their list.`, field);
    }
  }

  complete(refs: string[]): void {
    this.requireUnfixed();
    const tasks = this.resolve.tasks(refs);
    this.refuseHeadings(tasks);
    const open = tasks.filter((t) => t.completedAt === null).map((t) => t.id);
    if (open.length > 0) this.writable().toggleComplete(open);
  }

  uncomplete(refs: string[]): void {
    this.requireUnfixed();
    const tasks = this.resolve.tasks(refs);
    this.refuseHeadings(tasks);
    const done = tasks.filter((t) => t.completedAt !== null).map((t) => t.id);
    if (done.length > 0) this.writable().toggleComplete(done);
  }

  toggle(refs: string[]): void {
    this.requireUnfixed();
    const tasks = this.resolve.tasks(refs);
    this.refuseHeadings(tasks);
    this.writable().toggleComplete(tasks.map((t) => t.id));
  }

  setWhen(refs: string[], date: DateArg): void {
    this.requireUnfixed();
    if (date === undefined) throw CLIError.invalid("Give a date, or none to remove When.", "date");
    const tasks = this.resolve.tasks(refs);
    this.refuseHeadings(tasks);
    this.writable().setWhen(tasks.map((t) => t.id), date.value);
  }

  setDeadline(refs: string[], date: DateArg): void {
    this.requireUnfixed();
    if (date === undefined) throw CLIError.invalid("Give a date, or none to remove the deadline.", "date");
    const tasks = this.resolve.tasks(refs);
    this.refuseHeadings(tasks);
    this.writable().setDeadline(tasks.map((t) => t.id), date.value);
  }

  delete(refs: string[]): void {
    this.requireUnfixed();
    const ids = this.resolve.tasks(refs).map((t) => t.id);
    this.writable().delete(ids);
  }

  /** `deleted: false`, for when there's no undo stack to bring a task back. A task whose list is deleted has no place to
   *  go back to: that fails, naming the list. */
  restore(refs: string[]): void {
    this.requireUnfixed();
    const tasks = this.resolve.tasks(refs, true);
    for (const t of tasks) {
      const l = this.p.list(t.list);
      if (l && l.archivedAt !== null) {
        const ref = new RefIndex(this.p.allTaskIDs()).ref(t.id);
        throw CLIError.invalid(`Task ${ref} ("${t.title}") is in ${l.name}, which is deleted; ${deletedListHint(l, ref)}`, "tasks");
      }
    }
    const gone = tasks.filter((t) => t.deleted);
    if (gone.length === 0) return;
    const s = this.writable();
    s.perform(gone.map((t) => ({ id: s.newID(), at: this.clock.now(), type: "task.update", target: t.id, set: { deleted: false } })));
  }

  move(refs: string[], list: string | undefined, place: Place | null): void {
    this.requireUnfixed();
    const r = this.resolve;
    const tasks = r.tasks(refs, false, true);
    const ids = tasks.map((t) => t.id);
    if (list === undefined && place === null) {
      throw CLIError.invalid("Say where: a list (--to) or a place (--top, --after REF, --up…).", "to");
    }
    const target = list !== undefined ? r.list(list) : undefined;
    if (target) this.refuseDeleted(target, "to");
    // Out of a deleted list (Put back in): to the bottom of a live list, nothing else.
    const trashed = tasks.filter((t) => this.p.isDeleted(t.list));
    if (trashed.length > 0) {
      const l = this.p.list(trashed[0].list)!;
      if (trashed.length !== tasks.length) {
        throw CLIError.invalid(`Some of these are in ${l.name}, which is deleted: move those on their own, with --to.`, "tasks");
      }
      if (trashed.some((t) => t.isHeading)) {
        throw CLIError.invalid(`${l.name} is deleted, and a heading stays in its list; tasks list restore ${quotedName(l.name)} brings it back.`, "tasks");
      }
      if (!target || !(place === null || place === "bottom")) {
        throw CLIError.invalid(`${l.name} is deleted: its tasks can only go to the bottom of another list, with --to.`, "to");
      }
      this.writable().putBack(ids, target.id);
      return;
    }
    if (tasks.some((t) => t.isHeading)) {
      this.moveHeading(tasks, target, place);
      return;
    }
    if (place === null) {
      this.writable().move(ids, target!.id);
      return;
    }
    if (tasks.some((t) => t.completedAt !== null)) {
      throw CLIError.invalid("Completed tasks have no place among the open ones; mark them not done first.", "place");
    }
    if (place === "up" || place === "down") {
      if (tasks.length !== 1) throw CLIError.invalid("--up and --down move one task.", "place");
      const t = tasks[0];
      if (target && target.id !== t.list) throw CLIError.invalid("--up and --down move a task within its own list.", "place");
      const items = this.p.orderedOpenTasks(t.list);
      const i = items.findIndex((x) => x.id === t.id);
      if (i < 0) return;
      if (place === "up" && i > 0) this.writable().reorder([t.id], t.list, { before: items[i - 1].id });
      else if (place === "down" && i + 1 < items.length) this.writable().reorder([t.id], t.list, { after: items[i + 1].id });
      return;
    }
    if (typeof place === "object") {
      const a = "after" in place ? place.after : place.before;
      const anchorTask = r.task(a);
      if (ids.includes(anchorTask.id)) throw CLIError.invalid("A task can't be placed next to itself.", "place");
      if (anchorTask.completedAt !== null) throw CLIError.invalid("Place them next to an open task.", "place");
      if (target && target.id !== anchorTask.list) {
        throw CLIError.invalid(`${a} is in ${this.p.list(anchorTask.list)?.name ?? "another list"}, not ${target.name}.`, "place");
      }
      const at: Anchor = "after" in place ? { after: anchorTask.id } : { before: anchorTask.id };
      this.writable().reorder(ids, anchorTask.list, at);
      return;
    }
    // top, bottom
    const lists = new Set(tasks.map((t) => t.list));
    const listID = target?.id ?? (lists.size === 1 ? [...lists][0] : undefined);
    if (listID === undefined) throw CLIError.invalid("The tasks are in different lists; say which with --to.", "to");
    this.writable().reorder(ids, listID, place === "top" ? "top" : "bottom");
  }

  /** `move <heading>`: its section moves with it; it lands only before another heading or at the end. */
  private moveHeading(tasks: TaskItem[], target: TaskList | undefined, place: Place | null): void {
    if (tasks.length !== 1) throw CLIError.invalid("Move a heading on its own: its tasks go with it.", "tasks");
    const h = tasks[0];
    if (target && target.id !== h.list) this.refuseHeadings([h], "to");
    if (place === null) return;
    const p = this.p;
    const headingIDs = p.headings(h.list);
    const others = headingIDs.filter((id) => id !== h.id);
    const mineIndex = headingIDs.indexOf(h.id);
    const mine = mineIndex >= 0 ? mineIndex : 0;
    /** Before the first heading after `section` (null: the tasks above the first heading), or the end. */
    const after = (section: EntityID | null): Anchor => {
      if (section === null) return others.length > 0 ? { before: others[0] } : "bottom";
      const all = p.headings(h.list);
      const j = all.indexOf(section);
      const i = j >= 0 ? j : all.length;
      const next = all.slice(i + 1).find((id) => id !== h.id);
      return next !== undefined ? { before: next } : "bottom";
    };
    let anchor: Anchor | null;
    if (place === "top") anchor = others.length > 0 ? { before: others[0] } : null;
    else if (place === "bottom") anchor = "bottom";
    else if (place === "up") anchor = mine > 0 ? { before: others[mine - 1] } : null;
    else if (place === "down") anchor = mine < others.length ? (mine + 1 < others.length ? { before: others[mine + 1] } : "bottom") : null;
    else {
      const ref = "after" in place ? place.after : place.before;
      const r = this.resolve.task(ref);
      if (r.list !== h.list) {
        throw CLIError.invalid(`${ref} is in ${p.list(r.list)?.name ?? "another list"}; a heading stays in its list.`, "place");
      }
      if ("before" in place) {
        if (!r.isHeading) {
          throw CLIError.invalid("A heading goes before another heading, or --after a row (it lands after that row's section).", "place");
        }
        anchor = r.id === h.id ? null : { before: r.id };
      } else {
        anchor = after(r.isHeading ? r.id : p.headingOf(r.id));
      }
    }
    if (anchor === null || this.isWhere(h.id, anchor, p)) return;
    this.writable().moveSection(h.id, anchor);
  }

  /** Whether a heading's section already ends right before `anchor`'s heading (or at the end, for bottom). */
  private isWhere(heading: EntityID, anchor: Anchor, p: Projection): boolean {
    const t = p.task(heading);
    if (!t) return true;
    const all = p.orderedTasksIncludingCompleted(t.list).map((x) => x.id);
    const section = p.section(heading);
    const last = section[section.length - 1];
    const i = last === undefined ? -1 : all.indexOf(last);
    if (i < 0) return false;
    const next = i + 1 < all.length ? all[i + 1] : null;
    if (anchor === "bottom") return next === null;
    if (typeof anchor === "object" && "before" in anchor) return next === anchor.before;
    return false;
  }

  /** A heading: above `before R`, after `after R` (after R's section when R is a heading), at the top, or the bottom. */
  addHeading(o: { name: string; list?: string; notes?: string; place: Place | null }): TaskItem {
    this.requireUnfixed();
    const name = Context.text(o.name, "name", 1000, true);
    const notes = Context.text(o.notes ?? "", "notes", 20000, false);
    const r = this.resolve;
    const place = o.place;
    let anchorRow: TaskItem | undefined;
    if (place === "up" || place === "down") throw CLIError.invalid("A new heading can't move up or down.", "place");
    if (place !== null && typeof place === "object") {
      anchorRow = r.task("after" in place ? place.after : place.before);
      if (anchorRow.completedAt !== null) throw CLIError.invalid("Place it next to an open task or a heading.", "place");
    }
    const explicit = o.list !== undefined ? r.list(o.list) : undefined;
    if (explicit && anchorRow && anchorRow.list !== explicit.id) {
      throw CLIError.invalid(`The place is in ${this.p.list(anchorRow.list)?.name ?? "another list"}, not ${explicit.name}.`, "place");
    }
    const s = this.writable();
    const listID = explicit?.id ?? anchorRow?.list ?? s.defaultListID;
    if (listID === undefined) throw new CLIError("NoActiveList", "There's no active list to add to. Add one with tasks list add NAME.");
    const l = s.projection.list(listID);
    if (l) this.refuseDeleted(l, "list");
    let anchor: Anchor;
    if (place === "top") anchor = "top";
    else if (place !== null && typeof place === "object" && "before" in place) anchor = { before: anchorRow!.id };
    else if (place !== null && typeof place === "object") {
      // After a heading means after its section: before the next heading, or the end.
      if (anchorRow!.isHeading) {
        const all = s.projection.headings(listID);
        const j = all.indexOf(anchorRow!.id);
        const i = j >= 0 ? j : all.length;
        anchor = i + 1 < all.length ? { before: all[i + 1] } : "bottom";
      } else anchor = { after: anchorRow!.id };
    } else anchor = "bottom";
    const id = s.createHeading({ title: name, notes, list: listID, anchor });
    if (id === null) throw new CLIError("NoActiveList", "There's no active list to add to.");
    return s.projection.task(id)!;
  }

  setListNotes(ref: string, notes: string, append: boolean): void {
    this.requireUnfixed();
    const l = this.resolve.list(ref);
    this.refuseDeleted(l, "list");
    let text = notes;
    if (append && l.notes !== "") text = l.notes + (l.notes.endsWith("\n") ? "" : "\n") + notes;
    text = Context.text(text, "notes", 20000, false);
    this.writable().setListNotes(l.id, text);
  }

  addList(name: string, place: Place | null): TaskList {
    this.requireUnfixed();
    const v = Context.text(name, "name", 200, true);
    const anchor = this.listAnchor(place, undefined);
    const s = this.writable();
    const id = s.createList(v);
    if (anchor !== null) s.reorderLists([id], anchor);
    return s.projection.list(id)!;
  }

  renameList(ref: string, name: string): void {
    this.requireUnfixed();
    const v = Context.text(name, "name", 200, true);
    const l = this.resolve.list(ref);
    this.refuseDeleted(l, "list");
    this.writable().renameList(l.id, v);
  }

  moveList(ref: string, place: Place | null): void {
    this.requireUnfixed();
    const l = this.resolve.list(ref);
    if (l.archivedAt !== null) throw CLIError.invalid(`${l.name} is deleted, so it isn't in the sidebar.`, "list");
    if (place === null) throw CLIError.invalid("Give a place: top, bottom, up, down, or after/before a list.", "place");
    const anchor = this.listAnchor(place, l);
    if (anchor !== null) this.writable().reorderLists([l.id], anchor);
  }

  /** null means "the bottom" for a new list, or "nowhere to go" for up on the first list. */
  private listAnchor(place: Place | null, moving: TaskList | undefined): Anchor | null {
    if (place === null) return null;
    const items = this.p.orderedActiveLists();
    if (place === "top") return "top";
    if (place === "bottom") return moving === undefined ? null : "bottom";
    if (place === "up" || place === "down") {
      const i = moving === undefined ? -1 : items.findIndex((x) => x.id === moving.id);
      if (i < 0) throw CLIError.invalid("A new list can't move up or down.", "place");
      if (place === "up") return i > 0 ? { before: items[i - 1].id } : null;
      return i + 1 < items.length ? { after: items[i + 1].id } : null;
    }
    const other = this.resolve.list("after" in place ? place.after : place.before);
    if (other.archivedAt !== null) throw CLIError.invalid(`${other.name} is deleted.`, "place");
    if (other.id === moving?.id) throw CLIError.invalid("A list can't be placed next to itself.", "place");
    return "after" in place ? { after: other.id } : { before: other.id };
  }

  /** Delete List: `archivedAt` = now, one op. Its tasks count as deleted until it's restored. */
  deleteList(ref: string): void {
    this.requireUnfixed();
    const l = this.resolve.list(ref);
    this.writable().deleteList(l.id);
  }

  /** Restore List: back to its old place with everything it held; tasks deleted on their own stay deleted. */
  restoreList(ref: string): void {
    this.requireUnfixed();
    const l = this.resolve.list(ref);
    this.writable().restoreList(l.id);
  }

  /** A deleted list takes nothing: it's read-only until it's restored. */
  refuseDeleted(l: TaskList, field: string): void {
    if (l.archivedAt === null) return;
    throw CLIError.invalid(`${l.name} is deleted; tasks list restore ${quotedName(l.name)} brings it back.`, field);
  }

  // MARK: Undo

  history(): History {
    return new History(this.replica.entries(), this.replica.projection.pending.map((p) => p.op));
  }

  /** Undo one batch from the log: touched keys go back to their values just before it, except keys someone changed since. */
  undo(ref: string | undefined, force: boolean, redo = false): void {
    const h = this.history();
    const actor = this.replica.actor;
    let target;
    if (ref !== undefined) target = h.resolve(ref);
    else {
      const candidates = h.batches.filter((g) => g.actor === actor && h.depth(g.batch!) % 2 === (redo ? 1 : 0) && !h.isUndone(g.batch!));
      const newest = candidates[candidates.length - 1];
      if (!newest) throw new CLIError("NotFound", redo ? `Nothing of ${actor}'s to redo.` : `Nothing of ${actor}'s to undo.`, "batch");
      target = newest;
    }
    const batch = target.batch!;
    if (h.isUndone(batch)) {
      throw CLIError.invalid(`That change is already undone (by ${History.undoID(batch).slice(0, 6)}).`, "batch");
    }
    if (this.fork !== null || this.ops.length > 0) throw CLIError.invalid("An undo must be the only change in a command or run.");
    this.fixBatch(History.undoID(batch));
    const { depth, root } = h.lineage(batch);
    const rootGroup = h.group(root);
    const rootSummary = rootGroup ? Describe.of(this.p).summary(groupChanges(rootGroup)) : "a change";
    this.summaryOverride = (depth % 2 === 0 ? "Undo: " : "Redo: ") + rootSummary;

    const p = this.p;
    const r = new Render(p);
    const out: Op[] = [];
    const s = this.writable();
    const op = (type: string, id: EntityID, set: Patch): Op => ({ id: s.newID(), at: this.clock.now(), type, target: id, set });
    const skip = (what: string, ref: string, title: string) => {
      this.skipped.push(`kept the later edit to the ${what} of ${ref} "${title}"`);
    };
    for (const id of target.order) {
      const afterTask = target.afterTasks.get(id);
      const currentTask = p.task(id);
      if (afterTask && currentTask) {
        const ref = r.taskRefs.ref(id);
        const before = target.beforeTasks.get(id);
        if (!before) {
          if (!currentTask.deleted) out.push(op("task.update", id, { deleted: true }));
          continue;
        }
        const set: Patch = {};
        const field = <K extends keyof TaskItem>(name: string, k: K, apply: (v: TaskItem[K]) => void) => {
          if (before[k] === afterTask[k]) return;
          if (currentTask[k] === afterTask[k] || force) apply(before[k]);
          else skip(name, ref, currentTask.title);
        };
        if (before.list !== afterTask.list || before.order !== afterTask.order) {
          if ((currentTask.list === afterTask.list && currentTask.order === afterTask.order) || force) {
            set.list = before.list;
            set.order = before.order;
          } else skip("position", ref, currentTask.title);
        }
        field("title", "title", (v) => (set.title = v));
        field("notes", "notes", (v) => (set.notes = v));
        field("when", "when", (v) => (set.when = v));
        field("deadline", "deadline", (v) => (set.deadline = v));
        field("completion", "completedAt", (v) => (set.completedAt = v));
        field("deleted state", "deleted", (v) => (set.deleted = v));
        if (Object.keys(set).length > 0) out.push(op("task.update", id, set));
        continue;
      }
      const afterList = target.afterLists.get(id);
      const currentList = p.list(id);
      if (afterList && currentList) {
        const ref = r.listRefs.ref(id);
        const before = target.beforeLists.get(id);
        if (!before) {
          if (currentList.archivedAt === null) out.push(op("list.update", id, { archivedAt: this.clock.now() }));
          continue;
        }
        const set: Patch = {};
        const field = <K extends keyof TaskList>(name: string, k: K, apply: (v: TaskList[K]) => void) => {
          if (before[k] === afterList[k]) return;
          if (currentList[k] === afterList[k] || force) apply(before[k]);
          else skip(name, ref, currentList.name);
        };
        field("name", "name", (v) => (set.name = v));
        field("notes", "notes", (v) => (set.notes = v));
        field("position", "order", (v) => (set.order = v));
        field("deleted state", "archivedAt", (v) => (set.archivedAt = v));
        if (Object.keys(set).length > 0) out.push(op("list.update", id, set));
      }
    }
    if (out.length > 0) s.perform(out);
  }

  // MARK: Views

  todayJSON(): Json {
    const p = this.p;
    const r = new Render(p);
    const groups: Json[] = [];
    for (const id of p.activeLists()) {
      const tasks = r.tasks(p.todayTasks(id));
      const l = p.list(id);
      if (tasks.length === 0 || !l) continue;
      groups.push({ list: r.list(l) as unknown as Json, tasks: tasks.map((t) => r.task(t) as unknown as Json) });
    }
    const done = r.tasks(p.todayDone());
    return { date: p.day.date, groups, done: done.map((t) => r.task(t) as unknown as Json) };
  }

  listsJSON(): ListJSON[] {
    const p = this.p;
    const r = new Render(p);
    return p.activeLists().map((id) => p.list(id)).filter((l) => l !== undefined).map((l) => r.list(l!));
  }

  /** Deleted lists, in Trash, most recently deleted first. */
  deletedListsJSON(): ListJSON[] {
    const p = this.p;
    const r = new Render(p);
    return p.deletedLists().map((id) => p.list(id)).filter((l) => l !== undefined).map((l) => r.list(l!));
  }

  listJSON(ref: string | undefined): Json {
    const p = this.p;
    const r = new Render(p);
    let l: TaskList;
    if (ref !== undefined) l = this.resolve.list(ref);
    else {
      const id = p.activeLists()[0];
      const first = id === undefined ? undefined : p.list(id);
      if (!first) throw new CLIError("NoActiveList", "There are no lists. Add one with tasks list add NAME.");
      l = first;
    }
    const open = r.tasks(p.openTasks(l.id));
    const completed = r.tasks(p.completedTasks(l.id));
    return {
      list: r.list(l) as unknown as Json,
      open: open.map((t) => r.task(t) as unknown as Json),
      completed: completed.map((t) => r.task(t) as unknown as Json),
    };
  }

  find(q: { text?: string; list?: string; done?: boolean; deleted: boolean }): TaskJSON[] {
    const p = this.p;
    const r = new Render(p);
    const listID = q.list !== undefined ? this.resolve.list(q.list).id : undefined;
    const rank = new Map<EntityID, number>();
    [...p.activeLists(), ...p.deletedLists()].forEach((id, i) => rank.set(id, i));
    const needle = q.text !== undefined ? trimWhitespaces(q.text) : "";
    const matches = [...p.allTaskIDs()].map((id) => p.task(id)).filter((t): t is TaskItem => t !== undefined).filter((t) =>
      // A task in a deleted list counts as deleted: only `deleted` finds it.
      !t.isHeading && (q.deleted || p.isLive(t.id)) && (listID === undefined || t.list === listID)
      && (q.done === undefined || (t.completedAt !== null) === q.done)
      && (needle === "" || containsFolded(t.title, needle) || containsFolded(t.notes, needle)));
    matches.sort((a, b) => {
      if ((a.completedAt !== null) !== (b.completedAt !== null)) return a.completedAt === null ? -1 : 1;
      const ra = rank.get(a.list) ?? Number.MAX_SAFE_INTEGER;
      const rb = rank.get(b.list) ?? Number.MAX_SAFE_INTEGER;
      if (ra !== rb) return ra - rb;
      if (a.completedAt !== null && a.completedAt !== b.completedAt) return (b.completedAt ?? 0) - (a.completedAt ?? 0);
      if (orderPrecedes(a.order, a.id, b.order, b.id)) return -1;
      if (orderPrecedes(b.order, b.id, a.order, a.id)) return 1;
      return 0;
    });
    return matches.map((t) => r.task(t));
  }
}

export { charCount };
