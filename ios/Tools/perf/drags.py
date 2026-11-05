#!/usr/bin/env python3
"""drags.py <frame-trace.log> [<drag-trace.log>] [--frames N] [--all]

Reads the probes' logs (ios/Tools/perf/README.md): FrameProbe's (`-frameProbe YES`, every display frame) and
DragProbe's (`-dragTrace YES`, every frame of each drag). Per drag, from UIKit's drag session beginning to the finger's
lift, and the lift before it:

  frames   frame-time percentiles, hitches (a frame over 1.5 x the display's frame), the hitch time ratio (ms past
           the frame, per s), frames missed; the worst frames with what the main thread did in them (work: events,
           timers, display links, our code; commit: UIKit's layout, SwiftUI's cell updates, the CA commit; the Perf
           buckets: follow, layout, moveGap, apply, configure, cellApply, update, probe).
  finger   how often the drag session's finger moved, frame by frame (fg), and the drop updates (u) per frame.
  copy     the copy's steps against the finger's: frames it stood still while the finger moved, and its lag behind
           the finger's grab point (from the first frame's offset), in pt.
  gap      per slot change: the time since the last one, the cells that moved, how long their spring ran, and the
           largest single-frame step and change of speed (a jerk: the spring restarted from rest, or a jump).

--frames N   the per-frame table of drag N (from 1): dt, work, commit, fg, u, copy, the gap's cells.
--all        the full figures for lifts with no drag session too (by default a line each: the touch, the calls).
"""
import sys, re, statistics as st

def parse_frames(path):
    F, M = [], []
    for l in open(path, errors="replace"):
        p = l.split()
        if not p: continue
        if p[0] == "F" and len(p) >= 9:
            b = {}
            for tok in p[9:]:
                if "=" in tok:
                    k, v = tok.split("=", 1); n, ms = v.split("/")
                    b[k] = (int(n), float(ms))
            F.append(dict(t=float(p[1]), dt=float(p[2]), miss=int(p[3]), work=float(p[4]), commit=float(p[5]),
                          ps=float(p[6]), touches=int(p[7]), ticks=int(p[8]), b=b))
        elif p[0] == "M" and len(p) >= 3:
            M.append((float(p[1]), " ".join(p[2:])))
    return F, M

def num(s):
    try: return float(s)
    except ValueError: return None

def parse_drag(path):
    F, M = [], []
    for l in open(path, errors="replace"):
        p = l.rstrip("\n").split(" ")
        if len(p) < 2: continue
        if p[0] == "M":
            M.append((float(p[1]), " ".join(p[2:])))
        elif p[0] == "F":
            d = dict(t=float(p[1]))
            for tok in p[2:]:
                if "=" not in tok: continue
                k, v = tok.split("=", 1)
                if k == "copy": d["copy"] = [float(x) for x in v.split(",")]
                elif k in ("fg", "row", "tc"): d[k] = [float(x) for x in v.split(",")]
                elif k == "g":
                    g = {}
                    for c in v.split(","):
                        q = c.split(":")
                        if len(q) == 3:
                            g[int(q[0])] = (float(q[1]), float(q[2].rstrip("h")), q[2].endswith("h"))
                    d["g"] = g
                else:
                    x = num(v)
                    if x is not None: d[k] = x
            F.append(d)
    return F, M

def pct(xs, q):
    if not xs: return float("nan")
    xs = sorted(xs); i = min(len(xs) - 1, max(0, int(round(q / 100 * (len(xs) - 1)))))
    return xs[i]

def drags_from(M):
    """(lift, begin, release, landed) times per drag, from DragProbe's marks."""
    out, cur = [], None
    for t, s in M:
        if s == "call items":
            if cur: out.append(cur)
            cur = dict(lift=t, begin=None, release=None, landed=None, slots=[], marks=[])
        if cur is None: continue
        cur["marks"].append((t, s))
        if s == "call begin" and cur["begin"] is None: cur["begin"] = t
        elif s.startswith("release") and cur["release"] is None: cur["release"] = t
        elif s.startswith("landed") and cur["landed"] is None: cur["landed"] = t
        elif s.startswith("slot "):
            m = re.match(r"slot (\S+) was (\S+) at (\S+)", s)
            if m: cur["slots"].append((t, m.group(1), m.group(2), float(m.group(3))))
    if cur: out.append(cur)
    return out

def frame_stats(fr, label):
    if not fr: return f"  {label}: no frames"
    dts = [f["dt"] for f in fr]
    nominal = 1000 / round(1000 / st.median(dts))  # 16.67 at 60 Hz, 8.33 at 120 Hz
    hitch = [f for f in fr if f["dt"] > 1.5 * nominal]
    span = sum(dts) / 1000
    over = sum(f["dt"] - nominal for f in hitch)
    miss = sum(f["miss"] for f in fr)
    return (f"  {label}: {len(fr)} frames over {span:.2f} s at {1000 / nominal:.0f} Hz; dt p50 {pct(dts, 50):.1f} p90 {pct(dts, 90):.1f} "
            f"p99 {pct(dts, 99):.1f} max {max(dts):.1f} ms; hitches {len(hitch)}, hitch time {over / span if span else 0:.1f} ms/s; "
            f"missed {miss}")

def worst(fr, t0, n=5):
    rows = sorted(fr, key=lambda f: -f["dt"])[:n]
    out = []
    for f in sorted(rows, key=lambda f: f["t"]):
        b = " ".join(f"{k}={v[0]}/{v[1]:.1f}" for k, v in sorted(f["b"].items(), key=lambda kv: -kv[1][1]) if v[1] >= 0.05)
        out.append(f"    +{(f['t'] - t0) * 1000:6.0f} ms  dt {f['dt']:6.1f}  work {f['work']:6.1f}  commit {f['commit']:6.1f}  "
                   f"pass {f['ps']:6.1f}  {b}")
    return out

def main():
    args = sys.argv[1:]
    show = None; every = False
    if "--frames" in args:
        i = args.index("--frames"); show = int(args[i + 1]); del args[i:i + 2]
    if "--all" in args: args.remove("--all"); every = True
    if not args: print(__doc__); sys.exit(1)
    FF, FM = parse_frames(args[0])
    DF, DM = parse_drag(args[1]) if len(args) > 1 else ([], [])
    for t, s in FM:
        if s.startswith("keyboardWarmUp") or s.startswith("launch"): print(f"mark {t:.3f} {s}")
    if FF:
        print(frame_stats(FF, "whole log"))
    drags = drags_from(DM)
    if not drags: print("no drags in the drag log (was -dragTrace YES on?)"); return
    n = 0
    for d in drags:
        n += 1
        if d["begin"] is None:
            # A lift that no drag session followed: a hold that opened the menu, or a drag that didn't register.
            calls = [m[len("call "):] for _, m in d["marks"] if m.startswith("call ")]
            nxt = drags[n]["lift"] if n < len(drags) else float("inf")
            seg = [f for f in DF if d["lift"] <= f["t"] < min(nxt, d["lift"] + 3)]
            tc = [f for f in seg if "tc" in f]
            last_tc = tc[-1]["t"] if tc else d["lift"]
            moved = (f"the app's touch moved {tc[-1]['tc'][0] - tc[0]['tc'][0]:+.1f},{tc[-1]['tc'][1] - tc[0]['tc'][1]:+.1f} pt "
                     f"until +{(last_tc - d['lift']) * 1000:.0f} ms (then lifted or taken by UIKit)") if tc else "no touch traced"
            print(f"\ndrag {n}: lift with NO drag session: {moved}; calls {'>'.join(dict.fromkeys(calls))}")
            if not every: continue
        end = d["release"] or d["landed"] or (d["marks"][-1][0])
        t0 = d["begin"] or d["lift"]
        print(f"\ndrag {n}: lift +0, begin +{((d['begin'] or d['lift']) - d['lift']) * 1000:.0f} ms, "
              f"release +{(end - d['lift']) * 1000:.0f} ms, {len(d['slots'])} slot changes")
        lift = [f for f in FF if d["lift"] <= f["t"] <= t0]
        held = [f for f in FF if t0 < f["t"] <= end]
        after = [f for f in FF if end < f["t"] <= end + 0.5]
        print(frame_stats(lift, "lift to begin"))
        print(frame_stats(held, "begin to release"))
        print(frame_stats(after, "release + 0.5 s"))
        if held:
            print("  worst frames, begin to release (from begin):")
            print("\n".join(worst(held, t0)))
            tot = {}
            for f in held:
                for k, v in f["b"].items():
                    a = tot.setdefault(k, [0, 0.0]); a[0] += v[0]; a[1] += v[1]
            span = sum(f["dt"] for f in held) / 1000
            print("  main thread in the drag, per s: work %.0f ms, commit %.0f ms; " % (
                sum(f["work"] for f in held) / span, sum(f["commit"] for f in held) / span)
                + ", ".join(f"{k} {v[1] / span:.1f} ms ({v[0] / span:.0f}/s)" for k, v in sorted(tot.items(), key=lambda kv: -kv[1][1])))
        frames = [f for f in DF if t0 < f["t"] <= end]
        if frames:
            finger(frames)
            copy(frames, [f for f in DF if d["lift"] <= f["t"] <= t0])
        gap(d, [f for f in DF if t0 < f["t"] <= end + 0.5])
        if show == n:
            table(d, [f for f in DF if d["lift"] <= f["t"] <= end + 0.5], FF)

def finger(frames):
    fg = [f for f in frames if "fg" in f]
    if len(fg) < 3: print("  finger: no fg (no drag session)"); return
    moved = sum(1 for a, b in zip(fg, fg[1:]) if a["fg"] != b["fg"])
    u = [f.get("u", 0) for f in frames]
    hist = {k: sum(1 for x in u if x == k) for k in sorted(set(int(x) for x in u))}
    # Frames the finger stood still between two that moved it: the finger's updates came late or not at all.
    ys = [f["fg"][1] for f in fg]
    stills = sum(1 for i in range(1, len(ys) - 1) if ys[i] == ys[i - 1] and ys[i + 1] != ys[i] and
                 i >= 2 and ys[i - 1] != ys[i - 2])
    print(f"  finger: moved in {moved} of {len(fg) - 1} frames; drop updates per frame {hist}; single-frame holds while moving: {stills}")

def copy(frames, lifted):
    """The copy against the finger. The grab offset is the finger's on the copy at the lift (the app's own touch, tc),
    else the offset most frames keep."""
    cf = [f for f in frames if "copy" in f and "fg" in f]
    if len(cf) < 3: print("  copy: not traced"); return
    first = next((f for f in lifted if "tc" in f and "copy" in f), None)
    if first: grab = first["tc"][1] - first["copy"][1]
    else:
        offs = [round(f["fg"][1] - f["copy"][1]) for f in cf]
        grab = max(set(offs), key=offs.count)
    # From the lift to the drag's begin the copy stays where it lifted while the app's touch moves (tc).
    tcs = [f for f in lifted if "tc" in f]
    lc = [f for f in lifted if "copy" in f]
    if lc:
        y0 = lc[-1]["copy"][1]
        moved = next((f for f in cf if abs(f["copy"][1] - y0) > 0.05), None)
        jump = moved["copy"][1] - y0 if moved else 0.0
        after = (moved["t"] - cf[0]["t"]) * 1000 if moved else 0.0
        print(f"  lift to begin: the app's touch moved {tcs[-1]['tc'][1] - tcs[0]['tc'][1] if tcs else 0:+.1f} pt (y) before UIKit "
              f"took it, the copy waiting where it lifted; its first move after the begin (+{after:.0f} ms) was a jump of {jump:+.1f} pt")
    lag = [f["fg"][1] - grab - f["copy"][1] for f in cf]
    # Runs of frames the copy stood still while the finger went on (no follow: no drop update, no display link):
    # those where the finger moved over 2 pt in all, not held at the first or last slot.
    runs, cur, dist = [], 0, 0.0
    for a, b in zip(cf, cf[1:]):
        fv = b["fg"][1] - a["fg"][1]; cv = b["copy"][1] - a["copy"][1]
        if abs(cv) < 0.05: cur += 1; dist += fv
        else:
            if cur and abs(dist) > 2: runs.append((cur, dist))
            cur, dist = 0, 0.0
    if cur and abs(dist) > 2: runs.append((cur, dist))
    still = sum(r[0] for r in runs)
    long = max(runs, key=lambda r: r[0]) if runs else (0, 0)
    steps = [b["copy"][1] - a["copy"][1] for a, b in zip(cf, cf[1:])]
    fsteps = [b["fg"][1] - a["fg"][1] for a, b in zip(cf, cf[1:])]
    jerks = [abs(b - a) for a, b in zip(steps, steps[1:])]
    fj = [abs(b - a) for a, b in zip(fsteps, fsteps[1:])]
    print(f"  copy: still while the finger moved in {still} of {len(steps)} frames, longest {long[0]} frames "
          f"(the finger went {long[1]:+.1f} pt meanwhile); off the finger's grab point p50 {pct([abs(x) for x in lag], 50):.1f} "
          f"p90 {pct([abs(x) for x in lag], 90):.1f} max {max(abs(x) for x in lag):.1f} pt (held to the first or last slot, or behind)")
    if jerks:
        print(f"  copy speed change per frame p50 {pct(jerks, 50):.1f} p90 {pct(jerks, 90):.1f} max {max(jerks):.1f} pt; "
              f"largest step {max(abs(x) for x in steps):.1f} pt (the finger's: p50 {pct(fj, 50):.1f} p90 {pct(fj, 90):.1f} "
              f"max {max(fj):.1f}, step {max(abs(x) for x in fsteps):.1f})")

def gap(d, frames):
    if not d["slots"] or not frames: return
    print("  gap, per slot change (cells whose transform changed; their shown motion until it settles):")
    prev = d["begin"] or d["lift"]
    for i, (t, s, was, top) in enumerate(d["slots"]):
        nxt = d["slots"][i + 1][0] if i + 1 < len(d["slots"]) else t + 0.6
        seg = [f for f in frames if t - 0.02 <= f["t"] <= nxt + 0.001]
        before = [f for f in frames if f["t"] < t]
        b0 = before[-1]["g"] if before and "g" in before[-1] else {}
        moved = {}
        for f in seg:
            for k, (m, sh, h) in f.get("g", {}).items():
                if h: continue
                if b0.get(k, (0, 0, 0))[0] != m: moved.setdefault(k, []).append((f["t"], m, sh))
        worst_step = 0; worst_jerk = 0; settle = 0; cells = []
        for k, pts in moved.items():
            sh = [p[2] for p in pts]
            v = [b - a for a, b in zip(sh, sh[1:])]
            if v: worst_step = max(worst_step, max(abs(x) for x in v))
            if len(v) > 1: worst_jerk = max(worst_jerk, max(abs(b - a) for a, b in zip(v, v[1:])))
            done = next((p[0] for p in pts if abs(p[2] - p[1]) < 0.5), None)
            if done: settle = max(settle, done - t)
            cells.append(k)
        print(f"    +{(t - (d['begin'] or d['lift'])) * 1000:6.0f} ms slot {was}->{s} ({(t - prev) * 1000:4.0f} ms after the last) "
              f"cells {sorted(cells)[:8]}: settle {settle * 1000:4.0f} ms, max step {worst_step:5.1f} pt/frame, max speed change {worst_jerk:5.1f}")
        prev = t

def table(d, frames, FF):
    print(f"  frames of this drag (t from lift):")
    fi = 0
    for f in frames:
        while fi + 1 < len(FF) and FF[fi + 1]["t"] <= f["t"] + 0.004: fi += 1
        ff = FF[fi] if FF else None
        g = " ".join(f"{k}:{v[1]:.1f}{'h' if v[2] else ''}" for k, v in sorted(f.get("g", {}).items()))
        c = f.get("copy"); fg = f.get("fg")
        print(f"   {(f['t'] - d['lift']) * 1000:7.1f} " + (f"dt {ff['dt']:5.1f} w {ff['work']:5.1f} c {ff['commit']:5.1f} " if ff else "")
              + (f"fg {fg[1]:6.1f} " if fg else (f"tc {f['tc'][1]:6.1f} " if "tc" in f else "fg      - ")) + f"u {int(f.get('u', 0))} "
              + (f"copy {c[1]:6.1f} " if c else "") + g)

if __name__ == "__main__":
    main()
