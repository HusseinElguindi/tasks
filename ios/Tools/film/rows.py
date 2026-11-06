#!/usr/bin/env python3
"""rows.py <mov> <start s> <dur s> [mode]: per frame, the hairlines (heading rules) and the ink blobs in the text column,
in points (3 px each). mode 'rules' (default) or 'blobs'."""
import subprocess, sys, re, os, tempfile
mov, ss, dur = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
mode = sys.argv[4] if len(sys.argv) > 4 else "rules"
W, H, S = 1206, 2622, 3
err = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
pts = mov.rsplit(".", 1)[0] + ".pts"
if not os.path.exists(pts):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "frame=pts_time", "-of", "csv=p=0", mov],
                         capture_output=True, text=True).stdout
    open(pts, "w").write(out)
idx = list(enumerate(float(l.strip().strip(",")) for l in open(pts) if l.strip().strip(",")))
sel = [n for n, t in idx if ss <= t <= ss + dur]
n0, n1 = (sel[0], sel[-1]) if sel else (0, -1)
p = subprocess.Popen(["ffmpeg", "-v", "info", "-i", mov, "-fps_mode", "passthrough",
                      "-vf", f"select='between(n,{n0},{n1})',showinfo,format=gray", "-f", "rawvideo", "-"], stdout=subprocess.PIPE, stderr=err)
frames = []
while True:
    buf = p.stdout.read(W * H)
    if len(buf) < W * H: break
    frames.append(buf)
p.wait(); err.close()
times = [t for n, t in idx if n0 <= n <= n1]
os.unlink(err.name)
xs = [int(W * f) for f in (0.2, 0.35, 0.5, 0.65)]
def rules(f):
    out, last = [], -99
    for y in range(300, H - 60):
        r = y * W
        l = [f[r + x] for x in xs]; bg = f[r + 12]
        if all(abs(v - bg) >= 6 for v in l) and max(l) - min(l) <= 3 and y - last > 3:
            out.append(round(y / S, 1)); last = y
        elif all(abs(v - bg) >= 6 for v in l) and max(l) - min(l) <= 3:
            last = y
    return out
def blobs(f, x0=int(54 * S), x1=int(110 * S), thr=40):
    """Rows with ink (bright pixels) between x0 and x1, grouped into blobs: (top, bottom, peak) in points."""
    out, cur = [], None
    for y in range(int(float(os.environ.get("BY0", "133")) * S), int(float(os.environ.get("BY1", "874")) * S)):
        r = y * W
        peak = max(f[r + x0:r + x1:2])
        if peak > thr:
            if cur is None: cur = [y, y, peak]
            else: cur[1] = y; cur[2] = max(cur[2], peak)
        elif cur is not None and y - cur[1] > 6:
            out.append((round(cur[0] / S), round(cur[1] / S), cur[2])); cur = None
    if cur: out.append((round(cur[0] / S), round(cur[1] / S), cur[2]))
    return out
prev = None
for t, f in zip(times, frames):
    if mode == "rules":
        v = rules(f)
    else:
        x0 = int(float(sys.argv[5]) * S) if len(sys.argv) > 5 else int(20 * S)
        x1 = int(float(sys.argv[6]) * S) if len(sys.argv) > 6 else int(110 * S)
        v = blobs(f, x0, x1)
    if v != prev: print(f"{t:8.3f}", v)
    prev = v
