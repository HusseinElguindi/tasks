// GET /v1/events: the WebSocket poke (design/PUSH-SYNC.md §3). The socket only ever says {"head":N};
// the changes still come through /v1/sync.
import { evictDurableObject, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { call, logStub, ok, seed, taskCreate, taskUpdate, TOKEN } from "./helpers";

const JSON_TYPE = "application/json; charset=utf-8";

/** A connected client socket and the messages it has had, parsed. */
type Client = { ws: WebSocket; heads: number[]; next: () => Promise<number[]> };
const open: WebSocket[] = [];

afterEach(() => {
  for (const ws of open.splice(0)) {
    try {
      ws.close(1000, "done");
    } catch {
      // already closed
    }
  }
});

function upgrade(headers: Record<string, string> = {}): Promise<Response> {
  return call("/v1/events", { headers: { Upgrade: "websocket", Authorization: `Bearer ${TOKEN}`, ...headers } });
}

async function connect(): Promise<Client> {
  const res = await upgrade();
  expect(res.status).toBe(101);
  const ws = res.webSocket!;
  expect(ws).toBeTruthy();
  const heads: number[] = [];
  const waiters: (() => void)[] = [];
  ws.addEventListener("message", (e) => {
    heads.push(JSON.parse(e.data as string).head);
    for (const w of waiters.splice(0)) w();
  });
  ws.accept();
  open.push(ws);
  // How many messages next() has handed out. Date is faked in tests, so the deadline counts rounds.
  let seen = 0;
  /** Waits for the message after the last one next() returned, then returns every message so far. */
  const next = async () => {
    const n = ++seen;
    for (let round = 0; heads.length < n; round++) {
      if (round > 40) throw new Error(`timed out waiting for message ${n}; have ${JSON.stringify(heads)}`);
      await Promise.race([new Promise<void>((r) => waiters.push(r)), new Promise((r) => setTimeout(r, 50))]);
    }
    return [...heads];
  };
  return { ws, heads, next };
}

/** Gives the DO a moment to send anything it would, then the caller checks nothing more came. */
const settle = () => new Promise((r) => setTimeout(r, 100));

async function expectError(res: Response, status: number, error: string) {
  expect(res.status).toBe(status);
  expect(res.webSocket).toBeNull();
  expect(res.headers.get("Content-Type")).toBe(JSON_TYPE);
  const body = await res.json<Record<string, unknown>>();
  expect(body.error).toBe(error);
  expect(typeof body.message).toBe("string");
}

describe("upgrade", () => {
  it("426 without Upgrade: websocket", async () => {
    const res = await call("/v1/events", { headers: { Authorization: `Bearer ${TOKEN}` } });
    await expectError(res, 426, "upgrade_required");
  });

  it("426 for another upgrade", async () => {
    await expectError(await upgrade({ Upgrade: "h2c" }), 426, "upgrade_required");
  });

  it.each([
    ["no header", null],
    ["wrong token", "Bearer wrong-token"],
    ["token prefix", `Bearer ${TOKEN.slice(0, -1)}`],
    ["Basic scheme", `Basic ${TOKEN}`],
  ])("401 for %s", async (_, header) => {
    const headers: Record<string, string> = { Upgrade: "websocket" };
    if (header !== null) headers.Authorization = header;
    await expectError(await call("/v1/events", { headers }), 401, "bad_token");
  });

  // Without Upgrade: the test harness turns a request with Upgrade: websocket into a GET whatever its method.
  it.each(["POST", "PUT", "DELETE"])("405 with Allow: GET for %s", async (method) => {
    const res = await call("/v1/events", { method, headers: { Authorization: `Bearer ${TOKEN}` } });
    expect(res.headers.get("Allow")).toBe("GET");
    await expectError(res, 405, "method_not_allowed");
  });

  it("checks the route, then the method, then Upgrade, then the token", async () => {
    await expectError(await call("/v1/event", { headers: { Upgrade: "websocket" } }), 404, "not_found");
    await expectError(await call("/v1/events", { method: "POST" }), 405, "method_not_allowed");
    await expectError(await call("/v1/events", { headers: { Authorization: "Bearer nope" } }), 426, "upgrade_required");
  });

  it("accepts the scheme in any case and the Upgrade value in any case", async () => {
    const res = await upgrade({ Upgrade: "WebSocket", Authorization: `bearer ${TOKEN}` });
    expect(res.status).toBe(101);
    open.push(res.webSocket!);
    res.webSocket!.accept();
  });

  it("leaves /v1/sync as it was: GET there is still 405 with Allow: POST", async () => {
    const res = await call("/v1/sync", { headers: { Upgrade: "websocket", Authorization: `Bearer ${TOKEN}` } });
    expect(res.status).toBe(405);
    expect(res.headers.get("Allow")).toBe("POST");
  });
});

describe("pokes", () => {
  it("sends the current head on connect", async () => {
    const empty = await connect();
    expect(await empty.next()).toEqual([0]);
    await seed([taskCreate(), taskCreate(), taskCreate()]);
    const later = await connect();
    expect(await later.next()).toEqual([3]);
  });

  it("pokes every socket with the new head after another client's push", async () => {
    const a = await connect();
    const b = await connect();
    await a.next();
    await b.next();
    const page = await ok(0, null, [taskCreate(), taskCreate()]);
    expect(page.head).toBe(2);
    expect(await a.next()).toEqual([0, 2]);
    expect(await b.next()).toEqual([0, 2]);
    await ok(2, page.entries[1].hash, [taskUpdate()]);
    expect(await a.next()).toEqual([0, 2, 3]);
    expect(await b.next()).toEqual([0, 2, 3]);
  });

  it("pokes nothing for a pull or a push of only duplicates", async () => {
    const op = taskCreate();
    const page = await ok(0, null, [op]);
    const a = await connect();
    expect(await a.next()).toEqual([1]);
    await ok(0, null);
    await ok(1, page.entries[0].hash);
    await ok(0, null, [op]); // already in the log
    await settle();
    expect(a.heads).toEqual([1]);
  });

  it("a rejected sync (409) pokes nothing", async () => {
    const a = await connect();
    await a.next();
    const res = await call("/v1/sync", {
      method: "POST",
      headers: { Authorization: `Bearer ${TOKEN}` },
      body: JSON.stringify({ from: 5, base: "a".repeat(64), ops: [taskCreate()] }),
    });
    expect(res.status).toBe(409);
    await settle();
    expect(a.heads).toEqual([0]);
  });

  it("a socket that closed doesn't break sync()", async () => {
    const gone = await connect();
    const a = await connect();
    await gone.next();
    await a.next();
    gone.ws.close(1000, "bye");
    await settle();
    const page = await ok(0, null, [taskCreate()]);
    expect(page.head).toBe(1);
    expect(await a.next()).toEqual([0, 1]);
  });

  it("ignores what a client sends", async () => {
    const a = await connect();
    await a.next();
    a.ws.send("hello");
    a.ws.send(new Uint8Array([1, 2, 3]));
    await settle();
    await ok(0, null, [taskCreate()]);
    expect(await a.next()).toEqual([0, 1]);
  });
});

describe("hibernation", () => {
  it("accepts with the hibernatable API, so the socket is the DO's to find again", async () => {
    const a = await connect();
    await a.next();
    const count = await runInDurableObject(logStub(), (_, state) => state.getWebSockets().length);
    expect(count).toBe(1);
  });

  it("a socket survives the object's eviction, and the woken object pokes it", async () => {
    const a = await connect();
    await a.next();
    const stub = logStub();
    // Graceful eviction hibernates the socket and drops the instance (head, last and everything else in memory).
    await evictDurableObject(stub);
    // The next request wakes a new instance; the constructor re-reads head, and getWebSockets() still has the socket.
    const page = await ok(0, null, [taskCreate(), taskCreate()]);
    expect(page.head).toBe(2);
    expect(await a.next()).toEqual([0, 2]);
    // Once more, from a cold start with a log already there.
    await evictDurableObject(stub);
    await ok(2, page.entries[1].hash, [taskUpdate()]);
    expect(await a.next()).toEqual([0, 2, 3]);
  });

  it("a message sent to a hibernated socket wakes the object and is ignored", async () => {
    const a = await connect();
    await a.next();
    await evictDurableObject(logStub());
    a.ws.send("ping");
    await settle();
    await ok(0, null, [taskCreate()]);
    expect(await a.next()).toEqual([0, 1]);
  });
});
