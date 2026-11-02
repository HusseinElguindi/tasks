// /mcp over HTTP, end to end: the Worker, the Replica DO ("main"), scripts on Worker Loader, and a local server/.

import { exports } from "cloudflare:workers";
import { beforeAll, describe, expect, it } from "vitest";
import { declarations } from "../../src/cli/commands.ts";
import { Host } from "../../src/codemode.ts";
import { INSTRUCTIONS, TOOLS } from "../../src/mcp.ts";
import { freshServer, serverLog } from "./helpers.ts";

const TOKEN = "test-dev-token";
const post = (body: unknown, headers: Record<string, string> = { Authorization: `Bearer ${TOKEN}` }) =>
  exports.default.fetch("https://tasks-mcp.example/mcp", {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

let id = 0;
async function rpc(method: string, params?: unknown) {
  const r = await post({ jsonrpc: "2.0", id: ++id, method, params });
  expect(r.status).toBe(200);
  expect(r.headers.get("Content-Type")).toBe("application/json");
  return (await r.json()) as { result?: { content?: { text: string }[]; isError?: boolean; [k: string]: unknown }; error?: unknown };
}

/** tasks_run: the result object (the tool's text, parsed) and isError. */
async function runTool(script: string, dryRun?: boolean) {
  const r = await rpc("tools/call", { name: "tasks_run", arguments: dryRun === undefined ? { script } : { script, dryRun } });
  return { out: JSON.parse(r.result!.content![0].text) as Record<string, unknown>, isError: r.result!.isError, text: r.result!.content![0].text };
}

beforeAll(async () => {
  await freshServer();
});

describe("the endpoint", () => {
  it("needs the bearer token", async () => {
    expect((await post({ jsonrpc: "2.0", id: 1, method: "ping" }, {})).status).toBe(401);
    const wrong = await post({ jsonrpc: "2.0", id: 1, method: "ping" }, { Authorization: "Bearer nope" });
    expect(wrong.status).toBe(401);
    expect(wrong.headers.get("WWW-Authenticate")).toBe("Bearer");
  });

  it("is POST only, at /mcp only", async () => {
    const get = await exports.default.fetch("https://tasks-mcp.example/mcp", { headers: { Authorization: `Bearer ${TOKEN}` } });
    expect(get.status).toBe(405);
    expect(get.headers.get("Allow")).toBe("POST");
    expect((await exports.default.fetch("https://tasks-mcp.example/")).status).toBe(404);
  });

  it("answers a parse error, notifications with 202, and batches", async () => {
    const bad = await post("{nope");
    expect(bad.status).toBe(400);
    expect(await bad.json()).toEqual({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } });
    const note = await post({ jsonrpc: "2.0", method: "notifications/initialized" });
    expect(note.status).toBe(202);
    expect(await note.text()).toBe("");
    const batch = await post([{ jsonrpc: "2.0", id: 7, method: "ping" }, { jsonrpc: "2.0", method: "notifications/initialized" }]);
    expect(await batch.json()).toEqual([{ jsonrpc: "2.0", id: 7, result: {} }]);
  });

  it("initialize and tools/list are the local tasks mcp's", async () => {
    const init = await rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "0" } });
    expect(init.result).toEqual({ protocolVersion: "2025-06-18", capabilities: { tools: {} }, serverInfo: { name: "tasks", version: "1.0" }, instructions: INSTRUCTIONS });
    expect((await rpc("tools/list")).result).toEqual({ tools: TOOLS });
  });

  it("tasks_types is tasks.d.ts", async () => {
    const r = await rpc("tools/call", { name: "tasks_types", arguments: {} });
    expect(r.result).toEqual({ content: [{ type: "text", text: declarations() }], isError: false });
  });
});

describe("tasks_run", () => {
  it("writes and syncs one change, with the client's actor", async () => {
    const { out, isError, text } = await runTool(`
      const t = await tasks.add({ title: "From MCP", when: "today" });
      console.log("added", t.ref);
      return t.title;
    `);
    expect(isError).toBe(false);
    expect(out).toMatchObject({ ok: true, result: "From MCP", synced: true, change: { summary: 'New Task "From MCP" in Inbox' } });
    expect(out.logs).toEqual([expect.stringMatching(/^added [0-9a-f]{6}$/)]);
    expect(text).toBe(JSON.stringify(out));
    const last = (await serverLog()).at(-1)!;
    expect(last.op).toMatchObject({ type: "task.create", actor: "agent:dev", set: { title: "From MCP" } });
  });

  it("TypeScript, a dry run, and undo", async () => {
    const dry = await runTool(`const n: number = (await tasks.find({ text: "From MCP" })).length;\nawait tasks.add({ title: "Draft" } as const);\nreturn n;`, true);
    expect(dry.out).toMatchObject({ ok: true, result: 1, dryRun: true });
    const before = (await serverLog()).length;
    expect((await runTool(`return (await tasks.find({ text: "Draft" })).length;`)).out).toMatchObject({ ok: true, result: 0 });
    const undone = await runTool(`return (await tasks.undo()).summary;`);
    expect(undone.out).toMatchObject({ ok: true, result: 'Undo: New Task "From MCP" in Inbox', synced: true });
    expect((await serverLog()).length).toBe(before + 1);
  });

  it("an error has its type and line, writes nothing, and is isError", async () => {
    const before = (await serverLog()).length;
    const { out, isError } = await runTool(`await tasks.add({ title: "Never" });\nawait tasks.task("zzzz9999");`);
    expect(isError).toBe(true);
    expect(out).toEqual({
      ok: false,
      error: { candidates: [], column: 13, field: "task", line: 2, message: expect.any(String), type: "NotFound" },
      logs: [], change: null,
    });
    expect((await serverLog()).length).toBe(before);
  });

  it("no network, no env, and nothing kept between runs", async () => {
    const { out } = await runTool(`
      let net = "reached";
      try { await fetch("https://example.com"); } catch (e) { net = "blocked"; }
      const seen = (globalThis as any).leftover ?? null;
      (globalThis as any).leftover = "set";
      const env = typeof process === "object" ? Object.keys((process as any).env ?? {}) : [];
      return { net, seen, env, Deno: typeof Deno };
    `);
    expect(out).toMatchObject({ ok: true, result: { net: "blocked", seen: null, env: [], Deno: "undefined" } });
    expect((await runTool(`return (globalThis as any).leftover ?? null;`)).out).toMatchObject({ ok: true, result: null });
  });

  it("a script that waits past 10 s is stopped, keeps its logs, and writes nothing", { timeout: 30_000 }, async () => {
    const before = (await serverLog()).length;
    const t0 = Date.now();
    const { out } = await runTool(`await tasks.add({ title: "Too slow" });\nconsole.log("waiting");\nawait new Promise((r) => setTimeout(r, 30000));`);
    expect(Date.now() - t0).toBeLessThan(15_000);
    expect(out).toEqual({ ok: false, error: { type: "Limit", message: "The script ran longer than 10 s, so it was stopped." }, logs: ["waiting"], change: null });
    expect((await serverLog()).length).toBe(before);
  });

  it("a syntax error", async () => {
    const { out, isError } = await runTool(`return (;`);
    expect(isError).toBe(true);
    expect(out).toMatchObject({ ok: false, error: { type: "SyntaxError" }, change: null });
  });
});

describe("Host", () => {
  it("answers nothing after the deadline or once closed", async () => {
    const answer = async () => ({ result: 1 });
    expect(await new Host(answer, Date.now() + 60_000).call("today", [])).toEqual({ result: 1 });
    const late = { error: { type: "Limit", message: "The script ran longer than 10 s, so it was stopped." } };
    expect(await new Host(answer, Date.now() - 1).call("today", [])).toEqual(late);
    const h = new Host(answer, Date.now() + 60_000);
    h.closed = true;
    expect(await h.call("today", [])).toEqual(late);
    h.log("ignored");
    expect(h.lines).toEqual([]);
  });
});
