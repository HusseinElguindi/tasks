#!/usr/bin/env python3
"""steps.py <name> <run> [steps...] (in $FILM_DIR, after `events.py <name> > <name>.ev`): per step, the video motion of the rows (rules > 300 and rings): the frames that
change, the biggest single-frame jump of any tracked line, and how long the motion lasts."""
import sys, subprocess, re, os
HERE = os.path.dirname(os.path.abspath(__file__))
name, run = sys.argv[1], sys.argv[2]
steps = sys.argv[3:] or ["addNotes", "done1", "editNotes", "done2", "tapNotes", "done3", "rename", "cancelRename"]
ev = {}
for l in open(f"{name}.ev"):
    p = l.split()
    if p[0] == run: ev[p[1]] = float(p[5])
for st in steps:
    b = ev.get(st)
    if b is None: continue
    out = subprocess.run(["python3", os.path.join(HERE, "sync.py"), f"{name}.mov", str(b - 0.15), "1.4"], capture_output=True, text=True).stdout
    fr = []
    for l in out.splitlines():
        t = float(l.split()[0]); rings = eval(re.search(r"rings (\[.*?\])", l).group(1)); rules = eval(re.search(r"rules (\[.*?\])", l).group(1))
        fr.append((t, [r for r in rules if r > 300], rings))
    # track the lowest ring (a row under the edited heading) frame to frame
    track = [(t, rg[-1] if rg else None) for t, _, rg in fr]
    moves = [(a[0], b2[1] - a[1]) for a, b2 in zip(track, track[1:]) if a[1] and b2[1] and abs(b2[1] - a[1]) > 0.2 and abs(b2[1] - a[1]) < 60]
    if moves:
        big = max(moves, key=lambda m: abs(m[1]))
        total = sum(m for _, m in moves)
        print(f"{st:13s} moved {total:+6.1f}pt in {len(moves):2d} frames over {moves[-1][0] - moves[0][0]:.3f}s  biggest step {big[1]:+.1f}pt")
    else:
        print(f"{st:13s} no motion of the rows below")
