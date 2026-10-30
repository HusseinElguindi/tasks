#!/bin/bash
# End-to-end check (SPEC §10): real app instances with separate data directories against a local `wrangler dev`
# (never the deployed Worker). Each run launches the Debug app, which performs -debugActions through the Store,
# syncs, writes its state to JSON and quits. "Offline" is a dead port.
#
#   cd server && pnpm exec wrangler dev --port 8791 --persist-to /tmp/wrangler-state   # fresh state = empty log
#   app/Scripts/e2e.sh /tmp/tasks-e2e phase1    # two Macs, offline edits on both, a fresh third Mac
#   # restart wrangler dev with a new --persist-to directory: the server log is wiped
#   app/Scripts/e2e.sh /tmp/tasks-e2e phase2    # both Macs recover the log; a fresh fourth Mac sees everything
set -u
APP="${APP:-$(cd "$(dirname "$0")/.." && pwd)/.build/DerivedData/Build/Products/Debug/Tasks.app/Contents/MacOS/Tasks}"
E=$1
TOKEN="${TASKS_DEV_TOKEN:-$(sed -n "s/^API_TOKEN=//p" "$(cd "$(dirname "$0")/../.." && pwd)/server/.dev.vars")}"
GOOD="${TASKS_DEV_URL:-http://127.0.0.1:8791}"
DEAD=http://127.0.0.1:9
case "$GOOD" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "Refusing to run against $GOOD: the end-to-end check only talks to a local wrangler dev." >&2; exit 1 ;;
esac
run() { # dir url dump actions [extra args…]
  local dir=$1 url=$2 dump=$3 actions=$4; shift 4
  timeout 90 "$APP" -dataDirectory "$E/$dir" -serverURL "$url" -syncToken "$TOKEN" \
    -debugActions "$actions" -debugDumpTo "$E/$dump.json" "$@" >/dev/null 2>&1
  printf '%-4s %-3s pending=%s cursor=%s state=%s\n' "$dump" "$dir" "$(jq .pending "$E/$dump.json")" "$(jq .cursor "$E/$dump.json")" "$(jq -r .syncState "$E/$dump.json" | cut -c1-40)"
}
same() { # dumps… : visible states identical?
  local first=$(jq -S .visible "$E/$1.json" | shasum | cut -c1-12) ok=1
  for d in "$@"; do h=$(jq -S .visible "$E/$d.json" | shasum | cut -c1-12); [ "$h" = "$first" ] || ok=0; printf '  %s %s\n' "$d" "$h"; done
  [ $ok = 1 ] && echo "  => converged" || echo "  => DIVERGED"
}
case "${2:-phase1}" in
phase1)
  # Start from empty data directories, but only ever delete a directory this script made.
  if [ -e "$E" ] && [ ! -e "$E/.tasks-e2e" ]; then echo "$E exists and wasn't made by this script; pick a new path." >&2; exit 1; fi
  rm -rf "$E"; mkdir -p "$E"; touch "$E/.tasks-e2e"
  run A $GOOD A1 '[]' -demoData YES
  run B $GOOD B1 '[]'
  same A1 B1
  # Offline edits on A: reorder, archive, rename, create.
  run A $DEAD A2 '[{"reorder":"Print ECE 358 formula sheet","list":"School"},{"archive":"Errands"},{"rename":"Write sync log spec","to":"Write sync log spec v2"},{"createTask":"Offline on A","list":"Home","when":"today"}]'
  # Online edits on B, then more offline edits on B.
  run B $GOOD B2 '[{"createTask":"From B","list":"School"},{"complete":"Book flu shot"},{"reorder":"Water the plants","list":"Home","before":"Fix the bathroom fan"},{"move":"Look into a standing desk","to":"Tasks app"},{"reorderList":"Home"}]'
  run B $DEAD B3 '[{"rename":"Pick up prescription","to":"Pick up prescription (B offline)"},{"reorder":"Ask about co-op interview slots","list":"School"}]'
  # Both back online.
  run A $GOOD A3 '[]'
  run B $GOOD B4 '[]'
  run A $GOOD A4 '[]'
  # A fresh third instance syncing from 0 must match.
  run C $GOOD C1 '[]'
  same A4 B4 C1
  jq -c '{lists, today}' "$E/A4.json"
  ;;
phase2)
  # The server log was wiped (fresh wrangler dev state). Both instances recover it; a fresh one sees everything.
  run A $GOOD A5 '[]'
  run B $GOOD B5 '[]'
  run A $GOOD A6 '[]'
  run D $GOOD D1 '[]'
  same A4 A6 B5 D1
  ls "$E/A" "$E/B" | grep -c 'bak-' | sed 's/^/  backups left: /'
  ;;
esac
