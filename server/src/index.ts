// The Worker: routing, auth, size limits, parsing and validation, then one RPC to the
// UserLog Durable Object (SPEC §5 "Check order", §7). A bad request never reaches the DO.

import { createHash, timingSafeEqual } from "node:crypto";
import { HttpError, MAX_BODY_BYTES, parseSyncRequest } from "./validate";

export { UserLog } from "./log";

const PATH = "/v1/sync";

export default {
  async fetch(request, env): Promise<Response> {
    const encoding = pickEncoding(request);
    try {
      return json(200, await handle(request, env), encoding);
    } catch (e) {
      if (e instanceof HttpError) {
        const body: Record<string, unknown> = { error: e.code, message: e.message };
        if (e.index !== undefined) Object.assign(body, { index: e.index, field: e.field });
        return json(e.status, JSON.stringify(body), encoding, e.status === 405 ? { Allow: "POST" } : {});
      }
      console.error(e);
      return json(500, JSON.stringify({ error: "internal", message: "Internal error." }), encoding);
    }
  },
} satisfies ExportedHandler<Env>;

async function handle(request: Request, env: Env): Promise<string> {
  const { pathname } = new URL(request.url);
  if (pathname !== PATH) throw new HttpError(404, "not_found", `No such path: ${pathname}.`);
  if (request.method !== "POST") throw new HttpError(405, "method_not_allowed", `Use POST for ${PATH}.`);
  if (!authorized(request.headers.get("Authorization"), env.API_TOKEN)) {
    throw new HttpError(401, "bad_token", "Missing or invalid bearer token.");
  }

  const { from, base, ops } = parseSyncRequest(await readBody(request));
  const log = env.LOG.get(env.LOG.idFromName("me"));
  const result = await log.sync(from, base, ops);
  if (!result.ok) throw new HttpError(409, "log_mismatch", result.message);
  return result.body;
}

const sha256 = (s: string) => createHash("sha256").update(s).digest();
const utf8 = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false });

/** Constant-time: both sides are hashed first, so even the token's length doesn't leak. */
function authorized(header: string | null, token: string | undefined): boolean {
  const m = header && /^Bearer +(\S+)$/i.exec(header);
  return !!m && !!token && timingSafeEqual(sha256(m[1]), sha256(token));
}

async function readBody(request: Request): Promise<string> {
  const tooLarge = () => new HttpError(413, "too_large", `Body is larger than ${MAX_BODY_BYTES} bytes.`);
  if (Number(request.headers.get("Content-Length")) > MAX_BODY_BYTES) throw tooLarge();
  const bytes = await request.arrayBuffer();
  if (bytes.byteLength > MAX_BODY_BYTES) throw tooLarge();
  try {
    return utf8.decode(bytes);
  } catch {
    throw new HttpError(400, "bad_request", "Body is not valid UTF-8.");
  }
}

type Encoding = "br" | "gzip" | null;

/**
 * br, else gzip, else nothing, from the client's Accept-Encoding. Cloudflare may rewrite
 * that header before the Worker sees it and keeps the original in cf.clientAcceptEncoding.
 * Setting Content-Encoding is enough: the runtime compresses the body (encodeBody: "automatic").
 */
function pickEncoding(request: Request): Encoding {
  const header = (request.cf?.clientAcceptEncoding as string | undefined) ?? request.headers.get("Accept-Encoding") ?? "";
  const accepted = new Set<string>();
  for (const part of header.split(",")) {
    const [name, ...params] = part.trim().toLowerCase().split(";");
    const q = params.map((p) => p.trim()).find((p) => p.startsWith("q="));
    if (!q || Number(q.slice(2)) > 0) accepted.add(name.trim());
  }
  return accepted.has("br") ? "br" : accepted.has("gzip") ? "gzip" : null;
}

function json(status: number, body: string, encoding: Encoding, extra: Record<string, string> = {}): Response {
  const headers: Record<string, string> = { "Content-Type": "application/json; charset=utf-8", ...extra };
  if (encoding) headers["Content-Encoding"] = encoding;
  return new Response(body, { status, headers });
}
