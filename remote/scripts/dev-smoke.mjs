#!/usr/bin/env node
// The local setup end to end: server/ (unchanged) and tasks-mcp each under their own `wrangler dev`, the dev registry
// connecting tasks-mcp's SYNC binding to server/, dummy secrets, scratch state. Then what a person and an MCP client
// do: the passkey on /setup (a virtual one, test/workers/authenticator.ts), client registration, consent with the
// passkey, the PKCE code exchange, and MCP over HTTP with the token: initialize, tools/list, tasks_types, a
// tasks_run that writes, one that reads it back, an error, and the server's log. Stops both after.
//
//   node scripts/dev-smoke.mjs        (pnpm smoke)

import { spawn } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { SoftAuthenticator } from "../test/workers/authenticator.ts";

const REMOTE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SERVER = path.resolve(REMOTE, "../server");
const WRANGLER = path.join(REMOTE, "node_modules/.bin/wrangler");
const SYNC_TOKEN = "dummy-local-token";
const SETUP_SECRET = "dummy-setup-secret";
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
  const mcp = await start("tasks-mcp", REMOTE, ["--var", `SYNC_TOKEN:${SYNC_TOKEN}`, "--var", `SETUP_SECRET:${SETUP_SECRET}`]);
  // localhost, as a browser would use it: a passkey's RP ID can't be an IP address.
  mcp.url = mcp.url.replace("127.0.0.1", "localhost");
  say(`tasks-mcp on ${mcp.url}`);
  // The dev registry can take a moment to see the other session.
  for (let i = 0; i < 20 && !/env\.SYNC \(tasks\).*connected\]/.test(fs.readFileSync(mcp.logPath, "utf8")); i++) await new Promise((r) => setTimeout(r, 500));
  check(/env\.SYNC \(tasks\)\s+Worker\s+local \[connected\]/.test(fs.readFileSync(mcp.logPath, "utf8")), "SYNC is connected to server/ through the dev registry");

  // The person: set up the passkey.
  const owner = new SoftAuthenticator();
  const post = (p, body, headers = {}) => fetch(`${mcp.url}${p}`, { method: "POST", headers: { "Content-Type": "application/json", ...headers }, body: JSON.stringify(body) });
  const so = await (await post("/setup/options", { secret: SETUP_SECRET })).json();
  const sv = await (await post("/setup/verify", { secret: SETUP_SECRET, challengeId: so.challengeId, response: await owner.create(so.options, mcp.url) })).json();
  check(sv.ok === true, "/setup registers the passkey");
  check((await fetch(`${mcp.url}/setup`)).status === 410, "registration is closed after it");

  // The client: discovery, registration, consent with the passkey, the code exchange.
  const challenge401 = await fetch(`${mcp.url}/mcp`, { method: "POST", body: "{}" });
  check(challenge401.status === 401 && /resource_metadata=/.test(challenge401.headers.get("WWW-Authenticate") ?? ""), "/mcp without a token: 401 with resource_metadata");
  const redirect = "http://127.0.0.1:33418/callback";
  const reg = await (await post("/register", { client_name: "Smoke Client", redirect_uris: [redirect], token_endpoint_auth_method: "none" })).json();
  const b64url = (b) => Buffer.from(b).toString("base64url");
  const verifier = b64url(crypto.getRandomValues(new Uint8Array(32)));
  const q = new URLSearchParams({
    response_type: "code", client_id: reg.client_id, redirect_uri: redirect, state: "s1", scope: "tasks", resource: `${mcp.url}/mcp`,
    code_challenge: b64url(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier)))), code_challenge_method: "S256",
  });
  const consent = await fetch(`${mcp.url}/authorize?${q}`);
  const html = await consent.text();
  const cookie = consent.headers.getSetCookie().map((c) => c.split(";")[0]).join("; ");
  const handle = /const handle = "([^"]*)"/.exec(html)?.[1];
  check(consent.status === 200 && html.includes("agent:smoke-client") && !!handle, "/authorize shows the consent page with the actor");
  const ao = await (await post("/authorize/options", {}, { Cookie: cookie })).json();
  const approved = await (await post("/authorize/approve", { handle, challengeId: ao.challengeId, response: await owner.get(ao.options, mcp.url) }, { Cookie: cookie })).json();
  const code = approved.redirectTo && new URL(approved.redirectTo).searchParams.get("code");
  check(!!code, "the passkey approves it");
  const tok = await (await fetch(`${mcp.url}/token`, {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "authorization_code", code, redirect_uri: redirect, client_id: reg.client_id, code_verifier: verifier, resource: `${mcp.url}/mcp` }),
  })).json();
  check(typeof tok.access_token === "string", "the code exchange gives an access token");

  let id = 0;
  const rpc = async (method, params) => {
    const r = await fetch(`${mcp.url}/mcp`, {
      method: "POST",
      headers: { Authorization: `Bearer ${tok.access_token}`, "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
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
  check(JSON.stringify(ops) === '["list.create","task.create (agent:smoke-client)"]', `server/'s log: ${ops.join(", ")}`);
} catch (e) {
  check(false, String(e?.message ?? e));
} finally {
  await stopAll();
  if (process.exitCode) say(`logs kept in ${scratch}`);
  else fs.rmSync(scratch, { recursive: true, force: true });
}
