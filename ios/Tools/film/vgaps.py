#!/usr/bin/env python3
"""vgaps.py <name> [window s] (in $FILM_DIR): for each FILM mark, the recorded video's frames in [mark, mark+window]: how
many, the frame rate while the screen changes, and every interval over 25 ms inside a run of changing frames (a
dropped frame: the simulator records a frame only when the screen changes; runs are split at gaps over 150 ms)."""
import sys, re, subprocess, os
D = os.environ.get("FILM_DIR", "/tmp/tasks-film")
name = sys.argv[1]; win = float(sys.argv[2]) if len(sys.argv) > 2 else 3.0
pts = f"{D}/{name}.pts"
if not os.path.exists(pts):
    open(pts, "w").write(subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "frame=pts_time",
                                          "-of", "csv=p=0", f"{D}/{name}.mov"], capture_output=True, text=True).stdout)
ts = [float(l.strip().strip(",")) for l in open(pts) if l.strip().strip(",")]
start = float(open(f"{D}/{name}.start").read())
for label, t in re.findall(r"FILM (.+) ([\d.]+)$", open(f"{D}/{name}.log").read(), re.M):
    v = float(t) - start
    w = [x for x in ts if v <= x <= v + win]
    d = [(b - a, b - v) for a, b in zip(w, w[1:])]
    drops = [(round(dt * 1000), round(at, 2)) for dt, at in d if 0.025 < dt <= 0.15]
    inrun = sum(dt for dt, _ in d if dt <= 0.15)
    n = sum(1 for dt, _ in d if dt <= 0.15)
    print(f"{label:22s} {len(w):4d} frames, {n / inrun if inrun else 0:5.1f} fps while changing; drops (ms@s) {drops}")
