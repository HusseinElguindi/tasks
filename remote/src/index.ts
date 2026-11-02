// tasks-mcp: `/mcp`, the local `tasks mcp` over Streamable HTTP (JSON responses, no SSE stream), backed by the
// Replica DO. Phase 3 guards it with a bearer token, DEV_TOKEN (unset: closed); phase 4 replaces that with OAuth
// and a passkey, and each client's own actor.

import { declarations } from "./cli/commands.ts";
import { handle, parseError } from "./mcp.ts";
import type { Json } from "./cli/render.ts";
import type { Replica } from "./replica.ts";

export { Replica } from "./replica.ts";

/** Phase 3's one client. */
const DEV_ACTOR = "agent:dev";

const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", ...headers } });

async function sha256(s: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)));
}

/** Constant-time: both sides are hashed first, so even the token's length doesn't leak (as server/ does it). */
async function authorized(header: string | null, token: string | undefined): Promise<boolean> {
  const m = header && /^Bearer +(\S+)$/i.exec(header);
  if (!m || !token) return false;
  const [a, b] = await Promise.all([sha256(m[1]), sha256(token)]);
  return crypto.subtle.timingSafeEqual(a, b);
}

async function mcp(request: Request, env: Env): Promise<Response> {
  if (request.method !== "POST") return json({ error: "method_not_allowed", message: "Use POST for /mcp." }, 405, { Allow: "POST" });
  if (!(await authorized(request.headers.get("Authorization"), (env as { DEV_TOKEN?: string }).DEV_TOKEN))) {
    return json({ error: "unauthorized", message: "Missing or invalid bearer token." }, 401, { "WWW-Authenticate": "Bearer" });
  }
  let body: unknown;
  try {
    body = JSON.parse(await request.text());
  } catch {
    return json(parseError(), 400);
  }
  // The RPC stub's mapped type of a recursive Json is too deep for tsc; the method is Replica.run.
  const replica = env.REPLICA.get(env.REPLICA.idFromName("main")) as unknown as Pick<Replica, "run">;
  const deps = {
    types: declarations,
    run: async (script: string, dryRun: boolean): Promise<Json> => {
      try {
        return await replica.run(script, { dryRun, actor: DEV_ACTOR });
      } catch (e) {
        return { ok: false, error: { type: "Error", message: e instanceof Error ? e.message : String(e) }, logs: [], change: null };
      }
    },
  };
  // A batch (2025-03-26) or one message; notifications and responses get 202 and no body.
  if (Array.isArray(body)) {
    const replies = [];
    for (const m of body) {
      const r = await handle(m, deps);
      if (r) replies.push(r);
    }
    return replies.length > 0 ? json(replies) : new Response(null, { status: 202 });
  }
  const reply = await handle(body, deps);
  return reply ? json(reply) : new Response(null, { status: 202 });
}

export default {
  async fetch(request, env): Promise<Response> {
    const { pathname } = new URL(request.url);
    if (pathname === "/mcp") return mcp(request, env);
    return json({ error: "not_found", message: `No such path: ${pathname}.` }, 404);
  },
} satisfies ExportedHandler<Env>;
