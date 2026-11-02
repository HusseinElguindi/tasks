// The Replica Durable Object: one replica of the log for every client (`idFromName("main")`), like the CLI's data
// directory. A run is the local `tasks mcp`'s (MCP.swift `run`): take the lock, pull, run the script on a fork,
// commit its ops with the client's actor and one batch, push, and report whether they're in the log.

import { DurableObject } from "cloudflare:workers";
import { Context } from "./cli/context.ts";
import { CLIError } from "./cli/errors.ts";
import type { Json } from "./cli/render.ts";
import { execute, type Sandbox } from "./cli/run.ts";
import { loaderSandbox } from "./codemode.ts";
import { classify } from "./core/wire.ts";
import { SyncEngine, type SyncState, type Transport } from "./replica/engine.ts";
import { SqlReplicaStorage } from "./replica/storage.ts";

export interface RunRequest {
  dryRun: boolean;
  /** The op `actor`: the OAuth client's (`agent:claude-ai`), 1–64 characters. */
  actor: string;
}

export interface ReplicaStatus {
  cursor: number;
  pending: number;
  recovering: boolean;
  syncState: SyncState;
  log: number;
  rejected: number;
  /** The cursor of the snapshot the fold starts from (-1: none). */
  snapshot: number;
}

export const isTimeZone = (tz: string) => {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return true;
  } catch {
    return false;
  }
};

export class Replica extends DurableObject<Env> {
  private readonly storage: SqlReplicaStorage;
  private readonly engine: SyncEngine;
  private readonly configError: string | null;
  /** One run (or sync) at a time; the rest wait their turn. */
  private lock: Promise<unknown> = Promise.resolve();
  /** The waits between retries. Tests replace it. */
  sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    const tz: string = env.TIME_ZONE ?? "America/Toronto";
    const order: string = env.DATE_ORDER ?? "md";
    this.configError = !isTimeZone(tz)
      ? `TIME_ZONE is ${JSON.stringify(tz)}, which isn't an IANA time zone.`
      : order !== "md" && order !== "dm"
        ? `DATE_ORDER is ${JSON.stringify(order)}; use md or dm.`
        : null;
    this.storage = new SqlReplicaStorage(ctx.storage);
    this.engine = new SyncEngine(this.storage.load(), {
      storage: this.storage,
      transport: env.SYNC_TOKEN ? this.transport(env.SYNC_TOKEN) : null,
      now: () => Date.now(),
      sleep: (ms) => this.sleep(ms),
      timeZone: this.configError ? "UTC" : tz,
    });
  }

  /** `POST /v1/sync` on the main Worker, through the service binding. */
  private transport(token: string): Transport {
    return async (body) => {
      try {
        const r = await this.env.SYNC.fetch("https://tasks/v1/sync", {
          method: "POST",
          headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
          body,
        });
        return classify(r.status, await r.text());
      } catch (e) {
        return { kind: "transient", reason: e instanceof Error ? e.message : String(e) };
      }
    };
  }

  private exclusive<T>(work: () => Promise<T>): Promise<T> {
    const run = this.lock.then(work, work);
    this.lock = run.catch(() => undefined);
    return run;
  }

  /** A tasks_run call: the script in a Worker Loader isolate. */
  async run(source: string, request: RunRequest): Promise<Json> {
    return this.runScript(source, request, loaderSandbox(this.env.LOADER));
  }

  /** One script, as one `tasks run`: the sandbox runs it, its calls answer from this run's fork. */
  async runScript(source: string, request: RunRequest, sandbox: Sandbox): Promise<Json> {
    return this.exclusive(async () => {
      const e = this.engine;
      try {
        if (this.configError) throw new CLIError("Config", this.configError);
        const actor = request.actor;
        if (actor.length < 1 || actor.length > 64) throw CLIError.invalid("The actor must be 1 to 64 characters.", "actor");
        e.reset();
        e.refreshDay();
        e.seedInboxIfMissing();
        await e.syncForRun();
        const c = new Context(
          { projection: e.projection, entries: () => this.storage.entries(), actor },
          {
            clock: { now: () => Date.now(), newID: () => crypto.randomUUID() },
            timeZone: this.env.TIME_ZONE,
            dateOrder: (this.env.DATE_ORDER as string) === "dm" ? "dayFirst" : "monthFirst",
          },
        );
        return await execute(source, c, sandbox, { dryRun: request.dryRun, commit: (ops, batch) => e.commit(ops, actor, batch) });
      } catch (err) {
        const error = err instanceof CLIError ? { type: err.kind, message: err.message } : { type: "Error", message: String(err) };
        return { ok: false, error, logs: [], change: null };
      } finally {
        await this.scheduleRetry();
      }
    });
  }

  /** Push anything queued and pull, now (`tasks sync`). */
  async sync(): Promise<ReplicaStatus & { synced: boolean; error?: string }> {
    return this.exclusive(async () => {
      try {
        this.engine.reset();
        const synced = await this.engine.syncForRun();
        return { ...this.statusNow(), synced };
      } catch (err) {
        return { ...this.statusNow(), synced: false, error: err instanceof Error ? err.message : String(err) };
      } finally {
        await this.scheduleRetry();
      }
    });
  }

  async status(): Promise<ReplicaStatus> {
    return this.statusNow();
  }

  /** Retries what's still queued after a transient failure, with Store's backoff (1 s doubling, at most 60 s). */
  override async alarm(): Promise<void> {
    await this.exclusive(async () => {
      if (this.engine.pendingCount === 0 || this.engine.isStopped) return;
      await this.engine.sync();
      this.engine.notice = null;
      await this.scheduleRetry();
    });
  }

  private async scheduleRetry(): Promise<void> {
    const e = this.engine;
    if (e.pendingCount > 0 && !e.isStopped && e.syncState.kind === "retrying") {
      await this.ctx.storage.setAlarm(e.syncState.at);
    } else {
      await this.ctx.storage.deleteAlarm();
    }
  }

  private statusNow(): ReplicaStatus {
    const n = this.storage.counts();
    return {
      cursor: this.engine.cursor,
      pending: this.engine.pendingCount,
      recovering: this.engine.recovering,
      syncState: this.engine.syncState,
      log: n.log,
      rejected: n.rejected,
      snapshot: n.snapshotCursor,
    };
  }
}
