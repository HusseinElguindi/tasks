#!/usr/bin/env node
// The local setup end to end: server/ (unchanged) and tasks-mcp each under their own `wrangler dev`, the dev registry
// connecting tasks-mcp's SYNC binding to server/, dummy tokens, scratch state. Then MCP over HTTP: initialize,
// tools/list, tasks_types, a tasks_run that writes, one that reads it back, and the server's log. Stops both after.
//
//   node scripts/dev-smoke.mjs        (pnpm smoke)

import { spawn } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import { fileURLToPath } from "node:url";

const REMOTE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SERVER = path.resolve(REMOTE, "../server");
const WRANGLER = path.join(REMOTE, "node_modules/.bin/wrangler");
const SYNC_TOKEN = "dummy-local-token";
const DEV_TOKEN = "dummy-dev-token";
const scratch = path.join(REMOTE, ".wrangler", `smoke-${Date.now()}`);
fs.mkdirSync(scratch, { recursive: true });

const say = (s) => console.log(s);
const children = [];

function freePort() {
  return new Promise((resolve, reject) => {
    const s = net.createServer();
    s.unref();
    s.on("error", reject);
    s.listen(0, "127.0.0.1", () => {
      const { port } = s.address();
      s.close(() => resolve(port));
    });
  });
}

async function start(name, cwd, args) {
  const port = await freePort();
  const inspector = await freePort();
  const env = { ...process.env, WRANGLER_SEND_METRICS: "false" };
  for (const k of Object.keys(env)) if (/^(CLOUDFLARE_|CF_)/.test(k)) delete env[k]; // never an account
  const logPath = path.join(scratch, `${name}.log`);
  const log = fs.openSync(logPath, "w");
  const child = spawn(WRANGLER, ["dev", "--ip", "127.0.0.1", "--port", String(port), "--inspector-port", String(inspector),
    "--persist-to", path.join(scratch, `${name}-state`), "--show-interactive-dev-session=false", ...args],
  { cwd, env, detached: true, stdio: ["ignore", log, log] });
  children.push(child);
  const deadline = Date.now() + 120_000;
  while (Date.now() < deadline) {
    const text = fs.readFileSync(logPath, "utf8");
    if (/Ready on/.test(text)) return { url: `http://127.0.0.1:${port}`, logPath };
    if (child.exitCode !== null) throw new Error(`${name}: wrangler dev exited; see ${logPath}`);
    await new Promise((r) => setTimeout(r, 300));
  }
  throw new Error(`${name}: not ready in 120 s; see ${logPath}`);
}

async function stopAll() {
  for (const c of children) {
    try { process.kill(-c.pid, "SIGTERM"); } catch { /* gone */ }
  }
  await new Promise((r) => setTimeout(r, 1500));
  for (const c of children) {
    try { process.kill(-c.pid, "SIGKILL"); } catch { /* gone */ }
  }
}

function check(ok, what) {
  say(`${ok ? "ok  " : "FAIL"} ${what}`);
  if (!ok) process.exitCode = 1;
}

try {
  const server = await start("server", SERVER, ["--var", `API_TOKEN:${SYNC_TOKEN}`]);
  say(`server/ on ${server.url}`);
  const mcp = await start("tasks-mcp", REMOTE, ["--var", `SYNC_TOKEN:${SYNC_TOKEN}`, "--var", `DEV_TOKEN:${DEV_TOKEN}`]);
  say(`tasks-mcp on ${mcp.url}`);
  // The dev registry can take a moment to see the other session.
  for (let i = 0; i < 20 && !/env\.SYNC \(tasks\).*connected\]/.test(fs.readFileSync(mcp.logPath, "utf8")); i++) await new Promise((r) => setTimeout(r, 500));
  check(/env\.SYNC \(tasks\)\s+Worker\s+local \[connected\]/.test(fs.readFileSync(mcp.logPath, "utf8")), "SYNC is connected to server/ through the dev registry");

  let id = 0;
  const rpc = async (method, params) => {
    const r = await fetch(`${mcp.url}/mcp`, {
      method: "POST",
      headers: { Authorization: `Bearer ${DEV_TOKEN}`, "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
      body: JSON.stringify({ jsonrpc: "2.0", id: ++id, method, params }),
    });
    return r.json();
  };
  const run = async (script) => JSON.parse((await rpc("tools/call", { name: "tasks_run", arguments: { script } })).result.content[0].text);

  const init = await rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "smoke", version: "0" } });
  check(init.result?.serverInfo?.name === "tasks", "initialize");
  const tools = await rpc("tools/list");
  check(JSON.stringify(tools.result?.tools?.map((t) => t.name)) === '["tasks_types","tasks_run"]', "tools/list: tasks_types, tasks_run");
  const types = await rpc("tools/call", { name: "tasks_types", arguments: {} });
  check(types.result?.content?.[0]?.text?.includes("declare const tasks"), "tasks_types");

  const wrote = await run(`const t = await tasks.add({ title: "Smoke test", when: "today" });\nreturn t.title;`);
  check(wrote.ok === true && wrote.synced === true && wrote.result === "Smoke test", `tasks_run writes and syncs: ${JSON.stringify({ ok: wrote.ok, synced: wrote.synced, summary: wrote.change?.summary })}`);
  const read = await run(`return (await tasks.today()).groups.flatMap((g) => g.tasks.map((t) => t.title));`);
  check(JSON.stringify(read.result) === '["Smoke test"]', `tasks_run reads it back: ${JSON.stringify(read.result)}`);
  const failed = await run(`await tasks.task("zzzz9999");`);
  check(failed.ok === false && failed.error?.type === "NotFound" && failed.error?.line === 1, `an error has its type and line: ${JSON.stringify(failed.error)}`);

  const log = await (await fetch(`${server.url}/v1/sync`, {
    method: "POST", headers: { Authorization: `Bearer ${SYNC_TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: 0, base: null, ops: [] }),
  })).json();
  const ops = log.entries.map((e) => `${e.op.type}${e.op.actor ? ` (${e.op.actor})` : ""}`);
  check(JSON.stringify(ops) === '["list.create","task.create (agent:dev)"]', `server/'s log: ${ops.join(", ")}`);
} catch (e) {
  check(false, String(e?.message ?? e));
} finally {
  await stopAll();
  if (process.exitCode) say(`logs kept in ${scratch}`);
  else fs.rmSync(scratch, { recursive: true, force: true });
}
