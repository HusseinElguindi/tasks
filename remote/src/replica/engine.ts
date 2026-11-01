// The replica's sync loop: a port of TasksCore/Store.swift (`runSync` and what it calls) and of TasksCLI's
// `Session` around it (Replica.swift: `sync` with its retries, `commit`). Storage and transport are passed in, so
// this runs the same in the Durable Object and in Node tests.

import { AppState } from "../core/state.ts";
import { dayContaining } from "../core/day.ts";
import { pendingOf, type Op, type PendingOp } from "../core/op.ts";
import { Projection } from "../core/projection.ts";
import { syncBody, type ErrorBody, type LogEntry, type RawEntry, type SyncOutcome, type SyncPage } from "../core/wire.ts";
import { CLIError } from "../cli/errors.ts";

export const MAX_OPS_PER_REQUEST = 500;
export const MAX_BYTES_PER_REQUEST = 900_000;
/** Store's backoff: 1 s, doubling, at most 60 s. */
const FIRST_BACKOFF_MS = 1000;
const MAX_BACKOFF_MS = 60_000;

/** The fixed Inbox op every replica sends (TasksCore/Seed.swift), so the server stores it once. */
export const INBOX_LIST_ID = "00000000-0000-0000-0000-000000000001";
export const INBOX_OP_ID = "00000000-0000-0000-0000-000000000002";

export type SyncState =
  | { kind: "off" }
  | { kind: "syncing" }
  | { kind: "idle"; lastSynced: number }
  | { kind: "retrying"; at: number; reason: string }
  | { kind: "checkToken" }
  | { kind: "failed"; message: string };

/** One `/v1/sync` request body out, its classified response back. */
export type Transport = (body: string) => Promise<SyncOutcome>;

/** What the engine persists. Each call is one atomic write. */
export interface ReplicaStorage {
  /** A page that continues the log: append it. */
  appendLog(entries: RawEntry[]): void;
  addPending(ops: PendingOp[]): void;
  /** Ops that came back in the log, or were rejected, leave pending (every row with that id). */
  dropPending(ids: string[]): void;
  appendRejected(json: string, error: ErrorBody, at: number): void;
  /**
   * 409 (spec §5 "Recovering from a 409"), in one transaction: the queue is every op in the log in seq order (its
   * text, verbatim), then `pending`, keeping the first occurrence of each id. It becomes pending; the log and the
   * snapshot go; the replica is marked recovering. Returns the queue.
   */
  beginRecovery(pending: PendingOp[]): PendingOp[];
  /** A recovery finished: the log caught up and nothing is pending. */
  finishRecovery(): void;
  /** The whole log, for undo. */
  entries(): LogEntry[];
  /** Called after each sync: write a snapshot of the confirmed state if it's due. */
  snapshotIfDue(state: AppState, cursor: number, base: string | null): void;
}

/** What storage loaded: confirmed state at `cursor`, and the pending queue. */
export interface Loaded {
  confirmed: AppState;
  cursor: number;
  base: string | null;
  pending: PendingOp[];
  recovering: boolean;
}

export interface EngineOptions {
  storage: ReplicaStorage;
  /** null when SYNC_TOKEN isn't set. */
  transport: Transport | null;
  now: () => number;
  sleep: (ms: number) => Promise<void>;
  timeZone: string;
  /** How many times a run retries a transient failure before it works offline (the CLI's TASKS_RETRIES, 3). */
  retries?: number;
  /** The longest one of those waits. The CLI waits up to 8 s; a tool call shouldn't. */
  maxRetryWaitMs?: number;
}

export class SyncEngine {
  projection: Projection;
  /** The next seq this replica doesn't have, and the hash of entry `cursor − 1`. */
  cursor: number;
  base: string | null;
  syncState: SyncState = { kind: "off" };
  /** Set when the server rejected one of our ops (`invalid_op`). */
  notice: string | null = null;
  /** When a transient failure may be retried; the alarm uses it. */
  retryAt: number | null = null;

  private batchLimit = MAX_OPS_PER_REQUEST;
  private backoff = FIRST_BACKOFF_MS;
  private stopped = false;
  private mismatchesInARow = 0;
  /** Op ids the server acknowledged with a 200 that haven't come back in a page yet; not resent. */
  private inServerLog = new Set<string>();
  /** While a 409 recovery is under way: the queue's ids not yet confirmed. */
  private recoveryIDs: Set<string> | null;

  constructor(loaded: Loaded, private readonly o: EngineOptions) {
    this.cursor = loaded.cursor;
    this.base = loaded.base;
    this.projection = new Projection(loaded.confirmed, loaded.pending, dayContaining(o.now(), o.timeZone));
    this.recoveryIDs = loaded.recovering ? new Set(loaded.pending.map((p) => p.op.id)) : null;
  }

  get recovering(): boolean {
    return this.recoveryIDs !== null;
  }

  /** Sync stopped (a bad token, a misconfigured server, an invalid op…) until the next run. */
  get isStopped(): boolean {
    return this.stopped;
  }

  get pendingCount(): number {
    return this.projection.pending.length;
  }

  /** Today, as of now. */
  refreshDay(): void {
    this.projection.setDay(dayContaining(this.o.now(), this.o.timeZone));
  }

  /** `Seed.inboxIfMissing`, run when a Store opens (each CLI command): the one op that seeds the Inbox. */
  seedInboxIfMissing(): void {
    if (this.projection.list(INBOX_LIST_ID) !== undefined) return;
    this.perform([{ id: INBOX_OP_ID, at: this.o.now(), type: "list.create", target: INBOX_LIST_ID, set: { name: "Inbox", order: "a0" } }]);
  }

  /** Queues ops (already stamped) and applies them to visible state. */
  perform(ops: Op[]): void {
    if (ops.length === 0) return;
    const pending = ops.map(pendingOf);
    this.projection.perform(pending);
    this.o.storage.addPending(pending);
  }

  /** A fresh start for a run, like a new `Store` per CLI command (`requestSync(force: true)`). */
  reset(): void {
    this.stopped = false;
    this.retryAt = null;
    this.backoff = FIRST_BACKOFF_MS;
    this.mismatchesInARow = 0;
  }

  // MARK: The CLI's Session

  /**
   * Syncs until up to date. True when nothing is left unconfirmed, false when the server couldn't be reached (the
   * ops stay queued). Throws when sync stopped (401, 404, an invalid op…), as `Session.sync` does.
   */
  async syncForRun(): Promise<boolean> {
    this.notice = null;
    if (!this.o.transport) throw new CLIError("Config", "SYNC_TOKEN isn't set, so the replica can't reach the server.");
    const retries = this.o.retries ?? 3;
    const maxWait = this.o.maxRetryWaitMs ?? 2000;
    let tries = 0;
    while (true) {
      await this.sync();
      const s = this.syncState;
      if (s.kind === "retrying" && tries < retries) {
        tries += 1;
        await this.o.sleep(Math.min(Math.max(0, s.at - this.o.now()), maxWait));
        continue;
      }
      break;
    }
    if (this.notice !== null) {
      this.notice = null;
      throw new CLIError("Sync", "The server rejected a change (it's in the replica's rejected table). This is a bug in tasks-mcp.");
    }
    const s = this.syncState;
    switch (s.kind) {
      case "idle":
        return this.projection.pending.length === 0;
      case "retrying":
        return false;
      case "checkToken":
        throw new CLIError("Sync", "The server rejected the token (SYNC_TOKEN).");
      case "failed":
        throw new CLIError("Sync", `Sync stopped: ${s.message}`);
      default:
        return false;
    }
  }

  /** Writes a change: the ops get this run's actor and batch, go into pending before anything is sent, then out. */
  async commit(ops: Op[], actor: string, batch: string): Promise<boolean> {
    this.perform(ops.map((op) => ({ ...op, actor, batch })));
    return this.syncForRun();
  }

  // MARK: Store.runSync

  /** Runs requests until up to date, stopped or backing off. */
  async sync(): Promise<void> {
    const transport = this.o.transport;
    if (!transport) {
      this.syncState = { kind: "off" };
      return;
    }
    this.retryAt = null;
    this.syncState = { kind: "syncing" };
    this.batchLimit = MAX_OPS_PER_REQUEST;
    try {
      await this.runSync(transport);
    } finally {
      this.o.storage.snapshotIfDue(this.projection.confirmed, this.cursor, this.base);
    }
  }

  private async runSync(transport: Transport): Promise<void> {
    while (true) {
      const chunk = this.nextChunk();
      const outcome = await transport(syncBody(this.cursor, this.base, chunk.map((p) => p.json)));
      switch (outcome.kind) {
        case "page": {
          this.backoff = FIRST_BACKOFF_MS;
          for (const p of chunk) this.inServerLog.add(p.op.id);
          if (!this.apply(outcome.page)) {
            // A page that doesn't start at our cursor: the logs diverged. Never guess; recover.
            this.recoverFrom409();
            continue;
          }
          this.mismatchesInARow = 0;
          if (!outcome.page.more) this.inServerLog.clear();
          if (outcome.page.more || this.hasUnsent()) continue;
          this.finishRecoveryIfDone();
          this.syncState = { kind: "idle", lastSynced: this.o.now() };
          return;
        }
        case "invalidOp": {
          const i = outcome.error.index;
          if (i === undefined || i < 0 || i >= chunk.length) {
            this.stop({ kind: "failed", message: outcome.error.message ?? "The server rejected a change." });
            return;
          }
          this.reject(chunk[i], outcome.error);
          break;
        }
        case "tooLarge":
          if (chunk.length <= 1) {
            this.stop({ kind: "failed", message: "A change is too large to sync." });
            return;
          }
          this.batchLimit = Math.max(1, Math.floor(chunk.length / 2));
          break;
        case "logMismatch":
          this.mismatchesInARow += 1;
          if (this.mismatchesInARow > 3) {
            this.stop({ kind: "failed", message: "The server's log keeps changing." });
            return;
          }
          this.recoverFrom409();
          break;
        case "badToken":
          this.stop({ kind: "checkToken" });
          return;
        case "badRequest":
        case "misconfigured":
          this.stop({ kind: "failed", message: outcome.message });
          return;
        case "transient": {
          const wait = this.backoff;
          this.backoff = Math.min(this.backoff * 2, MAX_BACKOFF_MS);
          const at = this.o.now() + wait;
          this.retryAt = at;
          this.syncState = { kind: "retrying", at, reason: outcome.reason };
          return;
        }
      }
    }
  }

  private stop(state: SyncState): void {
    this.stopped = true;
    this.syncState = state;
  }

  private hasUnsent(): boolean {
    return this.projection.pending.some((p) => !this.inServerLog.has(p.op.id));
  }

  /** The next request's ops: oldest first, at most 500 ops and ~900 KB, each as its verbatim JSON. */
  private nextChunk(): PendingOp[] {
    const chunk: PendingOp[] = [];
    let bytes = 0;
    for (const p of this.projection.pending) {
      if (this.inServerLog.has(p.op.id)) continue;
      const size = utf8Length(p.json);
      if (chunk.length >= this.batchLimit || (chunk.length > 0 && bytes + size > MAX_BYTES_PER_REQUEST)) break;
      chunk.push(p);
      bytes += size + 1;
    }
    return chunk;
  }

  /**
   * Appends the page to the log, applies it to confirmed state and drops our confirmed ops from pending (only ids
   * that actually came back). False if the page doesn't continue our log.
   */
  private apply(page: SyncPage): boolean {
    const first = page.entries[0];
    const last = page.entries[page.entries.length - 1];
    if (!first || !last) return !page.more;
    if (first.entry.seq !== this.cursor || last.entry.seq !== this.cursor + page.entries.length - 1) return false;
    const before = new Set(this.projection.pending.map((p) => p.op.id));
    this.projection.confirm(page.entries.map((e) => e.entry.op));
    this.cursor = last.entry.seq + 1;
    this.base = last.entry.hash;
    this.o.storage.appendLog(page.entries);
    const after = new Set(this.projection.pending.map((p) => p.op.id));
    const gone = [...before].filter((id) => !after.has(id));
    if (gone.length > 0) this.o.storage.dropPending(gone);
    if (this.recoveryIDs) for (const e of page.entries) this.recoveryIDs.delete(e.entry.op.id);
    return true;
  }

  /** `invalid_op`: the op moves to the rejected table and leaves visible state; the run reports it. */
  private reject(p: PendingOp, error: ErrorBody): void {
    this.projection.reject(p.op.id);
    this.o.storage.dropPending([p.op.id]);
    this.o.storage.appendRejected(p.json, error, this.o.now());
    this.recoveryIDs?.delete(p.op.id);
    this.notice = "A change couldn't be saved.";
  }

  /** `409`: never discard an op. Every known op (log + pending) becomes pending and the next request is from 0. */
  private recoverFrom409(): void {
    const queue = this.o.storage.beginRecovery(this.projection.pending);
    this.projection.recover(queue);
    this.cursor = 0;
    this.base = null;
    this.inServerLog = new Set();
    this.batchLimit = MAX_OPS_PER_REQUEST;
    this.recoveryIDs = new Set(queue.map((p) => p.op.id));
  }

  private finishRecoveryIfDone(): void {
    if (this.recoveryIDs === null || this.projection.pending.length > 0) return;
    this.o.storage.finishRecovery();
    this.recoveryIDs = null;
  }
}

const encoder = new TextEncoder();
/** `Data.count` of the op's JSON. */
export const utf8Length = (s: string) => encoder.encode(s).length;
