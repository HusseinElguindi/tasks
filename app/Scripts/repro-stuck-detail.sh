#!/bin/zsh
# The detail pane left on screen after it closed (T50, the user 2026-11-11: "the task details view doesn't close").
#
# + (a new task, which opens the pane), then Esc before the title has a name: the draft is dropped and the pane
# closes (`detailOpen` false). Sometimes SwiftUI never finishes removing it: the pane stays on screen, live, while
# `detailOpen` says it's closed, and every way to close it is a no-op (× and its Esc go through `closeDetail`, whose
# guard sees it closed; the list's Esc, with the pane "closed", clears the selection instead). It isn't the delay:
# some instances hit it on nearly every try, others never, so this runs several instances at once.
#
#   app/Scripts/repro-stuck-detail.sh [instances] [cycles]
#
# Each cycle prints the state after + Esc, after Esc in the list, after the × (`close`), and after Esc in the pane,
# with what's under a point inside where the pane would be (`TaskListDocument`: the list, so the pane is gone).
# Exits 1 if any cycle left the pane on screen with `detail=false`. Debug app only: sample data in a scratch folder,
# sync off. APP overrides the binary.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="${APP:-$ROOT/app/.build/DerivedData/Build/Products/Debug/Tasks Dev.app/Contents/MacOS/Tasks Dev}"
N=${1:-4}; CYCLES=${2:-8}
OUT=$(mktemp -d /tmp/repro-stuck-detail.XXXX)
TASK="Email TA about midterm regrade"
X=1100; Y=400   # inside the pane at 1300 wide (the pane is 420, from 872)

run() {
  local i=$1 d=$OUT/$1; mkdir -p $d/data
  local s="size:1300,800;wait:500"
  for c in $(seq 1 $CYCLES); do
    local ms=$(( (c * 37 + i * 11) % 200 ))
    s="$s;act:select:$TASK;newesc:$ms;wait:1000;log:$d/log.txt;hit:$X,$Y"
    s="$s;key:53;wait:600;log:$d/log.txt;hit:$X,$Y"
    s="$s;focusdetail;close;wait:800;log:$d/log.txt;hit:$X,$Y"
    s="$s;key:53;wait:600;log:$d/log.txt;hit:$X,$Y"
    # Clean up for the next cycle: Show then Hide Details takes a stuck pane back out.
    s="$s;act:detail;wait:700;act:detail;wait:900"
  done
  "$APP" -dataDirectory $d/data -serverURL "" -demoData YES -debugRoute list:School -debugScript "$s" > $d/stdout.txt 2>&1
}
for i in $(seq 1 $N); do run $i & done; wait

stuck=0
for i in $(seq 1 $N); do
  d=$OUT/$i
  paste -d' ' <(grep '^hit' $d/stdout.txt | awk '{print $4}' | cut -c1-24) \
              <(sed -E 's/ zoom=[a-z]+//; s/ draft=.*//; s/'"$TASK"'/task/' $d/log.txt) |
  awk -v i=$i 'BEGIN { split("after + Esc|Esc in the list|the ×|Esc in the pane", step, "|") }
    { n = (NR - 1) % 4 + 1; c = int((NR - 1) / 4) + 1
      gone = ($1 == "TaskListDocument")
      closed = ($0 ~ /detail=false/)
      verdict = (closed && !gone) ? "STUCK" : "ok"
      printf "instance %d cycle %d %-16s %-5s %s\n", i, c, step[n], verdict, $0 }' > $d/verdicts.txt
  cat $d/verdicts.txt
  grep -q STUCK $d/verdicts.txt && stuck=1
done
echo "logs: $OUT"
if (( stuck )); then echo "FAIL: the detail pane stayed on screen with detail=false"; exit 1; fi
echo "ok: no stuck pane in $N x $CYCLES cycles"
