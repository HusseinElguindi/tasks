// The browser and the MCP client, for the tests: set up the passkey on /setup, register a client, walk /authorize
// with the passkey, and exchange the code (PKCE) for tokens. All against the Worker in this isolate.

import { exports } from "cloudflare:workers";
import { expect } from "vitest";
import { b64url, SoftAuthenticator } from "./authenticator.ts";

export const ORIGIN = "https://tasks-mcp.example";
export const SETUP_SECRET = "test-setup-secret";
export const REDIRECT = "https://client.example/callback";

export const fetchWorker = (path: string, init?: RequestInit) => exports.default.fetch(new URL(path, ORIGIN).toString(), init);
export const postJSON = (path: string, body: unknown, headers: Record<string, string> = {}) =>
  fetchWorker(path, { method: "POST", headers: { "Content-Type": "application/json", ...headers }, body: JSON.stringify(body) });

/** /setup with the secret: options, the authenticator's credential, verify. */
export async function setUp(authenticator: SoftAuthenticator, secret = SETUP_SECRET): Promise<Response> {
  const o = await postJSON("/setup/options", { secret });
  if (o.status !== 200) return o;
  const { challengeId, options } = (await o.json()) as { challengeId: string; options: Parameters<SoftAuthenticator["create"]>[0] };
  return postJSON("/setup/verify", { secret, challengeId, response: await authenticator.create(options, ORIGIN) });
}

/** RFC 7591 registration of a public client. */
export async function register(clientName: string, redirect = REDIRECT): Promise<string> {
  const r = await postJSON("/register", {
    client_name: clientName, redirect_uris: [redirect], token_endpoint_auth_method: "none",
    grant_types: ["authorization_code", "refresh_token"], response_types: ["code"],
  });
  expect(r.status).toBe(201);
  return ((await r.json()) as { client_id: string }).client_id;
}

export interface Consent {
  status: number;
  headers: Headers;
  html: string;
  cookie: string;
  handle: string;
  verifier: string;
  state: string;
}

/** GET /authorize as the browser: the consent page, its cookie and handle, with a PKCE verifier. */
export async function openConsent(clientId: string, redirect = REDIRECT): Promise<Consent> {
  const verifier = b64url(crypto.getRandomValues(new Uint8Array(32)));
  const challenge = b64url(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier))));
  const state = crypto.randomUUID();
  const q = new URLSearchParams({
    response_type: "code", client_id: clientId, redirect_uri: redirect, code_challenge: challenge,
    code_challenge_method: "S256", state, scope: "tasks", resource: `${ORIGIN}/mcp`,
  });
  const r = await fetchWorker(`/authorize?${q}`);
  const html = await r.text();
  const cookie = r.headers.getSetCookie().map((c) => c.split(";")[0]).join("; ");
  const handle = /const handle = "([^"]*)"/.exec(html)?.[1] ?? "";
  return { status: r.status, headers: r.headers, html, cookie, handle, verifier, state };
}

/** Allow with the passkey: options, assertion, approve. Returns the approve response. */
export async function approve(c: Consent, authenticator: SoftAuthenticator, o: { tamper?: boolean; cookie?: string } = {}): Promise<Response> {
  const opts = await postJSON("/authorize/options", {}, { Cookie: c.cookie });
  expect(opts.status).toBe(200);
  const { challengeId, options } = (await opts.json()) as { challengeId: string; options: Parameters<SoftAuthenticator["get"]>[0] };
  const response = await authenticator.get(options, ORIGIN, o.tamper);
  return postJSON("/authorize/approve", { handle: c.handle, challengeId, response }, { Cookie: o.cookie ?? c.cookie });
}

export async function token(params: Record<string, string>) {
  const r = await fetchWorker("/token", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams(params) });
  return { status: r.status, body: (await r.json()) as { access_token?: string; refresh_token?: string; scope?: string; error?: string } };
}

/** The whole connection, as an MCP client and its user do it: a client id and an access token. */
export async function connect(clientName: string, authenticator: SoftAuthenticator) {
  const clientId = await register(clientName);
  const c = await openConsent(clientId);
  expect(c.status).toBe(200);
  const a = await approve(c, authenticator);
  expect(a.status).toBe(200);
  const { redirectTo } = (await a.json()) as { redirectTo: string };
  const url = new URL(redirectTo);
  expect(url.searchParams.get("state")).toBe(c.state);
  const t = await token({
    grant_type: "authorization_code", code: url.searchParams.get("code")!, redirect_uri: REDIRECT, client_id: clientId,
    code_verifier: c.verifier, resource: `${ORIGIN}/mcp`,
  });
  expect(t.status).toBe(200);
  return { clientId, accessToken: t.body.access_token!, refreshToken: t.body.refresh_token!, scope: t.body.scope };
}

/** One JSON-RPC call to /mcp with a bearer token. */
export async function mcpCall(accessToken: string, method: string, params?: unknown) {
  const r = await fetchWorker("/mcp", {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  return r;
}
