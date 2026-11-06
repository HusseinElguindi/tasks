#!/bin/bash
# Upcoming drop check (the user, 2026-11-06: "a very wierd jump when movign tasks around"): a task dropped on another
# day in Upcoming must land where the copy flew, and stay. Launches the Debug app in the background (open -g, its own
# data folder, demo data, no server), drags a task up onto the day before and another down onto the day after, and
# traces every frame (`act:trace`). Fails if, once the dropped row shows, it is ever drawn anywhere but its final
# place: the bug drew it back on the day it left (the landing render read the old dates), then slid it to the gap.
#
#   xcodebuild -project Tasks.xcodeproj -scheme Tasks -derivedDataPath .build/DerivedData build   # the Debug app
#   app/Scripts/upcoming-drop-check.sh
set -u
APP="${APP:-$(cd "$(dirname "$0")/.." && pwd)/.build/DerivedData/Build/Products/Debug/Tasks Dev.app}"
[ -d "$APP" ] || { echo "no Debug app at $APP" >&2; exit 1; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/tasks-upcoming-drop-check.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# Demo data, today's Upcoming at 900x700: Tomorrow's label at y 46, its rows at 78, 110, 142 (Buy printer paper);
# Sunday's label at 174; Monday's at 270 with Make the midterm formula sheet at 302.
STEPS="size:900,700;act:go:Upcoming;wait:700"
# Up: Monday's task onto Sunday (it lands after Sunday's two rows).
STEPS+=";act:trace:2500:$WORK/up.txt;down:500,318;move:500,318,500,270,30;wait:400;up:500,270;wait:1500"
STEPS+=";act:rows:$WORK/rows-up.txt"
# Down: Tomorrow's last task onto Sunday (it lands after Sunday's rows, by list).
STEPS+=";act:trace:2500:$WORK/down.txt;down:500,158;move:500,158,500,250,30;wait:400;up:500,250;wait:1500"
STEPS+=";act:rows:$WORK/rows-down.txt"

mkdir -p "$WORK/data"
open -g -n "$APP" --args -dataDirectory "$WORK/data" -demoData YES -serverURL http://127.0.0.1:9 -syncToken none \
  -debugScript "$STEPS;wait:300"
sleep 2
while pgrep -f "MacOS/Tasks Dev -dataDirectory $WORK/data" >/dev/null; do sleep 0.5; done

python3 -I - "$WORK" <<'PY'
import os, re, sys
work = sys.argv[1]
ok = True
for name, title in [("up", "Make the midterm formula sheet"), ("down", "Buy printer paper")]:
    rows = open(os.path.join(work, f"rows-{name}.txt")).read().splitlines()
    final = next((int(l.split()[0]) for l in rows if f" {title} " in l + " "), None)
    when = next((re.search(r"when=(\S+)", l).group(1) for l in rows if f" {title} " in l + " "), None)
    seen, landed, wrong = False, None, []
    for line in open(os.path.join(work, f"{name}.txt")):
        t = line.split(" ", 1)[0]
        phase = re.search(r"drag=(\S+)", line).group(1)
        seen |= phase in ("drag", "fly")
        m = re.search(re.escape(title) + r"@(-?\d+)(/[\d.]+)?", line)
        if not seen or phase in ("drag", "fly") or not m or m.group(2):
            continue      # before the drop, or the row still hidden under the copy
        y = int(m.group(1))
        landed = landed or (t, y)
        if y != final:
            wrong.append(f"{t}s y {y}")
    moved = when is not None and when != {"up": "2026-11-09", "down": "2026-11-07"}[name]
    good = seen and landed is not None and moved and not wrong
    print(f"{'ok  ' if good else 'FAIL'} {name}: {title} when={when}, shown from {landed} at final y {final}"
          + (f"; drawn elsewhere: {', '.join(wrong[:6])}" if wrong else ""))
    ok &= good
print("ok: dropped rows land in place" if ok else "FAIL")
sys.exit(0 if ok else 1)
PY
