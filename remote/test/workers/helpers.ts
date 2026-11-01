// Test helpers inside workerd: the replicas, the run, the server's log, and the control channel to the Node side.

import { runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import type { Json } from "../../src/cli/render.ts";
import type { Replica, ReplicaStatus } from "../../src/replica.ts";
import { fnSandbox, type ScriptFn } from "../script-sandbox.ts";

export interface Seen {
  server: string;
  status: number;
  injected: boolean;
  from: number;
  ops: number;
  body: string;
}

/** Steers the Node-side SYNC handler (test/workers/servers.ts). */
export async function control(cmd: Record<string, unknown>): Promise<{ current: string; faults: number; seen: Seen[] }> {
  const r = await env.SYNC.fetch("http://control/__control", { method: "POST", body: JSON.stringify(cmd) });
  return r.json();
}

let n = 0;
/** A server nobody has used: an empty log. */
export async function freshServer(kind: "harness" | "wrangler" = "harness"): Promise<string> {
  const name = `${kind}-${Date.now()}-${++n}`;
  await control({ use: name, kind, clearFaults: true, take: true });
  return name;
}

export const replica = (name: string) => env.REPLICA.get(env.REPLICA.idFromName(name));

type Stub = ReturnType<typeof replica>;

/** One run on a replica, as a tool call would make it; retries don't wait. */
export function run(stub: Stub, fn: ScriptFn, o: { dryRun?: boolean; actor?: string } = {}): Promise<{ [k: string]: Json }> {
  return runInDurableObject(stub, async (r: Replica) => {
    r.sleep = async () => {};
    return (await r.runScript("// test", { dryRun: o.dryRun ?? false, actor: o.actor ?? "agent:test" }, fnSandbox(fn))) as { [k: string]: Json };
  });
}

export const status = (stub: Stub): Promise<ReplicaStatus> => runInDurableObject(stub, (r: Replica) => r.status());

export interface Entry {
  seq: number;
  received: number;
  hash: string;
  op: { id: string; at: number; type: string; target: string; set: Record<string, unknown>; actor?: string; batch?: string };
}

/** `POST /v1/sync` to the current server, straight through the binding. */
export async function sync(from: number, base: string | null, ops: unknown[] = []): Promise<{ status: number; body: { entries: Entry[]; head: number; more: boolean } }> {
  const r = await env.SYNC.fetch("https://tasks/v1/sync", {
    method: "POST",
    headers: { Authorization: `Bearer ${env.SYNC_TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from, base, ops }),
  });
  return { status: r.status, body: await r.json() };
}

/** The current server's whole log. */
export async function serverLog(): Promise<Entry[]> {
  const out: Entry[] = [];
  let base: string | null = null;
  while (true) {
    const { body } = await sync(out.length, base);
    out.push(...body.entries);
    base = out.length > 0 ? out[out.length - 1].hash : null;
    if (!body.more) return out;
  }
}
