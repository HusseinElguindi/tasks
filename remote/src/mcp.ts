// The MCP server: the local `tasks mcp`'s two tools (TasksCLI/MCP.swift), same instructions, tool text and replies,
// over Streamable HTTP instead of stdio. A test fails if this text drifts from MCP.swift's.

import type { Json } from "./cli/render.ts";

export const INSTRUCTIONS =
  "Tasks is the user's to-do app (lists, Today, When and Deadline dates). Read tasks_types once, then write one " +
  "tasks_run script per request: it can read and change everything the app can, and the whole script is one change " +
  "that the user can undo (the result names it). Use dryRun to preview a change you're unsure about.";

export const TOOLS = [
  {
    name: "tasks_types",
    description: "The TypeScript API (tasks.d.ts) that tasks_run scripts are written against: the `tasks` object, Task, List, Change, dates and refs. Read it before writing a script.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "tasks_run",
    description: "Run a TypeScript script against the user's Tasks. `tasks` is the API from tasks_types; every call is awaited; `return` a value to get it back, and console.log lines come back too. The whole script is one change: written and synced when it returns, nothing written if it throws. No files, network or env. Returns {ok, result, logs, change: {batch, summary, tasks, lists}, synced}, or {ok: false, error: {type, message, line}}.",
    inputSchema: {
      type: "object",
      properties: {
        script: { type: "string", description: "TypeScript; top-level await and return work." },
        dryRun: { type: "boolean", description: "Run it without writing anything; the result includes the diff it would make." },
      },
      required: ["script"],
    },
  },
];

export interface McpDeps {
  /** tasks.d.ts. */
  types(): string;
  /** One tasks_run: the run's result object. */
  run(script: string, dryRun: boolean): Promise<Json>;
}

type Message = { [k: string]: unknown };
const isObject = (v: unknown): v is Message => typeof v === "object" && v !== null && !Array.isArray(v);

const content = (text: string, isError: boolean) => ({ content: [{ type: "text", text }], isError });

export const parseError = () => ({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } });

/** One JSON-RPC message → its reply, or null for a notification (or a response). `MCP.handle`. */
export async function handle(m: unknown, deps: McpDeps): Promise<Message | null> {
  if (!isObject(m) || !("id" in m)) return null;
  const id = m.id;
  const result = (r: unknown) => ({ jsonrpc: "2.0", id, result: r });
  const error = (code: number, message: string) => ({ jsonrpc: "2.0", id, error: { code, message } });
  const params = isObject(m.params) ? m.params : undefined;
  switch (typeof m.method === "string" ? m.method : "") {
    case "initialize":
      return result({
        protocolVersion: typeof params?.protocolVersion === "string" ? params.protocolVersion : "2025-06-18",
        capabilities: { tools: {} },
        serverInfo: { name: "tasks", version: "1.0" },
        instructions: INSTRUCTIONS,
      });
    case "ping":
      return result({});
    case "tools/list":
      return result({ tools: TOOLS });
    case "tools/call": {
      const args = isObject(params?.arguments) ? params.arguments : undefined;
      switch (params?.name) {
        case "tasks_types":
          return result(content(deps.types(), false));
        case "tasks_run": {
          if (typeof args?.script !== "string") return error(-32602, "tasks_run needs a script.");
          const out = await deps.run(args.script, args.dryRun === true);
          return result(content(JSON.stringify(out), !(isObject(out) && out.ok === true)));
        }
        default:
          return error(-32602, `Unknown tool ${typeof params?.name === "string" ? params.name : ""}.`);
      }
    }
    default:
      return error(-32601, "Method not found");
  }
}
