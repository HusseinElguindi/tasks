#!/usr/bin/env python3
"""drag.py <spike log>: per drag (itemsForBeginning .. drop landed / drag didEnd), the gap's moves, the display link's
missed frames, each cell's biggest single-frame step (content coordinates; the dragged row excluded), and whether the
row landed where the gap was."""
import sys, re
ev = []
for l in open(sys.argv[1]).read().splitlines():
    p = l.split(" ", 2)
    if len(p) < 3: continue
    if p[0] == "M": ev.append(("M", float(p[1]), p[2]))
    elif p[0] == "F":
        cells = {}
        for tok in p[2].split(" "):
            if "@" not in tok: continue
            k, v = tok.split("@"); f = v.split(",")
            if len(f) < 3: continue   # copy@<y>: our lifted copy, not a cell
            if "H" in f[3:]: continue
            cells[k] = (float(f[0]), float(f[1]), float(f[2]))
        ev.append(("F", float(p[1]), cells))
starts = [i for i, e in enumerate(ev) if e[0] == "M" and e[2].startswith("drag itemsForBeginning")]
for n, i in enumerate(starts):
    t0 = ev[i][1]; who = ev[i][2].split()[2]
    j = next((k for k in range(i + 1, len(ev)) if ev[k][0] == "M" and (ev[k][2].startswith("drop landed"))), None)
    if j is None: j = next((k for k in range(i + 1, len(ev)) if ev[k][0] == "M" and ev[k][2].startswith("drag didEnd")), len(ev) - 1)
    end = ev[j][1] + 0.4
    seg = [e for e in ev[i:] if e[1] <= end]
    marks = [e for e in seg if e[0] == "M"]
    gaps = [m[2] for m in marks if m[2].startswith("gap slot")]
    moved = [float(re.search(r"in ([\d.]+)ms", m[2]).group(1)) for m in marks if m[2].startswith("gap moved")]
    skips = [(m[1] - t0, float(re.search(r"dt=([\d.]+)", m[2]).group(1))) for m in marks if m[2].startswith("skip")]
    lift = next((m[1] for m in marks if m[2].startswith("drag willBegin")), t0)
    drop = next((m for m in marks if m[2].startswith("drop t:") or m[2].startswith("drop h:")), None)
    lands = next((m for m in marks if m[2].startswith("drop lands")), None)
    fr = [e for e in seg if e[0] == "F" and e[1] >= lift]
    big, where = 0.0, ""
    steps = []
    for (_, ta, a), (_, tb, b) in zip(fr, fr[1:]):
        for k in a.keys() & b.keys():
            if k == who: continue
            if a[k][2] < 0.02 and b[k][2] < 0.02: continue
            d = b[k][0] - a[k][0]
            if abs(d) > abs(big): big, where = d, f"{k} at {tb - t0:.3f}s"
            if abs(d) > 0.05: steps.append(abs(d))
    print(f"\ndrag {who} at {t0:.3f}: {len(gaps)} gap moves; last {gaps[-1] if gaps else '-'}")
    if moved: print(f"  gap move cost: max {max(moved):.1f}ms, mean {sum(moved)/len(moved):.1f}ms")
    print(f"  missed frames after lift: {[f'{t:.2f}s:{d:.0f}ms' for t, d in skips if t >= lift - t0]}  (before lift: {len([s for s in skips if s[0] < lift - t0])})")
    print(f"  biggest single-frame step of another row: {big:+.1f}pt ({where}); steps >12pt: {sum(1 for s in steps if s > 12)}")
    if drop and lands:
        gy = float(re.search(r"gapY=([-\d.]+)", drop[2]).group(1)); ly = float(re.search(r"y=([-\d.]+)", lands[2]).group(1))
        print(f"  {drop[2].split(' wrote')[0]}  wrote={drop[2].split('wrote=')[1][:5]}  lands y={ly:.1f}  vs gap {gy:.1f}: {'exact' if abs(gy - ly) < 0.05 else 'OFF %.1f' % (ly - gy)}")
