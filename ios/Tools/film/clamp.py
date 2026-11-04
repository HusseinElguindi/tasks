#!/usr/bin/env python3
"""clamp.py <spike log>: per drag in Today/Undated, the run, its slots' y range, and on every frame whether the copy
stayed within 6pt of them; every gap move's slot and whether the item it's after is in the run; the drop."""
import sys, re
lines = open(sys.argv[1]).read().splitlines()
drags, cur = [], None
for l in lines:
    p = l.split(" ", 2)
    if len(p) < 3: continue
    kind, t, rest = p[0], float(p[1]), p[2]
    if kind == "M" and rest.startswith("drag run "):
        m = re.match(r"drag run (\S+) slots (.*)", rest)
        run = set(m.group(1).split(","))
        ys = [float(s.split("@")[1]) for s in m.group(2).split()]
        cur = dict(t=t, run=run, lo=min(ys), hi=max(ys), slots=m.group(2), copies=[], fingers=[], gaps=[], drop=None, id=None)
        drags.append(cur)
    elif cur is None:
        continue
    elif kind == "M" and rest.startswith("drag willBegin"):
        cur["id"] = rest.split()[2]
    elif kind == "M" and rest.startswith("gap slot="):
        after = re.search(r"after=(\S+)", rest).group(1)
        cur["gaps"].append((rest.split()[1], after, after in cur["run"] or after == "-"))
    elif kind == "M" and rest.startswith("drop ") and "->slot" in rest:
        cur["drop"] = rest
    elif kind == "M" and (rest.startswith("drop landed") or rest.startswith("go home")):
        cur["end"] = rest
    elif kind == "F" and cur["drop"] is None and "end" not in cur:
        m = re.search(r"copy@(-?[\d.]+)", rest)
        if m: cur["copies"].append(float(m.group(1)))
        m = re.search(r"finger@(-?[\d.]+)", rest)
        if m: cur["fingers"].append(float(m.group(1)))
for d in drags:
    c = d["copies"]
    out = [y for y in c if y < d["lo"] - 6.05 or y > d["hi"] + 6.05]
    print(f"drag {d['id']}: run {sorted(d['run'])}")
    print(f"  slots {d['slots']}  -> copy limits {d['lo']-6:.1f}..{d['hi']+6:.1f}")
    print(f"  copy on {len(c)} frames: min {min(c):.1f} max {max(c):.1f}; frames outside the limits: {len(out)}")
    fg = d["fingers"]
    if fg: print(f"  finger (unheld copy top): min {min(fg):.1f} max {max(fg):.1f}; past the limits by up to {max(d['lo'] - 6 - min(fg), max(fg) - d['hi'] - 6, 0):.1f}pt")
    print(f"  gap moves {len(d['gaps'])}: " + ", ".join(f"{s} after {a}{'' if ok else ' OUTSIDE'}" for s, a, ok in d["gaps"]))
    print(f"  {d['drop']}")
