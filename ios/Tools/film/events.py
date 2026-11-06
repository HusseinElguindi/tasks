#!/usr/bin/env python3
"""events.py <name> [filter]: for each FILM mark, the first burst of frames after it (video time)."""
import sys, re, subprocess, os
D = os.environ.get("FILM_DIR", "/tmp/tasks-film")
name = sys.argv[1]; filt = sys.argv[2] if len(sys.argv) > 2 else ""
mov = f"{D}/{name}.mov"; pts = f"{D}/{name}.pts"
if not os.path.exists(pts):
    open(pts, "w").write(subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "frame=pts_time",
                                          "-of", "csv=p=0", mov], capture_output=True, text=True).stdout)
ts = [float(l.strip().strip(",")) for l in open(pts) if l.strip().strip(",")]
start = float(open(f"{D}/{name}.start").read())
marks = re.findall(r"FILM (.+) ([\d.]+)$", open(f"{D}/{name}.log").read(), re.M)
for label, t in marks:
    if filt not in label: continue
    v = float(t) - start
    # the first frame after v that begins a burst (previous frame > 0.08 s before it)
    b = next((ts[i] for i in range(1, len(ts)) if ts[i] > v and ts[i] - ts[i - 1] > 0.08), None)
    print(f"{label:24s} mark {v:8.3f}  burst {b:8.3f}")
