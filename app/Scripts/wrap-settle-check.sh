#!/bin/bash
# Wrap settle check (the user, 2026-11-08: "the line wrapping is a bit distracting when it animates for the whole
# duration, and it's choppy when more lines are needed"): while the detail pane or the sidebar slides, the list pane's
# notes must re-wrap at most once, and the rows under them must move on a spring, not jump a line in one frame.
# Launches the Debug app in the background (open -g, its own data folder, demo data, no server), opens PHYS 122 (a
# list with notes) at 1100x760, then opens and closes the detail pane and hides and shows the sidebar, recording every
# turn of the run loop (`act:wraptrace`, so it runs with the screen locked). Fails if, in any of the four, the notes
# take more than two widths or two heights, or the first row's drawn place moves more than 12pt between two turns.
#
#   xcodebuild -project Tasks.xcodeproj -scheme Tasks -derivedDataPath .build/DerivedData build   # the Debug app
#   app/Scripts/wrap-settle-check.sh            # KEEP=1 keeps the traces (the folder is printed)
set -u
APP="${APP:-$(cd "$(dirname "$0")/.." && pwd)/.build/DerivedData/Build/Products/Debug/Tasks Dev.app}"
[ -d "$APP" ] || { echo "no Debug app at $APP" >&2; exit 1; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/tasks-wrap-settle-check.XXXXXX")
[ -n "${KEEP:-}" ] || trap 'rm -rf "$WORK"' EXIT
STEPS="size:1100,760;act:go:PHYS 122;wait:600;act:select:Read chapter 15 · oscillations;wait:400"
for step in open:detail close:detail hide:sidebar show:sidebar; do
    name=${step%%:*} what=${step#*:}
    if [ "$what" = detail ]; then go="act:detail"; else go="sidebar"; fi
    STEPS+=";act:wraptrace:800:$WORK/$name.txt;$go;wait:900"
done

mkdir -p "$WORK/data"
open -g -n "$APP" --args -dataDirectory "$WORK/data" -demoData YES -serverURL http://127.0.0.1:9 -syncToken none \
  -debugScript "$STEPS;wait:300"
sleep 2
while pgrep -f "MacOS/Tasks Dev -dataDirectory $WORK/data" >/dev/null; do sleep 0.5; done

[ -n "${KEEP:-}" ] && echo "traces: $WORK"
python3 -I - "$WORK" <<'PY'
import os, re, sys
work = sys.argv[1]
ok = True
for name in ["open", "close", "hide", "show"]:
    path = os.path.join(work, f"{name}.txt")
    if not os.path.exists(path):
        print(f"FAIL {name}: no frames"); ok = False; continue
    panes, widths, heights, ys = [], [], [], []
    for line in open(path):
        m = re.search(r"wrap pane=(\d+) notes=(\d+)x(\d+) settle=\S+ firstRow=([-\d.]+)", line)
        if not m:
            continue
        p, w, h, y = int(m.group(1)), int(m.group(2)), int(m.group(3)), float(m.group(4))
        panes.append(p)
        if not widths or widths[-1] != w: widths.append(w)
        if not heights or heights[-1] != h: heights.append(h)
        ys.append(y)
    step = max((abs(b - a) for a, b in zip(ys, ys[1:])), default=0)
    moved = len(set(panes)) > 2
    good = moved and len(widths) <= 2 and len(heights) <= 2 and step <= 12
    print(f"{'ok  ' if good else 'FAIL'} {name}: pane {panes[0] if panes else '-'}>{panes[-1] if panes else '-'} over"
          f" {len(set(panes))} widths; notes widths {widths[:8]}{'…' if len(widths) > 8 else ''} ({len(widths)}),"
          f" heights {heights} ; first row's biggest step {step:.1f}pt")
    ok &= good
print("ok: the notes wrap once and the rows glide" if ok else "FAIL")
sys.exit(0 if ok else 1)
PY
