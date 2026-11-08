#!/bin/bash
# Drop landing check (design/DECLARATIVE-DRAGGING.md, borrow 2): a drag's preview must be the layout of the state its
# drop writes, so the dropped row lands where the gap was and nothing else moves. Launches the Debug app in the
# background (open -g, its own data folder, demo data, no server) and runs `act:dropcheck` (Support/DebugDropCheck.swift)
# in Today, Upcoming, Undated and three lists, PHYS 122 with its headings open and with Labs, then Lectures, collapsed:
# every row that drags (a task, a heading's section, two selected tasks apart) onto every slot or day, written, laid
# out as the landing renders it, compared, and undone. No pointer and no frames: it reads the layouts.
#
#   xcodebuild -project Tasks.xcodeproj -scheme Tasks -derivedDataPath .build/DerivedData build   # the Debug app
#   app/Scripts/drop-landing-check.sh            # prints the failures and a summary per view; exits 1 on any
#   KEEP=/path.txt app/Scripts/drop-landing-check.sh   # also keeps the output there
set -u
APP="${APP:-$(cd "$(dirname "$0")/.." && pwd)/.build/DerivedData/Build/Products/Debug/Tasks Dev.app}"
[ -d "$APP" ] || { echo "no Debug app at $APP" >&2; exit 1; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/tasks-drop-landing-check.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
OUT="$WORK/out.txt"

STEPS="size:900,700"
for v in Today Upcoming Undated School Errands "PHYS 122"; do
  STEPS+=";act:go:$v;wait:300;act:dropcheck:$OUT"
done
# Collapsed headings (§23): a drop right under one folds the task into its section. Each is opened again after.
STEPS+=";act:collapse:Labs;wait:300;act:dropcheck:$OUT;act:collapse:Labs"
STEPS+=";act:collapse:Lectures;wait:300;act:dropcheck:$OUT;act:collapse:Lectures;wait:300"

mkdir -p "$WORK/data"
open -g -n "$APP" --args -dataDirectory "$WORK/data" -demoData YES -serverURL http://127.0.0.1:9 -syncToken none \
  -debugScript "$STEPS"
sleep 2
while pgrep -f "MacOS/Tasks Dev -dataDirectory $WORK/data" >/dev/null; do sleep 0.5; done

[ -s "$OUT" ] || { echo "FAIL: no output (did the app run the script?)"; exit 1; }
[ -n "${KEEP:-}" ] && cp "$OUT" "$KEEP"
cat "$OUT"
n=$(grep -c "^dropcheck .*: ok " "$OUT")
bad=$(grep -c "^FAIL\|^dropcheck .*: FAIL" "$OUT")
if [ "$n" -eq 8 ] && [ "$bad" -eq 0 ]; then echo "ok: every drop lands where its preview put it"; exit 0; fi
echo "FAIL: $bad failing lines, $n of 8 views ok"
exit 1
