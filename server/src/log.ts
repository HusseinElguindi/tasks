// The UserLog Durable Object: the append-only op log (SPEC §5–§7).
//
// Hot path: head and the last hash live in memory, the SQL strings are constants (workerd
// caches a prepared statement per query string), and an append is one synchronous
// transaction. Nothing in sync() awaits, so requests can't interleave.

import { DurableObject } from "cloudflare:workers";
import { createHash } from "node:crypto";
import type { PreparedOp } from "./validate";

export const PAGE_SIZE = 1000;
// A page also stops at this many UTF-16 units of op text, but always holds at least one entry. RPC caps a
// return value at 32 MiB and serializes a string with any non-Latin-1 character at 2 bytes per unit, and
// 1,000 near-limit notes would exceed that on every retry. 4M units is ≤ 8 MB over RPC, ≤ 12 MB as UTF-8.
export const PAGE_CHARS = 4_000_000;

export type SyncResult = { ok: true; body: string } | { ok: false; message: string };

const SCHEMA = `CREATE TABLE IF NOT EXISTS log (
  seq      INTEGER PRIMARY KEY,
  id       TEXT NOT NULL UNIQUE,
  received INTEGER NOT NULL,
  op       TEXT NOT NULL,
  hash     TEXT NOT NULL
)`;
const LAST = "SELECT seq, hash FROM log ORDER BY seq DESC LIMIT 1";
const HASH_AT = "SELECT hash FROM log WHERE seq = ?";
const INSERT = "INSERT INTO log (seq, id, received, op, hash) VALUES (?, ?, ?, ?, ?) ON CONFLICT (id) DO NOTHING";
const PAGE = "SELECT seq, received, hash, op FROM log WHERE seq >= ? AND seq < ? ORDER BY seq";

const sha256 = (s: string) => createHash("sha256").update(s).digest("hex");

export class UserLog extends DurableObject<Env> {
  private readonly sql: SqlStorage;
  private head: number; // number of entries = next seq
  private last: string; // hash of entry head - 1; "" for an empty log

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(SCHEMA);
    // MAX(seq) + 1 via the primary key: O(log n), unlike COUNT(*).
    const row = this.sql.exec<{ seq: number; hash: string }>(LAST).toArray()[0];
    this.head = row ? row.seq + 1 : 0;
    this.last = row ? row.hash : "";
  }

  /** Log check (409), append, then the page: up to PAGE_SIZE entries (and PAGE_CHARS) from `from`. */
  sync(from: number, base: string | null, ops: PreparedOp[]): SyncResult {
    if (from > this.head) return { ok: false, message: `from ${from} is past head ${this.head}.` };
    if (from > 0 && base !== this.hashAt(from - 1)) {
      return { ok: false, message: `base does not match the log at seq ${from - 1}.` };
    }
    if (ops.length > 0) this.append(ops);
    return { ok: true, body: this.page(from) };
  }

  private hashAt(seq: number): string | undefined {
    if (seq === this.head - 1) return this.last;
    return this.sql.exec<{ hash: string }>(HASH_AT, seq).toArray()[0]?.hash;
  }

  /** Appends ops contiguously in order, skipping op ids already in the log. One transaction. */
  private append(ops: PreparedOp[]): void {
    const received = Date.now();
    let head = this.head;
    let last = this.last;
    this.ctx.storage.transactionSync(() => {
      for (const op of ops) {
        const hash = sha256(last + "\n" + op.text);
        if (this.sql.exec(INSERT, head, op.id, received, op.text, hash).rowsWritten > 0) {
          head++;
          last = hash;
        }
      }
    });
    // Only after commit: if the transaction threw, the cache still matches storage.
    this.head = head;
    this.last = last;
  }

  /** The response body, built from the stored op text without re-parsing it. */
  private page(from: number): string {
    const entries: string[] = [];
    let next = from;
    let chars = 0;
    if (from < this.head) {
      for (const [seq, received, hash, op] of this.sql.exec(PAGE, from, Math.min(from + PAGE_SIZE, this.head)).raw()) {
        chars += (op as string).length;
        if (chars > PAGE_CHARS && entries.length > 0) break;
        entries.push(`{"seq":${seq},"received":${received},"hash":"${hash}","op":${op}}`);
        next = (seq as number) + 1;
      }
    }
    return `{"entries":[${entries.join(",")}],"head":${this.head},"more":${next < this.head}}`;
  }
}
