#!/bin/bash
# Notes box check (the user, 2026-11-08: "with a long description, when checking off a checkbox, it enters editing mode
# and the cursor goes all the way to the bottom of the text (scrolling down with it)"): clicking a checklist box in the
# detail pane's notes toggles it and nothing else moves (design/MARKDOWN.md §5: "It never moves the caret or takes the
# keys, editing or not"). Launches the Debug app in the background (open -g, its own data folder, demo data, no server)
# with a task whose notes are a long description and a checklist, scrolls a box into view near the bottom of the pane and clicks it
# for real, through the window (`nboxclick:`):
#   - at rest: the box toggles and is stored as its own step; the notes don't take the keys (no session, no caret);
#     the scroll stays.
#   - editing, the caret near the top and the view scrolled down to a box: the box toggles; the selection, the keys
#     and the scroll stay.
#   - and a click on the text still starts the session with the caret there.
# KEEP=1 keeps the work folder (logs, before/after snaps, frames with FRAMES=1).
#
#   xcodebuild -project Tasks.xcodeproj -scheme Tasks -derivedDataPath .build/DerivedData build   # the Debug app
#   app/Scripts/notes-box-check.sh
set -u
APP="${APP:-$(cd "$(dirname "$0")/.." && pwd)/.build/DerivedData/Build/Products/Debug/Tasks Dev.app}"
[ -d "$APP" ] || { echo "no Debug app at $APP" >&2; exit 1; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/tasks-notes-box-check.XXXXXX")
if [ "${KEEP:-0}" = 1 ]; then echo "work: $WORK"; else trap 'rm -rf "$WORK"' EXIT; fi

TITLE="Long notes box check"
PARA="Steps back from neural models to describe the structure sentences have, so the next lecture can ask whether models learn it. Count and normalize, the probability of a string, applied to trees."
NOTES="$PARA\n\n$PARA\n\n$PARA\n\n$PARA"
for i in $(seq 1 14); do NOTES+="\n- [ ] Item $i of the checklist, long enough to wrap onto a second line in the detail pane"; done
# The offsets of the characters between the brackets: the third box (at rest) and the sixth (editing).
read -r BR BE < <(python3 -I -c '
import sys
s = sys.argv[1].replace("\\n", "\n")
i, out = 0, []
while True:
    i = s.find("- [ ] ", i)
    if i < 0: break
    out.append(i + 3); i += 1
print(out[2], out[5])' "$NOTES")

FR=""
[ "${FRAMES:-0}" = 1 ] && FR="snap"
STEPS="size:1000,640;mktask:$TITLE|$NOTES;wait:300;act:select:$TITLE;wait:800"
# At rest: the third box scrolled into view, then a click on it.
STEPS+=";nscroll:box:$BR;wait:300;nlog:$WORK/rest.txt;snap:$WORK/rest-before.png"
STEPS+=";act:frames:24:$WORK/rest-frames.txt:$FR;nboxclick:$BR;wait:700;nlog:$WORK/rest.txt;snap:$WORK/rest-after.png"
# Editing: the caret near the top (a selection of 5 characters), the view scrolled down to the sixth box, a click on it.
STEPS+=";ncaret:10,15;wait:200;nscroll:box:$BE;wait:300;nlog:$WORK/edit.txt;snap:$WORK/edit-before.png"
STEPS+=";act:frames:24:$WORK/edit-frames.txt:$FR;nboxclick:$BE;wait:700;nlog:$WORK/edit.txt;snap:$WORK/edit-after.png"
# And a press on the text still takes the caret there (§6 Pointer): out of the session, then a click on the sixth item's text (on screen).
BT=$((BE + 12))
STEPS+=";act:commit;wait:300;nlog:$WORK/text.txt;ntextclick:$BT;wait:400;nlog:$WORK/text.txt"

mkdir -p "$WORK/data"
open -g -n "$APP" --args -dataDirectory "$WORK/data" -demoData YES -serverURL http://127.0.0.1:9 -syncToken none \
  -debugDetail YES -debugScript "$STEPS;wait:300"
sleep 2
while pgrep -f "MacOS/Tasks Dev -dataDirectory $WORK/data" >/dev/null; do sleep 0.5; done

python3 -I - "$WORK" "$BR" "$BE" "$BT" <<'PY'
import json, os, re, sys
work, br, be, bt = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
def read(name):
    out = []
    for line in open(os.path.join(work, name)):
        m = re.search(r'notes="(.*)" sel=(\d+),(\d+) .*editing=(\S+) stored="(.*)" responder=(\w+) .* scroll=(-?\d+)', line)
        text = lambda g: json.loads('"' + g + '"')     # Swift's debugDescription: \n, \" and \\ as JSON has them
        out.append(dict(notes=text(m.group(1)), sel=(int(m.group(2)), int(m.group(3))), editing=m.group(4),
                        stored=text(m.group(5)), responder=m.group(6) == "true", scroll=int(m.group(7))))
    return out
ok = True
def check(name, cond, what):
    global ok
    print(("ok   " if cond else "FAIL ") + name + ": " + what)
    ok &= cond
def show(d): return f"sel={d['sel']} responder={d['responder']} editing={d['editing']} scroll={d['scroll']}"

a, b = read("rest.txt")
print("rest   before: " + show(a) + "\n       after:  " + show(b))
check("rest", b["stored"][br] == "x" and a["stored"][br] == " ", "the box is checked and stored")
check("rest", not b["responder"] and b["editing"] == "-", "the notes didn't take the keys (no session, no caret)")
check("rest", b["scroll"] == a["scroll"], f"the scroll stayed ({a['scroll']} → {b['scroll']})")

a, b = read("edit.txt")
print("edit   before: " + show(a) + "\n       after:  " + show(b))
check("edit", b["notes"][be] == "x" and a["notes"][be] == " ", "the box is checked in the text")
check("edit", b["responder"] and b["editing"] != "-", "the session goes on")
check("edit", b["sel"] == a["sel"] == (10, 5), f"the selection stayed ({a['sel']} → {b['sel']})")
check("edit", b["scroll"] == a["scroll"], f"the scroll stayed ({a['scroll']} → {b['scroll']})")
a, b = read("text.txt")
print("text   before: " + show(a) + "\n       after:  " + show(b))
check("text", not a["responder"] and b["responder"] and b["editing"] != "-" and abs(b["sel"][0] - bt) <= 1 and b["sel"][1] == 0,
      "a click on the text still starts the session with the caret there")
print("ok: a box click moves nothing else" if ok else "FAIL")
sys.exit(0 if ok else 1)
PY
