#!/usr/bin/env node
// Golden behaviour of the stock `tasks` CLI's code mode, for the TypeScript port in remote/.
//
// Builds the debug CLI (app/TasksCore), starts a local `wrangler dev` of server/ with a dummy token and a fresh
// --persist-to, seeds a realistic state through the CLI, runs each scenario as one `tasks run --json` (the JSON
// the MCP tool `tasks_run` returns), pulls the server log after each one, and writes
// remote/test/golden/cli-scenarios.json. See CLI-CAPTURE.md. Node 24, built-ins only.
//
//   node capture-cli.mjs [--scratch DIR] [--out FILE] [--date-order md|dm] [--no-build] [--anytime]

import { spawn, spawnSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, "../..");
const CORE = path.join(REPO, "app/TasksCore");
const SERVER = path.join(REPO, "server");
const DTS = path.join(CORE, "Tests/TasksCLITests/tasks.d.ts");
const TOKEN = "dummy-local-token";
const ACTOR = "agent:parity"; // every case, unless it says otherwise
const SEED_ACTOR = "cli"; // the seed, and the person's later edit (from a second replica)
const INBOX = "00000000-0000-0000-0000-000000000001";

// ---------------------------------------------------------------- options

function parseArgs(argv) {
  const o = {
    scratch: process.env.PARITY_SCRATCH || path.join(os.tmpdir(), "tasks-parity-cli"),
    out: path.join(REPO, "remote/test/golden/cli-scenarios.json"),
    dateOrder: "md",
    build: true,
    anytime: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--scratch") o.scratch = argv[++i];
    else if (a === "--out") o.out = argv[++i];
    else if (a === "--date-order") o.dateOrder = argv[++i];
    else if (a === "--no-build") o.build = false;
    else if (a === "--anytime") o.anytime = true;
    else if (a === "-h" || a === "--help") {
      console.log("node capture-cli.mjs [--scratch DIR] [--out FILE] [--date-order md|dm] [--no-build] [--anytime]");
      process.exit(0);
    } else throw new Error(`Unknown argument ${a}`);
  }
  if (!["md", "dm"].includes(o.dateOrder)) throw new Error("--date-order is md or dm");
  o.scratch = path.resolve(o.scratch);
  o.out = path.resolve(o.out);
  return o;
}

const opt = parseArgs(process.argv.slice(2));
const say = (...a) => console.error("[capture]", ...a);
const warnings = [];
const warn = (m) => {
  warnings.push(m);
  console.error("[capture] WARNING:", m);
};

// ---------------------------------------------------------------- time zone and days

/** The Mac's IANA zone, the one the CLI's Calendar.autoupdatingCurrent uses (not TZ, which the CLI never gets). */
function macZone() {
  try {
    const m = /zoneinfo\/(.+)$/.exec(fs.readlinkSync("/etc/localtime"));
    if (m) return m[1];
  } catch {}
  return Intl.DateTimeFormat().resolvedOptions().timeZone;
}
const TZ = macZone();
const fmt = new Intl.DateTimeFormat("en-CA", {
  timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23",
});
function local(ms) {
  const p = Object.fromEntries(fmt.formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
  return { date: `${p.year}-${p.month}-${p.day}`, minutes: Number(p.hour) * 60 + Number(p.minute) };
}
function addDays(iso, n) {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

// ---------------------------------------------------------------- scratch

function prepareScratch() {
  const s = opt.scratch;
  const forbidden = [path.parse(s).root, os.homedir(), REPO, path.join(REPO, "remote")];
  if (!path.isAbsolute(s) || forbidden.includes(s) || REPO.startsWith(s + path.sep)) {
    throw new Error(`Refusing scratch dir ${s}`);
  }
  fs.mkdirSync(s, { recursive: true });
  // Only the folders this script makes, so a mistyped --scratch can't wipe anything else.
  for (const name of ["state", "replicas", "scripts", "home", "tmp", "cwd"]) {
    fs.rmSync(path.join(s, name), { recursive: true, force: true });
    fs.mkdirSync(path.join(s, name), { recursive: true });
  }
  const envFile = path.join(s, "no-such-tasks-sync.env");
  fs.rmSync(envFile, { force: true });
  return { envFile };
}

// ---------------------------------------------------------------- tools

function run(cmd, args, o = {}) {
  const r = spawnSync(cmd, args, { encoding: "utf8", maxBuffer: 64 << 20, ...o });
  if (r.error) throw r.error;
  return r;
}

function buildCLI() {
  if (opt.build) {
    say("building the debug CLI (swift build --product tasks)…");
    const b = run("mise", ["x", "swift", "--", "swift", "build", "--product", "tasks"], { cwd: CORE, stdio: ["ignore", "inherit", "inherit"] });
    if (b.status !== 0) throw new Error("swift build failed");
  }
  const r = run("mise", ["x", "swift", "--", "swift", "build", "--product", "tasks", "--show-bin-path"], { cwd: CORE });
  const dir = r.stdout.trim().split("\n").pop();
  const bin = path.join(dir, "tasks");
  if (!fs.existsSync(bin)) throw new Error(`No tasks binary at ${bin}`);
  return bin;
}

function findDeno() {
  const r = run("mise", ["which", "deno"]);
  const p = r.status === 0 ? r.stdout.trim() : run("which", ["deno"]).stdout.trim();
  if (!p || !fs.existsSync(p)) throw new Error("No deno (mise use -g deno)");
  return p;
}

function freePort() {
  return new Promise((resolve, reject) => {
    const s = net.createServer();
    s.unref();
    s.on("error", reject);
    s.listen(0, "127.0.0.1", () => {
      const { port } = s.address();
      s.close(() => resolve(port));
    });
  });
}

// ---------------------------------------------------------------- the local server

let server = null;

async function startServer() {
  if (!fs.existsSync(path.join(SERVER, "node_modules/.bin/wrangler"))) {
    throw new Error("server/node_modules is missing: run pnpm install in server/ first");
  }
  const port = await freePort();
  const inspector = await freePort();
  const npx = path.join(path.dirname(process.execPath), "npx");
  const env = { ...process.env, WRANGLER_SEND_METRICS: "false", PATH: `${path.dirname(process.execPath)}:${process.env.PATH}` };
  for (const k of Object.keys(env)) if (/^(CLOUDFLARE_|CF_)/.test(k)) delete env[k]; // never an account
  const logPath = path.join(opt.scratch, "wrangler.log");
  const log = fs.openSync(logPath, "w");
  const child = spawn(npx, ["wrangler", "dev", "--ip", "127.0.0.1", "--port", String(port), "--inspector-port", String(inspector),
    "--var", `API_TOKEN:${TOKEN}`, "--persist-to", path.join(opt.scratch, "state"), "--show-interactive-dev-session=false"],
  { cwd: SERVER, env, detached: true, stdio: ["ignore", log, log] });
  server = { child, port, url: `http://127.0.0.1:${port}`, logPath, exited: false };
  child.on("exit", () => { server && (server.exited = true); });
  const deadline = Date.now() + 120_000;
  while (Date.now() < deadline) {
    if (server.exited) throw new Error(`wrangler dev exited early; see ${logPath}`);
    try {
      const r = await fetch(`${server.url}/v1/sync`, {
        method: "POST", headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" },
        body: JSON.stringify({ from: 0, base: null, ops: [] }),
      });
      if (r.status === 200) { await r.text(); say(`server up on ${server.url}`); return server; }
    } catch {}
    await new Promise((r) => setTimeout(r, 300));
  }
  throw new Error(`wrangler dev didn't answer within 120 s; see ${logPath}`);
}

async function stopServer() {
  if (!server || server.exited) return;
  const { child } = server;
  const gone = new Promise((r) => child.once("exit", r));
  try { process.kill(-child.pid, "SIGTERM"); } catch {}
  const t = setTimeout(() => { try { process.kill(-child.pid, "SIGKILL"); } catch {} }, 5000);
  await Promise.race([gone, new Promise((r) => setTimeout(r, 8000))]);
  clearTimeout(t);
  try { process.kill(-child.pid, "SIGKILL"); } catch {}
  server.exited = true;
  say("server stopped");
}

for (const sig of ["SIGINT", "SIGTERM"]) {
  process.on(sig, async () => { await stopServer(); process.exit(130); });
}

// ---------------------------------------------------------------- the server log, read directly

/** Pulls `POST /v1/sync` from its cursor and keeps every entry as the server sent it, checking the hash chain. */
class Tail {
  cursor = 0;
  hash = null;
  lines = [];
  entries = [];

  async request(ops) {
    const r = await fetch(`${server.url}/v1/sync`, {
      method: "POST", headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from: this.cursor, base: this.hash, ops }),
    });
    const text = await r.text();
    if (r.status !== 200) throw new Error(`sync ${r.status}: ${text}`);
    return JSON.parse(text);
  }

  ingest(body) {
    for (const e of body.entries) {
      if (e.seq !== this.cursor) throw new Error(`log gap: expected seq ${this.cursor}, got ${e.seq}`);
      const opText = JSON.stringify(e.op);
      const h = createHash("sha256").update((this.hash ?? "") + "\n" + opText).digest("hex");
      // The hash covers the stored op text, so this also proves the re-serialized line is byte-identical.
      if (h !== e.hash) throw new Error(`hash mismatch at seq ${e.seq}`);
      this.lines.push(JSON.stringify(e));
      this.entries.push(e);
      this.cursor = e.seq + 1;
      this.hash = e.hash;
    }
    return body.more;
  }

  async pull() {
    while (this.ingest(await this.request([]))) {}
    return this.cursor;
  }

  /** App-style ops (no actor, no batch), as the Mac app sends them. */
  async push(ops) {
    await this.pull();
    let more = this.ingest(await this.request(ops));
    while (more) more = this.ingest(await this.request([]));
    for (const op of ops) if (!this.entries.some((e) => e.op.id === op.id)) throw new Error(`pushed op ${op.id} not in the log`);
  }

  ids(kind) {
    const type = kind === "task" ? "task.create" : "list.create";
    return [...new Set(this.entries.filter((e) => e.op.type === type).map((e) => e.op.target))];
  }

  batchesBetween(from, to) {
    return [...new Set(this.entries.slice(from, to).map((e) => e.op.batch).filter(Boolean))];
  }
}

// ---------------------------------------------------------------- the CLI

let BIN, DENO, ENV_FILE, tail;

function cliEnv(actor, replica, extra = {}) {
  return {
    PATH: process.env.PATH,
    HOME: path.join(opt.scratch, "home"),
    TMPDIR: path.join(opt.scratch, "tmp") + "/",
    TASKS_URL: server.url,
    TASKS_TOKEN: TOKEN,
    TASKS_DATA_DIR: path.join(opt.scratch, "replicas", replica),
    TASKS_ENV_FILE: ENV_FILE,
    TASKS_ACTOR: actor,
    TASKS_DENO: DENO,
    TASKS_DATE_ORDER: opt.dateOrder,
    ...extra,
  };
}

function cli(argv, { actor = SEED_ACTOR, replica = "main", env = {}, input = "" } = {}) {
  if (fs.existsSync(ENV_FILE)) throw new Error("TASKS_ENV_FILE exists; refusing");
  const r = spawnSync(BIN, argv, {
    env: cliEnv(actor, replica, env), cwd: path.join(opt.scratch, "cwd"), input, encoding: "utf8",
    timeout: 180_000, maxBuffer: 64 << 20,
  });
  if (r.error) throw r.error;
  let json;
  try { json = JSON.parse(r.stdout); } catch {}
  return { code: r.status, signal: r.signal, stdout: r.stdout, stderr: r.stderr, json };
}

const seedLog = [];

/** A plain CLI command for the seed or a case's prep: --json, exit 0, synced. */
function must(argv, o = {}) {
  const r = cli([...argv, "--json"], o);
  if (r.code !== 0 || !r.json || r.json.synced !== true) {
    throw new Error(`tasks ${argv.join(" ")} failed (${r.code}): ${r.stdout}${r.stderr}`);
  }
  return r.json;
}

// ---------------------------------------------------------------- the seed

const S = { today: null, L: { Inbox: INBOX }, T: {}, H: {}, out: {}, batch: {}, prepBatch: {} };

async function seed() {
  const T = S.today;
  const add = (key, argv) => { const j = s(["add", ...argv]); S.T[key] = j.id; return j; };
  const s = (argv) => { seedLog.push({ actor: SEED_ACTOR, argv }); return must(argv); };

  // Lists: a deleted "Garden", a deleted "Work" and a live one, a deleted "Old Projects".
  S.L.Garden = s(["list", "add", "Garden"]).id;
  s(["list", "delete", "Garden"]);
  S.L.Home = s(["list", "add", "Home"]).id;
  S.L.WorkOld = s(["list", "add", "Work"]).id;
  add("legacy", ["Legacy task", "--list", S.L.WorkOld]);
  s(["list", "delete", S.L.WorkOld]);
  S.L.Work = s(["list", "add", "Work"]).id;
  S.L.PHYS = s(["list", "add", "PHYS 122"]).id;
  S.L.Errands = s(["list", "add", "Errands"]).id;
  S.L.Someday = s(["list", "add", "Someday"]).id;
  S.L.Old = s(["list", "add", "Old Projects"]).id;
  s(["list", "notes", "Home", "Chores, **weekly**:\n- [ ] laundry\n- [x] dishes"]);
  s(["list", "notes", "PHYS 122", "Lectures **MWF** 10:30 in *Room 2*.\n\n[Syllabus](https://example.com/phys122)"]);

  // Inbox
  add("dentist", ["Call dentist", "--today"]);
  add("oatMilk", ["Buy oat milk", "--deadline", "today"]);
  add("article", ["Read article", "--notes", "# Why read it\n\nSee [the post](https://example.com/post).\n\n- point one\n- point two"]);
  add("bike", ["Fix bike", "--when", addDays(T, -2)]);
  add("trip", ["Plan trip", "--when", addDays(T, 7)]);
  add("sam", ["Email Sam", "--deadline", addDays(T, -1)]);
  add("cafe", ["Café ☕ \"quotes\" & <tags>", "--notes", "tab\there, a backslash \\ and an emoji 🎉"]);
  // Home
  add("rent", ["Pay rent", "--list", "Home", "--deadline", addDays(T, 5), "--key", "rent-2026-11"]);
  add("laundry", ["Laundry", "--list", "Home", "--today"]);
  add("fridge", ["Clean fridge", "--list", "Home"]);
  add("plants", ["Water plants", "--list", "Home", "--when", addDays(T, -1)]);
  add("shelf", ["Fix shelf", "--list", "Home"]);
  add("vacuum", ["Vacuum", "--list", "Home"]);
  // Work (the active one, by name)
  add("report", ["Write report", "--list", "Work", "--today", "--deadline", addDays(T, 2)]);
  add("pr", ["Review PR", "--list", "Work", "--when", "yesterday"]);
  add("slides", ["Prepare slides", "--list", "Work", "--deadline", "tomorrow"]);
  add("standup", ["Standup notes", "--list", "Work"]);
  add("ticket", ["Old ticket", "--list", "Work"]);
  add("expense", ["Expense report", "--list", "Work", "--when", addDays(T, 3)]);
  // PHYS 122: a task above the first heading, then three sections (the last one empty but for a done task)
  add("notebook", ["Buy lab notebook", "--list", "PHYS 122"]);
  S.H.Labs = s(["heading", "add", "Labs", "--list", "PHYS 122"]).id;
  add("lab1", ["Lab 1 writeup", "--list", "PHYS 122", "--deadline", addDays(T, 3)]);
  add("lab2", ["Lab 2 prep", "--list", "PHYS 122"]);
  S.H.Assignments = s(["heading", "add", "Assignments", "--list", "PHYS 122", "--notes", "Due **Fridays** at 5"]).id;
  add("ps5", ["Problem set 5", "--list", "PHYS 122", "--today", "--deadline", "tomorrow"]);
  add("ps6", ["Problem set 6", "--list", "PHYS 122"]);
  S.H.Readings = s(["heading", "add", "Readings", "--list", "PHYS 122"]).id;
  add("ch7", ["Chapter 7", "--list", "PHYS 122"]);
  // Errands: two ids that share the prefix "abcd"
  add("stamps", ["Buy stamps", "--list", "Errands", "--id", "abcd1111-0000-4000-8000-000000000001"]);
  add("letter", ["Mail letter", "--list", "Errands", "--id", "abcd2222-0000-4000-8000-000000000002"]);
  add("parcel", ["Pick up parcel", "--list", "Errands", "--when", "tomorrow"]);
  add("library", ["Return library books", "--list", "Errands", "--deadline", addDays(T, 14)]);
  // Someday
  add("piano", ["Learn piano", "--list", "Someday"]);
  add("novel", ["Write a novel", "--list", "Someday", "--notes", "Maybe *someday*."]);
  // Old Projects, deleted with an open task due today and a done one; two tasks deleted on their own before it
  add("archived", ["Archived task", "--list", "Old Projects", "--today"]);
  add("archivedDone", ["Archived done", "--list", "Old Projects"]);
  add("oldDraft", ["Old draft", "--list", "Old Projects"]);
  add("oldIdea", ["Old idea", "--list", "Old Projects", "--when", addDays(T, 2)]);

  s(["done", S.T.fridge, S.T.standup, S.T.ch7, S.T.archivedDone]);
  s(["delete", S.T.vacuum, S.T.ticket, S.T.oldDraft, S.T.oldIdea]);
  s(["list", "delete", "Old Projects"]);

  // Completed earlier, by the Mac app (no actor, no batch): the CLI can only complete "now".
  const now = Date.now();
  const yesterday = now - 26 * 3_600_000;
  const lastWeek = now - 8 * 86_400_000;
  const appOps = [
    { id: randomUUID(), at: yesterday, type: "task.update", target: S.T.plants, set: { completedAt: yesterday } },
    { id: randomUUID(), at: lastWeek, type: "task.update", target: S.T.shelf, set: { completedAt: lastWeek } },
  ];
  await tail.push(appOps);
  seedLog.push({ actor: null, app: "direct POST /v1/sync, no actor or batch", ops: appOps.map((o) => o.id) });
  await tail.pull();
}

// ---------------------------------------------------------------- refs for scripts

const q = JSON.stringify;
/** The shortest prefix of `id`, at least `min` characters, that no other id of its kind starts with. */
function prefix(id, kind, min = 4) {
  const others = tail.ids(kind).filter((x) => x !== id);
  for (let n = min; n <= id.length; n++) {
    const p = id.slice(0, n).toLowerCase();
    if (!others.some((o) => o.startsWith(p))) return id.slice(0, n);
  }
  return id;
}
const tp = (id, min) => prefix(id, "task", min);
const lp = (id, min) => prefix(id, "list", min);

// ---------------------------------------------------------------- the scenarios
//
// expect: "read" (ok, no change, nothing pushed), "write" (ok, a change, pushed; a dry run pushes nothing),
// "noop" (ok, no change), or an error type (ok false, nothing pushed). Only checked here, as a guard on the
// scenarios themselves; the golden is whatever the CLI printed.

const CASES = [];
const kase = (name, o) => CASES.push({ name, ...o });

const phraseScript = (phrases) =>
  `const phrases: string[] = ${q(phrases)};\nconst out: [string, string | null][] = [];\nfor (const p of phrases) out.push([p, await tasks.date(p)]);\nreturn out;`;

// Reads on the seeded state.
kase("today", { expect: "read", script: () => `return await tasks.today();` });
kase("lists", { expect: "read", script: () => `return await tasks.lists();` });
kase("list-default-is-first-list", { expect: "read", script: () => `return await tasks.list();` });
kase("list-undefined-arg", { expect: "read", script: () => `// undefined crosses the bridge as null, which means "no list"\nconst l = await tasks.list(undefined);\nreturn l.list.name;` });
kase("list-by-name-with-headings", { expect: "read", script: () => `return await tasks.list("PHYS 122");` });
kase("list-by-name-any-case", { expect: "read", script: () => `const l = await tasks.list("phys 122");\nreturn l.list;` });
kase("list-by-full-id", { expect: "read", script: () => `return await tasks.list(${q(S.L.Home)});` });
kase("list-by-id-prefix", { expect: "read", script: () => `return await tasks.list(${q(lp(S.L.Errands))});` });
kase("list-name-prefers-active", { expect: "read", script: () => `// a deleted list is also called Work\nreturn await tasks.list("Work");` });
kase("list-deleted", { expect: "read", script: () => `// its tasks have listDeleted: they count as deleted\nreturn await tasks.list("Old Projects");` });
kase("deletedLists", { expect: "read", script: () => `return await tasks.deletedLists();` });
kase("archive-old-name", { expect: "read", script: () => `// the old name still answers, though tasks.d.ts doesn't declare it\nconst old = await tasks.archive();\nreturn { old, same: JSON.stringify(old) === JSON.stringify(await tasks.deletedLists()) };` });
kase("task-in-deleted-list", { expect: "read", script: () => `return await tasks.task(${q(S.T.archived)});` });
kase("task-deleted-before-its-list", { expect: "read", script: () => `return await tasks.task(${q(S.T.oldDraft)});` });
kase("task-by-full-id", { expect: "read", script: () => `return await tasks.task(${q(S.T.article)});` });
kase("task-by-4-char-prefix", { expect: "read", script: () => `return await tasks.task(${q(tp(S.T.cafe))});` });
kase("task-ref-trimmed-and-lowercased", { expect: "read", script: () => `const t = await tasks.task(${q("  " + tp(S.T.report, 6).toUpperCase() + " ")});\nreturn t.title;` });
kase("task-deleted", { expect: "read", script: () => `return await tasks.task(${q(S.T.vacuum)});` });
kase("task-heading", { expect: "read", script: () => `return await tasks.task(${q(S.H.Assignments)});` });
kase("task-shared-prefix-made-unique", { expect: "read", script: () => `return (await tasks.task("abcd1")).title;` });
kase("find-text", { expect: "read", script: () => `return await tasks.find({ text: "lab" });` });
kase("find-case-and-diacritics", { expect: "read", script: () => `return await tasks.find({ text: "CAFE" });` });
kase("find-in-notes", { expect: "read", script: () => `return await tasks.find({ text: "point two" });` });
kase("find-everything", { expect: "read", script: () => `const all = await tasks.find();\nconst blank = await tasks.find({ text: "   " });\nreturn { all, blankIsAll: blank.length === all.length };` });
kase("find-in-list", { expect: "read", script: () => `return await tasks.find({ list: "Home" });` });
kase("find-in-deleted-list", { expect: "read", script: () => `// a task in a deleted list counts as deleted\nreturn await tasks.find({ list: "Old Projects" });` });
kase("find-deleted-in-deleted-list", { expect: "read", script: () => `return await tasks.find({ list: "Old Projects", deleted: true });` });
kase("find-done", { expect: "read", script: () => `return await tasks.find({ done: true });` });
kase("find-open-in-list", { expect: "read", script: () => `return await tasks.find({ list: "Work", done: false });` });
kase("find-with-deleted", { expect: "read", script: () => `return await tasks.find({ deleted: true });` });
kase("find-all-filters", { expect: "read", script: () => `return await tasks.find({ text: "e", list: "Inbox", done: false, deleted: true });` });
kase("find-no-match", { expect: "read", script: () => `return await tasks.find({ text: "zebra crossing" });` });
kase("date-words", { expect: "read", script: () => phraseScript(["today", "Today", "tomorrow", "yesterday", "now", "tod", "tmrw", "yest", "weekend", "this weekend", "next weekend", "next week", "next month", "t", "to", "n", "next", "this", "s", "m", "w", "th", "tu"]) });
kase("date-weekdays", { expect: "read", script: () => phraseScript(["mon", "monday", "tue", "tues", "wed", "weds", "thu", "thurs", "fri", "friday", "sat", "sun", "sunday", "next fri", "next sun", "next mon", "this fri", "on fri", "fr", "sa", "su"]) });
kase("date-counts", { expect: "read", script: () => phraseScript(["3d", "3 days", "in 3 days", "0d", "1w", "2 weeks", "in 2 weeks", "a week", "an hour", "1m", "1mo", "2 months", "1y", "a year", "ten days", "+5", "+0", "4000000d", "4000001d"]) });
kase("date-calendar", { expect: "read", script: () => phraseScript(["nov 9", "November 9th", "nov 9 2027", "nov 9 27", "9 nov", "9th november 2027", "dec 25", "jan 1", "nov 1", "oct 31", "feb 29", "feb 29 2028", "2026-11-06", "2026-2-3", "2026-02-30", "9", "9th", "the 9th", "the 31st", "31", "1st", "Nov. 9", "nov, 9"]) });
kase("date-numeric-md", { expect: "read", script: () => phraseScript(["11/9", "12/25", "25/12", "1/2/27", "1/2/2027", "2/30", "13/1", "11/1"]) });
kase("date-numeric-dm", { expect: "read", dateOrder: "dm", script: () => phraseScript(["11/9", "12/25", "25/12", "1/2/27", "1/2/2027", "2/30", "13/1", "11/1"]) });
kase("date-not-dates", { expect: "read", script: () => phraseScript(["", "   ", "none", "null", "garbage", "next year", "  fri  ", "FRI", "2026-11-6", "20261106", "2026/11/06", "nov 31", "0", "32"]) });

// Errors on reads and bad arguments.
kase("date-without-text", { expect: "Invalid", script: () => `return await tasks.date();` });
kase("date-not-a-string", { expect: "Invalid", script: () => `return await tasks.date(20261106);` });
kase("list-not-found", { expect: "NotFound", script: () => `return await tasks.list("Nonexistent list");` });
kase("task-not-found", { expect: "NotFound", script: () => `const lists = await tasks.lists();\n// line 3 is the bad ref\nreturn await tasks.task("zzzz9999");` });
kase("task-ref-too-short", { expect: "NotFound", script: () => `return await tasks.task("abc");` });
kase("task-ref-empty", { expect: "NotFound", script: () => `return await tasks.task("   ");` });
kase("task-ambiguous-prefix", { expect: "Ambiguous", script: () => `return await tasks.task("abcd");` });
kase("find-q-not-an-object", { expect: "Invalid", script: () => `return await tasks.find("lab");` });
kase("find-unknown-field", { expect: "Invalid", script: () => `return await tasks.find({ title: "lab" });` });
kase("unknown-method-with-suggestion", { expect: "NotFound", script: () => `await tasks.compelte(${q(S.T.dentist)});` });
kase("unknown-method-no-suggestion", { expect: "NotFound", script: () => `await tasks.frobnicate();` });
kase("unknown-method-near-new-name", { expect: "NotFound", script: () => `await tasks.deleteLists("Home");` });
kase("unknown-method-near-hidden-name", { expect: "NotFound", script: () => `// hidden old names are never suggested\nawait tasks.unarchive("Old Projects");` });
kase("too-many-args", { expect: "Invalid", script: () => `return await tasks.rename(${q(S.T.dentist)}, "New", "extra");` });
kase("ref-not-a-string", { expect: "Invalid", script: () => `return await tasks.task(42);` });
kase("refs-array-with-a-number", { expect: "Invalid", script: () => `return await tasks.complete([${q(S.T.dentist)}, 7]);` });
kase("place-malformed", { expect: "Invalid", script: () => `return await tasks.move(${q(S.T.dentist)}, { place: "middle" });` });

// The script itself: logs, return values, TypeScript, throws.
kase("console-log", { expect: "read", script: () => `console.log("plain");\nconsole.info("info", 1, true, null);\nconsole.warn({ b: 2, a: 1 });\nconsole.error([1, "two"]);\nconsole.debug(undefined);\nconsole.log("multi\\nline", "tab\\there");\nreturn "logged";` });
kase("return-values", { expect: "read", script: () => `return {\n  n: 42, f: 1.5, neg: -3, small: 1e-7, big: 2 ** 53, bigger: 1e21, s: "Ünïcødé ✓ \\"q\\" \\\\ \\n\\t\\u0001",\n  nul: null, undef: undefined, arr: [3, 1, 2], nested: { z: 1, a: { y: 2, b: 3 }, B: 0 }, date: new Date(0), bool: false,\n};` });
kase("return-array", { expect: "read", script: () => `return [await tasks.date("today"), 1, "x", null];` });
kase("return-primitive", { expect: "read", script: () => `return 7;` });
kase("return-nothing", { expect: "read", script: () => `await tasks.lists();` });
kase("typescript-syntax", { expect: "read", script: () => `interface Row { id: string; title: string }\ntype Pair<T> = [T, T];\nconst rows: Row[] = (await tasks.find({ list: "Someday" })).map((t): Row => ({ id: t.id, title: t.title }));\nconst p: Pair<number> = [rows.length, rows.length * 2];\nconst first = rows[0]!;\nreturn { count: p[0] as number, first: first.title } satisfies { count: number; first: string };` });
kase("syntax-error", { expect: "SyntaxError", script: () => `const lists = await tasks.lists();\nconst x = ;\nreturn x;` });
kase("reference-error", { expect: "ReferenceError", script: () => `const n = await tasks.lists();\nreturn notDefined + n.length;` });
kase("throw-after-writes", { expect: "Error", script: () => `const t = await tasks.add({ title: "Never written", list: "Inbox" });\nawait tasks.complete(${q(S.T.dentist)});\nawait tasks.setWhen(t.id, "fri");\nthrow new Error("Changed my mind");` });
kase("throw-a-string", { expect: "Error", script: () => `await tasks.add({ title: "Never written either" });\nthrow "plain string";` });
kase("throw-custom-error", { expect: "Oops", script: () => `class Oops extends Error { name = "Oops"; }\nawait tasks.rename(${q(S.T.piano)}, "Never renamed");\nthrow new Oops("custom");` });
kase("caught-api-error-then-write", { expect: "write", script: () => `let caught: unknown = null;\ntry {\n  await tasks.task("zzzz0000");\n} catch (e: any) {\n  caught = { name: e.name, type: e.type, message: e.message, field: e.field, candidates: e.candidates };\n}\nconst t = await tasks.add({ title: "Written after a caught error", list: "Inbox" });\nreturn { caught, title: t.title };` });
kase("caught-ambiguous-candidates", { expect: "read", script: () => `try {\n  await tasks.task("abcd");\n  return "no error";\n} catch (e: any) {\n  return { type: e.type, message: e.message, field: e.field, candidates: e.candidates, isError: e instanceof Error };\n}` });
kase("logs-over-200-lines", { expect: "read", script: () => `for (let i = 1; i <= 205; i++) console.log("line " + i);\nreturn 205;` });
kase("result-over-100-kb", { expect: "Limit", script: () => `return "x".repeat(120000);` });

// Adds.
kase("add-minimal", { expect: "write", script: () => `return await tasks.add({ title: "Minimal task" });` });
kase("add-every-field", { expect: "write", script: () => `return await tasks.add({\n  title: "Pick up prescription",\n  list: "Errands",\n  notes: "At **Shoppers**\\n\\n- bring the card",\n  when: "tomorrow",\n  deadline: "fri",\n  place: "top",\n});` });
kase("add-with-key", { expect: "write", script: () => `return await tasks.add({ title: "Pay water bill", list: "Home", key: "water-2026-11", deadline: ${q(addDays(S.today, 10))} });` });
kase("add-with-key-again", { expect: "noop", script: () => `// same key, different title: the same task comes back and nothing is written\nreturn await tasks.add({ title: "Pay water bill (again)", key: "water-2026-11" });` });
kase("add-with-key-twice-in-one-script", { expect: "write", script: () => `const a = await tasks.add({ title: "Gym", list: "Home", key: "gym-2026-11-01" });\nconst b = await tasks.add({ title: "Gym", list: "Home", key: "gym-2026-11-01" });\nreturn { same: a.id === b.id, a };` });
kase("add-with-seeded-key", { expect: "noop", script: () => `// tasks add "Pay rent" --key rent-2026-11 made it\nreturn await tasks.add({ title: "Pay rent", list: "Home", key: "rent-2026-11" });` });
kase("add-with-id", { expect: "write", script: () => `return await tasks.add({ id: "parity-fixed-id-0001", title: "Task with a chosen id", list: "Someday" });` });
kase("add-with-uppercase-id", { expect: "write", script: () => `const t = await tasks.add({ id: "Parity-UPPER-1", title: "Upper-case id", list: "Someday" });\nlet byPrefix: string;\ntry { byPrefix = (await tasks.task("Parity-UP")).title; } catch (e: any) { byPrefix = e.type + ": " + e.message; }\nreturn { exact: (await tasks.task("Parity-UPPER-1")).id, byPrefix };` });
kase("add-after-task", { expect: "write", script: () => `// no list: the anchor's list\nreturn await tasks.add({ title: "Lab 1 figures", place: { after: ${q(tp(S.T.lab1, 6))} } });` });
kase("add-before-heading", { expect: "write", script: () => `return await tasks.add({ title: "Safety quiz", place: { before: ${q(S.H.Assignments)} } });` });
kase("add-after-heading", { expect: "write", script: () => `return await tasks.add({ title: "Problem set 4 corrections", list: "PHYS 122", place: { after: ${q(S.H.Assignments)} } });` });
kase("add-dates-literal-and-null", { expect: "write", script: () => `return await tasks.add({ title: "Dentist follow-up", when: ${q(addDays(S.today, 19))}, deadline: null });` });
kase("add-then-read-own-write", { expect: "write", script: () => `const t = await tasks.add({ title: "Read my own write", when: "today" });\nconst today = await tasks.today();\nconst found = await tasks.find({ text: "own write" });\nreturn {\n  inToday: today.groups.some((g) => g.tasks.some((x) => x.id === t.id)),\n  found: found.map((f) => f.title),\n  byRef: (await tasks.task(t.ref)).title,\n  inboxOpen: (await tasks.lists()).find((l) => l.name === "Inbox")!.open,\n};` });
kase("add-five-in-one-batch", { expect: "write", script: () => `const ids: string[] = [];\nfor (const title of ["One", "Two", "Three", "Four", "Five"]) ids.push((await tasks.add({ title, list: "Someday" })).id);\nreturn ids.length;` });
kase("add-to-deleted-list", { expect: "Invalid", script: () => `return await tasks.add({ title: "Into the trash", list: "Old Projects" });` });
kase("add-with-no-active-list", { expect: "NoActiveList", script: () => `for (const l of await tasks.lists()) await tasks.deleteList(l.id);\nreturn await tasks.add({ title: "Nowhere to go" });` });
kase("add-key-and-id", { expect: "Invalid", script: () => `return await tasks.add({ title: "Both", key: "k1", id: "i1" });` });
kase("add-blank-title", { expect: "Invalid", script: () => `return await tasks.add({ title: "   " });` });
kase("add-no-args", { expect: "Invalid", script: () => `return await tasks.add();` });
kase("add-title-not-a-string", { expect: "Invalid", script: () => `return await tasks.add({ title: 42 });` });
kase("add-title-too-long", { expect: "Limit", script: () => `return await tasks.add({ title: "x".repeat(1001) });` });
kase("add-id-too-long", { expect: "Invalid", script: () => `return await tasks.add({ title: "Long id", id: "i".repeat(65) });` });
kase("add-unknown-field", { expect: "Invalid", script: () => `return await tasks.add({ title: "Red", colour: "red" });` });
kase("add-place-up", { expect: "Invalid", script: () => `return await tasks.add({ title: "Up", place: "up" });` });
kase("add-place-in-another-list", { expect: "Invalid", script: () => `return await tasks.add({ title: "Mismatch", list: "Home", place: { after: ${q(S.T.report)} } });` });
kase("add-place-next-to-completed", { expect: "Invalid", script: () => `return await tasks.add({ title: "Next to done", place: { after: ${q(S.T.fridge)} } });` });
kase("add-bad-date", { expect: "Invalid", script: () => `return await tasks.add({ title: "Bad date", when: "someday maybe" });` });

// Rename and notes.
kase("rename-by-prefix", { expect: "write", script: () => `return await tasks.rename(${q(tp(S.T.dentist))}, "Call the dentist (Dr. Lee)");` });
kase("rename-heading", { expect: "write", script: () => `return await tasks.rename(${q(S.H.Labs)}, "Lab reports");` });
kase("rename-blank", { expect: "Invalid", script: () => `return await tasks.rename(${q(S.T.dentist)}, "");` });
kase("rename-deleted", { expect: "NotFound", script: () => `return await tasks.rename(${q(S.T.vacuum)}, "Vacuum the stairs");` });
kase("setNotes-markdown", { expect: "write", script: () => `return await tasks.setNotes(${q(S.T.laundry)}, "# Laundry\\n\\n- [ ] darks\\n- [x] whites\\n\\n> fold *after* drying\\n\\n\`\`\`\\ncode\\n\`\`\`");` });
kase("setNotes-heading", { expect: "write", script: () => `return await tasks.setNotes(${q(S.H.Readings)}, "Chapters 7–9");` });
kase("setNotes-clear", { expect: "write", script: () => `return await tasks.setNotes(${q(S.T.article)}, "");` });

// Complete, uncomplete, toggle.
kase("complete-one", { expect: "write", script: () => `return await tasks.complete(${q(S.T.dentist)});` });
kase("complete-array-with-a-done-one", { expect: "write", script: () => `return await tasks.complete([${q(S.T.oatMilk)}, ${q(S.T.fridge)}]);` });
kase("complete-already-done", { expect: "noop", script: () => `return await tasks.complete(${q(S.T.standup)});` });
kase("complete-same-task-twice", { expect: "write", script: () => `return await tasks.complete([${q(S.T.sam)}, ${q(tp(S.T.sam, 6))}]);` });
kase("complete-heading", { expect: "Invalid", script: () => `return await tasks.complete(${q(S.H.Assignments)});` });
kase("complete-deleted", { expect: "NotFound", script: () => `return await tasks.complete(${q(S.T.vacuum)});` });
kase("uncomplete-one", { expect: "write", script: () => `return await tasks.uncomplete(${q(S.T.fridge)});` });
kase("uncomplete-mixed", { expect: "write", script: () => `// Water plants was completed yesterday by the app; Laundry is open\nreturn await tasks.uncomplete([${q(S.T.plants)}, ${q(S.T.laundry)}]);` });
kase("toggle-mixed-completes", { expect: "write", script: () => `// Fix shelf was completed a week ago; Fix bike is open\nreturn await tasks.toggle([${q(S.T.bike)}, ${q(S.T.shelf)}]);` });
kase("toggle-all-done-uncompletes", { expect: "write", script: () => `return await tasks.toggle([${q(S.T.bike)}, ${q(S.T.shelf)}]);` });

// When and Deadline.
kase("setWhen-iso-on-two", { expect: "write", script: () => `return await tasks.setWhen([${q(S.T.piano)}, ${q(S.T.novel)}], ${q(addDays(S.today, 5))});` });
kase("setWhen-phrase", { expect: "write", script: () => `return await tasks.setWhen(${q(S.T.library)}, "next week");` });
kase("setWhen-null", { expect: "write", script: () => `return await tasks.setWhen(${q(S.T.parcel)}, null);` });
kase("setWhen-none-word", { expect: "write", script: () => `return await tasks.setWhen(${q(S.T.expense)}, "none");` });
kase("setWhen-undefined-clears", { expect: "write", script: () => `// an explicit undefined crosses the bridge as null\nreturn await tasks.setWhen(${q(S.T.trip)}, undefined);` });
kase("setWhen-missing-date", { expect: "Invalid", script: () => `return await tasks.setWhen(${q(S.T.trip)});` });
kase("setWhen-bad-phrase", { expect: "Invalid", script: () => `return await tasks.setWhen(${q(S.T.trip)}, "blursday");` });
kase("setWhen-heading", { expect: "Invalid", script: () => `return await tasks.setWhen(${q(S.H.Readings)}, "today");` });
kase("setWhen-same-value", { expect: null, script: () => `return await tasks.setWhen(${q(S.T.laundry)}, "today");` });
kase("setDeadline-phrase", { expect: "write", script: () => `return await tasks.setDeadline(${q(S.T.lab2)}, "fri");` });
kase("setDeadline-today-on-two", { expect: "write", script: () => `return await tasks.setDeadline([${q(S.T.ps6)}, ${q(S.T.piano)}], "today");` });
kase("setDeadline-null", { expect: "write", script: () => `return await tasks.setDeadline(${q(S.T.slides)}, null);` });

// Move.
kase("move-to-list", { expect: "write", script: () => `return await tasks.move([${q(S.T.cafe)}, ${q(S.T.bike)}], { list: "Work" });` });
kase("move-to-own-list", { expect: null, script: () => `return await tasks.move(${q(S.T.rent)}, { list: "Home" });` });
kase("move-top", { expect: "write", script: () => `return await tasks.move(${q(S.T.expense)}, { place: "top" });` });
kase("move-bottom", { expect: "write", script: () => `return await tasks.move(${q(S.T.report)}, { place: "bottom" });` });
kase("move-up", { expect: "write", script: () => `return await tasks.move(${q(S.T.lab2)}, { place: "up" });` });
kase("move-down", { expect: "write", script: () => `return await tasks.move(${q(S.T.ps5)}, { place: "down" });` });
kase("move-up-at-top", { expect: null, script: () => `const top = (await tasks.list("Errands")).open[0];\nreturn await tasks.move(top.id, { place: "up" });` });
kase("move-after-task", { expect: "write", script: () => `return await tasks.move(${q(S.T.laundry)}, { place: { after: ${q(S.T.shelf)} } });` });
kase("move-after-task-where-it-is", { expect: "noop", script: () => `return await tasks.move(${q(S.T.laundry)}, { place: { after: ${q(S.T.shelf)} } });` });
kase("move-before-task", { expect: "write", script: () => `return await tasks.move(${q(S.T.parcel)}, { place: { before: ${q(S.T.stamps)} } });` });
kase("move-after-heading", { expect: "write", script: () => `// after a heading: the top of its section\nreturn await tasks.move(${q(S.T.notebook)}, { place: { after: ${q(S.H.Readings)} } });` });
kase("move-before-heading", { expect: "write", script: () => `// before a heading: the end of the section above it\nreturn await tasks.move(${q(S.T.ps6)}, { place: { before: ${q(S.H.Assignments)} } });` });
kase("move-to-list-and-place", { expect: "write", script: () => `return await tasks.move(${q(S.T.article)}, { list: "PHYS 122", place: { after: ${q(S.H.Labs)} } });` });
kase("move-two-to-top-of-list", { expect: "write", script: () => `return await tasks.move([${q(S.T.letter)}, ${q(S.T.stamps)}], { list: "Errands", place: "top" });` });
kase("move-heading-top", { expect: "write", script: () => `return await tasks.move(${q(S.H.Readings)}, { place: "top" });` });
kase("move-heading-down", { expect: "write", script: () => `return await tasks.move(${q(S.H.Readings)}, { place: "down" });` });
kase("move-heading-up", { expect: "write", script: () => `return await tasks.move(${q(S.H.Assignments)}, { place: "up" });` });
kase("move-heading-after-a-task", { expect: "write", script: () => `// lands after that task's whole section\nreturn await tasks.move(${q(S.H.Labs)}, { place: { after: ${q(S.T.ps5)} } });` });
kase("move-heading-before-heading", { expect: "write", script: () => `return await tasks.move(${q(S.H.Labs)}, { place: { before: ${q(S.H.Assignments)} } });` });
kase("move-heading-bottom", { expect: "write", script: () => `return await tasks.move(${q(S.H.Assignments)}, { place: "bottom" });` });
kase("move-heading-where-it-is", { expect: null, script: () => `return await tasks.move(${q(S.H.Assignments)}, { place: "bottom" });` });
kase("move-nowhere", { expect: "Invalid", script: () => `return await tasks.move(${q(S.T.rent)});` });
kase("move-to-deleted-list", { expect: "Invalid", script: () => `return await tasks.move(${q(S.T.rent)}, { list: "Old Projects" });` });
kase("complete-in-deleted-list", { expect: "NotFound", script: () => `return await tasks.complete(${q(S.T.archived)});` });
kase("rename-in-deleted-list", { expect: "NotFound", script: () => `return await tasks.rename(${q(tp(S.T.archived, 6))}, "Renamed in the trash");` });
kase("restore-in-deleted-list", { expect: "Invalid", script: () => `// deleted before its list: it has nowhere to go back to\nreturn await tasks.restore(${q(S.T.oldDraft)});` });
kase("restore-in-deleted-list-not-deleted", { expect: "Invalid", script: () => `return await tasks.restore(${q(S.T.archived)});` });
kase("move-out-of-deleted-list-to-a-place", { expect: "Invalid", script: () => `return await tasks.move(${q(S.T.archived)}, { place: "top" });` });
kase("move-out-of-deleted-list-mixed", { expect: "Invalid", script: () => `return await tasks.move([${q(S.T.archived)}, ${q(S.T.rent)}], { list: "Inbox" });` });
kase("move-out-of-deleted-list-into-deleted", { expect: "Invalid", script: () => `return await tasks.move(${q(S.T.archived)}, { list: ${q(S.L.Garden)} });` });
kase("move-out-of-deleted-list", { expect: "write", script: () => `// Put back in: deleted before its list, so deleted: false too\nconst c = await tasks.move(${q(S.T.oldIdea)}, { list: "Someday", place: "bottom" });\nreturn { c, someday: (await tasks.list("Someday")).open.map((t) => t.title) };` });
kase("move-out-of-deleted-list-completed", { expect: "write", script: () => `// went with its list: list and order only\nreturn await tasks.move(${q(S.T.archivedDone)}, { list: "Inbox" });` });
kase("move-completed-to-a-place", { expect: "Invalid", script: () => `return await tasks.move(${q(S.T.standup)}, { place: "top" });` });
kase("move-next-to-itself", { expect: "Invalid", script: () => `return await tasks.move(${q(S.T.rent)}, { place: { after: ${q(S.T.rent)} } });` });
kase("move-up-two-tasks", { expect: "Invalid", script: () => `return await tasks.move([${q(S.T.rent)}, ${q(S.T.laundry)}], { place: "up" });` });
kase("move-top-across-lists", { expect: "Invalid", script: () => `return await tasks.move([${q(S.T.rent)}, ${q(S.T.piano)}], { place: "top" });` });
kase("move-heading-before-a-task", { expect: "Invalid", script: () => `return await tasks.move(${q(S.H.Labs)}, { place: { before: ${q(S.T.lab1)} } });` });
kase("move-heading-to-another-list", { expect: "Invalid", script: () => `return await tasks.move(${q(S.H.Labs)}, { list: "Home" });` });
kase("move-heading-with-a-task", { expect: "Invalid", script: () => `return await tasks.move([${q(S.H.Labs)}, ${q(S.T.lab1)}], { place: "top" });` });

// Delete and restore.
kase("delete-one", { expect: "write", script: () => `return await tasks.delete(${q(S.T.novel)});` });
kase("delete-two", { expect: "write", script: () => `return await tasks.delete([${q(S.T.piano)}, ${q(S.T.library)}]);` });
kase("delete-heading-keeps-its-tasks", { expect: "write", script: () => `await tasks.delete(${q(S.H.Labs)});\nreturn (await tasks.list("PHYS 122")).open.map((t) => [t.kind ?? "task", t.title]);` });
kase("restore-heading", { expect: "write", script: () => `return await tasks.restore(${q(S.H.Labs)});` });
kase("restore-two", { expect: "write", script: () => `return await tasks.restore([${q(S.T.novel)}, ${q(S.T.piano)}]);` });
kase("restore-not-deleted", { expect: "noop", script: () => `return await tasks.restore(${q(S.T.rent)});` });
kase("delete-already-deleted", { expect: "NotFound", script: () => `return await tasks.delete(${q(S.T.ticket)});` });

// Headings.
kase("addHeading-bottom", { expect: "write", script: () => `return await tasks.addHeading({ name: "Exams", list: "PHYS 122" });` });
kase("addHeading-top-with-notes", { expect: "write", script: () => `return await tasks.addHeading({ name: "Admin", list: "PHYS 122", notes: "Office hours *Tue* 2–4", place: "top" });` });
kase("addHeading-before-task-no-list", { expect: "write", script: () => `// no list: the place's list\nreturn await tasks.addHeading({ name: "Urgent", place: { before: ${q(S.T.trip)} } });` });
kase("addHeading-after-heading", { expect: "write", script: () => `// after a heading: after its section\nreturn await tasks.addHeading({ name: "Problem sets (old)", place: { after: ${q(S.H.Readings)} } });` });
kase("addHeading-after-task", { expect: "write", script: () => `return await tasks.addHeading({ name: "Later", list: "Work", place: { after: ${q(S.T.slides)} } });` });
kase("addHeading-default-list", { expect: "write", script: () => `return await tasks.addHeading({ name: "Inbox heading" });` });
kase("addHeading-deleted-list", { expect: "Invalid", script: () => `return await tasks.addHeading({ name: "Nope", list: "Old Projects" });` });
kase("addHeading-place-down", { expect: "Invalid", script: () => `return await tasks.addHeading({ name: "Down", list: "Home", place: "down" });` });

// Lists.
kase("addList-bottom", { expect: "write", script: () => `return await tasks.addList("Reading");` });
kase("addList-top", { expect: "write", script: () => `return await tasks.addList("Top list", "top");` });
kase("addList-after", { expect: "write", script: () => `return await tasks.addList("Groceries", { after: "Home" });` });
kase("addList-before", { expect: "write", script: () => `return await tasks.addList("Health", { before: "Someday" });` });
kase("addList-same-name-other-case", { expect: "write", script: () => `return await tasks.addList("reading");` });
kase("list-ambiguous-name", { expect: "Ambiguous", script: () => `return await tasks.list("Reading");` });
kase("addList-place-up", { expect: "Invalid", script: () => `return await tasks.addList("Up", "up");` });
kase("addList-blank-name", { expect: "Invalid", script: () => `return await tasks.addList(" ");` });
kase("renameList-by-id", { expect: "write", script: () => `const dup = (await tasks.lists()).find((l) => l.name === "reading")!;\nreturn await tasks.renameList(dup.id, "Reading 2027");` });
kase("renameList-by-name", { expect: "write", script: () => `return await tasks.renameList("Top list", "Focus");` });
kase("setListNotes", { expect: "write", script: () => `return await tasks.setListNotes("Errands", "Saturdays.\\n\\n1. post office\\n2. **library**");` });
kase("setListNotes-clear", { expect: "write", script: () => `return await tasks.setListNotes("Home", "");` });
kase("moveList-top", { expect: "write", script: () => `return await tasks.moveList("Someday", "top");` });
kase("moveList-bottom", { expect: "write", script: () => `return await tasks.moveList("Focus", "bottom");` });
kase("moveList-up", { expect: "write", script: () => `return await tasks.moveList("Errands", "up");` });
kase("moveList-down", { expect: "write", script: () => `return await tasks.moveList(${q(S.L.Inbox)}, "down");` });
kase("moveList-after", { expect: "write", script: () => `return await tasks.moveList("Groceries", { after: "Errands" });` });
kase("moveList-before", { expect: "write", script: () => `return await tasks.moveList("Health", { before: ${q(lp(S.L.Home))} });` });
kase("moveList-up-at-top", { expect: null, script: () => `const first = (await tasks.lists())[0];\nreturn await tasks.moveList(first.id, "up");` });
kase("moveList-deleted", { expect: "Invalid", script: () => `return await tasks.moveList("Old Projects", "top");` });
kase("renameList-deleted", { expect: "Invalid", script: () => `return await tasks.renameList("Old Projects", "New Projects");` });
kase("setListNotes-deleted", { expect: "Invalid", script: () => `return await tasks.setListNotes("Old Projects", "x");` });
kase("moveList-next-to-itself", { expect: "Invalid", script: () => `return await tasks.moveList("Home", { after: "Home" });` });
kase("moveList-no-place", { expect: "Invalid", script: () => `return await tasks.moveList("Home");` });
kase("deleteList", { expect: "write", script: () => `const c = await tasks.deleteList("Groceries");\nreturn { c, sidebar: (await tasks.lists()).map((l) => l.name), deleted: (await tasks.deletedLists()).map((l) => l.name) };` });
kase("deleteList-already-deleted", { expect: null, script: () => `return await tasks.deleteList("Garden");` });
kase("deleteList-then-views", { expect: "write", script: () => `// Home's tasks count as deleted: out of today, find and the counts\nconst c = await tasks.deleteList("Home");\nreturn {\n  c,\n  today: await tasks.today(),\n  find: (await tasks.find({ text: "rent" })).map((t) => t.title),\n  findDeleted: (await tasks.find({ text: "rent", deleted: true })).map((t) => [t.title, t.listDeleted ?? false]),\n};` });
kase("restoreList-home", { expect: "write", script: () => `const c = await tasks.restoreList("Home");\nreturn { c, sidebar: (await tasks.lists()).map((l) => l.name), laundryInToday: (await tasks.today()).groups.some((g) => g.list.name === "Home") };` });
kase("restoreList", { expect: "write", script: () => `// everything comes back as it was; the draft deleted before the list stays deleted\nconst c = await tasks.restoreList("Old Projects");\nreturn { c, sidebar: (await tasks.lists()).map((l) => l.name), today: await tasks.today(), old: await tasks.list("Old Projects"), draft: await tasks.task(${q(S.T.oldDraft)}) };` });
kase("restore-after-its-list", { expect: "write", script: () => `// its list is back: the plain restore again\nreturn await tasks.restore(${q(S.T.oldDraft)});` });
kase("restoreList-name-hits-active", { expect: null, script: () => `// "Work" names the live list first, so this doesn't reach the deleted one\nreturn await tasks.restoreList("Work");` });
kase("restoreList-by-id", { expect: "write", script: () => `return await tasks.restoreList(${q(S.L.WorkOld)});` });
kase("archiveList-and-unarchiveList-old-names", { expect: "write", script: () => `// the old names still run\nconst l = await tasks.addList("Alias test");\nawait tasks.archiveList(l.id);\nconst deleted = (await tasks.deletedLists()).map((x) => x.name);\nawait tasks.unarchiveList(l.id);\nreturn { deleted, sidebar: (await tasks.lists()).map((x) => x.name) };` });

// Undo.
kase("undo-target-rename", { expect: "write", script: () => `return await tasks.rename(${q(S.T.pr)}, "Review PR #42");` });
kase("undo-target-add", { expect: "write", script: () => `return await tasks.add({ title: "Undo me", list: "Inbox", when: "today" });` });
kase("undo-newest", { expect: "write", script: () => `return await tasks.undo();` });
kase("undo-newest-walks-back", { expect: "write", script: () => `const c = await tasks.undo(null);\nreturn { c, title: (await tasks.task(${q(S.T.pr)})).title };` });
kase("undo-already-undone", { expect: "Invalid", script: () => `return await tasks.undo(${q(S.batch["undo-target-add"])});` });
kase("undo-the-undo-is-a-redo", { expect: "write", script: () => `return await tasks.undo(${q(S.batch["undo-newest"])});` });
kase("undo-by-batch-prefix", { expect: "write", script: () => `return await tasks.undo(${q(S.batch["move-to-list"].slice(0, 6))});` });
kase("undo-add-list", { expect: "write", script: () => `return await tasks.undo(${q(S.batch["addList-before"])});` });
kase("undo-delete-list", { expect: "write", script: () => `return await tasks.undo(${q(S.batch["deleteList"])});` });
kase("undo-delete-heading", { expect: null, script: () => `// restore-heading already brought it back: nothing to change\nreturn await tasks.undo(${q(S.batch["delete-heading-keeps-its-tasks"])});` });
kase("undo-dry-run", { expect: "write", dryRun: true, script: () => `return await tasks.undo(${q(S.batch["complete-one"])});` });
kase("conflict-agent-edit", { expect: "write", script: () => `await tasks.rename(${q(S.T.trip)}, "Plan the trip");\nawait tasks.setWhen(${q(S.T.trip)}, "fri");\nreturn await tasks.setNotes(${q(S.T.trip)}, "Flights, then the hotel.");` });
kase("undo-keeps-the-later-edit", {
  expect: "write",
  prep: () => [{ actor: SEED_ACTOR, replica: "other", argv: ["rename", S.T.trip, "Plan trip to Montréal"], key: "person-rename" }],
  script: () => `// someone renamed it since, from another Mac: the title stays, the rest goes back\nreturn await tasks.undo(${q(S.batch["conflict-agent-edit"])});`,
});
kase("undo-another-actors-change", { expect: "write", script: () => `return await tasks.undo(${q(S.prepBatch["person-rename"])});` });
kase("undo-then-write", { expect: "Invalid", script: () => `await tasks.undo(${q(S.batch["setListNotes"])});\nreturn await tasks.add({ title: "After an undo" });` });
kase("write-then-undo", { expect: "Invalid", script: () => `await tasks.add({ title: "Before an undo" });\nreturn await tasks.undo();` });
kase("undo-nothing-of-this-actor", { expect: "NotFound", actor: "agent:fresh", script: () => `return await tasks.undo();` });
kase("undo-unknown-batch", { expect: "NotFound", script: () => `return await tasks.undo("abcdef12");` });
kase("undo-batch-ref-too-short", { expect: "NotFound", script: () => `return await tasks.undo("ab");` });

// Dry runs.
kase("dry-run-add-and-move", { expect: "write", dryRun: true, script: () => `const t = await tasks.add({ title: "Dry run task", list: "Home", when: "tomorrow" });\nawait tasks.move([t.id, ${q(S.T.rent)}], { list: "Errands" });\nawait tasks.complete(${q(S.T.laundry)});\nreturn t.id.length;` });
kase("dry-run-lists", { expect: "write", dryRun: true, script: () => `const l = await tasks.addList("Dry list", { before: "Home" });\nawait tasks.renameList("Errands", "Errands & chores");\n// reads see the rename: the old name is gone\nawait tasks.setListNotes("Errands & chores", "x");\nawait tasks.deleteList("Someday");\nreturn l.name;` });
kase("dry-run-no-change", { expect: "read", dryRun: true, script: () => `return (await tasks.lists()).length;` });
kase("dry-run-error", { expect: "NotFound", dryRun: true, script: () => `await tasks.add({ title: "Dry" });\nawait tasks.complete("zzzz1234");` });

// The end state, then the limits.
kase("final-views", { expect: "read", script: () => `return {\n  today: await tasks.today(),\n  lists: await tasks.lists(),\n  deleted: await tasks.deletedLists(),\n  phys: await tasks.list("PHYS 122"),\n  inbox: await tasks.list("Inbox"),\n};` });
kase("over-500-ops", { expect: "Limit", script: () => `for (let i = 0; i < 501; i++) await tasks.add({ title: "Bulk " + i, list: "Someday" });\nreturn "made 501";` });
kase("over-10-seconds", { expect: "Limit", script: () => `await tasks.add({ title: "Too slow" });\nawait new Promise((r) => setTimeout(r, 30000));\nreturn "late";` });

// ---------------------------------------------------------------- running them

function checkExpect(c, out, from, to) {
  const e = c.expect;
  if (e == null || !out) return;
  const wrote = to > from;
  if (e === "read" || e === "noop") {
    if (out.ok !== true || out.change !== null || wrote) warn(`${c.name}: expected ${e}, got ok=${out.ok} change=${!!out.change} wrote=${wrote} ${out.error ? q(out.error) : ""}`);
  } else if (e === "write") {
    if (out.ok !== true || !out.change || wrote === !!c.dryRun) warn(`${c.name}: expected a write, got ok=${out.ok} change=${!!out.change} wrote=${wrote} ${out.error ? q(out.error) : ""}`);
  } else if (out.ok !== false || out.error?.type !== e || wrote) {
    warn(`${c.name}: expected ${e}, got ok=${out.ok} type=${out.error?.type} wrote=${wrote}`);
  }
}

async function runCase(c, i) {
  const prep = [];
  for (const p of c.prep ? c.prep() : []) {
    const from = await tail.pull();
    const json = must(p.argv, { actor: p.actor, replica: p.replica });
    const to = await tail.pull();
    if (p.key) S.prepBatch[p.key] = json.batch;
    prep.push({ actor: p.actor, replica: p.replica, argv: p.argv, from, to, output: json });
  }
  const script = c.script();
  const file = path.join(opt.scratch, "scripts", `${String(i + 1).padStart(3, "0")}-${c.name}.ts`);
  fs.writeFileSync(file, script);
  const actor = c.actor ?? ACTOR;
  const dateOrder = c.dateOrder ?? opt.dateOrder;
  const from = await tail.pull();
  const nowBefore = Date.now();
  const r = cli(["run", "--json", ...(c.dryRun ? ["--dry-run"] : []), file], { actor, env: { TASKS_DATE_ORDER: dateOrder } });
  const nowAfter = Date.now();
  const to = await tail.pull();
  if (!r.json) throw new Error(`${c.name}: unparseable output (exit ${r.code}): ${r.stdout}\n${r.stderr}`);
  S.out[c.name] = r.json;
  if (r.json.change?.batch && !c.dryRun) S.batch[c.name] = r.json.change.batch;
  checkExpect(c, r.json, from, to);
  const rec = { name: c.name, script, dryRun: !!c.dryRun, actor };
  if (dateOrder !== opt.dateOrder) rec.dateOrder = dateOrder;
  if (prep.length) rec.prep = prep;
  Object.assign(rec, { from, to, nowBefore, nowAfter, today: local(nowBefore).date, exitCode: r.code });
  if (r.stderr.trim()) rec.stderr = r.stderr;
  rec.output = r.json;
  // Swift writes some numbers differently from JSON.stringify (1e-07); keep the exact text when it differs.
  if (JSON.stringify(r.json) !== r.stdout.trim()) rec.outputText = r.stdout.trim();
  say(`${String(i + 1).padStart(3)} ${c.name}: ${r.json.ok ? "ok" : r.json.error?.type}${to > from ? ` +${to - from} ops` : ""}`);
  return rec;
}

/** The same scripts through `tasks mcp`: the tool's text must be the JSON `tasks run --json` prints. */
async function mcpCheck(script, dryRun) {
  const p = spawn(BIN, ["mcp"], { env: cliEnv(ACTOR, "main"), cwd: path.join(opt.scratch, "cwd"), stdio: ["pipe", "pipe", "pipe"] });
  const reply = await new Promise((resolve, reject) => {
    let buf = "";
    const timer = setTimeout(() => { p.kill("SIGKILL"); reject(new Error("tasks mcp timed out")); }, 60_000);
    p.stdout.setEncoding("utf8");
    p.stdout.on("data", (d) => {
      buf += d;
      let n;
      while ((n = buf.indexOf("\n")) >= 0) {
        const m = JSON.parse(buf.slice(0, n));
        buf = buf.slice(n + 1);
        if (m.id === 2) { clearTimeout(timer); resolve(m); }
      }
    });
    const send = (m) => p.stdin.write(JSON.stringify(m) + "\n");
    send({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "parity", version: "0" } } });
    send({ jsonrpc: "2.0", method: "notifications/initialized" });
    send({ jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "tasks_run", arguments: { script, dryRun } } });
  });
  p.stdin.end();
  await new Promise((r) => p.once("exit", r));
  const file = path.join(opt.scratch, "scripts", "mcp-check.ts");
  fs.writeFileSync(file, script);
  const viaCLI = cli(["run", "--json", ...(dryRun ? ["--dry-run"] : []), file], { actor: ACTOR }).stdout.trim();
  const viaMCP = reply.result.content[0].text;
  return { script, dryRun, isError: reply.result.isError, equal: viaCLI === viaMCP };
}

// ---------------------------------------------------------------- output

function writeGolden(golden) {
  const L = [];
  const top = Object.entries(golden);
  L.push("{");
  top.forEach(([k, v], i) => {
    const comma = i < top.length - 1 ? "," : "";
    if (k === "log" || k === "cases" || k === "seed") {
      L.push(`  ${q(k)}: [`);
      v.forEach((x, j) => L.push(`    ${q(x)}${j < v.length - 1 ? "," : ""}`));
      L.push(`  ]${comma}`);
    } else {
      L.push(`  ${q(k)}: ${q(v)}${comma}`);
    }
  });
  L.push("}");
  fs.mkdirSync(path.dirname(opt.out), { recursive: true });
  fs.writeFileSync(opt.out, L.join("\n") + "\n");
}

// ---------------------------------------------------------------- main

async function main() {
  const startedAt = Date.now();
  const start = local(startedAt);
  if (!opt.anytime && (start.minutes < 10 || start.minutes > 24 * 60 - 25)) {
    throw new Error(`It's ${start.date} ${Math.floor(start.minutes / 60)}:${String(start.minutes % 60).padStart(2, "0")} in ${TZ}: too close to midnight (a run must stay on one day). --anytime overrides.`);
  }
  ({ envFile: ENV_FILE } = prepareScratch());
  BIN = buildCLI();
  DENO = findDeno();
  say(`cli ${path.relative(REPO, BIN)}, deno ${DENO}, zone ${TZ}, scratch ${opt.scratch}`);

  await startServer();
  try {
    // A debug build refuses anything but localhost before it touches the network.
    const remote = cli(["status", "--json"], { env: { TASKS_URL: "https://tasks.invalid" } });
    if (remote.json?.error?.type !== "Config" || !/debug build/.test(remote.json.error.message)) {
      throw new Error(`Not a debug build of tasks? ${remote.stdout}`);
    }
    const types = cli(["types"]).stdout;
    const dts = fs.readFileSync(DTS, "utf8");
    if (types.trimEnd() !== dts.trimEnd()) warn("tasks types differs from app/TasksCore/Tests/TasksCLITests/tasks.d.ts");

    tail = new Tail();
    S.today = start.date;
    say("seeding…");
    await seed();
    say(`seeded: ${tail.cursor} entries`);

    const cases = [];
    for (let i = 0; i < CASES.length; i++) cases.push(await runCase(CASES[i], i));

    const mcp = [await mcpCheck("return await tasks.lists();", false), await mcpCheck(`await tasks.task("zzzz9999");`, true)];
    for (const m of mcp) if (!m.equal) warn(`tasks mcp and tasks run --json differ for ${q(m.script)}`);
    await tail.pull();

    // Coverage: every method of tasks.d.ts appears in some script.
    const methods = [...dts.slice(dts.indexOf("declare const tasks")).matchAll(/^\s{2}(\w+)\(/gm)].map((m) => m[1]);
    const missing = methods.filter((m) => !cases.some((c) => c.script.includes(`tasks.${m}(`)));
    if (missing.length) warn(`methods never called: ${missing.join(", ")}`);

    const days = new Set(cases.map((c) => c.today));
    if (days.size !== 1 || local(Date.now()).date !== start.date) throw new Error(`The day changed during the run (${[...days]}); run it again.`);

    const golden = {
      generatedAt: new Date(startedAt).toISOString(),
      timeZone: TZ,
      dateOrder: opt.dateOrder,
      actor: ACTOR,
      cli: { build: "debug", binary: path.relative(REPO, BIN), deno: run(DENO, ["--version"]).stdout.split("\n")[0] },
      entities: { lists: S.L, tasks: S.T, headings: S.H },
      typesMatchDts: !warnings.some((w) => w.startsWith("tasks types")),
      mcpCheck: mcp,
      warnings,
      seed: seedLog,
      log: tail.lines,
      cases,
    };
    writeGolden(golden);
    const size = fs.statSync(opt.out).size;
    say(`wrote ${path.relative(process.cwd(), opt.out)}: ${cases.length} cases, ${tail.lines.length} log entries, ${(size / 1024).toFixed(0)} KB, ${warnings.length} warnings, ${((Date.now() - startedAt) / 1000).toFixed(0)} s`);
  } finally {
    await stopServer();
  }
}

main().catch(async (e) => {
  console.error("[capture] FAILED:", e.message);
  await stopServer();
  process.exit(1);
});
