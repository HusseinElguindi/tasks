#!/bin/zsh
# The iPhone's drop landing check (design/DECLARATIVE-DRAGGING.md, borrow 2; design/DROP-LANDING-CHECK.md): a drag's
# preview must be the layout of the state its drop writes, so the dropped row lands where the gap was and nothing else
# moves. Runs DebugScript's `dropcheck` step (`CollectionDrag.debugDropCheck`, TaskCollection+Drag.swift) on the sample
# data in Today, Upcoming, Undated and every list (PHYS 122 also with Labs, then Lectures, collapsed) and on Home's lists:
# every row that lifts (a task, a heading with its section, a list) onto every slot or Upcoming day, written, laid out as
# the landing renders it, compared, and undone. No touches and no frames: it reads the layouts. The Mac's is
# app/Scripts/drop-landing-check.sh.
#
#   drop-landing-check.sh [--sim UDID] [--app Tasks.app] [--out DIR]   # a Debug build; prints the failures and a
#                                                                      # summary per view; exits 1 on any
# On the shared simulator, hold the sim lease while it runs.
set -u
here=${0:A:h}
sim=booted app=() out=./drop-check-out
while (( $# )); do
  case $1 in
    --sim) sim=$2; shift 2 ;;
    --app) app=(--app $2); shift 2 ;;
    --out) out=$2; shift 2 ;;
    -h|--help) sed -n 2,12p $0; exit 0 ;;
    *) echo "drop-landing-check.sh: unknown argument $1" >&2; exit 64 ;;
  esac
done

steps=""
views=(today upcoming undated inbox school phys tasks home errands)
for v in $views; do steps+="open:$v;wait:800;dropcheck;"; done
# Collapsed headings (§23): a drop right under one folds the task into its section. Each opens again after.
steps+="open:phys;wait:800;collapse:Labs;wait:800;dropcheck;collapse:Labs;wait:800;"
steps+="collapse:Lectures;wait:800;dropcheck;collapse:Lectures;wait:800;"
# Home's lists.
steps+="home;wait:800;dropcheck;quit"
want=$(( ${#views} + 3 ))

$here/run.sh --sim $sim $app --out $out --timeout 900 -e "$steps" -sampleData YES
code=$?
[[ -s $out/dropcheck.txt ]] || { echo "FAIL: no output (did the app run the script? run.sh exited $code)"; exit 1; }
cat $out/dropcheck.txt
n=$(grep -c "^dropcheck .*: ok " $out/dropcheck.txt)
bad=$(grep -c "^FAIL\|^dropcheck .*: FAIL" $out/dropcheck.txt)
total=$(grep "^dropcheck " $out/dropcheck.txt | sed -E 's/.* ([0-9]+) checks.*/\1/' | paste -sd+ - | bc)
if (( n == want && bad == 0 && code == 0 )); then echo "ok: every drop lands where its preview put it ($total drops)"; exit 0; fi
echo "FAIL: $bad failing lines, $n of $want views ok ($total drops)"
exit 1
