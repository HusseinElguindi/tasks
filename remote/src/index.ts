// tasks-mcp. Phase 2: the Replica DO and its sync with the main Worker. The MCP endpoint (code mode on Worker
// Loader) and OAuth come in phases 3 and 4; until then nothing is served.

export { Replica } from "./replica.ts";

export default {
  async fetch(): Promise<Response> {
    return new Response(JSON.stringify({ error: "not_found", message: "Nothing here yet." }), {
      status: 404,
      headers: { "Content-Type": "application/json; charset=utf-8" },
    });
  },
} satisfies ExportedHandler<Env>;
