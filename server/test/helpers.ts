import { env, exports } from "cloudflare:workers";
import { createHash } from "node:crypto";

export const TOKEN = "test-token";
export const NOW = 1761811261234;
export const INBOX = "00000000-0000-0000-0000-000000000001";
export const TASK = "9f8e7d6c-5b4a-4321-8fed-cba987654321";

export type Op = { id: string; at: number; type: string; target: string; set: Record<string, unknown> };
export type Entry = { seq: number; received: number; hash: string; op: Op };
export type Page = { entries: Entry[]; head: number; more: boolean };

export const logStub = () => env.LOG.get(env.LOG.idFromName("me"));

export function call(path: string, init: RequestInit = {}): Promise<Response> {
  return exports.default.fetch(`https://tasks.test${path}`, init);
}

/** POST /v1/sync. A string body is sent as is; anything else is JSON-encoded. */
export function post(
  body: unknown,
  { token = TOKEN, headers = {} }: { token?: string | null; headers?: Record<string, string> } = {},
): Promise<Response> {
  const h: Record<string, string> = { "Content-Type": "application/json", ...headers };
  if (token !== null) h.Authorization = `Bearer ${token}`;
  return call("/v1/sync", { method: "POST", headers: h, body: typeof body === "string" ? body : JSON.stringify(body) });
}

export async function sync(body: unknown): Promise<{ status: number; body: any }> {
  const res = await post(body);
  return { status: res.status, body: await res.json() };
}

export async function ok(from: number, base: string | null, ops: unknown[] = []): Promise<Page> {
  const res = await sync({ from, base, ops });
  if (res.status !== 200) throw new Error(`expected 200, got ${res.status}: ${JSON.stringify(res.body)}`);
  return res.body;
}

/** Appends ops through the API like a client that's up to date, 500 per request. */
export async function seed(ops: unknown[]): Promise<{ head: number; last: string | null }> {
  const log = await pullAll();
  let head = log.length;
  let last = log.at(-1)?.hash ?? null;
  for (let i = 0; i < ops.length; i += 500) {
    const res = await ok(head, last, ops.slice(i, i + 500));
    last = res.entries.at(-1)?.hash ?? last;
    head = res.head;
  }
  return { head, last };
}

/** Every entry in the log, following `more`. */
export async function pullAll(): Promise<Entry[]> {
  const all: Entry[] = [];
  let from = 0;
  let base: string | null = null;
  for (;;) {
    const page = await ok(from, base);
    all.push(...page.entries);
    if (!page.more) return all;
    from = page.entries.at(-1)!.seq + 1;
    base = page.entries.at(-1)!.hash;
  }
}

export const opText = (op: Op) => JSON.stringify({ id: op.id, at: op.at, type: op.type, target: op.target, set: op.set });
export const sha256 = (s: string) => createHash("sha256").update(s).digest("hex");

let counter = 0;
const uuid = () => `00000000-0000-4000-a000-${(++counter).toString(16).padStart(12, "0")}`;

export const taskUpdate = (set: Record<string, unknown> = { title: "x" }, over: Partial<Op> = {}): Op => ({
  id: uuid(), at: 1761811300000, type: "task.update", target: TASK, set, ...over,
});
export const taskCreate = (set: Record<string, unknown> = {}, over: Partial<Op> = {}): Op => ({
  id: uuid(), at: 1761811300000, type: "task.create", target: uuid(), set: { list: INBOX, order: "a0", ...set }, ...over,
});
export const listCreate = (set: Record<string, unknown> = {}, over: Partial<Op> = {}): Op => ({
  id: uuid(), at: 1761811300000, type: "list.create", target: uuid(), set: { name: "L", order: "a0", ...set }, ...over,
});
export const listUpdate = (set: Record<string, unknown> = { name: "L2" }, over: Partial<Op> = {}): Op => ({
  id: uuid(), at: 1761811300000, type: "list.update", target: INBOX, set, ...over,
});
