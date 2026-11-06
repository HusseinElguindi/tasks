#!/usr/bin/env python3
"""edits.py <trace> [--log <film>.log --start <film>.start] [--all | --moves] [--jump N]: the edit trace
(-editTrace YES, ios/Tasks/App/EditProbe.swift: tmp/edit-trace.log in the app's container) per frame, with each
quantity's step from the frame before; its marks, and with --log the film's FILM marks, in video time (--start).
Prints the frames with a step over N pt (default 6) in what's on screen (the list's offset as drawn, the row's top and
height, the next row, the editor's top, the drawn caret), or every frame that moved (--moves), or all (--all).
The trace samples on the app's main thread, so a frame hole there shows as a big step that the video (rows.py) may draw
smoothly: check flagged steps against the film."""
import sys, re
path = sys.argv[1]
show_all = "--all" in sys.argv
J = float(sys.argv[sys.argv.index("--jump") + 1]) if "--jump" in sys.argv else 6.0
def num(s):
    try: return float(s)
    except: return None
rows = []
t0 = None
if "--log" in sys.argv:
    for m in re.finditer(r"FILM (\S+) ([\d.]+)$", open(sys.argv[sys.argv.index("--log") + 1]).read(), re.M):
        rows.append(("M", float(m.group(2)), "FILM " + m.group(1)))
for line in open(path):
    line = line.rstrip("\n")
    if line.startswith("M "):
        _, t, rest = line.split(" ", 2)
        rows.append(("M", float(t), rest)); continue
    if not line.startswith("F "): continue
    t = float(line.split()[1])
    d = {}
    m = re.search(r"off=([-\d.]+)/([-\d.]+)", line); d["off"], d["offm"] = num(m.group(1)), num(m.group(2))
    m = re.search(r"ins=([-\d.]+)", line); d["ins"] = num(m.group(1))
    m = re.search(r"cell=([-\d.]+),([-\d.]+) \(([-\d.]+),([-\d.]+)\)", line)
    if m: d["cell"], d["cellh"], d["cellm"], d["cellhm"] = map(num, m.groups())
    m = re.search(r"next=([-\d.]+)", line); d["next"] = num(m.group(1)) if m else None
    m = re.search(r"tv=([-\d.]+),([-\d.]+) bo=([-\d.]+) cs=([-\d.]+)", line)
    if m: d["tv"], d["tvh"], d["bo"], d["cs"] = map(num, m.groups())
    m = re.search(r"caret=([-\d.]+),([-\d.]+) \(([-\d.]+)\) len=(\d+) nl=(\d+)", line)
    if m: d["caret"], d["ch"], d["mcaret"], d["len"], d["nl"] = num(m.group(1)), num(m.group(2)), num(m.group(3)), int(m.group(4)), int(m.group(5))
    rows.append(("F", t, d))
keys = ["off", "cell", "cellh", "next", "tv", "tvh", "caret", "mcaret", "ins", "cs", "bo"]
watch = ["off", "cell", "cellh", "next", "tv", "caret"]
prev = None
rows.sort(key=lambda r: r[1])
start = float(open(sys.argv[sys.argv.index("--start") + 1]).read()) if "--start" in sys.argv else (rows[0][1] if rows else 0)
for kind, t, d in rows:
    if kind == "M":
        print(f"{t - start:8.3f}  ---- {d}"); continue
    steps = {}
    if prev:
        for k in keys:
            a, b = prev.get(k), d.get(k)
            if a is not None and b is not None: steps[k] = b - a
    flag = [k for k in watch if abs(steps.get(k, 0)) > J]
    # the text's own place on screen: the editor's top less the row's (the text moving inside its row)
    changed = any(abs(v) > 0.05 for v in steps.values())
    if show_all or flag or (changed and "--moves" in sys.argv):
        vals = " ".join(f"{k}={d.get(k) if d.get(k) is not None else '-'}" + (f"({steps[k]:+.1f})" if abs(steps.get(k, 0)) > 0.05 else "") for k in keys)
        print(f"{t - start:8.3f} {'JUMP ' + ','.join(flag) if flag else '     '} {vals} len={d.get('len')} nl={d.get('nl')}")
    prev = d
