#!/usr/bin/env python3
"""scroll.py <name> <mark> [window s] (in $FILM_DIR): the content's vertical motion in the video after a FILM mark, by
matching each frame's brightness profile (rows 140-820 pt, x 20-90%) to the previous one's. Prints the scroll distance,
the peak speed, when the motion stops, the time from peak speed to 10% of it (deceleration), and any overshoot (the
offset passing its final value and coming back: a rubber band)."""
import sys, re, subprocess, os
D = os.environ.get("FILM_DIR", "/tmp/tasks-film")
name, label = sys.argv[1], sys.argv[2]; win = float(sys.argv[3]) if len(sys.argv) > 3 else 2.8
W, H = 402, 874
pts = [float(l.strip().strip(",")) for l in open(f"{D}/{name}.pts") if l.strip().strip(",")]
start = float(open(f"{D}/{name}.start").read())
marks = dict(re.findall(r"FILM (.+) ([\d.]+)$", open(f"{D}/{name}.log").read(), re.M))
v = float(marks[label]) - start
sel = [n for n, t in enumerate(pts) if v <= t <= v + win]
p = subprocess.Popen(["ffmpeg", "-v", "error", "-i", f"{D}/{name}.mov", "-fps_mode", "passthrough", "-vf",
                      f"select='between(n,{sel[0]},{sel[-1]})',scale={W}:{H},format=gray", "-f", "rawvideo", "-"], stdout=subprocess.PIPE)
x0, x1, y0, y1 = int(W * 0.2), int(W * 0.9), 140, 820
def prof(b): return [sum(b[y * W + x0:y * W + x1:3]) / ((x1 - x0) / 3) for y in range(H)]
prev, off, out = None, 0.0, []
for n in sel:
    b = p.stdout.read(W * H)
    if len(b) < W * H: break
    pr = prof(b)
    if prev is not None:
        best, bs = None, 0
        for s in range(-220, 221):
            a, z = max(y0, y0 + s), min(y1, y1 + s)
            if z - a < 200: continue
            e = sum(abs(prev[y] - pr[y - s]) for y in range(a, z, 2)) / ((z - a) / 2)
            if best is None or e < best: best, bs = e, s
        off += bs   # content moved up by bs pt (scrolling down the list) since the last frame
    prev = pr
    out.append((pts[n] - v, off))
ys = [o for _, o in out]
final = ys[-1]
moving = [i for i in range(1, len(out)) if ys[i] != ys[i - 1]]
if not moving: print(f"{label}: no motion"); sys.exit()
t0, t1 = out[moving[0] - 1][0], out[moving[-1]][0]
sp = [(out[i][0], (ys[i] - ys[i - 1]) / max(out[i][0] - out[i - 1][0], 1e-3)) for i in range(1, len(out))]
pk = max(sp, key=lambda q: abs(q[1]))
dec = next((t for t, s in sp if t > pk[0] and abs(s) < abs(pk[1]) * 0.1), None)
# overshoot: the farthest the offset goes past its final value, against the direction it came from
direction = 1 if final - ys[0] >= 0 else -1
over = max(0.0, max(direction * (y - final) for y in ys)) if abs(final - ys[0]) > 20 else max(abs(y - final) for y in ys)
print(f"{label:16s} dist {final:+7.0f}pt  moves {t0:.2f}-{t1:.2f}s ({t1 - t0:.2f}s)  peak {pk[1]:+6.0f}pt/s at {pk[0]:.2f}s  "
      f"to 10% {dec - pk[0] if dec else float('nan'):.2f}s  overshoot {over:.0f}pt  frames {len(out)}")
if os.environ.get("CURVE"): print(" ".join(f"{t:.2f}:{o:.0f}" for t, o in out[::3]))
