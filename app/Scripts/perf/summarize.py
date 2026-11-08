"""Sums rusage sample lines (rusage.swift's output) into one row per file (coord title-design T8).

    python3 -I app/Scripts/perf/summarize.py <interval-seconds> <file.rusage>...

Per file: wall seconds sampled, CPU seconds, mean and peak CPU %, idle and interrupt wakeups per second, physical and
logical bytes written, mean energy (mW), and the footprint at the start, the peak and the end.
"""
import re
import sys

interval = float(sys.argv[1])
pat = re.compile(r"cpu ([\d.]+)%\tidleW/s ([\d.]+)\tintW/s ([\d.]+)\tdiskW (\d+) B\tlogW (\d+) B\tdiskR (\d+) B\t([\d.]+) mW\tfp ([\d.]+) MB")
print("file\twall_s\tcpu_s\tcpu%_mean\tcpu%_peak\tidleW/s\tintW/s\tdiskW_KB\tlogW_KB\tmW\tfp_start\tfp_peak\tfp_end")
for path in sys.argv[2:]:
    rows = []
    for line in open(path):
        parts = line.split("\t")
        if len(parts) < 3 or not parts[1].isdigit():
            continue
        m = pat.search(line)
        if m:
            rows.append([float(x) for x in m.groups()])
    if not rows:
        print(f"{path}\tno samples")
        continue
    n = len(rows)
    wall = n * interval
    cpu_s = sum(r[0] for r in rows) / 100 * interval
    print("\t".join([
        path.split("/")[-1], f"{wall:.1f}", f"{cpu_s:.3f}", f"{cpu_s / wall * 100:.3f}", f"{max(r[0] for r in rows):.1f}",
        f"{sum(r[1] for r in rows) / n:.2f}", f"{sum(r[2] for r in rows) / n:.2f}",
        f"{sum(r[3] for r in rows) / 1024:.1f}", f"{sum(r[4] for r in rows) / 1024:.1f}",
        f"{sum(r[6] for r in rows) / n:.2f}", f"{rows[0][7]:.1f}", f"{max(r[7] for r in rows):.1f}", f"{rows[-1][7]:.1f}",
    ]))
