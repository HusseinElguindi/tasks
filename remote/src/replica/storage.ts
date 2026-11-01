// The replica's SQLite tables, in the Durable Object's storage. The CLI keeps the same things in files
// (TasksCore/Persistence.swift: log.jsonl, pending.jsonl, rejected.jsonl, snapshot.json); here each write is one
// transaction, so a 409 recovery has no half-done states to resume.

import { decodeOp, pendingFromJSON, unreadableOp, type PendingOp } from "../core/op.ts";
import { AppState, type TaskItem, type TaskList } from "../core/state.ts";
import type { ErrorBody, LogEntry, RawEntry } from "../core/wire.ts";
import type { Loaded, ReplicaStorage } from "./engine.ts";

const SCHEMA = [
  // The server's log from seq 0, contiguous: `op` is the server's stored text, verbatim.
  `CREATE TABLE IF NOT EXISTS log (seq INTEGER PRIMARY KEY, received INTEGER NOT NULL, hash TEXT NOT NULL, op TEXT NOT NULL)`,
  // Ops not yet seen in the log, oldest first, each as the exact JSON it is sent as.
  `CREATE TABLE IF NOT EXISTS pending (pos INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL, json TEXT NOT NULL)`,
  `CREATE INDEX IF NOT EXISTS pending_id ON pending (id)`,
  // Ops the server refused (invalid_op), kept for debugging. Never resent.
  `CREATE TABLE IF NOT EXISTS rejected (pos INTEGER PRIMARY KEY AUTOINCREMENT, json TEXT NOT NULL, error TEXT NOT NULL, at INTEGER NOT NULL)`,
  `CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)`,
  // The confirmed state at some cursor, as JSON split into parts (a row holds at most 2 MB).
  `CREATE TABLE IF NOT EXISTS snapshot (part INTEGER PRIMARY KEY, text TEXT NOT NULL)`,
];

/** Bumped when the snapshot's shape or the reducer changes: an old snapshot is then ignored and the log replayed. */
export const SNAPSHOT_SCHEMA = 1;
/** A snapshot is written once the log has grown this much past the last one. */
export const SNAPSHOT_EVERY = 1000;
/** UTF-16 units per snapshot row: at most 1.5 MB as UTF-8. */
const SNAPSHOT_PART = 500_000;

interface Snapshot {
  schema: number;
  cursor: number;
  base: string | null;
  tasks: TaskItem[];
  lists: TaskList[];
}

const entryOf = (seq: number, received: number, hash: string, op: string): LogEntry => {
  let raw: unknown = null;
  try {
    raw = JSON.parse(op);
  } catch {
    // stored by us from parsed JSON; can't happen
  }
  return { seq, received, hash, op: decodeOp(raw) ?? unreadableOp() };
};

export class SqlReplicaStorage implements ReplicaStorage {
  private cache: LogEntry[] | null = null;
  private snapshotCursor = -1;

  constructor(private readonly storage: DurableObjectStorage) {
    for (const s of SCHEMA) this.sql.exec(s);
  }

  private get sql(): SqlStorage {
    return this.storage.sql;
  }

  /** On wake: the snapshot (if it still matches the log) plus the log after it, and the pending queue. */
  load(): Loaded {
    const last = this.sql.exec<{ seq: number; hash: string }>("SELECT seq, hash FROM log ORDER BY seq DESC LIMIT 1").toArray()[0];
    const cursor = last ? last.seq + 1 : 0;
    const base = last ? last.hash : null;
    const snap = this.readSnapshot(cursor);
    const confirmed = new AppState();
    if (snap) {
      for (const t of snap.tasks) confirmed.tasks.set(t.id, t);
      for (const l of snap.lists) confirmed.lists.set(l.id, l);
    }
    this.snapshotCursor = snap ? snap.cursor : -1;
    for (const [seq, received, hash, op] of this.sql.exec("SELECT seq, received, hash, op FROM log WHERE seq >= ? ORDER BY seq", snap?.cursor ?? 0).raw()) {
      confirmed.apply(entryOf(seq as number, received as number, hash as string, op as string).op);
    }
    const pending: PendingOp[] = [];
    for (const [json] of this.sql.exec("SELECT json FROM pending ORDER BY pos").raw()) {
      const p = pendingFromJSON(json as string);
      if (p) pending.push(p);
    }
    return { confirmed, cursor, base, pending, recovering: this.meta("recovering") === "1" };
  }

  appendLog(entries: RawEntry[]): void {
    this.storage.transactionSync(() => {
      for (const e of entries) this.sql.exec("INSERT INTO log (seq, received, hash, op) VALUES (?, ?, ?, ?)", e.entry.seq, e.entry.received, e.entry.hash, e.opText);
    });
    if (this.cache) for (const e of entries) this.cache.push(e.entry);
  }

  addPending(ops: PendingOp[]): void {
    this.storage.transactionSync(() => {
      for (const p of ops) this.sql.exec("INSERT INTO pending (id, json) VALUES (?, ?)", p.op.id, p.json);
    });
  }

  dropPending(ids: string[]): void {
    this.storage.transactionSync(() => {
      for (const id of ids) this.sql.exec("DELETE FROM pending WHERE id = ?", id);
    });
  }

  appendRejected(json: string, error: ErrorBody, at: number): void {
    this.sql.exec("INSERT INTO rejected (json, error, at) VALUES (?, ?, ?)", json, JSON.stringify(error), at);
  }

  beginRecovery(pending: PendingOp[]): PendingOp[] {
    return this.storage.transactionSync(() => {
      const queue: PendingOp[] = [];
      const seen = new Set<string>();
      for (const [op] of this.sql.exec("SELECT op FROM log ORDER BY seq").raw()) {
        const p = pendingFromJSON(op as string);
        if (!p || seen.has(p.op.id)) continue;
        seen.add(p.op.id);
        queue.push(p);
      }
      for (const p of pending) {
        if (seen.has(p.op.id)) continue;
        seen.add(p.op.id);
        queue.push(p);
      }
      this.sql.exec("DELETE FROM pending");
      for (const p of queue) this.sql.exec("INSERT INTO pending (id, json) VALUES (?, ?)", p.op.id, p.json);
      this.sql.exec("DELETE FROM snapshot");
      this.sql.exec("DELETE FROM log");
      this.setMeta("recovering", "1");
      this.cache = null;
      this.snapshotCursor = -1;
      return queue;
    });
  }

  finishRecovery(): void {
    this.sql.exec("DELETE FROM meta WHERE key = 'recovering'");
  }

  entries(): LogEntry[] {
    if (!this.cache) {
      const out: LogEntry[] = [];
      for (const [seq, received, hash, op] of this.sql.exec("SELECT seq, received, hash, op FROM log ORDER BY seq").raw()) {
        out.push(entryOf(seq as number, received as number, hash as string, op as string));
      }
      this.cache = out;
    }
    return this.cache;
  }

  snapshotIfDue(state: AppState, cursor: number, base: string | null): void {
    if (cursor - Math.max(this.snapshotCursor, 0) < SNAPSHOT_EVERY) return;
    const snap: Snapshot = { schema: SNAPSHOT_SCHEMA, cursor, base, tasks: [...state.tasks.values()], lists: [...state.lists.values()] };
    const text = JSON.stringify(snap);
    this.storage.transactionSync(() => {
      this.sql.exec("DELETE FROM snapshot");
      for (let i = 0, part = 0; i < text.length; i += SNAPSHOT_PART, part++) {
        this.sql.exec("INSERT INTO snapshot (part, text) VALUES (?, ?)", part, text.slice(i, i + SNAPSHOT_PART));
      }
    });
    this.snapshotCursor = cursor;
  }

  /** Counts, for status and tests. */
  counts(): { log: number; pending: number; rejected: number; snapshotCursor: number } {
    const n = (table: string) => this.sql.exec<{ n: number }>(`SELECT COUNT(*) AS n FROM ${table}`).one().n;
    return { log: n("log"), pending: n("pending"), rejected: n("rejected"), snapshotCursor: this.snapshotCursor };
  }

  /** The snapshot if it's this schema and still a prefix of the log (its base is the hash at its cursor − 1). */
  private readSnapshot(cursor: number): Snapshot | null {
    const parts = this.sql.exec<{ text: string }>("SELECT text FROM snapshot ORDER BY part").toArray();
    if (parts.length === 0) return null;
    let snap: Snapshot;
    try {
      snap = JSON.parse(parts.map((p) => p.text).join(""));
    } catch {
      return null;
    }
    if (snap.schema !== SNAPSHOT_SCHEMA || snap.cursor > cursor || snap.cursor < 0) return null;
    if (snap.cursor > 0) {
      const row = this.sql.exec<{ hash: string }>("SELECT hash FROM log WHERE seq = ?", snap.cursor - 1).toArray()[0];
      if (!row || row.hash !== snap.base) return null;
    }
    return snap;
  }

  private meta(key: string): string | undefined {
    return this.sql.exec<{ value: string }>("SELECT value FROM meta WHERE key = ?", key).toArray()[0]?.value;
  }

  private setMeta(key: string, value: string): void {
    this.sql.exec("INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value", key, value);
  }
}
