// tasks.d.ts: the API a `tasks run` script sees. Run one with `tasks run script.ts` (--dry-run to preview).
// The whole script is one change: written when it returns, nothing written if it throws. `return` a value to
// get it back; console.log lines come back too. No files, network or env: only `tasks`.

/** A day, "YYYY-MM-DD", no time or zone. Compares correctly as a string. */
type CalendarDate = string;
/** "YYYY-MM-DD", or what the app's date field reads: "today", "fri", "next week", "3d", "nov 9". null clears. */
type DateInput = string | null;
/** A task or list id, a unique id prefix (4+ chars), or for lists a name. */
type Ref = string;
/** up/down: one row among the list's open rows. after/before: next to an open task or a heading, in its list (for a task,
 *  after a heading is the top of its section; a heading moves with its section, see move). */
type Place = "top" | "bottom" | "up" | "down" | { after: Ref } | { before: Ref };

interface Task {
  id: string;
  ref: string;
  kind?: "heading" /* only on a heading: a row that groups the tasks under it */;
  list: string;
  listName: string;
  title: string;
  notes: string /* Markdown */;
  when: CalendarDate | null;
  deadline: CalendarDate | null;
  done: boolean;
  completedAt: number | null;
  deleted: boolean;
  createdAt: number;
  updatedAt: number;
}
interface List {
  id: string;
  ref: string;
  name: string;
  notes: string /* Markdown, under the list's title */;
  archivedAt: number | null;
  open: number /* open tasks, headings not counted */;
}
/** What a write did. `batch` is this run's change id (tasks log, tasks undo). */
interface Change {
  batch: string | null /* null when nothing changed */;
  summary: string;
  tasks: Task[];
  lists: List[];
  skipped?: string[] /* undo: later edits it kept */;
}

declare const tasks: {
  /** Today: open tasks with When today or earlier, or due today or overdue, grouped by list in sidebar order, then those completed today. */
  today(): Promise<{ date: CalendarDate; groups: { list: List; tasks: Task[] }[]; done: Task[] }>;
  /** The sidebar: active lists in order, each with its open count. */
  lists(): Promise<List[]>;
  /** A list: its notes, then its rows in order (open tasks, and headings with the tasks under them), then completed tasks newest first. No list means the first one. */
  list(list?: Ref): Promise<{ list: List; open: Task[] /* rows in order: headings have kind "heading" */; completed: Task[] }>;
  /** Archived lists, most recently archived first. */
  archive(): Promise<List[]>;
  /** One task: every field and its notes (the detail pane). Deleted tasks too. */
  task(task: Ref): Promise<Task>;
  /** Tasks whose title or notes contain the text (any list; read-only). Empty text matches everything. Headings aren't tasks: tasks ls lists them. */
  find(q?: { text?: string; list?: Ref; done?: boolean; deleted?: boolean }): Promise<Task[]>;
  /** What a date phrase means today, without writing anything: null if it reads as no date. */
  date(text: string): Promise<CalendarDate | null>;
  /** New task, at the bottom of the list's open tasks (or the place given). No list means the first list. --key makes it safe to repeat: same key, same task. */
  add(t: { title: string; list?: Ref; notes?: string; when?: DateInput; deadline?: DateInput; place?: Place; key?: string; id?: string }): Promise<Task>;
  /** Rename a task or a heading. */
  rename(task: Ref, title: string): Promise<Change>;
  /** Replace a task's or a heading's notes (Markdown), or add a line with --append. - reads stdin. */
  setNotes(task: Ref, notes: string): Promise<Change>;
  /** Complete tasks. Already done ones are left alone. */
  complete(tasks: Ref | Ref[]): Promise<Change>;
  /** Mark tasks as not done. */
  uncomplete(tasks: Ref | Ref[]): Promise<Change>;
  /** ⌘K: complete them all, unless all are done, then mark them all not done. */
  toggle(tasks: Ref | Ref[]): Promise<Change>;
  /** Set When: the day a task shows in Today. A date, a phrase the date field reads ("fri", "next week", "3d"), or none. */
  setWhen(tasks: Ref | Ref[], date: DateInput): Promise<Change>;
  /** Set or remove the Deadline. */
  setDeadline(tasks: Ref | Ref[], date: DateInput): Promise<Change>;
  /** Move tasks to another list (they land at the bottom, in the order given), or to a place: next to an open task or a heading (in its list; --after a heading is the top of its section), the top or bottom, or one row up or down. A heading moves on its own, with its section: --before another heading, --after a row (after that row's section), --top, --bottom, --up, --down. */
  move(tasks: Ref | Ref[], to?: { list?: Ref; place?: Place }): Promise<Change>;
  /** Delete tasks. A heading goes alone: its tasks stay, under the heading above it. tasks restore (or undo) brings them back. */
  delete(tasks: Ref | Ref[]): Promise<Change>;
  /** Bring back deleted tasks. */
  restore(tasks: Ref | Ref[]): Promise<Change>;
  /** New heading, a row that groups the tasks under it down to the next heading: at the bottom of the list, above --before REF, or after --after REF (after a heading, that's after its section). No list means the place's list, else the first list. Headings never show in today, find or counts. */
  addHeading(h: { name: string; list?: Ref; notes?: string; place?: Place }): Promise<Task>;
  /** New list, at the bottom of the sidebar (or the place given). */
  addList(name: string, place?: Place): Promise<List>;
  /** Rename a list. */
  renameList(list: Ref, name: string): Promise<Change>;
  /** Replace a list's notes (Markdown, the text under its title), or add a line with --append. - reads stdin. */
  setListNotes(list: Ref, notes: string): Promise<Change>;
  /** Move a list in the sidebar. */
  moveList(list: Ref, place: Place): Promise<Change>;
  /** Archive a list (the app's "delete list"). Its tasks are kept and come back with it. */
  archiveList(list: Ref): Promise<Change>;
  /** Unarchive a list, back to its old place in the sidebar. */
  unarchiveList(list: Ref): Promise<Change>;
  /** Undo a change from the log: by batch id, or your newest one. Fields edited since are kept and reported, unless --force. */
  undo(batch?: string): Promise<Change>;
};
