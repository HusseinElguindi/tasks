// A virtual passkey for the tests: a P-256 key in WebCrypto that answers navigator.credentials.create() and .get()
// as a platform authenticator would ("none" attestation, user present and verified), byte for byte, so the server
// verifies it with @simplewebauthn/server unchanged.

const enc = new TextEncoder();
export const b64url = (b: Uint8Array) => btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const unb64url = (s: string) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
const sha256 = async (b: Uint8Array) => new Uint8Array(await crypto.subtle.digest("SHA-256", b));
const concat = (...parts: Uint8Array[]) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let i = 0;
  for (const p of parts) {
    out.set(p, i);
    i += p.length;
  }
  return out;
};
const u32 = (n: number) => new Uint8Array([(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255]);

// MARK: CBOR (the subset WebAuthn needs)

type Cbor = number | string | Uint8Array | Map<Cbor, Cbor> | { [k: string]: Cbor };

function head(major: number, n: number): Uint8Array {
  if (n < 24) return new Uint8Array([(major << 5) | n]);
  if (n < 256) return new Uint8Array([(major << 5) | 24, n]);
  if (n < 65536) return new Uint8Array([(major << 5) | 25, n >> 8, n & 255]);
  return concat(new Uint8Array([(major << 5) | 26]), u32(n));
}

export function cbor(v: Cbor): Uint8Array {
  if (typeof v === "number") return v >= 0 ? head(0, v) : head(1, -1 - v);
  if (typeof v === "string") {
    const b = enc.encode(v);
    return concat(head(3, b.length), b);
  }
  if (v instanceof Uint8Array) return concat(head(2, v.length), v);
  const entries = v instanceof Map ? [...v.entries()] : Object.entries(v);
  return concat(head(5, entries.length), ...entries.flatMap(([k, x]) => [cbor(k), cbor(x)]));
}

/** WebCrypto's raw r‖s → the DER SEQUENCE WebAuthn carries. */
function der(raw: Uint8Array): Uint8Array {
  const int = (b: Uint8Array) => {
    let i = 0;
    while (i < b.length - 1 && b[i] === 0) i++;
    let x = b.slice(i);
    if (x[0] & 0x80) x = concat(new Uint8Array([0]), x);
    return concat(new Uint8Array([2, x.length]), x);
  };
  const body = concat(int(raw.slice(0, 32)), int(raw.slice(32)));
  return concat(new Uint8Array([0x30, body.length]), body);
}

export interface CreationOptions {
  challenge: string;
  rp: { id?: string; name: string };
  user: { id: string };
}

export interface RequestOptions {
  challenge: string;
  rpId?: string;
  allowCredentials?: { id: string }[];
}

export class SoftAuthenticator {
  readonly credentialId = crypto.getRandomValues(new Uint8Array(16));
  private keys: CryptoKeyPair | null = null;
  private counter = 0;
  private userHandle: string | null = null;

  get id(): string {
    return b64url(this.credentialId);
  }

  private clientData(type: string, challenge: string, origin: string) {
    return enc.encode(JSON.stringify({ type, challenge, origin, crossOrigin: false }));
  }

  /** navigator.credentials.create({ publicKey }) on `origin`. */
  async create(o: CreationOptions, origin: string) {
    const rpID = o.rp.id ?? new URL(origin).hostname;
    this.keys = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
    const jwk = (await crypto.subtle.exportKey("jwk", this.keys.publicKey)) as JsonWebKey;
    const cose = cbor(new Map<Cbor, Cbor>([[1, 2], [3, -7], [-1, 1], [-2, unb64url(jwk.x!)], [-3, unb64url(jwk.y!)]]));
    const authData = concat(
      await sha256(enc.encode(rpID)),
      new Uint8Array([0x45]), // user present, user verified, attested credential data
      u32(this.counter),
      new Uint8Array(16), // AAGUID
      new Uint8Array([this.credentialId.length >> 8, this.credentialId.length & 255]),
      this.credentialId,
      cose,
    );
    this.userHandle = o.user.id;
    return {
      id: this.id,
      rawId: this.id,
      type: "public-key" as const,
      response: {
        clientDataJSON: b64url(this.clientData("webauthn.create", o.challenge, origin)),
        attestationObject: b64url(cbor({ fmt: "none", attStmt: {}, authData })),
        transports: ["internal"],
      },
      clientExtensionResults: {},
      authenticatorAttachment: "platform" as const,
    };
  }

  /** navigator.credentials.get({ publicKey }) on `origin`; `tamper` signs something else. */
  async get(o: RequestOptions, origin: string, tamper = false) {
    if (!this.keys) throw new Error("no credential yet");
    const rpID = o.rpId ?? new URL(origin).hostname;
    this.counter += 1;
    const authData = concat(await sha256(enc.encode(rpID)), new Uint8Array([0x05]), u32(this.counter));
    const clientDataJSON = this.clientData("webauthn.get", o.challenge, origin);
    const signed = concat(authData, await sha256(clientDataJSON), tamper ? new Uint8Array([1]) : new Uint8Array());
    const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, this.keys.privateKey, signed));
    return {
      id: this.id,
      rawId: this.id,
      type: "public-key" as const,
      response: {
        clientDataJSON: b64url(clientDataJSON),
        authenticatorData: b64url(authData),
        signature: b64url(der(raw)),
        ...(this.userHandle ? { userHandle: this.userHandle } : {}),
      },
      clientExtensionResults: {},
      authenticatorAttachment: "platform" as const,
    };
  }
}
