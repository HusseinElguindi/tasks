#!/bin/bash
# Completion check (v2 feedback 18): one press, one op. Launches the Debug app in the background (open -g, never
# activated; its own data folder, demo data, no server) with a debug script that completes tasks the ways a person
# does, in a list, Today, Upcoming and Undated: single clicks on checkboxes, quick clicks on three rows, a
# double-click on a checkbox, Space held past the key-repeat delay (in the list, the sidebar and the detail pane),
# and a task clicked twice on purpose. Then reads
# the op log and the rows the list laid out, and fails unless every task got exactly the completion ops expected and
# a task toggled back before the settle stayed where it was.
#
#   xcodebuild -project Tasks.xcodeproj -scheme Tasks -derivedDataPath .build/DerivedData build   # the Debug app
#   app/Scripts/completion-check.sh
set -u
APP="${APP:-$(cd "$(dirname "$0")/.." && pwd)/.build/DerivedData/Build/Products/Debug/Tasks Dev.app}"
[ -d "$APP" ] || { echo "no Debug app at $APP" >&2; exit 1; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/tasks-completion-check.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
ROWS="$WORK/rows.txt"

STEPS="size:1180,760;wait:300"
# A list: a held Space (three repeats), a click, quick clicks on three rows, a double-click, and a task clicked again
# 400 ms later (two ops, and its row stays put until the settle).
STEPS+=";act:go:School;wait:600;act:select:Email TA about midterm regrade;wait:200;hold:49:3;wait:1800"
STEPS+=";checkclick:Submit MSE 333 A2;wait:1800"
STEPS+=";checkclick:CS 489 final study plan;wait:120;checkclick:Print ECE 358 formula sheet;wait:120;checkclick:Ask about co-op interview slots;wait:1800"
STEPS+=";checkdbl:Midterm review session;wait:1800"
STEPS+=";act:rows:$ROWS;checkclick:ECE 358 final exam;wait:400;checkclick:ECE 358 final exam;wait:100;act:rows:$ROWS;wait:1800"
# Today: a click, a held Space, and a task clicked again 400 ms later.
STEPS+=";act:go:Today;wait:700;checkclick:Book flu shot;wait:1800"
STEPS+=";act:rows:$ROWS;checkclick:Pick up prescription;wait:400;checkclick:Pick up prescription;wait:100;act:rows:$ROWS;wait:1800"
STEPS+=";act:select:Return library books;wait:200;hold:49:3;wait:1800"
# Upcoming: a click and quick clicks; Undated: a click and a double-click.
STEPS+=";act:go:Upcoming;wait:700;checkclick:Buy printer paper;wait:120;checkclick:Fix the bathroom fan;wait:1800"
STEPS+=";act:go:Undated;wait:700;checkclick:Look into a standing desk;wait:300;checkdbl:Get a spare key cut;wait:1800"
# Space held with the sidebar focused, and with the detail pane focused.
STEPS+=";act:go:Tasks app;wait:600;act:select:Profile list switching;wait:200;key:123;wait:200;hold:49:3;wait:1800"
STEPS+=";act:go:Home;wait:600;act:select:Call landlord about the heating;act:detail;wait:800;key:48;wait:300;hold:49:3;wait:1800"

mkdir -p "$WORK/data"
open -g -n "$APP" --args -dataDirectory "$WORK/data" -demoData YES -serverURL http://127.0.0.1:9 -syncToken none \
  -debugScript "$STEPS;wait:300"
sleep 2
while pgrep -f "MacOS/Tasks Dev -dataDirectory $WORK/data" >/dev/null; do sleep 0.5; done

python3 -I - "$WORK/data/pending.jsonl" "$ROWS" <<'PY'
import json, sys
ops = [json.loads(l) for l in open(sys.argv[1])]
titles = {o["target"]: o["set"].get("title") for o in ops if o["type"] == "task.create"}
# A press writes completedAt = the op's own time, or null; the demo data's done tasks were completed in the past.
got = {}
for o in ops:
    c = o.get("set", {}).get("completedAt", 0)
    if c is None or c == o["at"]:
        got.setdefault(titles.get(o["target"]), []).append("complete" if c else "not done")
want = {t: ["complete"] for t in [
    "Email TA about midterm regrade", "Submit MSE 333 A2", "CS 489 final study plan", "Print ECE 358 formula sheet",
    "Ask about co-op interview slots", "Midterm review session", "Book flu shot", "Return library books",
    "Buy printer paper", "Fix the bathroom fan", "Look into a standing desk", "Get a spare key cut",
    "Profile list switching", "Call landlord about the heating"]}
want["ECE 358 final exam"] = want["Pick up prescription"] = ["complete", "not done"]
ok = True
for t in sorted(set(want) | set(got)):
    w, g = want.get(t, []), got.get(t, [])
    print(f"{'ok  ' if w == g else 'FAIL'} {t}: {', '.join(g) or 'no ops'}" + ("" if w == g else f" (want {', '.join(w) or 'none'})"))
    ok &= w == g
# A task clicked twice: on the same row before and after, shown not done.
dumps = open(sys.argv[2]).read().split("route=")[1:]
def row(dump, title):
    for line in dump.splitlines():
        if f" {title} " in line + " ":
            return line.split()[0], " done " in line + " "
    return None, None
for i, title in enumerate(["ECE 358 final exam", "Pick up prescription"]):
    (y0, _), (y1, done1) = row(dumps[2 * i], title), row(dumps[2 * i + 1], title)
    placed = y0 is not None and y0 == y1 and done1 is False
    print(f"{'ok  ' if placed else 'FAIL'} {title} clicked twice: row at y {y0} → {y1}, shown {'done' if done1 else 'not done'}")
    ok &= placed
print("ok: one op per press" if ok else "FAIL")
sys.exit(0 if ok else 1)
PY
