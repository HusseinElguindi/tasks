#!/usr/bin/env python3
"""landing.py <drag-trace.log> [all]: per drag in the app's -dragTrace log (CollectionDrag's DragProbe), the set-down
frame by frame, from the finger's lift: the copy's origin, opacity, shadow opacity and scale, the row cell's origin and
its content's opacity, and what UIKit showed outside the app's root view (its drop or cancel preview). Then: where
the copy ended against the row, the first frame the row showed and where the copy was then, and the frames UIKit drew
a preview in. With 'all', every frame of the drag, not just its landing."""
import sys, re
lines = open(sys.argv[1]).read().splitlines()
every = len(sys.argv) > 2 and sys.argv[2] == "all"
drags, cur = [], None
for l in lines:
    p = l.split(" ", 2)
    if len(p) < 2: continue
    kind, t, rest = p[0], float(p[1]), (p[2] if len(p) > 2 else "")
    if kind == "M" and rest.startswith("lift"):
        cur = {"t0": t, "ev": []}; drags.append(cur)
    if cur is not None: cur["ev"].append((kind, t, rest))

def kv(rest):
    d = {}
    for tok in rest.split(" "):
        if "=" in tok:
            k, v = tok.split("=", 1); d[k] = v
    return d

for n, d in enumerate(drags):
    ev = d["ev"]
    rel = next((t for k, t, r in ev if k == "M" and r.startswith("release")), None)
    landed = next((t for k, t, r in ev if k == "M" and r.startswith("landed")), None)
    print(f"\ndrag {n + 1}: lift at {d['t0']:.3f}")
    for k, t, r in ev:
        if k == "M" and (r.startswith("release") or r.startswith("landed")): print(f"  {t - (rel or d['t0']):+.3f}s {r}")
    if rel is None: print("  (no release)"); continue
    shown, ui_frames, prev = None, [], None
    print("     t      copy x,y        a    sh   sc  |  row y    ra  | uikit")
    ui = "none"
    for k, t, r in ev:
        if k == "M" and r.startswith("uikit "): ui = r[6:]; continue
        if k != "F": continue
        if not every and not (rel - 0.05 <= t <= (landed or rel) + 0.35): continue
        f = kv(r)
        c = f.get("copy", "").split(","); row = f.get("row", "").split(",")
        cs = f"{float(c[0]):6.1f},{float(c[1]):6.1f} {f['a']:>4} {f['sh']:>4} {f['sc']:>4}" if len(c) == 4 else " " * 31
        rs = f"{float(row[1]):6.1f} {f.get('ra', '-'):>4}" if len(row) == 2 else " " * 11
        print(f"  {t - rel:+.3f}  {cs} | {rs} | {ui}")
        if ui != "none" and t >= rel - 0.01: ui_frames.append(t - rel)
        if shown is None and f.get("ra") not in (None, "0.00") and t >= rel:
            shown = (t - rel, row, c)
    if shown:
        t, row, c = shown
        if len(c) == 4:
            print(f"  row shows at {t:+.3f}s at y {float(row[1]):.1f}; copy then at y {float(c[1]):.1f} (off {float(c[1]) - float(row[1]):+.1f})")
        else:
            print(f"  row shows at {t:+.3f}s at y {float(row[1]):.1f}; no copy then")
    print(f"  UIKit previews shown in {len(ui_frames)} frames after the release" + (f" ({ui_frames[0]:+.3f}s to {ui_frames[-1]:+.3f}s)" if ui_frames else ""))
