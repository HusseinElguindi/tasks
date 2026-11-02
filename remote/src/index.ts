// tasks-mcp: `/mcp` (the local `tasks mcp` over Streamable HTTP, backed by the Replica DO) behind OAuth 2.1 from
// @cloudflare/workers-oauth-provider. Clients register themselves (DCR, or a Client ID Metadata Document), and the
// owner approves each one on /authorize with the passkey set up once on /setup. A client's token carries its actor
// (`agent:claude-ai`), which every op it writes is stamped with.
//
// The resource is this request's own origin + /mcp, so the same build works on localhost, workers.dev or a custom
// domain without configuration. A token only works on the origin it was issued for.

import { AuthorizationError, CimdFetchError, OAuthProvider, type AuthRequest, type OAuthHelpers } from "@cloudflare/workers-oauth-provider";
import { actorFor, type RelyingParty } from "./auth.ts";
import { declarations } from "./cli/commands.ts";
import type { Json } from "./cli/render.ts";
import { handle, parseError } from "./mcp.ts";
import { consentPage, escape, htmlResponse, messagePage, setupPage } from "./pages.ts";
import type { Replica } from "./replica.ts";

export { Auth } from "./auth.ts";
export { Replica } from "./replica.ts";

/** The one scope: read and change everything, as the local `tasks mcp` can. */
const SCOPE = "tasks";

/** What a grant carries to /mcp (`ctx.props`). */
interface Props {
  actor: string;
}

const json = (body: unknown, status = 200, headers: HeadersInit = {}) => {
  const h = new Headers(headers);
  h.set("Content-Type", "application/json");
  return new Response(JSON.stringify(body), { status, headers: h });
};

// MARK: /mcp

async function mcp(request: Request, env: Env, actor: string): Promise<Response> {
  if (request.method !== "POST") return json({ error: "method_not_allowed", message: "Use POST for /mcp." }, 405, { Allow: "POST" });
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
        return await replica.run(script, { dryRun, actor });
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

const api = {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const { props, auth } = ctx as unknown as { props?: Props; auth?: { scope: string[] } };
    if (!props?.actor || !auth?.scope.includes(SCOPE)) {
      return json({ error: "insufficient_scope", message: `This token doesn't carry the ${SCOPE} scope.` }, 403);
    }
    return mcp(request, env, props.actor);
  },
};

// MARK: Setup and consent

const auth = (env: Env) => env.AUTH.get(env.AUTH.idFromName("owner"));
const relyingParty = (request: Request): RelyingParty => {
  const url = new URL(request.url);
  return { origin: url.origin, rpID: url.hostname };
};

async function sha256(s: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)));
}

/** Constant-time: both sides are hashed first, so even the length doesn't leak. Unset: always false. */
async function secretMatches(given: unknown, secret: string | undefined): Promise<boolean> {
  if (typeof given !== "string" || !secret) return false;
  const [a, b] = await Promise.all([sha256(given), sha256(secret)]);
  return crypto.subtle.timingSafeEqual(a, b);
}

async function body(request: Request): Promise<Record<string, unknown>> {
  try {
    const b = await request.json();
    return b && typeof b === "object" && !Array.isArray(b) ? (b as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

const failure = (reason: string, status = 400) => json({ ok: false, reason }, status);

async function setup(request: Request, env: Env, path: string): Promise<Response> {
  const secret = (env as { SETUP_SECRET?: string }).SETUP_SECRET;
  const rp = relyingParty(request);
  if (path === "/setup" && request.method === "GET") {
    if (!secret) return htmlResponse(messagePage("Setup is off", "SETUP_SECRET isn't set on this Worker."), 404);
    const { registrationOpen } = await auth(env).status();
    return htmlResponse(setupPage(registrationOpen, rp.rpID), registrationOpen ? 200 : 410);
  }
  if (request.method !== "POST") return failure("Use POST.", 405);
  const b = await body(request);
  if (!(await secretMatches(b.secret, secret))) return failure("That isn't the setup secret.", 403);
  if (path === "/setup/options") {
    const r = await auth(env).registrationOptions(rp);
    return r.ok ? json(r) : failure(r.reason, 410);
  }
  if (path === "/setup/verify") {
    const r = await auth(env).register(String(b.challengeId), b.response as never, rp);
    return r.ok ? json(r) : failure(r.reason, 400);
  }
  return failure("No such path.", 404);
}

/** The client's description and the actor its ops will carry, as the page shows them. */
async function describe(oauth: OAuthHelpers, request: AuthRequest) {
  const d = await oauth.describeConsent(request);
  return { d, actor: actorFor(d) };
}

async function authorize(request: Request, env: Env, path: string): Promise<Response> {
  const oauth = (env as unknown as { OAUTH_PROVIDER: OAuthHelpers }).OAUTH_PROVIDER;
  const rp = relyingParty(request);
  try {
    if (path === "/authorize" && request.method === "GET") {
      const authRequest = await oauth.parseAuthRequest(request);
      const { d, actor } = await describe(oauth, authRequest);
      const { passkeys } = await auth(env).status();
      if (passkeys === 0) return htmlResponse(consentPage(d, "", actor, false), 409);
      const consent = await oauth.beginConsent(authRequest);
      return htmlResponse(consentPage(d, consent.handle, actor, true), 200, consent.headers);
    }
    if (request.method !== "POST") return failure("Use POST.", 405);
    const b = await body(request);
    if (path === "/authorize/options") {
      const r = await auth(env).authenticationOptions(rp);
      return r.ok ? json(r) : failure(r.reason, 409);
    }
    if (path === "/authorize/approve") {
      // The passkey first: approving consumes the consent handle.
      const verified = await auth(env).authenticate(String(b.challengeId), b.response as never, rp);
      if (!verified.ok) return failure(verified.reason, 403);
      const approved = await oauth.approveConsent(request, String(b.handle), { scope: [SCOPE] });
      const { d, actor } = await describe(oauth, approved.request);
      const { redirectTo } = await oauth.completeAuthorization({
        request: approved.request,
        userId: "owner",
        metadata: { client: d.clientName, actor },
        scope: approved.request.scope,
        props: { actor } satisfies Props,
      });
      return json({ ok: true, redirectTo }, 200, approved.headers);
    }
    if (path === "/authorize/deny") {
      const denied = await oauth.denyConsent(request, String(b.handle));
      const headers = new Headers(denied.headers);
      headers.delete("Location");
      return json({ ok: true, redirectTo: denied.redirectTo }, 200, headers);
    }
    return failure("No such path.", 404);
  } catch (error) {
    // The library's table: redirect only once the client and its redirect URI are validated; else render here.
    if (error instanceof AuthorizationError && error.redirectTo && request.method === "GET") return Response.redirect(error.redirectTo, 302);
    if (error instanceof AuthorizationError || error instanceof CimdFetchError) {
      const message = error instanceof AuthorizationError ? error.description ?? error.code : "This app could not be verified.";
      if (request.method !== "GET") return failure(message, 400);
      return htmlResponse(messagePage("Can't connect this app", message), 400);
    }
    throw error;
  }
}

const app = {
  async fetch(request: Request, env: Env): Promise<Response> {
    const { pathname } = new URL(request.url);
    if (pathname === "/setup" || pathname.startsWith("/setup/")) return setup(request, env, pathname);
    if (pathname === "/authorize" || pathname.startsWith("/authorize/")) return authorize(request, env, pathname);
    if (pathname === "/") return new Response(`tasks-mcp: connect an MCP client to ${escape(new URL(request.url).origin)}/mcp\n`, { headers: { "Content-Type": "text/plain; charset=utf-8" } });
    return json({ error: "not_found", message: `No such path: ${pathname}.` }, 404);
  },
};

// One provider per origin: the resource and the issuer are the origin the request came in on.
const providers = new Map<string, OAuthProvider<Env>>();

function providerFor(origin: string): OAuthProvider<Env> {
  let p = providers.get(origin);
  if (!p) {
    p = new OAuthProvider<Env>({
      apiRoute: "/mcp",
      apiHandler: api,
      defaultHandler: app,
      authorizeEndpoint: "/authorize",
      tokenEndpoint: "/token",
      clientRegistrationEndpoint: "/register",
      clientIdMetadataDocumentEnabled: true,
      scopesSupported: [SCOPE],
      requiredScopes: [SCOPE],
      resourceMetadata: { resource: `${origin}/mcp`, authorization_servers: [origin], resource_name: "Tasks" },
      // A grant lives while it's used: each refresh moves its expiry 60 days out.
      refreshTokenIdleTTL: 60 * 24 * 3600,
    });
    providers.set(origin, p);
  }
  return p;
}

export default {
  fetch(request, env, ctx): Promise<Response> {
    return providerFor(new URL(request.url).origin).fetch(request, env, ctx);
  },
} satisfies ExportedHandler<Env>;
