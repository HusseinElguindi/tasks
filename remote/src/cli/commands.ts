// The code-mode half of the CLI's command table (TasksCLI/Commands.swift): each method's parameters, its argument
// decoding, what it returns, and `tasks.d.ts` generated from the table (a test holds it to the CLI's copy).

import { Context } from "./context.ts";
import { CLIError } from "./errors.ts";
import { Render, type Json } from "./render.ts";

type ParamType = "text" | "ref" | "refs" | "listRef" | "date" | "place" | "bool" | "int";

const TS: Record<ParamType, string> = {
  text: "string", ref: "Ref", listRef: "Ref", refs: "Ref | Ref[]", date: "DateInput", place: "Place", bool: "boolean", int: "number",
};

interface Param {
  name: string;
  type: ParamType;
  optional?: boolean;
}

type MethodArg = { param: string } | { object: string; fields: string[] };

type Args = Record<string, Json>;

/** What a method returns: a value, a change (rendered once it's built), or a created entity. */
type Reply = { value: Json } | { change: true } | { createdTask: string } | { createdList: string };

interface Method {
  method: string;
  doc: string;
  params: Param[];
  signature: MethodArg[];
  returns: string;
  run: (c: Context, a: Args) => Reply;
}

const text = (a: Args, k: string) => (typeof a[k] === "string" ? (a[k] as string) : undefined);
const bool = (a: Args, k: string) => (typeof a[k] === "boolean" ? (a[k] as boolean) : false);

function refs(a: Args, k: string): string[] {
  const v = a[k];
  if (typeof v === "string") return [v];
  if (Array.isArray(v)) {
    return v.map((x) => {
      if (typeof x !== "string") throw CLIError.invalid(`${k} must be refs (strings).`, k);
      return x;
    });
  }
  throw CLIError.invalid(`${k} is required.`, k);
}

function required(a: Args, k: string): string {
  const v = a[k];
  if (typeof v !== "string") throw CLIError.invalid(`${k} is required.`, k);
  return v;
}

const P = (name: string, type: ParamType, optional = false): Param => ({ name, type, optional });
const change = { change: true } as const;

export const METHODS: Method[] = [
  // Views
  {
    method: "today", doc: "Today: open tasks with When today or earlier, or due today or overdue, grouped by list in sidebar order, then those completed today.",
    params: [], signature: [], returns: "{ date: CalendarDate; groups: { list: List; tasks: Task[] }[]; done: Task[] }",
    run: (c) => ({ value: c.todayJSON() }),
  },
  {
    method: "lists", doc: "The sidebar: active lists in order, each with its open count.", params: [], signature: [], returns: "List[]",
    run: (c) => ({ value: c.listsJSON() as unknown as Json }),
  },
  {
    method: "list", doc: "A list: its notes, then its rows in order (open tasks, and headings with the tasks under them), then completed tasks newest first. No list means the first one.",
    params: [P("list", "listRef", true), P("done", "bool", true)], signature: [{ param: "list" }],
    returns: "{ list: List; open: Task[] /* rows in order: headings have kind \"heading\" */; completed: Task[] }",
    run: (c, a) => ({ value: c.listJSON(text(a, "list")) }),
  },
  {
    method: "archive", doc: "Archived lists, most recently archived first.", params: [], signature: [], returns: "List[]",
    run: (c) => ({ value: c.archiveJSON() as unknown as Json }),
  },
  {
    method: "task", doc: "One task: every field and its notes (the detail pane). Deleted tasks too.",
    params: [P("task", "ref"), P("history", "bool", true)], signature: [{ param: "task" }], returns: "Task",
    run: (c, a) => {
      const t = c.resolve.task(required(a, "task"), true);
      return { value: new Render(c.p).task(t) as unknown as Json };
    },
  },
  {
    method: "find", doc: "Tasks whose title or notes contain the text (any list; read-only). Empty text matches everything. Headings aren't tasks: tasks ls lists them.",
    params: [P("text", "text", true), P("list", "listRef", true), P("done", "bool", true), P("deleted", "bool", true)],
    signature: [{ object: "q", fields: ["text", "list", "done", "deleted"] }], returns: "Task[]",
    run: (c, a) => ({
      value: c.find({ text: text(a, "text"), list: text(a, "list"), done: typeof a.done === "boolean" ? a.done : undefined, deleted: bool(a, "deleted") }) as unknown as Json,
    }),
  },
  {
    method: "date", doc: "What a date phrase means today, without writing anything: null if it reads as no date.",
    params: [P("text", "text")], signature: [{ param: "text" }], returns: "CalendarDate | null",
    run: (c, a) => ({ value: c.resolveDate(required(a, "text")) }),
  },
  // Tasks
  {
    method: "add", doc: "New task, at the bottom of the list's open tasks (or the place given). No list means the first list. --key makes it safe to repeat: same key, same task.",
    params: [P("title", "text"), P("list", "listRef", true), P("notes", "text", true), P("when", "date", true), P("deadline", "date", true),
      P("place", "place", true), P("key", "text", true), P("id", "text", true)],
    signature: [{ object: "t", fields: ["title", "list", "notes", "when", "deadline", "place", "key", "id"] }], returns: "Task",
    run: (c, a) => {
      const t = c.add({
        title: required(a, "title"), list: text(a, "list"), notes: text(a, "notes"), when: c.date(a.when, "when"),
        deadline: c.date(a.deadline, "deadline"), place: c.place(a.place), id: text(a, "id"), key: text(a, "key"),
      });
      return { createdTask: t.id };
    },
  },
  {
    method: "rename", doc: "Rename a task or a heading.", params: [P("task", "ref"), P("title", "text")],
    signature: [{ param: "task" }, { param: "title" }], returns: "Change",
    run: (c, a) => (c.rename(required(a, "task"), required(a, "title")), change),
  },
  {
    method: "setNotes", doc: "Replace a task's or a heading's notes (Markdown), or add a line with --append. - reads stdin.",
    params: [P("task", "ref"), P("notes", "text"), P("append", "bool", true)], signature: [{ param: "task" }, { param: "notes" }], returns: "Change",
    run: (c, a) => (c.setNotes(required(a, "task"), required(a, "notes"), bool(a, "append")), change),
  },
  {
    method: "complete", doc: "Complete tasks. Already done ones are left alone.", params: [P("tasks", "refs")], signature: [{ param: "tasks" }], returns: "Change",
    run: (c, a) => (c.complete(refs(a, "tasks")), change),
  },
  {
    method: "uncomplete", doc: "Mark tasks as not done.", params: [P("tasks", "refs")], signature: [{ param: "tasks" }], returns: "Change",
    run: (c, a) => (c.uncomplete(refs(a, "tasks")), change),
  },
  {
    method: "toggle", doc: "⌘K: complete them all, unless all are done, then mark them all not done.", params: [P("tasks", "refs")],
    signature: [{ param: "tasks" }], returns: "Change",
    run: (c, a) => (c.toggle(refs(a, "tasks")), change),
  },
  {
    method: "setWhen", doc: "Set When: the day a task shows in Today. A date, a phrase the date field reads (\"fri\", \"next week\", \"3d\"), or none.",
    params: [P("tasks", "refs"), P("date", "date")], signature: [{ param: "tasks" }, { param: "date" }], returns: "Change",
    run: (c, a) => (c.setWhen(refs(a, "tasks"), c.date(a.date ?? null, "date")), change),
  },
  {
    method: "setDeadline", doc: "Set or remove the Deadline.", params: [P("tasks", "refs"), P("date", "date")],
    signature: [{ param: "tasks" }, { param: "date" }], returns: "Change",
    run: (c, a) => (c.setDeadline(refs(a, "tasks"), c.date(a.date ?? null, "date")), change),
  },
  {
    method: "move", doc: "Move tasks to another list (they land at the bottom, in the order given), or to a place: next to an open task or a heading (in its list; --after a heading is the top of its section), the top or bottom, or one row up or down. A heading moves on its own, with its section: --before another heading, --after a row (after that row's section), --top, --bottom, --up, --down.",
    params: [P("tasks", "refs"), P("list", "listRef", true), P("place", "place", true)],
    signature: [{ param: "tasks" }, { object: "to", fields: ["list", "place"] }], returns: "Change",
    run: (c, a) => (c.move(refs(a, "tasks"), text(a, "list"), c.place(a.place)), change),
  },
  {
    method: "delete", doc: "Delete tasks. A heading goes alone: its tasks stay, under the heading above it. tasks restore (or undo) brings them back.",
    params: [P("tasks", "refs")], signature: [{ param: "tasks" }], returns: "Change",
    run: (c, a) => (c.delete(refs(a, "tasks")), change),
  },
  {
    method: "restore", doc: "Bring back deleted tasks.", params: [P("tasks", "refs")], signature: [{ param: "tasks" }], returns: "Change",
    run: (c, a) => (c.restore(refs(a, "tasks")), change),
  },
  // Headings
  {
    method: "addHeading", doc: "New heading, a row that groups the tasks under it down to the next heading: at the bottom of the list, above --before REF, or after --after REF (after a heading, that's after its section). No list means the place's list, else the first list. Headings never show in today, find or counts.",
    params: [P("name", "text"), P("list", "listRef", true), P("notes", "text", true), P("place", "place", true)],
    signature: [{ object: "h", fields: ["name", "list", "notes", "place"] }], returns: "Task",
    run: (c, a) => ({ createdTask: c.addHeading({ name: required(a, "name"), list: text(a, "list"), notes: text(a, "notes"), place: c.place(a.place) }).id }),
  },
  // Lists
  {
    method: "addList", doc: "New list, at the bottom of the sidebar (or the place given).", params: [P("name", "text"), P("place", "place", true)],
    signature: [{ param: "name" }, { param: "place" }], returns: "List",
    run: (c, a) => ({ createdList: c.addList(required(a, "name"), c.place(a.place)).id }),
  },
  {
    method: "renameList", doc: "Rename a list.", params: [P("list", "listRef"), P("name", "text")], signature: [{ param: "list" }, { param: "name" }], returns: "Change",
    run: (c, a) => (c.renameList(required(a, "list"), required(a, "name")), change),
  },
  {
    method: "setListNotes", doc: "Replace a list's notes (Markdown, the text under its title), or add a line with --append. - reads stdin.",
    params: [P("list", "listRef"), P("notes", "text"), P("append", "bool", true)], signature: [{ param: "list" }, { param: "notes" }], returns: "Change",
    run: (c, a) => (c.setListNotes(required(a, "list"), required(a, "notes"), bool(a, "append")), change),
  },
  {
    method: "moveList", doc: "Move a list in the sidebar.", params: [P("list", "listRef"), P("place", "place")], signature: [{ param: "list" }, { param: "place" }], returns: "Change",
    run: (c, a) => (c.moveList(required(a, "list"), c.place(a.place)), change),
  },
  {
    method: "archiveList", doc: "Archive a list (the app's \"delete list\"). Its tasks are kept and come back with it.", params: [P("list", "listRef")],
    signature: [{ param: "list" }], returns: "Change",
    run: (c, a) => (c.archiveList(required(a, "list")), change),
  },
  {
    method: "unarchiveList", doc: "Unarchive a list, back to its old place in the sidebar.", params: [P("list", "listRef")],
    signature: [{ param: "list" }], returns: "Change",
    run: (c, a) => (c.unarchiveList(required(a, "list")), change),
  },
  // History
  {
    method: "undo", doc: "Undo a change from the log: by batch id, or your newest one. Fields edited since are kept and reported, unless --force.",
    params: [P("batch", "text", true), P("force", "bool", true)], signature: [{ param: "batch" }], returns: "Change",
    run: (c, a) => (c.undo(text(a, "batch"), bool(a, "force")), change),
  },
];

const byName = new Map(METHODS.map((m) => [m.method, m]));
const param = (m: Method, name: string) => m.params.find((p) => p.name === name)!;

const isObject = (v: Json | undefined): v is { [k: string]: Json } => typeof v === "object" && v !== null && !Array.isArray(v);

/** Positional code-mode arguments → the method's named parameters, type-checked (the script's types aren't checked). */
export function decode(m: Method, args: Json[]): Args {
  const name = `tasks.${m.method}`;
  if (args.length > m.signature.length) {
    throw CLIError.invalid(`${name} takes ${m.signature.length} argument${m.signature.length === 1 ? "" : "s"}; got ${args.length}.`);
  }
  const out: Args = {};
  m.signature.forEach((arg, i) => {
    if (i >= args.length) return;
    const v = args[i];
    if ("param" in arg) {
      if (v === null && param(m, arg.param).type !== "date") return;
      out[arg.param] = v;
    } else {
      if (v === null) return;
      if (!isObject(v)) throw CLIError.invalid(`${name}: ${arg.object} must be an object.`, arg.object);
      // The Swift host reads objects with sorted keys, so the first bad field it names is the first in sorted order.
      for (const key of Object.keys(v).sort()) {
        if (!arg.fields.includes(key)) {
          throw CLIError.invalid(`${name}: ${arg.object} has no field ${key} (it takes ${arg.fields.join(", ")}).`, key);
        }
        if (v[key] === null && param(m, key).type !== "date") continue;
        out[key] = v[key];
      }
    }
  });
  const accepted = new Set(m.signature.flatMap((arg) => ("param" in arg ? [arg.param] : arg.fields)));
  for (const p of m.params) {
    if (!accepted.has(p.name)) continue;
    const v = out[p.name];
    if (v === undefined) {
      if (!p.optional) throw CLIError.invalid(`${name} needs ${p.name}.`, p.name);
      continue;
    }
    let ok: boolean;
    switch (p.type) {
      case "text": case "ref": case "listRef": ok = typeof v === "string"; break;
      case "refs": ok = typeof v === "string" || (Array.isArray(v) && v.every((x) => typeof x === "string")); break;
      case "date": ok = typeof v === "string" || v === null; break;
      case "place": ok = typeof v === "string" || (isObject(v) && (typeof v.after === "string" || typeof v.before === "string")); break;
      case "bool": ok = typeof v === "boolean"; break;
      case "int": ok = typeof v === "number" && Number.isInteger(v); break;
    }
    if (!ok) throw CLIError.invalid(`${name}: ${p.name} must be ${TS[p.type]}.`, p.name);
  }
  return out;
}

function distance(a: string, b: string): number {
  const x = Array.from(a.toLowerCase());
  const y = Array.from(b.toLowerCase());
  if (x.length === 0) return y.length;
  const row = Array.from({ length: y.length + 1 }, (_, j) => j);
  for (let i = 1; i <= x.length; i++) {
    let prev = row[0];
    row[0] = i;
    for (let j = 1; j <= y.length; j++) {
      const cur = row[j];
      row[j] = Math.min(row[j] + 1, row[j - 1] + 1, prev + (x[i - 1] === y[j - 1] ? 0 : 1));
      prev = cur;
    }
  }
  return row[y.length];
}

export type CallResult = { result: Json } | { error: { type: string; message: string; field?: string | null; candidates?: string[] } };

/** One `tasks.<method>(…)` call from a script, run like the CLI command of that name. */
export function answer(c: Context, method: string, args: Json[]): CallResult {
  try {
    const m = byName.get(method);
    if (!m) {
      let near: string | undefined;
      for (const n of METHODS.map((x) => x.method)) if (near === undefined || distance(n, method) < distance(near, method)) near = n;
      const hint = near !== undefined && distance(near, method) <= 3 ? `; did you mean ${near}?` : "";
      throw new CLIError("NotFound", `There's no tasks.${method}${hint} (tasks types lists them).`);
    }
    const before = c.ops.length;
    const reply = m.run(c, decode(m, args));
    let result: Json;
    if ("value" in reply) result = reply.value;
    else if ("change" in reply) result = c.changeJSON(before);
    else if ("createdTask" in reply) result = new Render(c.p).task(c.p.task(reply.createdTask)!) as unknown as Json;
    else result = new Render(c.p).list(c.p.list(reply.createdList)!) as unknown as Json;
    return { result };
  } catch (e) {
    if (e instanceof CLIError) {
      return { error: { type: e.kind === "Usage" ? "Invalid" : e.kind, message: e.message, field: e.field, candidates: e.candidates } };
    }
    return { error: { type: "Error", message: String(e) } };
  }
}

// MARK: tasks.d.ts

interface Field {
  name: string;
  ts: string;
  optional?: boolean;
}

const SHAPES: Record<"task" | "list" | "change", Field[]> = {
  task: [
    { name: "id", ts: "string" }, { name: "ref", ts: "string" },
    { name: "kind", ts: "\"heading\" /* only on a heading: a row that groups the tasks under it */", optional: true },
    { name: "list", ts: "string" }, { name: "listName", ts: "string" }, { name: "title", ts: "string" },
    { name: "notes", ts: "string /* Markdown */" }, { name: "when", ts: "CalendarDate | null" },
    { name: "deadline", ts: "CalendarDate | null" }, { name: "done", ts: "boolean" },
    { name: "completedAt", ts: "number | null" }, { name: "deleted", ts: "boolean" },
    { name: "createdAt", ts: "number" }, { name: "updatedAt", ts: "number" },
  ],
  list: [
    { name: "id", ts: "string" }, { name: "ref", ts: "string" }, { name: "name", ts: "string" },
    { name: "notes", ts: "string /* Markdown, under the list's title */" },
    { name: "archivedAt", ts: "number | null" }, { name: "open", ts: "number /* open tasks, headings not counted */" },
  ],
  change: [
    { name: "batch", ts: "string | null /* null when nothing changed */" }, { name: "summary", ts: "string" },
    { name: "tasks", ts: "Task[]" }, { name: "lists", ts: "List[]" },
    { name: "skipped", ts: "string[] /* undo: later edits it kept */", optional: true },
  ],
};

/** The field order of each JSON shape, for tests. */
export const SHAPE_KEYS = {
  task: SHAPES.task.map((f) => f.name),
  list: SHAPES.list.map((f) => f.name),
  change: SHAPES.change.map((f) => f.name),
};

/** `tasks.d.ts`, generated from the table and the shapes exactly as `TypeScript.declarations()` does. */
export function declarations(): string {
  const iface = (name: string, fields: Field[]) =>
    `interface ${name} {\n` + fields.map((f) => `  ${f.name}${f.optional ? "?" : ""}: ${f.ts};`).join("\n") + "\n}";
  const out = [
    "// tasks.d.ts: the API a `tasks run` script sees. Run one with `tasks run script.ts` (--dry-run to preview).",
    "// The whole script is one change: written when it returns, nothing written if it throws. `return` a value to",
    "// get it back; console.log lines come back too. No files, network or env: only `tasks`.",
    "",
    "/** A day, \"YYYY-MM-DD\", no time or zone. Compares correctly as a string. */",
    "type CalendarDate = string;",
    "/** \"YYYY-MM-DD\", or what the app's date field reads: \"today\", \"fri\", \"next week\", \"3d\", \"nov 9\". null clears. */",
    "type DateInput = string | null;",
    "/** A task or list id, a unique id prefix (4+ chars), or for lists a name. */",
    "type Ref = string;",
    "/** up/down: one row among the list's open rows. after/before: next to an open task or a heading, in its list (for a task,",
    " *  after a heading is the top of its section; a heading moves with its section, see move). */",
    "type Place = \"top\" | \"bottom\" | \"up\" | \"down\" | { after: Ref } | { before: Ref };",
    "",
    iface("Task", SHAPES.task),
    iface("List", SHAPES.list),
    "/** What a write did. `batch` is this run's change id (tasks log, tasks undo). */",
    iface("Change", SHAPES.change),
    "",
    "declare const tasks: {",
  ];
  for (const m of METHODS) {
    const args = m.signature.map((arg) => {
      if ("param" in arg) {
        const p = param(m, arg.param);
        return `${arg.param}${p.optional ? "?" : ""}: ${TS[p.type]}`;
      }
      const inner = arg.fields.map((f) => {
        const p = param(m, f);
        return `${f}${p.optional ? "?" : ""}: ${TS[p.type]}`;
      }).join("; ");
      const allOptional = arg.fields.every((f) => param(m, f).optional);
      return `${arg.object}${allOptional ? "?" : ""}: { ${inner} }`;
    }).join(", ");
    out.push(`  /** ${m.doc} */`);
    out.push(`  ${m.method}(${args}): Promise<${m.returns}>;`);
  }
  out.push("};");
  return out.join("\n") + "\n";
}
