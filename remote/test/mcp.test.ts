// The MCP text against TasksCLI/MCP.swift (the local `tasks mcp`), and the JSON-RPC replies against its `handle`.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { Json } from "../src/cli/render.ts";
import { handle, INSTRUCTIONS, TOOLS } from "../src/mcp.ts";

const swift = readFileSync(join(import.meta.dirname, "../../app/TasksCore/Sources/TasksCLI/MCP.swift"), "utf8");

/** A Swift `"""` literal with `\` line continuations, as its value. */
function multiline(name: string): string {
  const m = new RegExp(`static let ${name} = """\\n([\\s\\S]*?)\\n\\s*"""`).exec(swift);
  if (!m) throw new Error(`no ${name} in MCP.swift`);
  return m[1].split("\n").map((l) => l.trim()).join("\n").replace(/\\\n/g, "");
}

describe("the same text as MCP.swift", () => {
  it("instructions", () => expect(INSTRUCTIONS).toBe(multiline("instructions")));
  it("tool names, descriptions and argument descriptions", () => {
    // Every plain `.string("…")` literal (interpolated ones, `\(…)`, aren't tool text).
    const strings = [...swift.matchAll(/\.string\("((?:[^"\\]|\\.)*)"\)/g)].map((m) => m[1]).filter((s) => !s.includes("\\(")).map((s) => JSON.parse(`"${s}"`) as string);
    for (const t of TOOLS) {
      expect(strings).toContain(t.name);
      expect(strings).toContain(t.description);
      for (const [k, p] of Object.entries(t.inputSchema.properties as Record<string, { type: string; description: string }>)) {
        expect(strings, k).toContain(p.description);
        expect(strings, k).toContain(p.type);
      }
    }
    expect(TOOLS.map((t) => t.name)).toEqual(["tasks_types", "tasks_run"]);
    expect(swift).toContain(`"required": .array([.string("script")])`);
  });
});

describe("handle, as MCP.handle", () => {
  const runs: [string, boolean][] = [];
  const deps = {
    types: () => "declare const tasks: Tasks;",
    run: async (script: string, dryRun: boolean): Promise<Json> => {
      runs.push([script, dryRun]);
      return script === "fail" ? { ok: false, error: { type: "Error", message: "x" }, logs: [], change: null } : { ok: true, result: 1 };
    },
  };
  const call = (method: string, params?: unknown, id: unknown = 1) => handle({ jsonrpc: "2.0", id, method, params }, deps);

  it("initialize echoes the client's protocol version", async () => {
    expect(await call("initialize", { protocolVersion: "2025-03-26" })).toEqual({
      jsonrpc: "2.0", id: 1,
      result: { protocolVersion: "2025-03-26", capabilities: { tools: {} }, serverInfo: { name: "tasks", version: "1.0" }, instructions: INSTRUCTIONS },
    });
    expect(((await call("initialize")) as { result: { protocolVersion: string } }).result.protocolVersion).toBe("2025-06-18");
  });

  it("notifications and responses get no reply", async () => {
    expect(await handle({ jsonrpc: "2.0", method: "notifications/initialized" }, deps)).toBeNull();
    expect(await handle({ jsonrpc: "2.0", result: {} }, deps)).toBeNull();
    expect(await handle([1, 2], deps)).toBeNull();
  });

  it("ping, tools/list, unknown methods and tools", async () => {
    expect(await call("ping")).toEqual({ jsonrpc: "2.0", id: 1, result: {} });
    expect(await call("tools/list")).toEqual({ jsonrpc: "2.0", id: 1, result: { tools: TOOLS } });
    expect(await call("nope")).toEqual({ jsonrpc: "2.0", id: 1, error: { code: -32601, message: "Method not found" } });
    expect(await call("tools/call", { name: "x" })).toEqual({ jsonrpc: "2.0", id: 1, error: { code: -32602, message: "Unknown tool x." } });
    expect(await call("tools/call", {})).toEqual({ jsonrpc: "2.0", id: 1, error: { code: -32602, message: "Unknown tool ." } });
  });

  it("tools/call: the types, a run's JSON text, isError, and a missing script", async () => {
    expect(await call("tools/call", { name: "tasks_types" })).toEqual({
      jsonrpc: "2.0", id: 1, result: { content: [{ type: "text", text: "declare const tasks: Tasks;" }], isError: false },
    });
    expect(await call("tools/call", { name: "tasks_run", arguments: { script: "ok", dryRun: true } }, "a")).toEqual({
      jsonrpc: "2.0", id: "a", result: { content: [{ type: "text", text: '{"ok":true,"result":1}' }], isError: false },
    });
    const failed = (await call("tools/call", { name: "tasks_run", arguments: { script: "fail", dryRun: "yes" } })) as { result: { isError: boolean } };
    expect(failed.result.isError).toBe(true);
    expect(runs).toEqual([["ok", true], ["fail", false]]);
    expect(await call("tools/call", { name: "tasks_run", arguments: { script: 1 } })).toEqual({
      jsonrpc: "2.0", id: 1, error: { code: -32602, message: "tasks_run needs a script." },
    });
  });
});
