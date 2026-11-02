// The two pages a person sees: /setup (the first passkey, with SETUP_SECRET) and /authorize (consent, approved with
// that passkey). Everything that came from a client is escaped. Each page's script runs under a nonce CSP and talks
// only to this origin.

import type { ConsentDescription } from "@cloudflare/workers-oauth-provider";

export const escape = (value: string) => value.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

const STYLE = `
  :root { color-scheme: light dark; --fg: #1d1d1f; --bg: #fbfbfd; --muted: #6e6e73; --card: #fff; --line: #d2d2d7; --accent: #0a66d8; --warn: #b25000; }
  @media (prefers-color-scheme: dark) { :root { --fg: #f5f5f7; --bg: #111113; --muted: #a1a1a6; --card: #1c1c1e; --line: #3a3a3c; --accent: #4c9bff; --warn: #ff9f40; } }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.5 -apple-system, system-ui, sans-serif; }
  main { max-width: 30rem; margin: 3rem auto; padding: 0 16px; }
  .card { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 1.25rem 1.5rem; }
  h1 { font-size: 1.35rem; margin: 0 0 .75rem; }
  p { margin: .5rem 0; }
  dl { display: grid; grid-template-columns: auto 1fr; gap: .25rem 1rem; margin: 1rem 0; }
  dt { color: var(--muted); }
  dd { margin: 0; overflow-wrap: anywhere; }
  code { font: 14px ui-monospace, monospace; }
  .warn { color: var(--warn); }
  .muted { color: var(--muted); font-size: .9rem; }
  .row { display: flex; gap: .75rem; margin-top: 1.25rem; flex-wrap: wrap; }
  button { font: inherit; padding: .55rem 1rem; border-radius: 8px; border: 1px solid var(--line); background: var(--card); color: var(--fg); cursor: pointer; }
  button.primary { background: var(--accent); border-color: var(--accent); color: #fff; }
  input { font: inherit; width: 100%; padding: .5rem .6rem; border-radius: 8px; border: 1px solid var(--line); background: var(--bg); color: var(--fg); }
  #status { min-height: 1.5em; }
`;

/** Base64url and the JSON forms of WebAuthn options and credentials, for browsers without the native helpers. */
const WEBAUTHN_JS = `
const dec = (s) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0)).buffer;
const enc = (b) => btoa(String.fromCharCode(...new Uint8Array(b))).replace(/\\+/g, "-").replace(/\\//g, "_").replace(/=+$/, "");
const creationOptions = (o) => ({ ...o, challenge: dec(o.challenge), user: { ...o.user, id: dec(o.user.id) },
  excludeCredentials: (o.excludeCredentials || []).map((c) => ({ ...c, id: dec(c.id) })) });
const requestOptions = (o) => ({ ...o, challenge: dec(o.challenge), allowCredentials: (o.allowCredentials || []).map((c) => ({ ...c, id: dec(c.id) })) });
function credentialJSON(c) {
  const r = c.response;
  const out = { id: c.id, rawId: enc(c.rawId), type: c.type, clientExtensionResults: c.getClientExtensionResults(),
    authenticatorAttachment: c.authenticatorAttachment || undefined, response: { clientDataJSON: enc(r.clientDataJSON) } };
  if (r.attestationObject) {
    out.response.attestationObject = enc(r.attestationObject);
    out.response.transports = r.getTransports ? r.getTransports() : [];
  } else {
    out.response.authenticatorData = enc(r.authenticatorData);
    out.response.signature = enc(r.signature);
    if (r.userHandle) out.response.userHandle = enc(r.userHandle);
  }
  return out;
}
const status = (text) => { document.getElementById("status").textContent = text; };
async function post(path, body) {
  const r = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const j = await r.json().catch(() => ({ ok: false, reason: "HTTP " + r.status }));
  if (!r.ok || j.ok === false) throw new Error(j.reason || "HTTP " + r.status);
  return j;
}
`;

function page(title: string, body: string, script = ""): { html: string; headers: Headers } {
  const nonce = crypto.randomUUID().replace(/-/g, "");
  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(title)}</title><style>${STYLE}</style></head>
<body><main><div class="card">${body}</div></main>${script ? `<script nonce="${nonce}">${WEBAUTHN_JS}${script}</script>` : ""}</body></html>`;
  const headers = new Headers({
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-store",
    "Content-Security-Policy": `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`,
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
  });
  return { html, headers };
}

export function htmlResponse(p: { html: string; headers: Headers }, status = 200, extra?: Headers): Response {
  if (extra) extra.forEach((v, k) => (k.toLowerCase() === "set-cookie" ? p.headers.append(k, v) : k.toLowerCase() === "content-security-policy" ? undefined : p.headers.set(k, v)));
  return new Response(p.html, { status, headers: p.headers });
}

export function messagePage(title: string, message: string) {
  return page(title, `<h1>${escape(title)}</h1><p>${escape(message)}</p>`);
}

export function setupPage(open: boolean, host: string) {
  if (!open) return messagePage("Setup is closed", "A passkey is already set up for Tasks. Registration is closed.");
  return page("Set up Tasks", `
<h1>Set up your passkey</h1>
<p>This passkey approves every app that connects to your Tasks. Only one can be set up; registration closes after it.</p>
<p class="muted">It's tied to <code>${escape(host)}</code>: set it up on the address apps will connect to.</p>
<p><label for="secret">Setup secret</label><input id="secret" type="password" autocomplete="off"></p>
<div class="row"><button class="primary" id="go">Create passkey</button></div>
<p id="status" class="muted"></p>`, `
document.getElementById("go").addEventListener("click", async () => {
  const secret = document.getElementById("secret").value;
  try {
    status("Waiting for your passkey…");
    const { challengeId, options } = await post("/setup/options", { secret });
    const credential = await navigator.credentials.create({ publicKey: creationOptions(options) });
    await post("/setup/verify", { secret, challengeId, response: credentialJSON(credential) });
    document.querySelector(".card").innerHTML = "<h1>Passkey set up</h1><p>Registration is now closed. Connect an app to approve it with this passkey.</p>";
  } catch (e) { status(e.message); }
});`);
}

export function consentPage(d: ConsentDescription, handle: string, actor: string, hasPasskey: boolean) {
  const name = escape(d.clientName);
  const origin = d.clientDomain
    ? `Published by <strong>${escape(d.clientDomain)}</strong>.`
    : "This app registered itself; its name is not verified.";
  if (!hasPasskey) {
    return page("No passkey yet", `<h1>No passkey yet</h1><p>Set one up at <code>/setup</code> on this address, then connect again.</p>`);
  }
  return page(`Allow ${d.clientName}?`, `
<h1>Allow ${name} to use your Tasks?</h1>
<p>${origin}</p>
<p>It will be able to read and change all your lists and tasks.</p>
<dl>
  <dt>Access goes to</dt><dd><strong>${escape(d.redirectHost)}</strong></dd>
  <dt>Redirect</dt><dd><code>${escape(d.redirectUri)}</code></dd>
  <dt>Its changes show as</dt><dd><code>${escape(actor)}</code></dd>
</dl>
${d.redirectIsLoopback ? `<p class="warn"><strong>This sends access to an app on your computer.</strong> Continue only if you just started connecting from it.</p>` : ""}
<div class="row"><button class="primary" id="allow">Allow with passkey</button><button id="deny">Deny</button></div>
<p id="status" class="muted"></p>`, `
const handle = ${JSON.stringify(handle).replace(/</g, "\\u003c")};
document.getElementById("allow").addEventListener("click", async () => {
  try {
    status("Waiting for your passkey…");
    const { challengeId, options } = await post("/authorize/options", {});
    const credential = await navigator.credentials.get({ publicKey: requestOptions(options) });
    const { redirectTo } = await post("/authorize/approve", { handle, challengeId, response: credentialJSON(credential) });
    status("Allowed. Returning to the app…");
    location.assign(redirectTo);
  } catch (e) { status(e.message); }
});
document.getElementById("deny").addEventListener("click", async () => {
  try {
    const { redirectTo } = await post("/authorize/deny", { handle });
    location.assign(redirectTo);
  } catch (e) { status(e.message); }
});`);
}
