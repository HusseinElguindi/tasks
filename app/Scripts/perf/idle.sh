#!/bin/zsh
# Idle scenarios for a running scratch app (coord title-design T8): window open but in the background, hidden, then
# frontmost; each phase sampled with rusage, with the local server's request count and the data folder's files.
#
#   app/Scripts/perf/idle.sh <tools-dir> <pid> <data-dir> <wrangler.log> <seconds per phase> <out-file> [installed-pid]
#
# <tools-dir> holds rusage and appctl (built from rusage.swift and appctl.swift). With [installed-pid], the installed
# app is sampled passively alongside every phase (read-only: proc_pid_rusage only).
set -u
T=$1 pid=$2 data=$3 wlog=$4 secs=$5 out=$6 inst=${7:-}
n=$(( secs / 5 ))
files() { stat -f '%N %z B %Sm' -t '%T' "$data"/* | sed "s|$data/||"; }
phase() {
  local name=$1
  local before=$(grep -c 'POST /v1/sync' "$wlog")
  echo "== $name ($(date +%T)) $("$T/appctl" $pid state)" >> "$out"
  [[ -n $inst ]] && "$T/rusage" $inst 5 $n "installed:$name" > "$out.inst.$name" &
  "$T/rusage" $pid 5 $n "$name" >> "$out"
  wait
  [[ -n $inst ]] && cat "$out.inst.$name" | grep -E 'TOTAL' >> "$out" && rm "$out.inst.$name"
  echo "syncs during $name: $(( $(grep -c 'POST /v1/sync' "$wlog") - before ))" >> "$out"
  files >> "$out"
}
: > "$out"
phase background
"$T/appctl" $pid hide > /dev/null; sleep 1
phase hidden
"$T/appctl" $pid unhide > /dev/null; "$T/appctl" $pid front > /dev/null; sleep 1
phase front
echo "done $(date +%T)" >> "$out"
