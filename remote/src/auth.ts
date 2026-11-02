// The Auth Durable Object: the owner's passkeys (WebAuthn, via @simplewebauthn/server), the one-time registration
// that SETUP_SECRET opens, and the short-lived challenges in between. One instance (`idFromName("owner")`).
//
// Registration closes when the first passkey is stored, in the same transaction, so a second setup can't race it.
// A passkey is bound to the hostname it was made on (its RP ID): register on the host clients will use.

import { DurableObject } from "cloudflare:workers";
import {
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
  type AuthenticationResponseJSON,
  type RegistrationResponseJSON,
} from "@simplewebauthn/server";

const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS passkeys (id TEXT PRIMARY KEY, public_key TEXT NOT NULL, counter INTEGER NOT NULL,
     transports TEXT NOT NULL, rp_id TEXT NOT NULL, created INTEGER NOT NULL, used INTEGER)`,
  `CREATE TABLE IF NOT EXISTS challenges (id TEXT PRIMARY KEY, challenge TEXT NOT NULL, kind TEXT NOT NULL, rp_id TEXT NOT NULL, expires INTEGER NOT NULL)`,
  `CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)`,
];

/** How long a passkey prompt stays valid. */
const CHALLENGE_TTL_MS = 5 * 60_000;

/** Where a ceremony runs: the page's origin and its hostname (the RP ID). */
export interface RelyingParty {
  origin: string;
  rpID: string;
}

export type AuthResult = { ok: true } | { ok: false; reason: string };

const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const unb64url = (s: string) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));

export class Auth extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    for (const s of SCHEMA) ctx.storage.sql.exec(s);
  }

  private get sql(): SqlStorage {
    return this.ctx.storage.sql;
  }

  private get closed(): boolean {
    return this.sql.exec("SELECT 1 FROM meta WHERE key = 'registration' AND value = 'closed'").toArray().length > 0;
  }

  async status(): Promise<{ registrationOpen: boolean; passkeys: number }> {
    const n = this.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM passkeys").one().n;
    return { registrationOpen: !this.closed, passkeys: n };
  }

  private saveChallenge(challenge: string, kind: "register" | "authenticate", rpID: string): string {
    const id = crypto.randomUUID();
    const now = Date.now();
    this.sql.exec("DELETE FROM challenges WHERE expires < ?", now);
    this.sql.exec("INSERT INTO challenges (id, challenge, kind, rp_id, expires) VALUES (?, ?, ?, ?, ?)", id, challenge, kind, rpID, now + CHALLENGE_TTL_MS);
    return id;
  }

  /** Takes a challenge (once): its value if it's this kind, for this RP, and not expired. */
  private takeChallenge(id: string, kind: string, rpID: string): string | null {
    const row = this.sql.exec<{ challenge: string; kind: string; rp_id: string; expires: number }>(
      "SELECT challenge, kind, rp_id, expires FROM challenges WHERE id = ?", String(id)).toArray()[0];
    this.sql.exec("DELETE FROM challenges WHERE id = ?", String(id));
    if (!row || row.kind !== kind || row.rp_id !== rpID || row.expires < Date.now()) return null;
    return row.challenge;
  }

  // MARK: Registration (setup)

  async registrationOptions(rp: RelyingParty): Promise<{ ok: true; challengeId: string; options: unknown } | { ok: false; reason: string }> {
    if (this.closed) return { ok: false, reason: "Registration is closed: a passkey is already set up." };
    const options = await generateRegistrationOptions({
      rpName: "Tasks",
      rpID: rp.rpID,
      userName: "owner",
      userDisplayName: "Tasks owner",
      attestationType: "none",
      authenticatorSelection: { residentKey: "preferred", userVerification: "required" },
    });
    return { ok: true, challengeId: this.saveChallenge(options.challenge, "register", rp.rpID), options };
  }

  async register(challengeId: string, response: RegistrationResponseJSON, rp: RelyingParty): Promise<AuthResult> {
    if (this.closed) return { ok: false, reason: "Registration is closed: a passkey is already set up." };
    const expectedChallenge = this.takeChallenge(challengeId, "register", rp.rpID);
    if (!expectedChallenge) return { ok: false, reason: "That passkey prompt expired. Start again." };
    let verified;
    try {
      verified = await verifyRegistrationResponse({
        response, expectedChallenge, expectedOrigin: rp.origin, expectedRPID: rp.rpID, requireUserVerification: true,
      });
    } catch (e) {
      return { ok: false, reason: `The passkey couldn't be verified: ${e instanceof Error ? e.message : String(e)}` };
    }
    if (!verified.verified) return { ok: false, reason: "The passkey couldn't be verified." };
    const c = verified.registrationInfo.credential;
    // After the awaits above: check again and store in one transaction, so only one registration ever wins.
    return this.ctx.storage.transactionSync((): AuthResult => {
      if (this.closed) return { ok: false, reason: "Registration is closed: a passkey is already set up." };
      this.sql.exec("INSERT INTO passkeys (id, public_key, counter, transports, rp_id, created) VALUES (?, ?, ?, ?, ?, ?)",
        c.id, b64url(c.publicKey), c.counter, JSON.stringify(c.transports ?? []), rp.rpID, Date.now());
      this.sql.exec("INSERT INTO meta (key, value) VALUES ('registration', 'closed') ON CONFLICT (key) DO UPDATE SET value = 'closed'");
      return { ok: true };
    });
  }

  // MARK: Authentication (consent)

  async authenticationOptions(rp: RelyingParty): Promise<{ ok: true; challengeId: string; options: unknown } | { ok: false; reason: string }> {
    const keys = this.sql.exec<{ id: string; transports: string }>("SELECT id, transports FROM passkeys WHERE rp_id = ?", rp.rpID).toArray();
    if (keys.length === 0) return { ok: false, reason: `No passkey is set up for ${rp.rpID}. Open /setup first.` };
    const options = await generateAuthenticationOptions({
      rpID: rp.rpID,
      allowCredentials: keys.map((k) => ({ id: k.id, transports: JSON.parse(k.transports) })),
      userVerification: "required",
    });
    return { ok: true, challengeId: this.saveChallenge(options.challenge, "authenticate", rp.rpID), options };
  }

  async authenticate(challengeId: string, response: AuthenticationResponseJSON, rp: RelyingParty): Promise<AuthResult> {
    const expectedChallenge = this.takeChallenge(challengeId, "authenticate", rp.rpID);
    if (!expectedChallenge) return { ok: false, reason: "That passkey prompt expired. Start again." };
    const key = this.sql.exec<{ id: string; public_key: string; counter: number; transports: string }>(
      "SELECT id, public_key, counter, transports FROM passkeys WHERE id = ? AND rp_id = ?", String(response?.id), rp.rpID).toArray()[0];
    if (!key) return { ok: false, reason: "That passkey isn't the one set up for Tasks." };
    let verified;
    try {
      verified = await verifyAuthenticationResponse({
        response, expectedChallenge, expectedOrigin: rp.origin, expectedRPID: rp.rpID, requireUserVerification: true,
        credential: { id: key.id, publicKey: unb64url(key.public_key), counter: key.counter, transports: JSON.parse(key.transports) },
      });
    } catch (e) {
      return { ok: false, reason: `The passkey couldn't be verified: ${e instanceof Error ? e.message : String(e)}` };
    }
    if (!verified.verified) return { ok: false, reason: "The passkey couldn't be verified." };
    this.sql.exec("UPDATE passkeys SET counter = ?, used = ? WHERE id = ?", verified.authenticationInfo.newCounter, Date.now(), key.id);
    return { ok: true };
  }
}

/**
 * The op `actor` for a client: `agent:` and a slug of its verified domain (a CIMD client, e.g. claude.ai →
 * agent:claude-ai) or else of its self-asserted name. 1–64 characters, as the CLI requires.
 */
export function actorFor(client: { clientName: string; clientDomain?: string }): string {
  const base = client.clientDomain ?? client.clientName;
  const slug = base.normalize("NFKD").replace(/[̀-ͯ]/g, "").toLowerCase()
    .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 58).replace(/-+$/, "");
  return "agent:" + (slug || "client");
}
