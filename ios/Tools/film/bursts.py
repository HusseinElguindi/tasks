import re, sys
idx = [(int(a), float(b)) for a, b in re.findall(r"n: *([0-9]+) pts: *[0-9]+ pts_time:([0-9.]+)", open(sys.argv[1]).read())]
ts = [t for _, t in idx]
s, n = ts[0], 1
for a, b in zip(ts, ts[1:]):
    if b - a > 0.1:
        if n >= 3: print(f"{s:8.3f}-{a:8.3f} {n:4d}")
        s, n = b, 1
    else: n += 1
if n >= 3: print(f"{s:8.3f}-{ts[-1]:8.3f} {n:4d}")
