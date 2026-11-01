// A calendar day with no time and no zone, "YYYY-MM-DD": a port of TasksCore/CalendarDate.swift and the integer day
// arithmetic at the end of DatePhrase.swift. Fixed width (years 0000–9999), so dates compare correctly as strings.

export type CalendarDate = string;

export function daysIn(month: number, year: number): number {
  switch (month) {
    case 2:
      return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0 ? 29 : 28;
    case 4:
    case 6:
    case 9:
    case 11:
      return 30;
    default:
      return 31;
  }
}

const pad = (v: number, width: number) => String(v).padStart(width, "0");

/** The date for year/month/day, or null if it isn't a real date in years 0–9999. */
export function makeDate(year: number, month: number, day: number): CalendarDate | null {
  if (!Number.isInteger(year) || !Number.isInteger(month) || !Number.isInteger(day)) return null;
  if (year < 0 || year > 9999 || month < 1 || month > 12 || day < 1 || day > daysIn(month, year)) return null;
  return `${pad(year, 4)}-${pad(month, 2)}-${pad(day, 2)}`;
}

/** Exactly "YYYY-MM-DD" naming a real date (ASCII digits only). */
export function isCalendarDate(s: string): boolean {
  return parseCalendarDate(s) !== null;
}

export function parseCalendarDate(s: string): CalendarDate | null {
  if (s.length !== 10 || s[4] !== "-" || s[7] !== "-") return null;
  for (const i of [0, 1, 2, 3, 5, 6, 8, 9]) {
    const c = s.charCodeAt(i);
    if (c < 48 || c > 57) return null;
  }
  return makeDate(Number(s.slice(0, 4)), Number(s.slice(5, 7)), Number(s.slice(8, 10)));
}

export const yearOf = (d: CalendarDate) => Number(d.slice(0, 4));
export const monthOf = (d: CalendarDate) => Number(d.slice(5, 7));
export const dayOf = (d: CalendarDate) => Number(d.slice(8, 10));

/** Days since 1970-01-01 (H. Hinnant's days_from_civil). */
export function dayNumber(d: CalendarDate): number {
  const year = yearOf(d);
  const month = monthOf(d);
  const day = dayOf(d);
  const y = month <= 2 ? year - 1 : year;
  const era = Math.trunc((y >= 0 ? y : y - 399) / 400);
  const yoe = y - era * 400;
  const doy = Math.trunc((153 * (month > 2 ? month - 3 : month + 9) + 2) / 5) + day - 1;
  const doe = yoe * 365 + Math.trunc(yoe / 4) - Math.trunc(yoe / 100) + doy;
  return era * 146_097 + doe - 719_468;
}

/** The date `n` days after 1970-01-01; null outside years 0–9999. */
export function fromDayNumber(n: number): CalendarDate | null {
  const z = n + 719_468;
  const era = Math.trunc((z >= 0 ? z : z - 146_096) / 146_097);
  const doe = z - era * 146_097;
  const yoe = Math.trunc((doe - Math.trunc(doe / 1460) + Math.trunc(doe / 36524) - Math.trunc(doe / 146_096)) / 365);
  const doy = doe - (365 * yoe + Math.trunc(yoe / 4) - Math.trunc(yoe / 100));
  const mp = Math.trunc((5 * doy + 2) / 153);
  const month = mp < 10 ? mp + 3 : mp - 9;
  return makeDate(yoe + era * 400 + (month <= 2 ? 1 : 0), month, doy - Math.trunc((153 * mp + 2) / 5) + 1);
}

/** 0 = Sunday … 6 = Saturday. */
export const weekdayIndex = (d: CalendarDate) => (((dayNumber(d) + 4) % 7) + 7) % 7;

/** 1 = Sunday … 7 = Saturday (`CalendarDate.weekday`). */
export const weekday = (d: CalendarDate) => weekdayIndex(d) + 1;

export const offsetDays = (d: CalendarDate, days: number): CalendarDate | null => fromDayNumber(dayNumber(d) + days);

/** Whole days from `a` to `b` (positive when `b` is later). */
export const daysUntil = (a: CalendarDate, b: CalendarDate) => dayNumber(b) - dayNumber(a);
