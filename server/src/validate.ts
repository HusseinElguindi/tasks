// Request parsing and op validation (SPEC §5 "Request"). Pure: no I/O, no log access.

export const MAX_BODY_BYTES = 1 << 20; // 1 MiB
export const MAX_OPS = 500;

/** An op that passed validation, serialized exactly as the log stores and hashes it. */
export interface PreparedOp {
  id: string;
  text: string;
}

export interface SyncRequest {
  from: number;
  base: string | null;
  ops: PreparedOp[];
}

export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly index?: number,
    readonly field?: string,
  ) {
    super(message);
  }
}

const badRequest = (message: string) => new HttpError(400, "bad_request", message);

type Check = (v: unknown) => boolean;

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const isNat = (v: unknown): v is number => Number.isSafeInteger(v) && (v as number) >= 0;
// Lengths are UTF-16 code units (String.length). Lone surrogates are rejected: they can't be
// encoded as UTF-8, and a client that can't decode an entry could never sync past it.
const isString = (min: number, max: number): Check => (v) =>
  typeof v === "string" && v.length >= min && v.length <= max && v.isWellFormed();

const ORDER = /^[0-9A-Za-z]{1,128}$/;
const DATE = /^(\d{4})-(\d{2})-(\d{2})$/;
const HASH = /^[0-9a-f]{64}$/;
const DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

function isCalendarDate(v: unknown): boolean {
  const m = typeof v === "string" ? DATE.exec(v) : null;
  if (!m) return false;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const leap = y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0);
  return mo >= 1 && mo <= 12 && d >= 1 && d <= (mo === 2 && leap ? 29 : DAYS[mo - 1]);
}

const nullable = (check: Check): Check => (v) => v === null || check(v);

const VALUES: Record<string, [Check, string]> = {
  list: [isString(1, 64), "must be a string of 1 to 64 characters"],
  order: [(v) => typeof v === "string" && ORDER.test(v), "must match ^[0-9A-Za-z]{1,128}$"],
  title: [isString(0, 1000), "must be a string of at most 1000 characters"],
  notes: [isString(0, 20000), "must be a string of at most 20000 characters"],
  name: [isString(0, 200), "must be a string of at most 200 characters"],
  when: [nullable(isCalendarDate), "must be null or a real YYYY-MM-DD date"],
  deadline: [nullable(isCalendarDate), "must be null or a real YYYY-MM-DD date"],
  completedAt: [nullable(isNat), "must be null or an integer >= 0"],
  archivedAt: [nullable(isNat), "must be null or an integer >= 0"],
  deleted: [(v) => typeof v === "boolean", "must be a boolean"],
};

const TASK_KEYS = ["list", "order", "title", "notes", "when", "deadline", "completedAt"];
const TYPES: Record<string, { allowed: Set<string>; required: string[] }> = {
  "task.create": { allowed: new Set(TASK_KEYS), required: ["list", "order"] },
  "task.update": { allowed: new Set([...TASK_KEYS, "deleted"]), required: [] },
  "list.create": { allowed: new Set(["name", "order"]), required: ["name", "order"] },
  "list.update": { allowed: new Set(["name", "order", "archivedAt"]), required: [] },
};
// `actor` and `batch` are optional attribution keys (SPEC §5): who wrote the op, and the change it belongs to.
const ENVELOPE = new Set(["id", "at", "type", "target", "set", "actor", "batch"]);
const isId = isString(1, 64);

/** Validates ops[index]. Checks run in a fixed order and the first failure is reported. */
function prepareOp(op: unknown, index: number): PreparedOp {
  const fail = (field: string, problem: string) =>
    new HttpError(400, "invalid_op", `ops[${index}]${field === "op" ? "" : "." + field} ${problem}`, index, field);

  if (!isObject(op)) throw fail("op", "must be an object");
  const { id, at, type, target, set, actor, batch } = op;
  if (!isId(id)) throw fail("id", "must be a string of 1 to 64 characters");
  if (!isNat(at)) throw fail("at", "must be an integer >= 0");
  const rules = typeof type === "string" && Object.hasOwn(TYPES, type) ? TYPES[type] : undefined;
  if (!rules) throw fail("type", "must be one of task.create, task.update, list.create, list.update");
  if (!isId(target)) throw fail("target", "must be a string of 1 to 64 characters");
  if (!isObject(set)) throw fail("set", "must be an object");
  if (Object.hasOwn(op, "actor") && !isId(actor)) throw fail("actor", "must be a string of 1 to 64 characters");
  if (Object.hasOwn(op, "batch") && !isId(batch)) throw fail("batch", "must be a string of 1 to 64 characters");
  for (const key of Object.keys(op)) if (!ENVELOPE.has(key)) throw fail(key, "is not an op field");

  for (const key of Object.keys(set)) {
    if (!rules.allowed.has(key)) throw fail(`set.${key}`, `is not allowed for ${type}`);
    const [check, problem] = VALUES[key];
    if (!check(set[key])) throw fail(`set.${key}`, problem);
  }
  for (const key of rules.required) if (!Object.hasOwn(set, key)) throw fail(`set.${key}`, `is required for ${type}`);

  // Top-level keys in this order, `set` keys in the order received (SPEC §5). JSON.stringify omits an absent
  // actor or batch, so an op without them is stored exactly as before.
  return { id: id as string, text: JSON.stringify({ id, at, type, target, set, actor, batch }) };
}

/** Parses and validates a request body. Throws HttpError(400 / 413). */
export function parseSyncRequest(text: string): SyncRequest {
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    throw badRequest("Body is not valid JSON.");
  }
  if (!isObject(body)) throw badRequest("Body must be a JSON object.");

  const { from, base, ops } = body;
  if (!isNat(from)) throw badRequest("from must be an integer >= 0.");
  if (base === null) {
    if (from > 0) throw badRequest("base must not be null when from > 0.");
  } else if (typeof base !== "string" || !HASH.test(base)) {
    throw badRequest("base must be null or 64 lowercase hex characters.");
  } else if (from === 0) {
    throw badRequest("base must be null when from is 0.");
  }
  if (!Array.isArray(ops)) throw badRequest("ops must be an array.");
  if (ops.length > MAX_OPS) throw new HttpError(413, "too_large", `At most ${MAX_OPS} ops per request; got ${ops.length}.`);

  return { from, base, ops: ops.map(prepareOp) };
}
