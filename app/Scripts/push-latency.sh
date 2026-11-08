#!/bin/bash
# Push sync's end-to-end latency (design/PUSH-SYNC.md §3 Testing): two scratch Debug app instances against a local
# `wrangler dev` (never the deployed Worker). B runs hidden (no window visible, Settings ▸ Sync with no window open
# on); A is launched once per sample, creates a task through the Store, syncs and quits. Each sample is the time from
# A's push starting to B's sync ending at a cursor that has it, from the two -debugNudgeLog files. In the app an edit
# waits ~1 s before its push (Store.perform), on top of this.
#
#   cd server && pnpm exec wrangler dev --port 8797 --persist-to <dir>
#   app/Scripts/push-latency.sh <scratch dir> socket 8   # with the poke socket
#   app/Scripts/push-latency.sh <scratch dir> poll 8     # -debugNoSocket: polling only, as before
#
# APP overrides the app bundle, TASKS_DEV_URL the server, TASKS_DEV_TOKEN the token.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUNDLE="${APP:-$ROOT/app/.build/DerivedData/Build/Products/Debug/Tasks Dev.app}"
BIN="$BUNDLE/Contents/MacOS/Tasks Dev"
E=$1
MODE=${2:-socket}
N=${3:-6}
TOKEN="${TASKS_DEV_TOKEN:-$(sed -n "s/^API_TOKEN=//p" "$ROOT/server/.dev.vars")}"
GOOD="${TASKS_DEV_URL:-http://127.0.0.1:8797}"
case "$GOOD" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "Refusing to run against $GOOD: this check only talks to a local wrangler dev." >&2; exit 1 ;;
esac
if [ -e "$E" ] && [ ! -e "$E/.push-latency" ]; then echo "$E exists and wasn't made by this script; pick a new path." >&2; exit 1; fi
mkdir -p "$E"; touch "$E/.push-latency"
NOSOCKET=(); [ "$MODE" = poll ] && NOSOCKET=(-debugNoSocket YES)
BLOG="$E/B-$MODE.log"; : > "$BLOG"

# B: hidden, long-running.
open -n -g -j -a "$BUNDLE" --args -dataDirectory "$E/B" -serverURL "$GOOD" -syncToken "$TOKEN" \
  -syncWithoutWindow YES -debugNudgeLog "$BLOG" ${NOSOCKET[@]+"${NOSOCKET[@]}"}
for _ in $(seq 100); do grep -q "state idle" "$BLOG" 2>/dev/null && break; sleep 0.2; done
BPID=$(pgrep -f -- "-debugNudgeLog $BLOG" | head -1)
[ -n "$BPID" ] || { echo "B didn't start" >&2; exit 1; }
trap 'kill "$BPID" 2>/dev/null' EXIT
sleep 2

echo "mode=$MODE B=$BPID"
for i in $(seq "$N"); do
  ALOG="$E/A-$MODE-$i.log"; : > "$ALOG"
  timeout 60 "$BIN" -dataDirectory "$E/A" -serverURL "$GOOD" -syncToken "$TOKEN" -debugNudgeLog "$ALOG" \
    -debugActions "[{\"createTask\":\"Probe $MODE $i\"}]" -debugDumpTo "$E/A-$MODE-$i.json" ${NOSOCKET[@]+"${NOSOCKET[@]}"} >/dev/null 2>&1
  CUR=$(jq .cursor "$E/A-$MODE-$i.json")
  T0=$(awk '/state syncing/ { print $1; exit }' "$ALOG")
  # B's first sync, after A's push, that ends with A's op (cursor ≥ A's).
  T1=""
  for _ in $(seq 900); do
    T1=$(awk -v t0="$T0" -v cur="$CUR" '$1 >= t0 && /state idle/ { split($4, c, "="); if (c[2] + 0 >= cur + 0) { print $1; exit } }' "$BLOG")
    [ -n "$T1" ] && break
    sleep 0.1
  done
  if [ -z "$T1" ]; then echo "  $i: B never synced to cursor $CUR"; continue; fi
  awk -v a="$T0" -v b="$T1" -v i="$i" -v cur="$CUR" 'BEGIN { printf "  %d: cursor %d  %.3f s\n", i, cur, b - a }'
  # The next sample lands at a random point in B's poll cycle.
  sleep $((RANDOM % 12 + 3))
done
