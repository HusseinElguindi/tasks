#!/usr/bin/env python3
"""folds.py <spike log> (tmp/spike-<name>.log in the app's container, from -spikeLog): each fold's numbers. Per fold: the next row (first non-folding item under the heading), its motion
(start, end, duration, one-way), the folding cells' largest overlap into the next row (frame), their largest departure
from moving rigidly with it, where their mask clips them (vs the heading's foot), and the settle (last presented vs
model)."""
import sys, re, ast
ev = []
for l in open(sys.argv[1]).read().splitlines():
    p = l.split(" ", 2)
    if p[0] == "M": ev.append(("M", float(p[1]), p[2]))
    elif p[0] == "F":
        cells = {}
        for tok in p[2].split(" "):
            if "@" in tok:
                k, v = tok.split("@"); f = v.split(",")
                cells[k] = dict(y=float(f[0]), h=float(f[1]), a=float(f[2]), m=next((float(x[1:]) for x in f[3:] if x.startswith("m")), None))
        ev.append(("F", float(p[1]), cells))
marks = [(i, t, s) for i, (k, t, s) in enumerate(ev) if k == "M"]
for n, (i, t, s) in enumerate(marks):
    m = re.match(r"apply (.+?) fold=(collapse|open) (\S+) (\[.*?\])", s)
    if not m: continue
    reason, kind, head, items = m.group(1), m.group(2), m.group(3), set(ast.literal_eval(m.group(4)))
    done = next((tt for _, tt, ss in marks[n+1:] if ss.startswith("apply done")), t + 1)
    model = {}
    dm = next((ss for _, tt, ss in marks[n+1:] if ss.startswith("apply done")), "")
    for tok in dm.split(" "):
        if "@" in tok: k, v = tok.split("@"); model[k] = float(v.split(",")[0])
    fs = [(tt, c) for k, tt, c in ev[i+1:] if k == "F" and tt <= done + 0.1][1:]
    begins = []
    for _, tt, ss in marks[n+1:n+8]:
        if not ss.startswith("anims"): continue
        b = sorted({float(x.split("@")[1].split(",")[0]) for x in ss.split(" ")[1:] if "@" in x})
        if b and b[0] > t - 1: begins = b; break   # the first: before the commit
    if not fs: continue
    # the next row: the non-folding cell just under the heading at the expanded end
    exp = fs[0][1] if kind == "collapse" else fs[-1][1]
    hy = exp[head]["y"] + exp[head]["h"] if head in exp else None
    below = sorted((c["y"], k) for k, c in exp.items() if k not in items and k != head and hy is not None and c["y"] >= hy - 0.5)
    nxt = below[0][1] if below else None
    foot = fs[0][1][head]["y"] + fs[0][1][head]["h"]
    ys = [(tt, c[nxt]["y"]) for tt, c in fs if nxt in c] if nxt else []
    print(f"\n{t:.3f} {reason} {kind} {head} next={nxt} foot={foot:.1f} items={sorted(items)}")
    if begins: print(f"  animations begin {begins[0] - t:.3f}s after the apply, spread {(begins[-1] - begins[0])*1000:.1f}ms")
    if not ys: continue
    y0, y1 = ys[0][1], ys[-1][1]
    st = next((ys[j-1][0] for j in range(1, len(ys)) if abs(ys[j][1] - y0) > 0.05), None)
    en = next((ys[j][0] for j in range(len(ys)) if all(abs(y - y1) <= 0.05 for _, y in ys[j:])), None)
    d = [b - a for (_, a), (_, b) in zip(ys, ys[1:])]
    oneway = all(x <= 0.05 for x in d) or all(x >= -0.05 for x in d)
    # rigid reference: at the folded end, each folding cell's offset from the next row
    ref = fs[-1][1] if kind == "collapse" else fs[-1][1]
    over, dev, vis, aend = -1e9, 0.0, 1e9, []
    for tt, c in fs:
        if nxt not in c: continue
        for k in items:
            if k not in c: continue
            cc = c[k]
            over = max(over, cc["y"] + cc["h"] - c[nxt]["y"]) if cc["a"] > 0.005 else over
            if k in ref and nxt in ref:
                dev = max(dev, abs((cc["y"] - c[nxt]["y"]) - (ref[k]["y"] - ref[nxt]["y"])))
            if cc["m"] is not None and cc["a"] > 0.005:
                vis = min(vis, max(cc["y"] + cc["m"], cc["y"]))
            elif cc["a"] > 0.005:
                vis = min(vis, cc["y"])
    settle = abs(y1 - model.get(nxt, y1))
    ts = [tt for tt, _ in fs if st and en and st - 0.001 <= tt <= en + 0.001]
    gap = max((b - a for a, b in zip(ts, ts[1:])), default=0)
    print(f"  {nxt}: {y0:.1f} -> {y1:.1f}  start {st - t if st else float('nan'):.3f}  end {en - t if en else float('nan'):.3f}  "
          f"dur {(en - st) if st and en else float('nan'):.3f}s  one-way {oneway}  settle {settle:.2f}  frames {len(ts)} max gap {gap*1000:.0f}ms")
    print(f"  folding cells: max overlap into next row {over:.1f}pt  max departure from rigid {dev:.1f}pt  "
          f"highest visible top {vis:.1f} (foot {foot:.1f})")
