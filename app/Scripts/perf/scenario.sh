#!/bin/zsh
# One interaction scenario on the automation build (build.sh --automation): launch with a fresh copy of a data folder,
# run -debugScript steps, sample the process every 0.5 s while it runs, and take footprint / vmmap / heap / leaks during
# the script's last wait (coord title-design T8).
#
#   app/Scripts/perf/scenario.sh <tools-dir> <app-executable> <name> <seed-data-dir|demo[:N]> <server-url> <steps> <out-dir>
#
# The steps should end with a wait of at least 20000 ms: the memory tools run 6 s into it. <seed-data-dir> is copied, so
# the seed is never written; `demo` starts from an empty folder with -demoData (and -demoBulk N). Sync goes to
# <server-url> with the local token "perflocal" (a local wrangler dev, or http://127.0.0.1:9 for nowhere).
set -u
T=$1 exe=$2 name=$3 seed=$4 server=$5 steps=$6 out=$7
mkdir -p "$out"
data="$out/$name.data"
rm -rf "$data"
extra=()
case $seed in
  demo*) mkdir -p "$data"; extra=(-demoData YES); [[ $seed == demo:* ]] && extra+=(-demoBulk ${seed#demo:}) ;;
  *) cp -Rp "$seed" "$data" ;;
esac
r=$("$T/launchtime" "$exe" -dataDirectory "$data" -serverURL "$server" -syncToken perflocal "${extra[@]}" -debugScript "$steps")
pid=$(echo "$r" | awk '/^pid/{print $2}')
echo "$r" > "$out/$name.launch"
"$T/rusage" $pid ${RUSAGE_DT:-0.5} 1200 "$name" > "$out/$name.rusage" &
rp=$!
# The memory tools, once the script is in its final wait: when the samples show the CPU back near zero for 3 s.
(
  quiet=0
  while kill -0 $pid 2>/dev/null; do
    sleep 0.5
    c=$(tail -1 "$out/$name.rusage" | sed -n 's/.*cpu \([0-9.]*\)%.*/\1/p')
    [[ -n $c ]] && (( c < 1.0 )) && quiet=$((quiet + 1)) || quiet=0
    n=$(grep -c . "$out/$name.rusage")
    if (( quiet >= 6 && n > 8 )); then
      footprint $pid > "$out/$name.footprint" 2>&1
      vmmap --summary $pid > "$out/$name.vmmap" 2>&1
      heap -s $pid > "$out/$name.heap" 2>&1
      leaks $pid > "$out/$name.leaks" 2>&1
      break
    fi
  done
) &
mp=$!
while kill -0 $pid 2>/dev/null; do sleep 0.5; done
kill $rp 2>/dev/null; wait $rp $mp 2>/dev/null
ls -la "$data" > "$out/$name.files"
echo "$name: $(grep -c . "$out/$name.rusage") samples; $(grep -m1 -o 'Footprint: [0-9.]* [KMG]B' "$out/$name.footprint" 2>/dev/null)"
