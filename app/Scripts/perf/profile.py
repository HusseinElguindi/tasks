"""Top functions from an xctrace Time Profiler export (coord title-design T8).

    xcrun xctrace export --input run.trace --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' > tp.xml
    python3 -I app/Scripts/perf/profile.py tp.xml [binary-name] [top]

Prints, by sample count (1 ms each): the heaviest leaf frames (self time), and the heaviest frames from [binary-name]
anywhere on the stack (total time), so app code shows even when the time is spent in the frameworks under it.
xctrace's XML refers back to earlier elements by id ("ref"), which this resolves.
"""
import collections
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
binary = sys.argv[2] if len(sys.argv) > 2 else "Tasks Perf"
top = int(sys.argv[3]) if len(sys.argv) > 3 else 25

frames = {}   # id -> (name, binary)
bins = {}     # id -> name
stacks = {}   # backtrace id -> [frame ids]
leaf = collections.Counter()
total_app = collections.Counter()
threads = collections.Counter()
n = 0

def frame_of(el):
    fid = el.get("id")
    if fid is None:
        return el.get("ref")
    b = el.find("binary")
    bname = ""
    if b is not None:
        if b.get("id"):
            bins[b.get("id")] = b.get("name", "")
            bname = b.get("name", "")
        else:
            bname = bins.get(b.get("ref"), "")
    frames[fid] = (el.get("name", "?"), bname)
    return fid

for _, row in ET.iterparse(path, events=("end",)):
    if row.tag != "row":
        continue
    bt = row.find("tagged-backtrace")
    if bt is None:
        bt = row.find("backtrace")
    th = row.find("thread")
    tname = ""
    if th is not None:
        tname = th.get("fmt", "") if th.get("id") else stacks.get(("t", th.get("ref")), "")
        if th.get("id"):
            stacks[("t", th.get("id"))] = tname
    if bt is None:
        row.clear()
        continue
    if bt.get("ref"):
        ids = stacks.get(bt.get("ref"), [])
    else:
        ids = [frame_of(f) for f in bt.findall("frame")]
        stacks[bt.get("id")] = ids
    n += 1
    threads["main" if "Main Thread" in tname else tname.split(" ")[0] or "?"] += 1
    if ids:
        leaf[frames.get(ids[0], ("?", ""))] += 1
        seen = set()
        for fid in ids:
            name, b = frames.get(fid, ("?", ""))
            if b == binary and name not in seen:
                seen.add(name)
                total_app[name] += 1
    row.clear()

print(f"{n} samples (ms); by thread: {dict(threads.most_common(5))}")
print("\n-- self time (leaf frames)")
for (name, b), c in leaf.most_common(top):
    print(f"{c:6d}  {c / max(n, 1) * 100:5.1f}%  {name[:110]}  [{b}]")
print(f"\n-- total time in {binary} frames")
for name, c in total_app.most_common(top):
    print(f"{c:6d}  {c / max(n, 1) * 100:5.1f}%  {name[:130]}")
