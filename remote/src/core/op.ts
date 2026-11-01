// Ops, patches and their canonical JSON: a port of TasksCore/Op.swift (spec §5).

import { isCalendarDate, type CalendarDate } from "./calendar-date.ts";

/** Task and list ids are client-generated strings (UUIDs in practice, 1–64 chars on the wire). */
export type EntityID = string;

export type OpType = "task.create" | "task.update" | "list.create" | "list.update" | (string & {});

export const isTaskOp = (t: OpType) => t === "task.create" || t === "task.update";
export const isListOp = (t: OpType) => t === "list.create" || t === "list.update";

/**
 * The `set` of an op. A present key overwrites the field, `null` clears it, a missing key leaves it alone.
 * Nullable fields are `T | null`; an absent key is `undefined` (and not an own property).
 */
export interface Patch {
  list?: EntityID;
  order?: string;
  title?: string;
  notes?: string;
  when?: CalendarDate | null;
  deadline?: CalendarDate | null;
  completedAt?: number | null;
  deleted?: boolean;
  name?: string;
  archivedAt?: number | null;
  /** `task.create` only: "heading" makes the task a heading. */
  kind?: string;
}

export const HEADING = "heading";

export interface Op {
  /** Client-generated UUID, the idempotency key. */
  id: string;
  /** Client wall clock in epoch ms. Informational only. */
  at: number;
  type: OpType;
  target: EntityID;
  set: Patch;
  actor?: string;
  batch?: string;
}

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

/** A JSON string Swift can decode: a lone surrogate makes JSONDecoder fail on that value. */
const isString = (v: unknown): v is string => typeof v === "string" && v.isWellFormed();

/** Swift's JSONDecoder reading `Int`: a JSON number with an exact integer value in Int64's range. */
export const isInt = (v: unknown): v is number => typeof v === "number" && Number.isInteger(v) && Math.abs(v) <= 2 ** 63;

/** Per-key lenient decoding (rule 6): unknown keys and values of the wrong type are dropped, never fatal. */
export function decodePatch(raw: unknown): Patch {
  const p: Patch = {};
  if (!isObject(raw)) return p;
  for (const key of Object.keys(raw)) {
    const v = raw[key];
    switch (key) {
      case "list":
      case "order":
      case "title":
      case "notes":
      case "name":
      case "kind":
        if (isString(v)) p[key] = v;
        break;
      case "deleted":
        if (typeof v === "boolean") p.deleted = v;
        break;
      case "when":
      case "deadline":
        if (v === null) p[key] = null;
        else if (isString(v) && isCalendarDate(v)) p[key] = v;
        break;
      case "completedAt":
      case "archivedAt":
        if (v === null) p[key] = null;
        else if (isInt(v) && v >= 0) p[key] = v;
        break;
    }
  }
  return p;
}

/** An op from parsed JSON, as `Op(from:)` decodes it; null if it has no string id and target. */
export function decodeOp(raw: unknown): Op | null {
  if (!isObject(raw)) return null;
  if (!isString(raw.id) || !isString(raw.target)) return null;
  const op: Op = {
    id: raw.id,
    at: isInt(raw.at) ? raw.at : 0,
    type: isString(raw.type) ? raw.type : "",
    target: raw.target,
    set: decodePatch(raw.set),
  };
  if (isString(raw.actor)) op.actor = raw.actor;
  if (isString(raw.batch)) op.batch = raw.batch;
  return op;
}

/** The placeholder for a log line whose op this client can't read: it keeps its seq and hash, the reducer ignores it. */
export const unreadableOp = (): Op => ({ id: "", at: 0, type: "", target: "", set: {} });

/**
 * The op as compact JSON with keys in the server's fixed order (`id, at, type, target, set`, then `actor, batch`),
 * `set` keys in `Op.jsonData`'s order. Strings are escaped the way `JSON.stringify` does, which is what the Swift writes.
 */
export function opJSON(op: Op): string {
  const s = op.set;
  const parts: string[] = [];
  const put = (k: string, v: unknown) => {
    if (v !== undefined) parts.push(`"${k}":${JSON.stringify(v)}`);
  };
  put("name", s.name);
  put("list", s.list);
  put("order", s.order);
  put("title", s.title);
  put("notes", s.notes);
  put("kind", s.kind);
  put("when", s.when);
  put("deadline", s.deadline);
  put("completedAt", s.completedAt);
  put("deleted", s.deleted);
  put("archivedAt", s.archivedAt);
  let out = `{"id":${JSON.stringify(op.id)},"at":${op.at},"type":${JSON.stringify(op.type)},"target":${JSON.stringify(op.target)},"set":{${parts.join(",")}}`;
  if (op.actor !== undefined) out += `,"actor":${JSON.stringify(op.actor)}`;
  if (op.batch !== undefined) out += `,"batch":${JSON.stringify(op.batch)}`;
  return out + "}";
}

/** Two ops are equal when every envelope field and every patch key is (Swift's synthesized `==`). */
export function opsEqual(a: Op, b: Op): boolean {
  return opJSON(a) === opJSON(b);
}

/** A pending op and the exact JSON it is sent as: verbatim, never re-encoded (spec §8). */
export interface PendingOp {
  op: Op;
  json: string;
}

export const pendingOf = (op: Op): PendingOp => ({ op, json: opJSON(op) });

/** A verbatim op line; null if it has no readable id and target. */
export function pendingFromJSON(json: string): PendingOp | null {
  let raw: unknown;
  try {
    raw = JSON.parse(json);
  } catch {
    return null;
  }
  const op = decodeOp(raw);
  return op ? { op, json } : null;
}
