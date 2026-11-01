// Manual order: a port of TasksCore/Ordering.swift. Keys come from `fractional-indexing` 3.2.0, the npm package
// TasksCore's FractionalIndex is a port of (its test vectors were generated from it).

import { generateKeyBetween, generateNKeysBetween } from "fractional-indexing";
import type { EntityID } from "./op.ts";

export interface OrderedItem {
  id: EntityID;
  order: string;
}

/**
 * UTF-8 byte order, which is code point order. JS `<` compares UTF-16 units, which differs for astral characters
 * against U+E000–U+FFFF.
 */
export function utf8Compare(a: string, b: string): number {
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) {
    const x = a.charCodeAt(i);
    const y = b.charCodeAt(i);
    if (x === y) continue;
    return a.codePointAt(i)! - b.codePointAt(i)!;
  }
  return a.length - b.length;
}

export const utf8Less = (a: string, b: string) => utf8Compare(a, b) < 0;

/** Sort by `order` byte-wise, ties by `id` (spec §3). */
export function orderPrecedes(aOrder: string, aID: string, bOrder: string, bID: string): boolean {
  if (aOrder === bOrder) return utf8Less(aID, bID);
  return utf8Less(aOrder, bOrder);
}

export const compareOrdered = (a: OrderedItem, b: OrderedItem) =>
  orderPrecedes(a.order, a.id, b.order, b.id) ? -1 : orderPrecedes(b.order, b.id, a.order, a.id) ? 1 : 0;

export const FractionalIndex = {
  keyBetween(a: string | null, b: string | null): string {
    return generateKeyBetween(checked(a), checked(b));
  },
  /** `n` evenly spread keys strictly between `a` and `b`, ascending; throws like the Swift. */
  keysBetween(a: string | null, b: string | null, n: number): string[] {
    return generateNKeysBetween(checked(a), checked(b), n);
  },
};

/**
 * TasksCore's port also rejects a key with any character outside base 62 (the npm package only checks the integer
 * part and a trailing zero), so a stray key like "a0\u0301" forces a rebalance there. Same here.
 */
const BASE62 = /^[0-9A-Za-z]*$/;
const checked = (k: string | null) => {
  if (k !== null && !BASE62.test(k)) throw new Error(`invalid order key: ${k}`);
  return k;
};

function tryKeys(a: string | null, b: string | null, n: number): string[] | null {
  try {
    return generateNKeysBetween(checked(a), checked(b), n);
  } catch {
    return null;
  }
}

export const MAX_KEY_LENGTH = 32;
const utf8Length = (s: string) => new TextEncoder().encode(s).length;
const fits = (keys: string[]) => keys.every((k) => utf8Length(k) <= MAX_KEY_LENGTH);

export type Anchor = "top" | "bottom" | { after: EntityID } | { before: EntityID };

export const Ordering = {
  /**
   * New keys that place `moving` (in this order) at `anchor` in `items` (sorted by (order, id)); moving items already
   * in it are lifted out first. Re-keyed tied runs and rebalances are included in the result.
   */
  place(moving: EntityID[], anchor: Anchor, items: OrderedItem[]): OrderedItem[] {
    if (moving.length === 0) return [];
    const movingSet = new Set(moving);
    const rest = items.filter((i) => !movingSet.has(i.id)).map((i) => ({ ...i }));
    let p: number;
    if (anchor === "top") p = 0;
    else if (anchor === "bottom") p = rest.length;
    else if ("after" in anchor) {
      const i = rest.findIndex((x) => x.id === anchor.after);
      p = i >= 0 ? i + 1 : rest.length;
    } else {
      const i = rest.findIndex((x) => x.id === anchor.before);
      p = i >= 0 ? i : rest.length;
    }

    const rekeyed: OrderedItem[] = [];
    // Inserting between equal keys: give the tied run distinct keys first (rare).
    if (p > 0 && p < rest.length && rest[p - 1].order === rest[p].order) {
      const tied = rest[p].order;
      let s = p - 1;
      while (s > 0 && rest[s - 1].order === tied) s -= 1;
      let e = p + 1;
      while (e < rest.length && rest[e].order === tied) e += 1;
      const above = e < rest.length ? rest[e].order : null;
      const keys = tryKeys(tied, above, e - s - 1);
      if (keys && fits(keys)) {
        keys.forEach((key, offset) => {
          rest[s + 1 + offset].order = key;
          rekeyed.push({ ...rest[s + 1 + offset] });
        });
      } else {
        return Ordering.rebalance(moving, p, rest);
      }
    }

    const prev = p > 0 ? rest[p - 1].order : null;
    const next = p < rest.length ? rest[p].order : null;
    const keys = tryKeys(prev, next, moving.length);
    if (!keys || !fits(keys)) return Ordering.rebalance(moving, p, rest);
    return [...rekeyed, ...moving.map((id, i) => ({ id, order: keys[i] }))];
  },

  append(moving: EntityID[], items: OrderedItem[]): OrderedItem[] {
    return Ordering.place(moving, "bottom", items);
  },

  /** Fresh, short, evenly spaced keys for the whole sequence in its new order (spec §3 "Rebalance"). */
  rebalance(moving: EntityID[], p: number, rest: OrderedItem[]): OrderedItem[] {
    const ids = rest.map((r) => r.id);
    ids.splice(p, 0, ...moving);
    const keys = tryKeys(null, null, ids.length) ?? [];
    const old = new Map<EntityID, string>();
    for (const r of rest) if (!old.has(r.id)) old.set(r.id, r.order);
    const movingSet = new Set(moving);
    const out: OrderedItem[] = [];
    const n = Math.min(ids.length, keys.length);
    for (let i = 0; i < n; i++) {
      const id = ids[i];
      if (movingSet.has(id) || old.get(id) !== keys[i]) out.push({ id, order: keys[i] });
    }
    return out;
  },
};
