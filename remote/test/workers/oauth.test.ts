// OAuth and the passkey, end to end in workerd: setup with SETUP_SECRET (once), discovery, client registration,
// consent approved with a (virtual) passkey, PKCE, tokens and refresh, and /mcp with each client's actor.

import { reset } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import { SoftAuthenticator } from "./authenticator.ts";
import { freshServer, serverLog } from "./helpers.ts";
import { approve, connect, fetchWorker, mcpCall, openConsent, ORIGIN, postJSON, REDIRECT, register, setUp, token } from "./oauth.ts";

const owner = new SoftAuthenticator();

beforeAll(async () => {
  await reset();
  await freshServer();
});

describe("before setup", () => {
  it("/authorize says there's no passkey yet", async () => {
    const c = await openConsent(await register("Early"));
    expect(c.status).toBe(409);
    expect(c.html).toContain("No passkey yet");
    expect(c.handle).toBe("");
    const o = await postJSON("/authorize/options", {});
    expect(o.status).toBe(409);
  });

  it("/setup needs the secret", async () => {
    expect((await fetchWorker("/setup")).status).toBe(200);
    const wrong = await setUp(new SoftAuthenticator(), "not-the-secret");
    expect(wrong.status).toBe(403);
    expect(await wrong.json()).toEqual({ ok: false, reason: "That isn't the setup secret." });
    expect((await postJSON("/setup/options", {})).status).toBe(403);
  });
});

describe("setup", () => {
  it("registers the first passkey and closes registration", async () => {
    const r = await setUp(owner);
    expect(r.status).toBe(200);
    expect(await r.json()).toEqual({ ok: true });
    const page = await fetchWorker("/setup");
    expect(page.status).toBe(410);
    expect(await page.text()).toContain("Registration is closed");
    const again = await setUp(new SoftAuthenticator());
    expect(again.status).toBe(410);
    expect(await again.json()).toEqual({ ok: false, reason: "Registration is closed: a passkey is already set up." });
  });
});

describe("discovery", () => {
  it("/mcp without a token is a 401 pointing at the resource metadata", async () => {
    const r = await fetchWorker("/mcp", { method: "POST", body: "{}" });
    expect(r.status).toBe(401);
    expect(r.headers.get("WWW-Authenticate")).toMatch(/^Bearer .*resource_metadata="https:\/\/tasks-mcp\.example\/\.well-known\/oauth-protected-resource\/mcp"/);
    const bad = await mcpCall("not-a-token", "ping");
    expect(bad.status).toBe(401);
  });

  it("publishes the resource and the authorization server", async () => {
    const pr = (await (await fetchWorker("/.well-known/oauth-protected-resource/mcp")).json()) as Record<string, unknown>;
    expect(pr).toMatchObject({ resource: `${ORIGIN}/mcp`, authorization_servers: [ORIGIN], scopes_supported: ["tasks"] });
    const as = (await (await fetchWorker("/.well-known/oauth-authorization-server")).json()) as Record<string, unknown>;
    expect(as).toMatchObject({
      issuer: ORIGIN, authorization_endpoint: `${ORIGIN}/authorize`, token_endpoint: `${ORIGIN}/token`,
      registration_endpoint: `${ORIGIN}/register`, scopes_supported: ["tasks"], code_challenge_methods_supported: ["S256"],
    });
  });
});

describe("consent", () => {
  it("shows the client, where access goes, and its actor, escaped", async () => {
    const c = await openConsent(await register(`<script>alert("x")</script> Claude`));
    expect(c.status).toBe(200);
    expect(c.html).not.toContain("<script>alert");
    expect(c.html).toContain("&#60;script&#62;alert(&#34;x&#34;)&#60;/script&#62; Claude");
    expect(c.html).toContain("client.example");
    expect(c.html).toContain("<code>agent:script-alert-x-script-claude</code>");
    expect(c.html).toContain("This app registered itself; its name is not verified.");
    const csp = c.headers.get("Content-Security-Policy") ?? "";
    const nonce = /script-src 'nonce-([0-9a-f]+)'/.exec(csp)?.[1];
    expect(nonce).toBeTruthy();
    expect(c.html).toContain(`<script nonce="${nonce}">`);
    expect(csp).toContain("frame-ancestors 'none'");
    expect(csp).toContain("connect-src 'self'");
    expect(c.headers.get("X-Frame-Options")).toBe("DENY");
    expect(c.headers.get("Cache-Control")).toBe("no-store");
  });

  it("warns when access goes to an app on this computer", async () => {
    const local = "http://127.0.0.1:33418/callback";
    const c = await openConsent(await register("Local app", local), local);
    expect(c.html).toContain("This sends access to an app on your computer.");
  });

  it("a passkey that isn't the owner's, or a forged assertion, is refused", async () => {
    const c = await openConsent(await register("Intruder"));
    const stranger = new SoftAuthenticator();
    await stranger.create({ challenge: "AAAA", rp: { name: "x" }, user: { id: "AAAA" } }, ORIGIN);
    const r1 = await approve(c, stranger);
    expect(r1.status).toBe(403);
    expect(await r1.json()).toEqual({ ok: false, reason: "That passkey isn't the one set up for Tasks." });
    const r2 = await approve(c, owner, { tamper: true });
    expect(r2.status).toBe(403);
    // The handle survives a refused passkey: the owner can still allow it.
    expect((await approve(c, owner)).status).toBe(200);
  });

  it("the handle works only with its cookie, and only once", async () => {
    const c = await openConsent(await register("Replay"));
    expect((await approve(c, owner, { cookie: "" })).status).toBe(400);
    expect((await approve(c, owner)).status).toBe(200);
    expect((await approve(c, owner)).status).toBe(400);
  });

  it("Deny sends the client access_denied with its state", async () => {
    const c = await openConsent(await register("Declined"));
    const r = await postJSON("/authorize/deny", { handle: c.handle }, { Cookie: c.cookie });
    expect(r.status).toBe(200);
    const url = new URL(((await r.json()) as { redirectTo: string }).redirectTo);
    expect(url.origin + url.pathname).toBe(REDIRECT);
    expect(url.searchParams.get("error")).toBe("access_denied");
    expect(url.searchParams.get("state")).toBe(c.state);
  });

  it("the code needs the PKCE verifier", async () => {
    const clientId = await register("No verifier");
    const c = await openConsent(clientId);
    const a = (await (await approve(c, owner)).json()) as { redirectTo: string };
    const code = new URL(a.redirectTo).searchParams.get("code")!;
    const t = await token({ grant_type: "authorization_code", code, redirect_uri: REDIRECT, client_id: clientId, code_verifier: "wrong".repeat(10) });
    expect(t.status).toBe(400);
    expect(t.body.error).toBe("invalid_grant");
  });
});

describe("/mcp with a token", () => {
  it("runs as the client's actor, and two clients write as themselves", async () => {
    const claude = await connect("claude.ai", owner);
    expect(claude.scope).toBe("tasks");
    const other = await connect("Other Agent", owner);
    const run = async (accessToken: string, script: string) => {
      const r = await mcpCall(accessToken, "tools/call", { name: "tasks_run", arguments: { script } });
      expect(r.status).toBe(200);
      return JSON.parse(((await r.json()) as { result: { content: { text: string }[] } }).result.content[0].text);
    };
    expect(await run(claude.accessToken, `return (await tasks.add({ title: "From Claude" })).title;`)).toMatchObject({ ok: true, synced: true });
    expect(await run(other.accessToken, `return (await tasks.add({ title: "From the other" })).title;`)).toMatchObject({ ok: true, synced: true });
    const actors = (await serverLog()).filter((e) => e.op.type === "task.create").map((e) => [e.op.set.title, e.op.actor]);
    expect(actors).toEqual([["From Claude", "agent:claude-ai"], ["From the other", "agent:other-agent"]]);
    // Undo is per actor: each client's undo takes back its own change.
    expect(await run(other.accessToken, `return (await tasks.undo()).summary;`)).toMatchObject({ ok: true, result: 'Undo: New Task "From the other" in Inbox' });
  });

  it("the refresh token gives a new access token", async () => {
    const c = await connect("Refresher", owner);
    const t = await token({ grant_type: "refresh_token", refresh_token: c.refreshToken, client_id: c.clientId });
    expect(t.status).toBe(200);
    const r = await mcpCall(t.body.access_token!, "ping");
    expect(await r.json()).toEqual({ jsonrpc: "2.0", id: 1, result: {} });
  });

  it("a token for another origin isn't accepted here", async () => {
    const c = await connect("Elsewhere", owner);
    const r = await exports_fetch("https://other-host.example/mcp", c.accessToken);
    expect(r.status).toBe(401);
  });
});

async function exports_fetch(url: string, accessToken: string) {
  const { exports } = await import("cloudflare:workers");
  return exports.default.fetch(url, {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "ping" }),
  });
}

describe("actorFor", () => {
  it("is agent: and a slug of the verified domain, else the name; 1–64 characters", async () => {
    const { actorFor } = await import("../../src/auth.ts");
    expect(actorFor({ clientName: "Claude", clientDomain: "claude.ai" })).toBe("agent:claude-ai");
    expect(actorFor({ clientName: "Claude" })).toBe("agent:claude");
    expect(actorFor({ clientName: "  Café Ünïcode — App!! " })).toBe("agent:cafe-unicode-app");
    expect(actorFor({ clientName: "日本語" })).toBe("agent:client");
    const long = actorFor({ clientName: "x".repeat(40) + " " + "y".repeat(40) });
    expect(long.length).toBeLessThanOrEqual(64);
    expect(long).toMatch(/^agent:x+-y+$/);
  });
});
