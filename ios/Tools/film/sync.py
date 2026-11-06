#!/usr/bin/env python3
"""sync.py <mov> <start> <dur>: per frame, the heading rules (pt) and the tops of the task rings (pt) in the ring column."""
import subprocess, sys, os
mov, ss, dur = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
W, H, S = 1206, 2622, 3
pts = [float(l.strip().strip(",")) for l in open(mov.rsplit(".", 1)[0] + ".pts") if l.strip().strip(",")]
sel = [n for n, t in enumerate(pts) if ss <= t <= ss + dur]
p = subprocess.Popen(["ffmpeg", "-v", "error", "-i", mov, "-fps_mode", "passthrough", "-vf",
                      f"select='between(n,{sel[0]},{sel[-1]})',format=gray", "-f", "rawvideo", "-"], stdout=subprocess.PIPE)
xs = [int(W * f) for f in (0.2, 0.35, 0.5, 0.65)]
def rules(f):
    out, last = [], -99
    for y in range(300, H - 60):
        r = y * W; l = [f[r + x] for x in xs]; bg = f[r + 12]
        if all(abs(v - bg) >= 6 for v in l) and max(l) - min(l) <= 3:
            if y - last > 3: out.append(round(y / S, 1))
            last = y
    return out
def rings(f):
    # The ring's top arc at its centre column: a short bright run with dark under it, the next bright run ~21pt down.
    x = int(31 * S); runs = []; cur = None
    for y in range(300, H - 60):
        v = max(f[y * W + x - 1: y * W + x + 2])
        if v > 55:
            if cur is None: cur = [y, y]
            else: cur[1] = y
        elif cur is not None:
            runs.append(cur); cur = None
    tops = []
    for a in runs:
        if a[1] - a[0] > 3 * S: continue
        for b in runs:
            if 19 * S <= b[0] - a[0] <= 23 * S and b[1] - b[0] <= 3 * S: tops.append(round(a[0] / S, 1)); break
    return tops
for i, n in enumerate(sel):
    buf = p.stdout.read(W * H)
    if len(buf) < W * H: break
    print(f"{pts[n]:8.3f} rules {rules(buf)} rings {rings(buf)}")
