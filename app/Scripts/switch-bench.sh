#!/bin/bash
# List-switch benchmark (SPEC §9: switching lists ≤ 1 frame to first rows). Builds an optimized app with the Debug
# hooks (bundle com.elguindi.Tasks.dev, its own data folder, local-only sync), fills a scratch data folder with the
# design-board demo data plus a 2,000-task list "Big", walks the sidebar ROUNDS times and prints, per transition, the
# median main-thread work (route change → update, layout and draw done) and the median latency (→ the first newly
# built row; "-" when every row was reused). Each switch is also a "switch" interval in Instruments' Points of
# Interest. Fails when any median work exceeds MAX_MS: a regression guard set just above today's worst (into the
# 2,000-task list), not the budget.
#
#   app/Scripts/switch-bench.sh [rounds]        MAX_MS=45 by default
set -eu
ROUNDS=${1:-8}
MAX_MS=${MAX_MS:-45}
APP_DIR=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/tasks-switch-bench.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

cd "$APP_DIR"
xcodebuild -project Tasks.xcodeproj -scheme Tasks -configuration Release -derivedDataPath .build/DerivedDataProfile \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG PRODUCT_BUNDLE_IDENTIFIER=com.elguindi.Tasks.dev PRODUCT_NAME="Tasks Dev" \
  build >/dev/null 2>&1 || { echo "build failed" >&2; exit 1; }
APP=".build/DerivedDataProfile/Build/Products/Release/Tasks Dev.app/Contents/MacOS/Tasks Dev"

# Never a real server: a dead local port.
"$APP" -dataDirectory "$WORK/data" -demoData YES -debugBulk 2000 -serverURL http://127.0.0.1:9 -syncToken none \
  -debugMeasureSwitch "$WORK/out.txt" -debugRounds "$ROUNDS" >/dev/null 2>&1

python3 - "$WORK/out.txt" "$MAX_MS" <<'PY'
import sys, collections, statistics
lat = collections.defaultdict(list); work = collections.defaultdict(list)
for line in open(sys.argv[1]):
    f = line.rstrip("\n").split("\t")
    lat[f[0]].append(float(f[1].split()[0])); work[f[0]].append(float(f[2].split()[0]))
limit = float(sys.argv[2]); worst = 0.0
print(f"{'switch':28s} {'work':>8s} {'latency':>8s}   (median ms; budget 16.7 per frame)")
for k in sorted(work):
    w = statistics.median(work[k]); worst = max(worst, w)
    seen = [x for x in lat[k] if x >= 0]
    l = f"{statistics.median(seen):8.1f}" if seen else "       -"
    print(f"{k:28s} {w:8.1f} {l}   {'within a frame' if w <= 16.7 else ''}")
if worst > limit:
    print(f"FAIL: worst median work {worst:.1f} ms > {limit:.0f} ms"); sys.exit(1)
print(f"ok: worst median work {worst:.1f} ms ≤ {limit:.0f} ms")
PY
