// The sync wire format: a port of TasksCore/Wire.swift and SyncClient.swift's error table (spec §5).

import { decodeOp, isInt, unreadableOp, type Op } from "./op.ts";

/** A log entry as the server sends it. */
export interface LogEntry {
  seq: number;
  received: number;
  /** SHA-256(prev hash + "\n" + op text), hex. Never computed here, only echoed as `base`. */
  hash: string;
  op: Op;
}

/** A log entry and the exact JSON it is stored as. */
export interface RawEntry {
  entry: LogEntry;
  json: string;
  /** The entry's `op`, verbatim (the server's stored text): the 409 recovery queue resends it as is. */
  opText: string;
}

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

/** `LogEntry(from:)`: seq and hash are required; an op this client can't read still occupies its seq and hash. */
export function decodeEntry(raw: unknown): LogEntry | null {
  if (!isObject(raw) || !isInt(raw.seq) || typeof raw.hash !== "string") return null;
  return {
    seq: raw.seq,
    received: isInt(raw.received) ? raw.received : 0,
    hash: raw.hash,
    op: decodeOp(raw.op) ?? unreadableOp(),
  };
}

export function decodeEntryLine(line: string): LogEntry | null {
  try {
    return decodeEntry(JSON.parse(line));
  } catch {
    return null;
  }
}

/** `POST /v1/sync` body from already-encoded op JSON, so pending ops go out verbatim. */
export function syncBody(from: number, base: string | null, opJSON: string[]): string {
  return `{"from":${from},"base":${base === null ? "null" : JSON.stringify(base)},"ops":[${opJSON.join(",")}]}`;
}

export interface SyncPage {
  entries: RawEntry[];
  head: number;
  more: boolean;
}

export interface ErrorBody {
  error: string;
  message?: string;
  index?: number;
  field?: string;
}

/** One `/v1/sync` response, classified by the error table. */
export type SyncOutcome =
  | { kind: "page"; page: SyncPage }
  /** 400 invalid_op: `ops[index]` failed validation at `field`. */
  | { kind: "invalidOp"; error: ErrorBody }
  /** 400 bad_request: a client bug. Stop, no retry. */
  | { kind: "badRequest"; message: string }
  /** 401: stop until the token changes. */
  | { kind: "badToken" }
  /** 404 / 405: a misconfigured server URL. Stop. */
  | { kind: "misconfigured"; message: string }
  /** 409: the logs diverged. Recover and retry from 0. */
  | { kind: "logMismatch" }
  /** 413: halve the batch and retry. */
  | { kind: "tooLarge" }
  /** 5xx, network errors, non-JSON bodies: retry with backoff. */
  | { kind: "transient"; reason: string };

/**
 * A 200 body. Each entry keeps its JSON text; the server writes its bodies with `JSON.stringify`, so re-stringifying
 * the parsed entry gives back its bytes (the Swift slices them out instead).
 */
export function decodePage(text: string): SyncPage | null {
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    return null;
  }
  if (!isObject(raw) || !Array.isArray(raw.entries) || !isInt(raw.head) || typeof raw.more !== "boolean") return null;
  const entries: RawEntry[] = [];
  for (const e of raw.entries) {
    const entry = decodeEntry(e);
    if (!entry) return null;
    entries.push({ entry, json: JSON.stringify(e), opText: JSON.stringify((e as { op?: unknown }).op ?? null) });
  }
  return { entries, head: raw.head, more: raw.more };
}

/** The error table. Anything that isn't one of its JSON bodies is server or network trouble, retried. */
export function classify(status: number, body: string): SyncOutcome {
  if (status === 200) {
    const page = decodePage(body);
    return page ? { kind: "page", page } : { kind: "transient", reason: "Unreadable 200 response" };
  }
  let error: ErrorBody | null = null;
  try {
    const raw = JSON.parse(body);
    // Codable: `error` is required; an optional key that is present must be null or the right type.
    const ok = (v: unknown, test: (v: unknown) => boolean) => v === undefined || v === null || test(v);
    const isString = (v: unknown) => typeof v === "string";
    if (isObject(raw) && typeof raw.error === "string" && ok(raw.message, isString) && ok(raw.index, isInt) && ok(raw.field, isString)) {
      error = { error: raw.error };
      if (typeof raw.message === "string") error.message = raw.message;
      if (isInt(raw.index)) error.index = raw.index;
      if (typeof raw.field === "string") error.field = raw.field;
    }
  } catch {
    // not JSON
  }
  if (!error) return { kind: "transient", reason: `HTTP ${status}` };
  if (status === 400 && error.error === "invalid_op" && error.index !== undefined) return { kind: "invalidOp", error };
  if (status === 400) return { kind: "badRequest", message: error.message ?? error.error };
  if (status === 401) return { kind: "badToken" };
  if (status === 404 || status === 405) return { kind: "misconfigured", message: error.message ?? `HTTP ${status}` };
  if (status === 409) return { kind: "logMismatch" };
  if (status === 413) return { kind: "tooLarge" };
  return { kind: "transient", reason: error.message ?? `HTTP ${status}` };
}
