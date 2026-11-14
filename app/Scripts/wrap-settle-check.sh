#!/bin/bash
# Wrap settle check (the user, 2026-11-08: "the line wrapping is a bit distracting when it animates for the whole
# duration, and it's choppy when more lines are needed"): while the detail pane or the sidebar slides, the list pane's
# notes must re-wrap at most once, and the rows under them must move on a spring, not jump a line in one frame.
# Launches the Debug app in the background (open -g, its own data folder, demo data, no server), opens PHYS 122 (a
# list with notes) at 1100x760, then opens and closes the detail pane and hides and shows the sidebar, recording every
# turn of the run loop (`act:wraptrace`, so it runs with the screen locked). Fails if, in any of the four, the notes
# take more than two widths or two heights, or the first row's drawn place moves more than 12pt between two turns.
# The large title wraps the same way (§23), so its field may take two widths and two heights too. And the one re-wrap
# comes as the slide starts, not after it (the user, 2026-11-08: "there's definitely a delay in the wrap, which i dont
# quite like, it should be smooth"): fails if the notes or the title last change width more than 50 ms after the pane
# first moves.
#
# The detail pane's text keeps the same rule (the user, 2026-11-14: "we need to do the same on detail"). A second run
# gives PHYS 122 a task whose title and notes wrap, shows it in the detail pane and records (`act:detailtrace`) every
# animated change of that pane's width: a zoom in and out, the sidebar hiding and showing under a zoomed pane and
# under a narrow window's drill-in, the pane's width springing out and back (a divider's double-click), and a zoomed
# pane closing; then a deleted list shown in the detail pane, zoomed in and out. Fails if the title or the notes are
# wrapped at more than two widths or two heights, if the notes' top (what's under the title) moves more than 12pt
# in a frame (16.7 ms; a turn that took longer is allowed as many), or if the last re-wrap is more than 50 ms after
# the pane first moves. A closing pane keeps the wrap it has: one width. And with the caret in the notes (a
# selection), then in the title, a zoom in and out keeps it there the whole way.
#
#   xcodebuild -project Tasks.xcodeproj -scheme Tasks -derivedDataPath .build/DerivedData build   # the Debug app
#   app/Scripts/wrap-settle-check.sh            # KEEP=1 keeps the traces (the folder is printed)
#   ONLY=list|detail app/Scripts/wrap-settle-check.sh   # one of the two runs
set -u
APP="${APP:-$(cd "$(dirname "$0")/.." && pwd)/.build/DerivedData/Build/Products/Debug/Tasks Dev.app}"
[ -d "$APP" ] || { echo "no Debug app at $APP" >&2; exit 1; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/tasks-wrap-settle-check.XXXXXX")
[ -n "${KEEP:-}" ] || trap 'rm -rf "$WORK"' EXIT
ONLY="${ONLY:-}"

# Runs the steps in a fresh copy of the app (the default pane widths, whatever the Debug app has stored) and waits
# for it to quit; a run that hangs is stopped after two minutes.
run() {
    local data="$WORK/data-$1" n=0
    mkdir -p "$data"
    open -g -n "$APP" --args -dataDirectory "$data" -demoData YES -serverURL http://127.0.0.1:9 -syncToken none \
      -sidebarWidth 230 -detailWidth 420 -debugScript "$2;wait:300"
    sleep 2
    while pgrep -f "MacOS/Tasks Dev -dataDirectory $data" >/dev/null; do
        sleep 0.5
        n=$((n + 1))
        if [ $n -gt 240 ]; then echo "FAIL $1: the app didn't finish" >&2; pkill -f "MacOS/Tasks Dev -dataDirectory $data"; break; fi
    done
}

if [ "$ONLY" != detail ]; then
    STEPS="size:1100,760;act:go:PHYS 122;wait:600;act:select:Read chapter 15 · oscillations;wait:400"
    for step in open:detail close:detail hide:sidebar show:sidebar; do
        name=${step%%:*} what=${step#*:}
        if [ "$what" = detail ]; then go="act:detail"; else go="sidebar"; fi
        STEPS+=";act:wraptrace:800:$WORK/$name.txt;$go;wait:900"
    done
    run list "$STEPS"
fi

if [ "$ONLY" != list ]; then
    TITLE="Write up the oscillations lab with every figure regenerated from the raw data and the damping fit redone"
    NOTES="The damped fit drifts after the fourth period, so regenerate every figure from the raw CSV before writing anything, and say which runs were dropped and why.\n\n- [ ] Redo the damping fit with the first four periods only and compare the residuals\n- [ ] Ask Priya whether the photogate timings were logged in milliseconds or in samples\n\nThe report is one PDF per pair on Crowdmark, due Friday at 11:59 pm."
    STEPS="size:1100,760;act:go:PHYS 122;wait:500;mktask:$TITLE|$NOTES;wait:400;act:select:$TITLE;wait:300;act:detail;wait:900"
    t() { STEPS+=";act:detailtrace:800:$WORK/detail-$1.txt;$2;wait:900"; }
    t zoom-in act:zoom
    t zoomed-hide-sidebar sidebar
    t zoomed-show-sidebar sidebar
    t zoom-out act:zoom
    t width-out act:springwidth:560
    t width-back act:springwidth:420
    STEPS+=";dcaret:40,120;wait:300"
    t notes-caret-zoom-in act:zoom
    t notes-caret-zoom-out act:zoom
    STEPS+=";act:commit;wait:200;focusdetail;wait:200;key:36;wait:400"
    t title-caret-zoom-in act:zoom
    t title-caret-zoom-out act:zoom
    STEPS+=";act:commit;wait:200"
    STEPS+=";size:860,760;wait:500"
    t narrow-hide-sidebar sidebar
    t narrow-show-sidebar sidebar
    STEPS+=";size:1100,760;wait:500;act:zoom;wait:900"
    t close-zoomed close
    STEPS+=";act:deletelist:PHYS 122;wait:300;act:go:Trash;wait:400;act:selectlist:PHYS 122;wait:300;act:detail;wait:900"
    t list-zoom-in act:zoom
    t list-zoom-out act:zoom
    run detail "$STEPS"
fi

[ -n "${KEEP:-}" ] && echo "traces: $WORK"
python3 -I - "$WORK" "$ONLY" <<'PY'
import os, re, sys
work, only = sys.argv[1], sys.argv[2]
ok = True

def runs(values):
    """The values in order, without repeats in a row."""
    out = []
    for v in values:
        if not out or out[-1] != v: out.append(v)
    return out

for name in ([] if only == "detail" else ["open", "close", "hide", "show"]):
    path = os.path.join(work, f"{name}.txt")
    if not os.path.exists(path):
        print(f"FAIL {name}: no frames"); ok = False; continue
    panes, widths, heights, ys, titles = [], [], [], [], []
    moved_at, wrapped_at, last_wrap = None, None, None
    for line in open(path):
        m = re.search(r"^([\d.]+)\s+wrap pane=(\d+) notes=(\d+)x(\d+) settle=\S+ firstRow=([-\d.]+)", line)
        if not m:
            continue
        t, p, w, h, y = float(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)), float(m.group(5))
        tm = re.search(r"title=(\d+)x", line)
        wrap = (w, tm.group(1) if tm else None)
        if panes and p != panes[0] and moved_at is None: moved_at = t
        if last_wrap is not None and wrap != last_wrap: wrapped_at = t
        last_wrap = wrap
        panes.append(p)
        if not widths or widths[-1] != w: widths.append(w)
        if not heights or heights[-1] != h: heights.append(h)
        ys.append(y)
        t = re.search(r"title=(\d+)x(\d+)", line)
        if t and (not titles or titles[-1] != t.groups()): titles.append(t.groups())
    step = max((abs(b - a) for a, b in zip(ys, ys[1:])), default=0)
    moved = len(set(panes)) > 2
    tw, th = len({w for w, _ in titles}), len({h for _, h in titles})
    lag = (wrapped_at - moved_at) if wrapped_at is not None and moved_at is not None else None
    good = moved and len(widths) <= 2 and len(heights) <= 2 and step <= 12 and 0 < tw <= 2 and th <= 2 \
        and (lag is None or lag <= 0.05)
    print(f"{'ok  ' if good else 'FAIL'} {name}: pane {panes[0] if panes else '-'}>{panes[-1] if panes else '-'} over"
          f" {len(set(panes))} widths; notes widths {widths[:8]}{'…' if len(widths) > 8 else ''} ({len(widths)}),"
          f" heights {heights} ; first row's biggest step {step:.1f}pt; title {tw} widths, {th} heights;"
          f" re-wrap {'-' if lag is None else f'{lag * 1000:+.0f} ms'} after the pane moved")
    ok &= good

# The detail pane: `detail pane=W title=WxH titleBox=… notes=WxH notesBox=… notesTop=Y`, or with a deleted list in it
# `detail pane=W hosted:  wrap pane=… notes=WxH settle=… firstRow=Y title=WxH` (the list's own line, as above).
DETAIL = ["zoom-in", "zoomed-hide-sidebar", "zoomed-show-sidebar", "zoom-out", "width-out", "width-back",
          "notes-caret-zoom-in", "notes-caret-zoom-out", "title-caret-zoom-in", "title-caret-zoom-out",
          "narrow-hide-sidebar", "narrow-show-sidebar", "close-zoomed", "list-zoom-in", "list-zoom-out"]
for name in ([] if only == "list" else DETAIL):
    path = os.path.join(work, f"detail-{name}.txt")
    if not os.path.exists(path):
        print(f"FAIL detail {name}: no frames"); ok = False; continue
    times, panes, titles, notes, tops, carets = [], [], [], [], [], []
    for line in open(path):
        m = re.search(r"^([\d.]+)\s+detail pane=(\d+)(.*)$", line)
        if not m:
            continue   # the pane is gone (closed)
        rest = m.group(3)
        hosted = "hosted:" in rest
        text = rest.split("hosted:")[1] if hosted else rest
        tm, nm = re.search(r" title=(\d+)x(\d+)", text), re.search(r" notes=(\d+)x(\d+)", text)
        ym = re.search(r" firstRow=([-\d.]+)" if hosted else r" notesTop=([-\d.]+)", text)
        if not (tm and nm and ym):
            continue
        times.append(float(m.group(1))); panes.append(int(m.group(2)))
        titles.append(tm.groups()); notes.append(nm.groups()); tops.append(float(ym.group(1)))
        # The caret: in the notes (`caret=`), or in the title (its field editor's `sel=`).
        carets.append(" caret=" in rest if name.startswith("notes-caret") else " sel=" in rest)
    if not times:
        print(f"FAIL detail {name}: no frames"); ok = False; continue
    moved_at = next((t for t, p in zip(times, panes) if p != panes[0]), None)
    wraps = list(zip(titles, notes))
    wrapped_at = max((t for t, a, b in zip(times[1:], wraps, wraps[1:]) if a != b), default=None)
    lag = (wrapped_at - moved_at) if wrapped_at is not None and moved_at is not None else None
    tw, th = runs(w for w, _ in titles), runs(h for _, h in titles)
    nw, nh = runs(w for w, _ in notes), runs(h for _, h in notes)
    # Per frame: a turn that took two frames may move what two frames would.
    step = max((abs(b - a) / max(1, (t1 - t0) / 0.0167) for a, b, t0, t1 in zip(tops, tops[1:], times, times[1:])), default=0)
    most = 1 if name == "close-zoomed" else 2
    caret = all(carets) if "-caret-" in name else True
    good = len(set(panes)) > 2 and all(len(v) <= most for v in (tw, th, nw, nh)) and step <= 12 \
        and (lag is None or lag <= 0.05) and caret
    short = lambda v: f"{'>'.join(v[:6])}{'…' if len(v) > 6 else ''} ({len(v)})"
    print(f"{'ok  ' if good else 'FAIL'} detail {name}: pane {panes[0]}>{panes[-1]} over {len(set(panes))} widths;"
          f" title wrapped at {short(tw)}, heights {short(th)}; notes at {short(nw)}, heights {short(nh)};"
          f" biggest step under the title {step:.1f}pt a frame;"
          f" re-wrap {'-' if lag is None else f'{lag * 1000:+.0f} ms'} after the pane moved"
          + ("" if "-caret-" not in name else "; the caret stayed" if caret else "; the caret was lost"))
    ok &= good
print("ok: the notes and the title wrap once, as the slide starts, and the rows glide" if ok else "FAIL")
sys.exit(0 if ok else 1)
PY
