// S1: routing, auth, JSON error bodies, check order, response encoding (SPEC §5 HTTP).
import { describe, expect, it } from "vitest";
import { call, post, TOKEN } from "./helpers";

const PULL = JSON.stringify({ from: 0, base: null, ops: [] });
const JSON_TYPE = "application/json; charset=utf-8";

async function expectError(res: Response, status: number, error: string) {
  expect(res.status).toBe(status);
  expect(res.headers.get("Content-Type")).toBe(JSON_TYPE);
  const body = await res.json<Record<string, unknown>>();
  expect(body.error).toBe(error);
  expect(typeof body.message).toBe("string");
  expect(Object.keys(body)).toEqual(["error", "message"]);
}

describe("routing", () => {
  it.each(["/", "/v1", "/v1/sync/", "/v1/syncx", "/v2/sync", "/V1/SYNC", "/v1/health"])("404 for %s", async (path) => {
    await expectError(await call(path, { method: "POST", headers: { Authorization: `Bearer ${TOKEN}` }, body: PULL }), 404, "not_found");
  });

  it.each(["GET", "PUT", "PATCH", "DELETE", "OPTIONS"])("405 with Allow: POST for %s", async (method) => {
    const res = await call("/v1/sync", { method, headers: { Authorization: `Bearer ${TOKEN}` } });
    expect(res.headers.get("Allow")).toBe("POST");
    await expectError(res, 405, "method_not_allowed");
  });

  it("405 for HEAD, with no body", async () => {
    const res = await call("/v1/sync", { method: "HEAD" });
    expect(res.status).toBe(405);
    expect(res.headers.get("Allow")).toBe("POST");
  });

  it("ignores the query string", async () => {
    const res = await call("/v1/sync?x=1", { method: "POST", headers: { Authorization: `Bearer ${TOKEN}` }, body: PULL });
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe(JSON_TYPE);
    expect(await res.json()).toEqual({ entries: [], head: 0, more: false });
  });

  it("doesn't require a Content-Type", async () => {
    const res = await call("/v1/sync", { method: "POST", headers: { Authorization: `Bearer ${TOKEN}` }, body: PULL });
    expect(res.status).toBe(200);
  });
});

describe("auth", () => {
  it.each([
    ["no header", null],
    ["wrong token", "Bearer wrong-token"],
    ["the .dev.vars token", "Bearer dev-token"],
    ["token prefix", `Bearer ${TOKEN.slice(0, -1)}`],
    ["token plus suffix", `Bearer ${TOKEN}x`],
    ["different case", `Bearer ${TOKEN.toUpperCase()}`],
    ["no scheme", TOKEN],
    ["Basic scheme", `Basic ${TOKEN}`],
    ["empty bearer", "Bearer "],
    ["two tokens", `Bearer ${TOKEN} ${TOKEN}`],
  ])("401 for %s", async (_, header) => {
    const headers: Record<string, string> = header === null ? {} : { Authorization: header };
    await expectError(await call("/v1/sync", { method: "POST", headers, body: PULL }), 401, "bad_token");
  });

  it("accepts the scheme in any case", async () => {
    const res = await call("/v1/sync", { method: "POST", headers: { Authorization: `bearer ${TOKEN}` }, body: PULL });
    expect(res.status).toBe(200);
  });
});

describe("check order: route, auth, size, parse, validate", () => {
  it("404 before 401", async () => {
    await expectError(await call("/nope", { method: "POST", body: "{" }), 404, "not_found");
  });
  it("405 before 401", async () => {
    await expectError(await call("/v1/sync", { method: "GET" }), 405, "method_not_allowed");
  });
  it("401 before 413", async () => {
    await expectError(await post(" ".repeat((1 << 20) + 1), { token: null }), 401, "bad_token");
  });
  it("401 before 400", async () => {
    await expectError(await post("not json", { token: "nope" }), 401, "bad_token");
  });
  it("413 before 400", async () => {
    await expectError(await post("x".repeat((1 << 20) + 1)), 413, "too_large");
  });
  it("400 bad_request before 413 for too many ops", async () => {
    await expectError(await post({ from: -1, base: null, ops: new Array(501).fill(0) }), 400, "bad_request");
  });
  it("413 for too many ops before per-op validation", async () => {
    await expectError(await post({ from: 0, base: null, ops: new Array(501).fill(0) }), 413, "too_large");
  });
  // The Worker's checks come before the DO's log check, so a stale cursor never turns a client bug into a 409.
  it("400 bad_request before 409", async () => {
    await expectError(await post({ from: 5, base: null, ops: [] }), 400, "bad_request");
  });
  it("400 invalid_op before 409", async () => {
    const res = await post({ from: 5, base: "a".repeat(64), ops: [{ id: "x", at: 0, type: "task.update", target: "t", set: { order: "a 0" } }] });
    expect(res.status).toBe(400);
    expect(await res.json()).toMatchObject({ error: "invalid_op", index: 0, field: "set.order" });
  });
  it("413 too_large before 409", async () => {
    await expectError(await post({ from: 5, base: "a".repeat(64), ops: new Array(501).fill(0) }), 413, "too_large");
  });
});

describe("body size without Content-Length", () => {
  const streamed = (bytes: Uint8Array) =>
    call("/v1/sync", {
      method: "POST",
      headers: { Authorization: `Bearer ${TOKEN}` },
      body: new ReadableStream({ start(c) { c.enqueue(bytes); c.close(); } }),
    });

  it("413 for a streamed body over 1 MiB", async () => {
    const body = new TextEncoder().encode(PULL + " ".repeat((1 << 20) - PULL.length + 1));
    const res = await streamed(body);
    await expectError(res, 413, "too_large");
  });
  it("accepts a small streamed body", async () => {
    expect((await streamed(new TextEncoder().encode(PULL))).status).toBe(200);
  });
});

describe("response encoding", () => {
  it.each([
    ["gzip, deflate, br", "br"],
    ["br", "br"],
    ["BR", "br"],
    ["gzip", "gzip"],
    ["gzip;q=0.5, br;q=0", "gzip"],
    ["br; q=0, gzip; q=0", null],
    ["deflate", null],
    ["identity", null],
    ["", null],
  ])("Accept-Encoding %j gives Content-Encoding %j", async (accept, expected) => {
    const ok = await post(PULL, { headers: { "Accept-Encoding": accept } });
    expect(ok.status).toBe(200);
    expect(ok.headers.get("Content-Encoding")).toBe(expected);
    const err = await post(PULL, { token: "nope", headers: { "Accept-Encoding": accept } });
    expect(err.status).toBe(401);
    expect(err.headers.get("Content-Encoding")).toBe(expected);
  });

  it("prefers cf.clientAcceptEncoding, the header before Cloudflare rewrote it", async () => {
    const send = (cf: string, header: string) =>
      call("/v1/sync", {
        method: "POST",
        headers: { Authorization: `Bearer ${TOKEN}`, "Accept-Encoding": header },
        body: PULL,
        cf: { clientAcceptEncoding: cf },
      } as RequestInit);
    expect((await send("gzip, deflate, br", "gzip")).headers.get("Content-Encoding")).toBe("br");
    expect((await send("gzip", "br")).headers.get("Content-Encoding")).toBe("gzip");
  });

  it("no Accept-Encoding, no Content-Encoding", async () => {
    expect((await post(PULL)).headers.get("Content-Encoding")).toBeNull();
  });
});
