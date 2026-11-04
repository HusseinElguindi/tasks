#!/usr/bin/env python3
"""strip.py <mov> <out.png> t1 t2 ...: the frames nearest those times, side by side at 1/3 size, cropped to y0..y1 pt."""
import subprocess, sys, os
mov, out = sys.argv[1], sys.argv[2]
y0, y1 = int(os.environ.get("Y0", "250")), int(os.environ.get("Y1", "874"))
ts = [float(a) for a in sys.argv[3:]]
pts = [float(l.strip().strip(",")) for l in open(mov.rsplit(".", 1)[0] + ".pts") if l.strip().strip(",")]
ns = [min(range(len(pts)), key=lambda i: abs(pts[i] - t)) for t in ts]
expr = "+".join(f"eq(n,{n})" for n in ns)
subprocess.run(["ffmpeg", "-v", "error", "-i", mov, "-fps_mode", "passthrough", "-vf",
                f"select='{expr}',scale=402:874,crop=402:{y1-y0}:0:{y0},tile={len(ns)}x1:padding=4:color=red", "-frames:v", "1", "-y", out], check=True)
print([round(pts[n], 3) for n in ns])
