// Refs: abbreviated ids for output, and resolving what a caller typed. Port of TasksCLI/Refs.swift.

import type { Projection } from "../core/projection.ts";
import { utf8Compare } from "../core/ordering.ts";
import type { TaskItem, TaskList } from "../core/state.ts";
import { CLIError } from "./errors.ts";
import { charCount, charPrefix, equalsIgnoringCase, trimWhitespaces } from "./text.ts";

const encoder = new TextEncoder();

/** The shortest unique prefix of each id, at least 6 characters, like Git's abbreviated hashes. */
export class RefIndex {
  private lengths = new Map<string, number>();

  constructor(ids: Iterable<string>) {
    const sorted = [...ids].map((id) => ({ id, bytes: encoder.encode(id) })).sort((a, b) => utf8Compare(a.id, b.id));
    const common = (a: Uint8Array, b: Uint8Array) => {
      let n = 0;
      while (n < a.length && n < b.length && a[n] === b[n]) n++;
      return n;
    };
    sorted.forEach((x, i) => {
      let shared = 0;
      if (i > 0) shared = Math.max(shared, common(sorted[i - 1].bytes, x.bytes));
      if (i + 1 < sorted.length) shared = Math.max(shared, common(x.bytes, sorted[i + 1].bytes));
      this.lengths.set(x.id, Math.min(charCount(x.id), Math.max(6, shared + 1)));
    });
  }

  ref(id: string): string {
    return charPrefix(id, this.lengths.get(id) ?? 6);
  }
}

const byID = <T extends { id: string }>(a: T, b: T) => utf8Compare(a.id, b.id);

/** A full id, a unique id prefix of 4+ characters, or for lists a name. Missing or ambiguous refs fail closed. */
export class Resolver {
  constructor(private p: Projection) {}

  task(ref: string, includeDeleted = false): TaskItem {
    const r = trimWhitespaces(ref);
    if (r === "") throw new CLIError("NotFound", "An empty task ref.", "task");
    const exact = this.p.task(r);
    if (exact) return this.visible(exact, r, includeDeleted);
    const lower = r.toLowerCase();
    if (charCount(lower) < 4) {
      throw new CLIError("NotFound", `No task ${r}. A ref is an id or an id prefix of at least 4 characters.`, "task");
    }
    const matches = [...this.p.allTaskIDs()].filter((id) => id.startsWith(lower)).map((id) => this.p.task(id)!).filter(Boolean);
    const live = matches.filter((t) => !t.deleted);
    const pool = includeDeleted ? matches : live;
    if (pool.length === 1) return pool[0];
    if (pool.length === 0) {
      if (matches.length === 1) {
        throw new CLIError("NotFound", `Task ${r} ("${matches[0].title}") is deleted; tasks restore ${r} brings it back.`, "task");
      }
      throw new CLIError("NotFound", `No task ${r}.`, "task");
    }
    const refs = new RefIndex(this.p.allTaskIDs());
    const names = [...pool].sort(byID).map((t) => `${refs.ref(t.id)} "${t.title}"`);
    throw new CLIError("Ambiguous", `${r} matches ${pool.length} tasks: ${names.join(", ")}.`, "task",
      pool.map((t) => t.id).sort(utf8Compare));
  }

  private visible(t: TaskItem, ref: string, includeDeleted: boolean): TaskItem {
    if (t.deleted && !includeDeleted) {
      throw new CLIError("NotFound", `Task ${ref} ("${t.title}") is deleted; tasks restore ${ref} brings it back.`, "task");
    }
    return t;
  }

  tasks(refs: string[], includeDeleted = false): TaskItem[] {
    const seen = new Set<string>();
    return refs.map((r) => this.task(r, includeDeleted)).filter((t) => {
      if (seen.has(t.id)) return false;
      seen.add(t.id);
      return true;
    });
  }

  /** By id, then by name (case-insensitive; active lists first, then archived), then by id prefix. */
  list(ref: string): TaskList {
    const r = trimWhitespaces(ref);
    if (r === "") throw new CLIError("NotFound", "An empty list ref.", "list");
    const exact = this.p.list(r);
    if (exact) return exact;
    const all = [...this.p.allListIDs()].map((id) => this.p.list(id)!).filter(Boolean);
    const named = all.filter((l) => equalsIgnoringCase(l.name, r));
    const active = named.filter((l) => l.archivedAt === null);
    for (const group of [active, named]) {
      if (group.length === 0) continue;
      if (group.length === 1) return group[0];
      throw this.ambiguous(r, group, "name");
    }
    const lower = r.toLowerCase();
    if (charCount(lower) >= 4) {
      const prefixed = all.filter((l) => l.id.startsWith(lower));
      if (prefixed.length === 1) return prefixed[0];
      if (prefixed.length > 1) throw this.ambiguous(r, prefixed, "id");
    }
    const names = active.length === 0 ? this.p.activeLists().map((id) => this.p.list(id)?.name).filter((n) => n !== undefined) : [];
    const hint = names.length === 0 ? "" : ` Lists: ${names.join(", ")}.`;
    throw new CLIError("NotFound", `No list "${r}".${hint}`, "list");
  }

  private ambiguous(r: string, lists: TaskList[], _by: string): CLIError {
    const refs = new RefIndex(this.p.allListIDs());
    const names = [...lists].sort(byID).map((l) => `${refs.ref(l.id)} "${l.name}"${l.archivedAt !== null ? " (archived)" : ""}`);
    return new CLIError("Ambiguous", `"${r}" matches ${lists.length} lists: ${names.join(", ")}. Use an id prefix.`, "list",
      lists.map((l) => l.id).sort(utf8Compare));
  }
}
