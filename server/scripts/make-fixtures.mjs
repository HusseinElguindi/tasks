// Writes fixtures/sync/: the SPEC §5 worked examples as request/response pairs, plus a few
// extra error cases and the opA/opB hash vectors. Hashes are computed here, independently of
// the server, and the server tests check the server reproduces every response byte for byte.
//
//   pnpm fixtures

import { createHash } from "node:crypto";
import { mkdirSync, readdirSync, rmSync, writeFileSync } from "node:fs";

const OUT = new URL("../../fixtures/sync/", import.meta.url);
const TOKEN = "test-token";
const RECEIVED = 1761811261234; // the server clock in every fixture
const PAGE = 1000;

const INBOX = "00000000-0000-0000-0000-000000000001";
const TASK = "9f8e7d6c-5b4a-4321-8fed-cba987654321";

const opA = { id: "00000000-0000-0000-0000-000000000002", at: 1761811200000, type: "list.create", target: INBOX, set: { name: "Inbox", order: "a0" } };
const opB = { id: "5b0c6c1e-3f0a-4c8e-9d61-0f4f6f1a2b3c", at: 1761811260000, type: "task.create", target: TASK, set: { list: INBOX, order: "a0", title: "Buy milk", when: "2026-10-30" } };
// Example 3 elides these ids ("7d1e…", "8e2f…"); any UUIDs do.
const op3a = { id: "7d1e0a2b-4c3d-4e5f-8a6b-7c8d9e0f1a2b", at: 1761811300000, type: "task.update", target: TASK, set: { title: "Buy oat milk" } };
const op3b = { id: "8e2f1b3c-5d4e-4f60-9b7c-8d9e0f1a2b3c", at: 1761811301000, type: "task.update", target: TASK, set: { list: INBOX, order: "a 0" } };
// Example 5: the restored log grew a different entry 1.
const opX = { id: "6c1d7d2f-4a1b-4d9f-8e72-1a5a7a2b3c4d", at: 1761811270000, type: "task.create", target: TASK, set: { list: INBOX, order: "a0", title: "Buy bread" } };

const SPEC_HASH_0 = "bc2a6e3a4de77a2ce16c4a38c6f4d76237a98434f7d213049e3fd77dde66dacd";
const SPEC_HASH_1 = "184ceb4c3d11bd53025385963c25f50298c2d652f84d5989941d2ec13a66fd79";

// Example 11: an agent's op, with the optional attribution keys.
const opC = { id: "3a7f2c1e-8b4d-4e6a-9c5f-1d2e3f4a5b6c", at: 1761811320000, type: "task.update", target: TASK, set: { when: "2026-11-06" }, actor: "agent:claude-code", batch: "2c1f9e0a-7b3d-4c5e-8f6a-9b0c1d2e3f4a" };

// Example 12 (SPEC §2, §5): a heading is a task.create with kind "heading", and a list carries Markdown notes.
const HEADING = "4c2b8e1d-6f3a-4b7c-9d0e-2a1b3c4d5e6f";
const opD = { id: "b1e4c7a2-9d3f-4e8b-8c1a-5f6e7d8c9b0a", at: 1761811330000, type: "list.update", target: INBOX, set: { notes: "Things to sort.\n- [ ] **Monday**: groceries" } };
const opE = { id: "c2f5d8b3-0e4a-4f9c-9d2b-6a7b8c9d0e1f", at: 1761811331000, type: "task.create", target: HEADING, set: { list: INBOX, order: "Zz", title: "Errands", kind: "heading" } };
// Example 13: kind is set once, at create; an update can't carry it.
const opF = { id: "d3a6e9c4-1f5b-4a0d-8e3c-7b8c9d0e1f2a", at: 1761811340000, type: "task.update", target: TASK, set: { kind: "heading" } };

const opText = (op) => JSON.stringify({ id: op.id, at: op.at, type: op.type, target: op.target, set: op.set, actor: op.actor, batch: op.batch });
const sha256 = (s) => createHash("sha256").update(s).digest("hex");

/** The log the server would hold after appending `ops` in order, as entries. */
function log(ops) {
  let prev = "";
  return ops.map((op, seq) => {
    const hash = sha256(prev + "\n" + opText(op));
    prev = hash;
    return { seq, received: RECEIVED, hash, op };
  });
}

function page(entries, from, head = entries.length) {
  const end = Math.min(from + PAGE, head);
  return { entries: entries.slice(from, end), head, more: end < head };
}

const JSON_HEADERS = { "Content-Type": "application/json; charset=utf-8" };

function request(body, { token = TOKEN, method = "POST", path = "/v1/sync", acceptEncoding } = {}) {
  const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
  if (acceptEncoding) headers["Accept-Encoding"] = acceptEncoding;
  return { method, path, headers, ...(body === undefined ? {} : { body }) };
}

const response = (status, body, headers = {}) => ({ status, headers: { ...JSON_HEADERS, ...headers }, body });
const error = (status, error, message, extra = {}) => response(status, { error, message, ...extra });

// Filler for example 2: title edits to opB's task, seq 2…2344, with deterministic UUIDs.
const filler = Array.from({ length: 2343 }, (_, i) => {
  const n = i + 2;
  return { id: `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`, at: 1761811260000 + n * 1000, type: "task.update", target: TASK, set: { title: `Buy milk (edit ${n})` } };
});

const logAB = log([opA, opB]);
const logAXB = log([opA, opX, opB]);
const log2345 = log([opA, opB, ...filler]);
const after3 = log([opA, opB, op3a]);
const afterC = log([opA, opB, opC]);
const afterDE = log([opA, opB, opD, opE]);

if (logAB[0].hash !== SPEC_HASH_0 || logAB[1].hash !== SPEC_HASH_1) throw new Error("hash vectors disagree with SPEC §5");
// Example 5's recovery response, entries 1 and 2.
if (logAXB[1].hash !== "d26a435858c180d340e58ccc240e66e280a27dbb8a68c6581cea8c5e7341448b" || logAXB[2].hash !== "2a34469203cb49eae9ac47f94f152dd5096801d50cd45dccb5682ea889992350") {
  throw new Error("example 5 recovery hashes disagree with SPEC §5");
}

const hash1 = logAB[1].hash;
const fixtures = {
  "01-push": {
    spec: "§5 worked example 1",
    description: "A fresh Mac pushes opA and opB to an empty log. The response includes its own ops.",
    setup: { log: [] },
    request: request({ from: 0, base: null, ops: [opA, opB] }, { acceptEncoding: "gzip, deflate, br" }),
    response: response(200, page(logAB, 0), { "Content-Encoding": "br" }),
  },
  "01b-push-retry": {
    spec: "§5 worked example 1",
    description: "The same request sent again returns the same body: both op ids are deduplicated.",
    setup: { log: [opA, opB] },
    request: request({ from: 0, base: null, ops: [opA, opB] }, { acceptEncoding: "gzip, deflate, br" }),
    response: response(200, page(logAB, 0), { "Content-Encoding": "br" }),
  },
  "02a-pull-page-1": {
    spec: "§5 worked example 2",
    description: "A second Mac pulls from 0 when the log has 2,345 entries: seq 0–999, more is true.",
    setup: { logFile: "log-2345.jsonl" },
    request: request({ from: 0, base: null, ops: [] }),
    response: response(200, page(log2345, 0)),
  },
  "02b-pull-page-2": {
    spec: "§5 worked example 2",
    description: "The next page: seq 1000–1999, more is true.",
    setup: { logFile: "log-2345.jsonl" },
    request: request({ from: 1000, base: log2345[999].hash, ops: [] }),
    response: response(200, page(log2345, 1000)),
  },
  "02c-pull-page-3": {
    spec: "§5 worked example 2",
    description: "The last page: seq 2000–2344, more is false.",
    setup: { logFile: "log-2345.jsonl" },
    request: request({ from: 2000, base: log2345[1999].hash, ops: [] }),
    response: response(200, page(log2345, 2000)),
  },
  "03-invalid-op": {
    spec: "§5 worked example 3",
    description: "ops[1].set.order contains a space. Nothing is appended, not even ops[0].",
    setup: { log: [opA, opB] },
    request: request({ from: 2, base: hash1, ops: [op3a, op3b] }),
    response: error(400, "invalid_op", "ops[1].set.order must match ^[0-9A-Za-z]{1,128}$", { index: 1, field: "set.order" }),
  },
  "03b-resend-without-rejected": {
    spec: "§5 worked example 3",
    description: "The client resends the request from example 3 with only ops[0].",
    setup: { log: [opA, opB] },
    request: request({ from: 2, base: hash1, ops: [op3a] }),
    response: response(200, page(after3, 2)),
  },
  "04-bad-token": {
    spec: "§5 worked example 4",
    description: "Wrong bearer token.",
    setup: { log: [opA, opB] },
    request: request({ from: 2, base: hash1, ops: [] }, { token: "wrong-token" }),
    response: error(401, "bad_token", "Missing or invalid bearer token."),
  },
  "05-log-mismatch": {
    spec: "§5 worked example 5",
    description: "The server log was restored and grew a different entry 1, so base does not match.",
    setup: { log: [opA, opX] },
    request: request({ from: 2, base: hash1, ops: [] }),
    response: error(409, "log_mismatch", "base does not match the log at seq 1."),
  },
  "05b-resync-from-zero": {
    spec: "§5 worked example 5",
    description: "After the 409 the client re-pushes every op it knows (confirmed opA, opB; pending empty). opA is deduplicated and opB is appended at seq 2.",
    setup: { log: [opA, opX] },
    request: request({ from: 0, base: null, ops: [opA, opB] }),
    response: response(200, page(logAXB, 0)),
  },
  "06-from-past-head": {
    spec: "§5 errors table, 409",
    description: "from is past the head of the log.",
    setup: { log: [opA, opB] },
    request: request({ from: 5, base: hash1, ops: [] }),
    response: error(409, "log_mismatch", "from 5 is past head 2."),
  },
  "07-bad-request": {
    spec: "§5 errors table, 400 bad_request",
    description: "base is null with from > 0.",
    setup: { log: [opA, opB] },
    request: request({ from: 2, base: null, ops: [] }),
    response: error(400, "bad_request", "base must not be null when from > 0."),
  },
  "08-too-many-ops": {
    spec: "§5 errors table, 413 too_large",
    description: "501 ops in one request.",
    setup: { log: [opA, opB] },
    request: request({
      from: 2,
      base: hash1,
      ops: Array.from({ length: 501 }, (_, i) => ({ id: `00000000-0000-4000-9000-${i.toString(16).padStart(12, "0")}`, at: 1761811400000, type: "task.update", target: TASK, set: { title: `t${i}` } })),
    }),
    response: error(413, "too_large", "At most 500 ops per request; got 501."),
  },
  "09-not-found": {
    spec: "§5 HTTP table",
    description: "Any path other than /v1/sync.",
    setup: { log: [] },
    request: request({ from: 0, base: null, ops: [] }, { path: "/v1/push" }),
    response: error(404, "not_found", "No such path: /v1/push."),
  },
  "10-method-not-allowed": {
    spec: "§5 HTTP table",
    description: "Any method other than POST on /v1/sync, with an Allow header.",
    setup: { log: [] },
    request: request(undefined, { method: "GET" }),
    response: response(405, { error: "method_not_allowed", message: "Use POST for /v1/sync." }, { Allow: "POST" }),
  },
  "11-push-with-actor": {
    spec: "§5 op schema, actor and batch",
    description: "An agent pushes an op with the optional actor and batch keys. They're stored after set and hashed with the op; ops without them are stored exactly as before.",
    setup: { log: [opA, opB] },
    request: request({ from: 2, base: hash1, ops: [opC] }),
    response: response(200, page(afterC, 2)),
  },
  "12-push-heading-and-list-notes": {
    spec: "§5 op schema, kind and a list's notes",
    description: "A list.update with notes (Markdown, up to 20,000 characters) and a task.create with kind \"heading\": a heading is a task with that kind, set once at create.",
    setup: { log: [opA, opB] },
    request: request({ from: 2, base: hash1, ops: [opD, opE] }),
    response: response(200, page(afterDE, 2)),
  },
  "13-kind-on-update": {
    spec: "§5 validation table, kind",
    description: "kind is allowed only on task.create: a task.update that carries it is rejected, and nothing is appended.",
    setup: { log: [opA, opB] },
    request: request({ from: 2, base: hash1, ops: [opF] }),
    response: error(400, "invalid_op", "ops[0].set.kind is not allowed for task.update", { index: 0, field: "set.kind" }),
  },
};

// Pretty-print with every array element (ops, entries) on one line.
function format(value, indent = "") {
  if (Array.isArray(value)) {
    if (value.length === 0) return "[]";
    const inner = indent + "  ";
    return "[\n" + value.map((v) => inner + JSON.stringify(v)).join(",\n") + "\n" + indent + "]";
  }
  if (value && typeof value === "object") {
    const inner = indent + "  ";
    const keys = Object.keys(value);
    if (keys.length === 0) return "{}";
    return "{\n" + keys.map((k) => `${inner}${JSON.stringify(k)}: ${format(value[k], inner)}`).join(",\n") + "\n" + indent + "}";
  }
  return JSON.stringify(value);
}

mkdirSync(OUT, { recursive: true });
for (const f of readdirSync(OUT)) if (/\.(json|jsonl)$/.test(f)) rmSync(new URL(f, OUT));

for (const [name, fixture] of Object.entries(fixtures)) {
  writeFileSync(new URL(`${name}.json`, OUT), format({ name, ...fixture }) + "\n");
}
writeFileSync(new URL("log-2345.jsonl", OUT), log2345.map((e) => JSON.stringify(e)).join("\n") + "\n");
writeFileSync(
  new URL("hash-vectors.json", OUT),
  format({
    description: "hash(n) = SHA-256(hash(n-1) + \"\\n\" + opText(n)) as lowercase hex, with hash(-1) = \"\". opText is the op exactly as the server stores it.",
    vectors: logAB.map((e, i) => ({ seq: e.seq, prev: i ? logAB[i - 1].hash : "", opText: opText(e.op), hash: e.hash })),
  }) + "\n",
);

console.log(`wrote ${Object.keys(fixtures).length} fixtures, log-2345.jsonl and hash-vectors.json to ${OUT.pathname}`);
