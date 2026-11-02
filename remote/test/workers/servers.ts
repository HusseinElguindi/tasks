// The SYNC binding in the Worker tests: a function in Node (Miniflare runs it outside workerd) that forwards
// `POST /v1/sync` to a local copy of the main Worker, the unchanged server/ with a dummy token:
//
// - "harness" servers: server/wrangler.jsonc run in this process by wrangler's test harness, each with its own empty
//   log, so a test can have a fresh server, or two servers whose logs differ (409s);
// - "wrangler": a real `wrangler dev` of server/, started on first use with a scratch --persist-to.
//
// A test steers it through `POST /__control` on the same binding: which server answers, canned responses
// (the server's own fixtures) to put in front of it, and the requests it saw.

import { spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { gunzipSync } from "node:zlib";
import { createTestHarness } from "wrangler";

export const TOKEN = "dummy-local-token";
const REMOTE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const SERVER = path.resolve(REMOTE, "../server");
const SCRATCH = path.join(REMOTE, ".wrangler/test");

interface Backend {
  fetch(body: string, headers: Headers): Promise<{ status: number; body: string }>;
  close(): Promise<void>;
}

interface Fault {
  status: number;
  body: string;
  /** Only requests that carry ops (a push), not a bare pull. */
  onPush?: boolean;
  /** Fail the request itself (a network error), not answer it. */
  drop?: boolean;
  times?: number;
}

interface Seen {
  server: string;
  status: number;
  injected: boolean;
  from: number;
  ops: number;
  body: string;
}

// Shared through globalThis: the config and the global setup load this module separately.
interface State {
  backends: Map<string, Promise<Backend>>;
  current: string;
  faults: Fault[];
  seen: Seen[];
}
const g = globalThis as unknown as { __tasksServers?: State };
const state: State = (g.__tasksServers ??= { backends: new Map(), current: "default", faults: [], seen: [] });

/** server/ as its own wrangler config builds and runs it, in this process, with a dummy token and its own empty storage. */
async function harnessServer(): Promise<Backend> {
  const server = createTestHarness({ workers: [{ configPath: path.join(SERVER, "wrangler.jsonc"), secrets: { API_TOKEN: TOKEN } }] });
  await server.listen();
  return {
    async fetch(body, headers) {
      const h = new Headers(headers);
      h.delete("host");
      const r = await server.fetch("http://localhost/v1/sync", { method: "POST", headers: Object.fromEntries(h), body });
      return { status: r.status, body: await r.text() };
    },
    close: () => server.close(),
  };
}

function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const s = net.createServer();
    s.unref();
    s.on("error", reject);
    s.listen(0, "127.0.0.1", () => {
      const { port } = s.address() as net.AddressInfo;
      s.close(() => resolve(port));
    });
  });
}

// Each harness server adds an exit listener.
process.setMaxListeners(100);

const children = new Set<ChildProcess>();
process.once("exit", () => {
  for (const c of children) try { process.kill(-c.pid!, "SIGKILL"); } catch { /* gone */ }
});

/** `wrangler dev` of server/, unchanged, on a free port with a dummy token and a fresh --persist-to. */
async function wranglerServer(): Promise<Backend> {
  if (!fs.existsSync(path.join(SERVER, "node_modules/.bin/wrangler"))) throw new Error("server/node_modules is missing: pnpm install in server/");
  const port = await freePort();
  const inspector = await freePort();
  const dir = path.join(SCRATCH, `wrangler-${Date.now()}`);
  fs.mkdirSync(dir, { recursive: true });
  const env: NodeJS.ProcessEnv = { ...process.env, WRANGLER_SEND_METRICS: "false" };
  for (const k of Object.keys(env)) if (/^(CLOUDFLARE_|CF_)/.test(k)) delete env[k]; // never an account
  const log = fs.openSync(path.join(dir, "wrangler.log"), "w");
  const child = spawn(path.join(SERVER, "node_modules/.bin/wrangler"), ["dev", "--ip", "127.0.0.1", "--port", String(port),
    "--inspector-port", String(inspector), "--var", `API_TOKEN:${TOKEN}`, "--persist-to", path.join(dir, "state"),
    "--show-interactive-dev-session=false"], { cwd: SERVER, env, detached: true, stdio: ["ignore", log, log] });
  children.add(child);
  let exited = false;
  child.on("exit", () => { exited = true; children.delete(child); });
  const url = `http://127.0.0.1:${port}/v1/sync`;
  const deadline = Date.now() + 120_000;
  while (Date.now() < deadline) {
    if (exited) throw new Error(`wrangler dev exited early; see ${dir}/wrangler.log`);
    try {
      const r = await fetch(url, { method: "POST", headers: { Authorization: `Bearer ${TOKEN}` }, body: `{"from":0,"base":null,"ops":[]}` });
      await r.text();
      if (r.status === 200) break;
    } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 300));
  }
  return {
    async fetch(body, headers) {
      const h = new Headers(headers);
      h.delete("host");
      const r = await fetch(url, { method: "POST", headers: h, body });
      return { status: r.status, body: await r.text() };
    },
    async close() {
      const gone = exited ? Promise.resolve() : new Promise((r) => child.once("exit", r));
      try { process.kill(-child.pid!, "SIGTERM"); } catch { /* gone */ }
      await Promise.race([gone, new Promise((r) => setTimeout(r, 5000))]);
      fs.rmSync(dir, { recursive: true, force: true });
    },
  };
}

function backend(name: string, kind: "harness" | "wrangler" = "harness"): Promise<Backend> {
  let b = state.backends.get(name);
  if (!b) {
    b = kind === "wrangler" ? wranglerServer() : harnessServer();
    state.backends.set(name, b);
  }
  return b;
}

const json = (v: unknown, status = 200) => new Response(JSON.stringify(v), { status, headers: { "Content-Type": "application/json" } });

async function control(cmd: Record<string, unknown>): Promise<Response> {
  if (typeof cmd.use === "string") {
    state.current = cmd.use;
    await backend(cmd.use, cmd.kind === "wrangler" ? "wrangler" : "harness");
  }
  if (Array.isArray(cmd.inject)) state.faults.push(...(cmd.inject as Fault[]));
  if (cmd.clearFaults) state.faults = [];
  const seen = cmd.take ? state.seen.splice(0) : [];
  return json({ current: state.current, faults: state.faults.length, seen });
}

/** The binding's handler. */
export async function syncHandler(request: Request): Promise<Response> {
  const url = new URL(request.url);
  if (url.pathname === "/__control") return control(await request.json());
  const body = await request.text();
  let parsed: { from?: number; ops?: unknown[] } = {};
  try {
    parsed = JSON.parse(body);
  } catch { /* the server answers that */ }
  const push = (parsed.ops?.length ?? 0) > 0;
  const i = state.faults.findIndex((f) => !f.onPush || push);
  const record = (status: number, injected: boolean) =>
    state.seen.push({ server: state.current, status, injected, from: parsed.from ?? -1, ops: parsed.ops?.length ?? 0, body });
  if (i >= 0) {
    const f = state.faults[i];
    if (f.times && f.times > 1) f.times -= 1;
    else state.faults.splice(i, 1);
    record(f.status, true);
    if (f.drop) throw new Error("connection reset (injected)");
    return new Response(f.body, { status: f.status, headers: { "Content-Type": "application/json; charset=utf-8" } });
  }
  const r = await (await backend(state.current)).fetch(body, request.headers);
  record(r.status, false);
  return new Response(r.body, { status: r.status, headers: { "Content-Type": "application/json; charset=utf-8" } });
}

export async function closeAll(): Promise<void> {
  for (const b of state.backends.values()) await (await b).close().catch(() => undefined);
  state.backends.clear();
}

/** GOLDEN, a test-only binding: test/golden/<name> (gunzipped), since workerd can't read files. */
export async function goldenHandler(request: Request): Promise<Response> {
  const name = new URL(request.url).pathname.slice(1);
  if (!/^[a-z0-9-]+\.json$/.test(name)) return new Response("bad name", { status: 400 });
  const dir = path.join(REMOTE, "test/golden");
  const plain = path.join(dir, name);
  if (fs.existsSync(plain)) return new Response(fs.readFileSync(plain));
  const gz = plain + ".gz";
  if (fs.existsSync(gz)) return new Response(gunzipSync(fs.readFileSync(gz)));
  return new Response("missing", { status: 404 });
}
