// "Today" in a time zone and the Today predicate: a port of TasksCore/Today.swift. The Mac uses its own calendar;
// the Worker uses the configured IANA zone through Intl (which carries full time zone data on Workers and Node).

import { makeDate, offsetDays, type CalendarDate } from "./calendar-date.ts";
import type { TaskItem, TaskList } from "./state.ts";

export interface Day {
  date: CalendarDate;
  /** Epoch ms of local midnight starting `date`. */
  start: number;
  /** Epoch ms of the next local midnight. */
  end: number;
}

const formatters = new Map<string, Intl.DateTimeFormat>();

function formatter(timeZone: string): Intl.DateTimeFormat {
  let f = formatters.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", {
      timeZone,
      hourCycle: "h23",
      year: "numeric",
      month: "numeric",
      day: "numeric",
      hour: "numeric",
      minute: "numeric",
      second: "numeric",
    });
    formatters.set(timeZone, f);
  }
  return f;
}

/** The wall clock at `ms` in `timeZone`. */
function wall(ms: number, timeZone: string) {
  const parts: Record<string, number> = {};
  for (const p of formatter(timeZone).formatToParts(new Date(ms))) {
    if (p.type !== "literal" && p.type !== "era") parts[p.type] = Number(p.value);
  }
  return { year: parts.year, month: parts.month, day: parts.day, hour: parts.hour, minute: parts.minute, second: parts.second };
}

/** The zone's offset from UTC at `ms`, in ms (whole seconds). */
function offsetAt(ms: number, timeZone: string): number {
  const w = wall(ms, timeZone);
  const asUTC = Date.UTC(w.year, w.month - 1, w.day, w.hour, w.minute, w.second);
  return asUTC - Math.floor(ms / 1000) * 1000;
}

/** The local calendar date of an instant. */
export function localDate(ms: number, timeZone: string): CalendarDate {
  const w = wall(ms, timeZone);
  return makeDate(w.year, w.month, w.day)!;
}

/**
 * The instant of a wall time in `timeZone`, as Foundation resolves it: in a fall-back overlap the earlier instant,
 * and in a spring-forward gap the wall time moved forward by the gap (the pre-gap offset applied).
 */
function instantOf(y: number, m: number, d: number, h: number, mi: number, sec: number, timeZone: string): number {
  const naive = Date.UTC(y, m - 1, d, h, mi, sec);
  const offsets = new Set<number>();
  for (const probe of [naive - 36 * 3600_000, naive - 12 * 3600_000, naive, naive + 12 * 3600_000, naive + 36 * 3600_000]) {
    offsets.add(offsetAt(probe, timeZone));
  }
  let best: number | null = null;
  for (const off of offsets) {
    const t = naive - off;
    const w = wall(t, timeZone);
    if (w.year === y && w.month === m && w.day === d && w.hour === h && w.minute === mi && w.second === sec) {
      if (best === null || t < best) best = t;
    }
  }
  return best ?? naive - Math.min(...offsets);
}

/** Local midnight starting `date` (or, where midnight is skipped, the first instant after the gap). */
export function startOfDay(date: CalendarDate, timeZone: string): number {
  return instantOf(Number(date.slice(0, 4)), Number(date.slice(5, 7)), Number(date.slice(8, 10)), 0, 0, 0, timeZone);
}

/**
 * `Day(containing:)`: the date, its start, and its end = `calendar.date(byAdding: .day, value: 1, to: start)`, the
 * same wall time a day later. That's the next midnight, except after a day whose midnight was skipped
 * (America/Santiago), where it's 01:00 and overlaps the next day by an hour, as in the app.
 */
export function dayContaining(nowMs: number, timeZone: string): Day {
  const date = localDate(nowMs, timeZone);
  const start = startOfDay(date, timeZone);
  const w = wall(start, timeZone);
  const next = offsetDays(date, 1)!;
  const end = instantOf(Number(next.slice(0, 4)), Number(next.slice(5, 7)), Number(next.slice(8, 10)), w.hour, w.minute, w.second, timeZone);
  return { date, start, end };
}

export const dayContains = (day: Day, ms: number) => ms >= day.start && ms < day.end;

/** The date half of the Today predicate: either date has arrived. A heading never arrives. */
export function datesArrived(t: TaskItem, today: CalendarDate): boolean {
  if (t.isHeading) return false;
  if (t.when !== null && t.when <= today) return true;
  if (t.deadline !== null && t.deadline <= today) return true;
  return false;
}

/** The Today predicate (spec §4). */
export function inToday(t: TaskItem, list: TaskList | undefined, day: Day): boolean {
  if (t.deleted || list === undefined || list.archivedAt !== null) return false;
  if (t.completedAt !== null && !dayContains(day, t.completedAt)) return false;
  return datesArrived(t, day.date);
}
