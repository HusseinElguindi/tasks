// String helpers that behave like the Swift and Foundation calls the CLI makes.

const segmenter = new Intl.Segmenter("en", { granularity: "grapheme" });

/** Swift Characters (grapheme clusters). */
export const chars = (s: string): string[] => Array.from(segmenter.segment(s), (x) => x.segment);
export const charCount = (s: string) => chars(s).length;
export const charPrefix = (s: string, n: number) => chars(s).slice(0, n).join("");

/** CharacterSet.whitespaces: tab and the Zs spaces. */
const WHITESPACES = "\t \u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u202f\u205f\u3000";
/** CharacterSet.whitespacesAndNewlines adds U+000A–U+000D, U+0085, U+2028, U+2029. */
const NEWLINES = "\n\u000b\u000c\r\u0085\u2028\u2029";

function trimSet(s: string, set: string): string {
  const cps = Array.from(s);
  let a = 0;
  let b = cps.length;
  while (a < b && set.includes(cps[a])) a++;
  while (b > a && set.includes(cps[b - 1])) b--;
  return cps.slice(a, b).join("");
}

export const trimWhitespaces = (s: string) => trimSet(s, WHITESPACES);
export const trimWhitespacesAndNewlines = (s: string) => trimSet(s, WHITESPACES + NEWLINES);

/** Case folding for Foundation's `.caseInsensitive` comparisons (an approximation of full case folding). */
const caseFold = (s: string) => s.normalize("NFD").toUpperCase().toLowerCase().normalize("NFD");

/** `a.compare(b, options: .caseInsensitive) == .orderedSame` */
export const equalsIgnoringCase = (a: string, b: string) => caseFold(a) === caseFold(b);

/** `.caseInsensitive, .diacriticInsensitive` search folding: decompose, drop combining marks, fold case. */
const searchFold = (s: string) => caseFold(s).replace(/\p{M}/gu, "");

/** `haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil` */
export const containsFolded = (haystack: string, needle: string) => searchFold(haystack).includes(searchFold(needle));

export const utf16Count = (s: string) => s.length;

/** Keeps a string within `limit` UTF-16 units, cutting on a Character boundary (`Store.clamp`). */
export function clamp(s: string, limit: number): string {
  if (s.length <= limit) return s;
  let out = "";
  for (const c of chars(s)) {
    if (out.length + c.length > limit) break;
    out += c;
  }
  return out;
}
