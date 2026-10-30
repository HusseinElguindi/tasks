// The shared contract: replay every fixtures/sync pair and require a byte-exact response.
import { runInDurableObject } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import log2345 from "../../fixtures/sync/log-2345.jsonl?raw";
import vectors from "../../fixtures/sync/hash-vectors.json";
import { call, logStub, NOW, seed, sha256, type Op } from "./helpers";

interface Fixture {
  name: string;
  setup: { log?: Op[]; logFile?: string };
  request: { method: string; path: string; headers: Record<string, string>; body?: unknown };
  response: { status: number; headers: Record<string, string>; body: unknown };
}

const files = import.meta.glob<Fixture>("../../fixtures/sync/[0-9]*.json", { eager: true, import: "default" });
const fixtures = Object.values(files);
const logFiles: Record<string, string> = { "log-2345.jsonl": log2345 };
const lines = (text: string) => text.trimEnd().split("\n");

describe("fixtures/sync", () => {
  it("has every SPEC §5 worked example", () => {
    const names = fixtures.map((f) => f.name);
    for (const n of ["01-push", "02a-pull-page-1", "03-invalid-op", "04-bad-token", "05-log-mismatch"]) expect(names).toContain(n);
  });

  it.each(fixtures.map((f) => [f.name, f] as const))("%s", async (_, f) => {
    const setup = f.setup.log ?? lines(logFiles[f.setup.logFile!]).map((l) => JSON.parse(l).op);
    await seed(setup);

    const { method, path, headers, body } = f.request;
    const res = await call(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });

    expect(res.status).toBe(f.response.status);
    for (const [name, value] of Object.entries(f.response.headers)) expect(res.headers.get(name), name).toBe(value);
    if (!("Content-Encoding" in f.response.headers)) expect(res.headers.get("Content-Encoding")).toBeNull();
    expect(await res.text()).toBe(JSON.stringify(f.response.body));
  });

  it("log-2345.jsonl is exactly the log the server builds from its ops", async () => {
    const expected = lines(log2345);
    await seed(expected.map((l) => JSON.parse(l).op));
    const stored = await runInDurableObject(logStub(), (_, state) =>
      state.storage.sql.exec<{ seq: number; received: number; hash: string; op: string }>("SELECT seq, received, hash, op FROM log ORDER BY seq").toArray(),
    );
    expect(stored.map((r) => `{"seq":${r.seq},"received":${r.received},"hash":"${r.hash}","op":${r.op}}`)).toEqual(expected);
    expect(stored.every((r) => r.received === NOW)).toBe(true);
  });

  it("hash-vectors.json: the server stores exactly opText and hashes it as specified", async () => {
    await seed(vectors.vectors.map((v) => JSON.parse(v.opText)));
    const stored = await runInDurableObject(logStub(), (_, state) =>
      state.storage.sql.exec<{ op: string; hash: string }>("SELECT op, hash FROM log ORDER BY seq").toArray(),
    );
    expect(stored).toEqual(vectors.vectors.map((v) => ({ op: v.opText, hash: v.hash })));
    for (const v of vectors.vectors) expect(sha256(v.prev + "\n" + v.opText)).toBe(v.hash);
  });
});
