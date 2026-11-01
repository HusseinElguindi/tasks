// What the date field reads as: a port of TasksCore/DatePhrase.swift (INTERACTIONS-v2 §11 "Typed dates"), and its
// DateLabel. Calendar-date arithmetic only: `today` is always passed in.
//
// Swift works on Characters (grapheme clusters) and compares strings by canonical equivalence. The port segments
// graphemes with Intl.Segmenter and NFC-normalizes the text once, which gives the same answers for this vocabulary.

import {
  dayNumber,
  daysIn,
  fromDayNumber,
  makeDate,
  monthOf,
  offsetDays,
  dayOf,
  weekdayIndex,
  yearOf,
  type CalendarDate,
} from "./calendar-date.ts";

export type NumericOrder = "monthFirst" | "dayFirst";

const segmenter = new Intl.Segmenter("en", { granularity: "grapheme" });
const chars = (s: string): string[] => Array.from(segmenter.segment(s), (x) => x.segment);

/** Character.isWhitespace looks at the first scalar only: " \u0301" (a space and a combining mark) is whitespace. */
const WHITESPACE = /^[\t\n\v\f\r \u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]/u;
const isSeparator = (c: string) => c === "," || c === "." || WHITESPACE.test(c);

/** Lowercased, commas and periods as spaces, runs of whitespace as one space, trimmed. */
function normalize(text: string): string {
  const words: string[] = [];
  let cur = "";
  for (const c of chars(text.toLowerCase())) {
    if (isSeparator(c)) {
      if (cur) words.push(cur);
      cur = "";
    } else cur += c;
  }
  if (cur) words.push(cur);
  return words.join(" ").normalize("NFC");
}

const isDigit = (c: string) => c.length === 1 && c >= "0" && c <= "9";
const isDigits = (s: string, min = 1, max = Infinity) => {
  const cs = chars(s);
  return cs.length >= min && cs.length <= max && cs.every(isDigit);
};
const isLetters = (s: string) => s.length > 0 && chars(s).every((c) => c.length === 1 && c >= "a" && c <= "z");

/** Swift's `Int(String)` on ASCII digits: nil past Int64. */
function toInt(digits: string): number | null {
  if (!/^[0-9]+$/.test(digits)) return null;
  const b = BigInt(digits);
  if (b > 9223372036854775807n) return null;
  return b > BigInt(Number.MAX_SAFE_INTEGER) ? Number.MAX_SAFE_INTEGER + 1 : Number(b);
}

/** The leading ASCII digits of a word (by Character). */
const leadingDigits = (word: string) => {
  let out = "";
  for (const c of chars(word)) {
    if (!isDigit(c)) break;
    out += c;
  }
  return out;
};

const PHRASES = ["today", "tomorrow", "this weekend", "next week", "next month",
  "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];

const NUMBER_WORDS: Record<string, number> = {
  a: 1, an: 1, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
};

const WEEKDAY_ABBREVIATIONS: Record<string, number> = {
  mon: 1, tue: 2, tues: 2, wed: 3, weds: 3, thu: 4, thur: 4, thurs: 4, fri: 5, sat: 6, sun: 0,
};

const UNITS = new Set(["d", "day", "days", "w", "wk", "wks", "week", "weeks", "mo", "mos", "month", "months", "m",
  "y", "yr", "yrs", "year", "years"]);

const ORDINAL_SUFFIXES = new Set(["", "st", "nd", "rd", "th"]);

const MAX_COUNT = 4_000_000;

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const WEEKDAYS_LOWER = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const MONTHS_LONG = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
  "October", "November", "December"];
const MONTHS_LOWER = MONTHS_LONG.map((m) => m.toLowerCase());

const own = (o: Record<string, number>, k: string) => (Object.hasOwn(o, k) ? o[k] : undefined);

const FIRST_DATE = "0000-01-01";
const LAST_DATE = "9999-12-31";

/** The next `weekday` (0 = Sunday) strictly after today: a week away when today is that day. */
function nextWeekday(weekday: number, today: CalendarDate): CalendarDate | null {
  const n = (weekday - weekdayIndex(today) + 7) % 7;
  return offsetDays(today, n === 0 ? 7 : n);
}

function weekendDay(today: CalendarDate): CalendarDate | null {
  const w = weekdayIndex(today);
  return w === 6 || w === 0 ? today : nextWeekday(6, today);
}

function addingMonths(n: number, date: CalendarDate): CalendarDate | null {
  const total = yearOf(date) * 12 + monthOf(date) - 1 + n;
  if (total < 0) return null;
  const year = Math.trunc(total / 12);
  const month = (total % 12) + 1;
  if (year > 9999) return null;
  return makeDate(year, month, Math.min(dayOf(date), daysIn(month, year)));
}

/** `(?:in\s+)?(\d+|a|an|one|…|ten)\s*(unit)` */
function countAndUnit(words: string[]): { count: string; unit: string } | null {
  let rest = words;
  if (rest.length > 1 && rest[0] === "in") rest = rest.slice(1);
  if (rest.length === 2) {
    const [count, unit] = rest;
    return (isDigits(count) || own(NUMBER_WORDS, count) !== undefined) && UNITS.has(unit) ? { count, unit } : null;
  }
  if (rest.length !== 1) return null;
  const word = rest[0];
  const digits = leadingDigits(word);
  if (digits) {
    const unit = word.slice(digits.length);
    return UNITS.has(unit) ? { count: digits, unit } : null;
  }
  for (const count of Object.keys(NUMBER_WORDS)) {
    if (word.startsWith(count) && UNITS.has(word.slice(count.length))) return { count, unit: word.slice(count.length) };
  }
  return null;
}

/** `(?:(next|this|on)\s+)?([a-z]+)` */
function qualifiedWord(words: string[]): { qualifier: string | null; word: string } | null {
  if (words.length === 1 && isLetters(words[0])) return { qualifier: null, word: words[0] };
  if (words.length === 2 && ["next", "this", "on"].includes(words[0]) && isLetters(words[1])) {
    return { qualifier: words[0], word: words[1] };
  }
  return null;
}

/** `(\d{1,2})(?:st|nd|rd|th)?` */
function dayOfMonth(word: string): number | null {
  const digits = leadingDigits(word);
  if (digits.length < 1 || digits.length > 2 || !ORDINAL_SUFFIXES.has(word.slice(digits.length))) return null;
  return Number(digits);
}

/** `(?:\s+(\d{2,4}))?`: undefined when the pattern fails, null when there's no year. */
function optionalYear(rest: string[]): string | null | undefined {
  if (rest.length === 0) return null;
  return rest.length === 1 && isDigits(rest[0], 2, 4) ? rest[0] : undefined;
}

function resolve(month: number, day: number, year: string | null, today: CalendarDate): CalendarDate | null {
  if (year !== null) {
    const y = Number(year);
    return makeDate(y < 100 ? y + 2000 : y, month, day);
  }
  const r = makeDate(yearOf(today), month, day);
  if (r === null) return null;
  return r < today ? makeDate(yearOf(today) + 1, month, day) : r;
}

/** 0 = Sunday … 6 = Saturday: a full name, an abbreviation, or a 2+ letter prefix of exactly one day. */
function weekdayNamed(word: string): number | null {
  const i = WEEKDAYS_LOWER.indexOf(word);
  if (i >= 0) return i;
  const a = own(WEEKDAY_ABBREVIATIONS, word);
  if (a !== undefined) return a;
  if (chars(word).length < 2) return null;
  const hits = WEEKDAYS_LOWER.map((d, k) => (d.startsWith(word) ? k : -1)).filter((k) => k >= 0);
  return hits.length === 1 ? hits[0] : null;
}

/** 1 = January … 12 = December, from a prefix of three or more letters. */
function monthNamed(word: string): number | null {
  if (chars(word).length < 3) return null;
  const i = MONTHS_LOWER.findIndex((m) => m.startsWith(word));
  return i >= 0 ? i + 1 : null;
}

function exact(s: string, today: CalendarDate, order: NumericOrder): CalendarDate | null {
  switch (s) {
    case "today": case "tod": case "tdy": case "toda": case "now":
      return today;
    case "tomorrow": case "tom": case "tmr": case "tmrw": case "tomo": case "tomor": case "tomorr": case "tomorro":
      return offsetDays(today, 1);
    case "yesterday": case "yest":
      return offsetDays(today, -1);
    case "weekend": case "wknd": case "this weekend": case "this wknd":
      return weekendDay(today);
    case "next weekend": {
      const w = weekdayIndex(today);
      const sat = nextWeekday(6, today);
      return sat === null ? null : offsetDays(sat, w === 6 || w === 0 ? 0 : 7);
    }
    case "next week": case "next wk":
      return nextWeekday(1, today);
    case "next month": case "next mo":
      return monthOf(today) === 12 ? makeDate(yearOf(today) + 1, 1, 1) : makeDate(yearOf(today), monthOf(today) + 1, 1);
  }
  const words = s.split(" ");

  const cu = countAndUnit(words);
  if (cu) {
    const n = own(NUMBER_WORDS, cu.count) ?? toInt(cu.count);
    if (n === null || n > MAX_COUNT) return null;
    switch (chars(cu.unit)[0]) {
      case "d": return offsetDays(today, n);
      case "w": return offsetDays(today, 7 * n);
      case "y": return addingMonths(12 * n, today);
      default: return addingMonths(n, today);
    }
  }
  if (words.length === 1 && words[0].startsWith("+") && isDigits(words[0].slice(1))) {
    const n = toInt(words[0].slice(1));
    if (n === null || n > MAX_COUNT) return null;
    return offsetDays(today, n);
  }
  const qw = qualifiedWord(words);
  if (qw) {
    const w = weekdayNamed(qw.word);
    if (w !== null) {
      if (qw.qualifier === "next") {
        const mon = nextWeekday(1, today);
        return mon === null ? null : offsetDays(mon, (w + 6) % 7);
      }
      return nextWeekday(w, today);
    }
  }
  if (words.length >= 2 && words.length <= 3 && isLetters(words[0])) {
    const day = dayOfMonth(words[1]);
    const year = optionalYear(words.slice(2));
    const month = day !== null && year !== undefined ? monthNamed(words[0]) : null;
    if (day !== null && year !== undefined && month !== null) return resolve(month, day, year, today);
  }
  if (words.length >= 2 && words.length <= 3) {
    const day = dayOfMonth(words[0]);
    if (day !== null && isLetters(words[1])) {
      const year = optionalYear(words.slice(2));
      const month = year !== undefined ? monthNamed(words[1]) : null;
      if (year !== undefined && month !== null) return resolve(month, day, year, today);
    }
  }
  if (words.length === 1) {
    const p = words[0].split("-");
    if (p.length === 3 && isDigits(p[0], 4, 4) && isDigits(p[1], 1, 2) && isDigits(p[2], 1, 2)) {
      return makeDate(Number(p[0]), Number(p[1]), Number(p[2]));
    }
  }
  if (words.length === 1) {
    const p = words[0].split("/");
    if (p.length >= 2 && p.length <= 3 && isDigits(p[0], 1, 2) && isDigits(p[1], 1, 2)) {
      const year = optionalYear(p.slice(2));
      if (year !== undefined) {
        const [a, b] = [Number(p[0]), Number(p[1])];
        return order === "monthFirst" ? resolve(a, b, year, today) : resolve(b, a, year, today);
      }
    }
  }
  if (words.length === 1 || (words.length === 2 && words[0] === "the")) {
    const day = dayOfMonth(words[words.length - 1]);
    if (day !== null) {
      if (day < 1 || day > 31) return null;
      for (let k = 0; k < 3; k++) {
        const total = yearOf(today) * 12 + monthOf(today) - 1 + k;
        const r = makeDate(Math.trunc(total / 12), (total % 12) + 1, day);
        if (r !== null && r >= today) return r;
      }
      return null;
    }
  }
  return null;
}

export const DatePhrase = {
  /** The exact reading of the whole text, null if it reads as no date. */
  parse(text: string, today: CalendarDate, order: NumericOrder = "monthFirst"): CalendarDate | null {
    const s = normalize(text);
    return s === "" ? null : exact(s, today, order);
  },

  /** What the text means while it's typed: the exact reading, else the first phrase that starts with it. */
  match(text: string, today: CalendarDate, order: NumericOrder = "monthFirst"): CalendarDate | null {
    const s = normalize(text);
    if (s === "") return null;
    const d = exact(s, today, order);
    if (d !== null) return d;
    const phrase = PHRASES.find((p) => p.startsWith(s));
    return phrase === undefined ? null : exact(phrase, today, order);
  },

  /** This Weekend: the coming Saturday, or today on a Saturday or Sunday. */
  weekend(today: CalendarDate): CalendarDate {
    return weekendDay(today) ?? LAST_DATE;
  },

  /** Next Week: the next Monday after today. */
  nextWeek(today: CalendarDate): CalendarDate {
    return nextWeekday(1, today) ?? LAST_DATE;
  },

  addingMonths(months: number, date: CalendarDate): CalendarDate {
    const n = Math.min(Math.max(months, -200_000), 200_000);
    return addingMonths(n, date) ?? (n < 0 ? FIRST_DATE : LAST_DATE);
  },
};

const daysTo = (a: CalendarDate, b: CalendarDate) => dayNumber(b) - dayNumber(a);
/** `Math.round(n / d)` for n ≥ 0. */
const rounded = (n: number, d: number) => Math.trunc((2 * n + d) / (2 * d));

function pastSpan(d: number, oneYear: string): string {
  if (d < 14) return `${d} days`;
  if (d < 60) return `${rounded(d, 7)} weeks`;
  if (d < 365) return `${rounded(d, 30)} months`;
  const y = rounded(d, 365);
  return y === 1 ? oneYear : `${y} years`;
}

/** How dates read in rows, the detail pane and the CLI (INTERACTIONS-v2 §24). */
export const DateLabel = {
  countdownDays: 14,

  whenChip(d: CalendarDate, today: CalendarDate): string {
    const n = daysTo(today, d);
    if (n <= 0) return "Today";
    if (n === 1) return "Tomorrow";
    if (n <= 14) return `in ${n}d`;
    return DateLabel.monthDayYear(d, today);
  },

  deadlineChip(d: CalendarDate, today: CalendarDate): { text: string; tone: "neutral" | "soon" | "due" | "late" } {
    const n = daysTo(today, d);
    if (n < 0) return { text: `${-n}d ago`, tone: "late" };
    if (n === 0) return { text: "Due today", tone: "due" };
    return { text: n <= 14 ? `${n}d left` : DateLabel.monthDayYear(d, today), tone: n === 1 ? "soon" : "neutral" };
  },

  deadlineWords(d: CalendarDate, today: CalendarDate): string {
    const n = daysTo(today, d);
    if (n < 0) return -n === 1 ? "1 day overdue" : pastSpan(-n, "1 year") + " overdue";
    if (n === 0) return "due today";
    if (n <= 14) return n === 1 ? "1 day left" : `${n} days left`;
    return DateLabel.relative(d, today);
  },

  tooltip(deadline: boolean, d: CalendarDate, today: CalendarDate): string {
    return (deadline ? "Deadline: " : "When: ") + DateLabel.long(d, today) + " · "
      + (deadline ? DateLabel.deadlineWords(d, today) : DateLabel.relative(d, today));
  },

  long(d: CalendarDate, today: CalendarDate): string {
    return WEEKDAYS[weekdayIndex(d)] + ", " + DateLabel.monthDayYear(d, today);
  },

  relative(d: CalendarDate, today: CalendarDate): string {
    const n = daysTo(today, d);
    if (n === 0) return "today";
    if (n === 1) return "tomorrow";
    if (n === -1) return "yesterday";
    if (n >= 2 && n <= 14) return `in ${n} days`;
    if (n >= 15 && n < 60) return `in ${rounded(n, 7)} weeks`;
    if (n >= 60 && n < 365) return `in ${rounded(n, 30)} months`;
    if (n >= 365) {
      const y = rounded(n, 365);
      return y === 1 ? "in a year" : `in ${y} years`;
    }
    return pastSpan(-n, "a year") + " ago";
  },

  monthDay(d: CalendarDate): string {
    return MONTHS[monthOf(d) - 1] + " " + String(dayOf(d));
  },

  monthTitle(year: number, month: number): string {
    return MONTHS_LONG[month - 1] + " " + String(year);
  },

  monthDayYear(d: CalendarDate, today: CalendarDate): string {
    return DateLabel.monthDay(d) + (yearOf(d) !== yearOf(today) ? ", " + String(yearOf(d)) : "");
  },
};

export { fromDayNumber };
