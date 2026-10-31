# Dates, round 2: the user's picks and the new exploration

## The user's picks on §24 (final)

- **Dates on a row: B, Quiet When.** The When is plain grey text, and only the Deadline is a badge.
- **Overdue cue: the checkbox ring turns red.** The user prefers this to the left-edge bar, so it's no longer "off".

Remove the unpicked variants for these two from the prototype, the canvas and the spec, and make the picks the defaults.

## Explore: cues that sit with the red overdue ring

Show two or three directions side by side, in dark and light, for:
1. **Due today** (the deadline is today). For example, an amber ring.
2. **When is today, seen in a list other than Today,** so you can tell from a list what's on today's plate. For example, an accent ring, a small dot, a filled ring or a tint.

Overdue, due today and when-today must be easy to tell apart, quiet, and not confused with selection, focus or a completed checkbox. Decide what happens when one task has several states at once (for example, when today and overdue): which wins. Also decide whether Today itself shows these cues.

## The wording (already explored, f718d70)

The user asked for relative dates under two weeks, and for compressed relative timing all the time; your Compact proposal covers the latter. Keep the Wording switch. Show the recommended wording together with the new cues on the boards, so the whole row can be judged at once.

Republish the same canvas, keep §24 proposed for the new parts, commit per path, and report back with your recommendations.

## Added: the user's wording for future deadlines

The user's words: "for future relative deadline wording, i want '13d left' (which is not including the day of the deadline). so then the day before the deadline says '1d left' and the deadline says 'today' or something. like that vibe."

- **Future deadline:** "Nd left", where N is the number of days from today until the deadline day.
  - The day before the deadline says "1d left".
  - The deadline day itself says "Today" (or similar; propose the exact word).
  - Never "0d left".
- **Overdue:** propose wording in the same vibe, such as "2d over", "2d late" or "2d ago", and recommend one.
- **Far-off deadlines:** say whether "Nd left" switches to weeks or months ("3w left", "2mo left"), and where. Show it.
- **The quiet When:** keep it consistent but distinct. It's a plan, not a countdown, so it probably shouldn't say "left". Propose the wording.
- **The tooltip** still gives the full date.

Make this the default Wording on the canvas, next to the earlier options.
