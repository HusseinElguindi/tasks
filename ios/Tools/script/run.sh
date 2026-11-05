#!/bin/zsh
# Runs an in-app debug script (ios/Tasks/App/DebugScript.swift) in the simulator or on the phone, waits for its done
# marker and copies its output (the app container's tmp/script/) back. README.md has the steps and examples.
#
#   run.sh [--sim UDID | --phone DEVICE] [--app Tasks.app] [--out DIR] [--timeout S] [--] (-e "STEPS" | SCRIPT_FILE) [APP ARGS…]
#
#   --sim UDID     the simulator (default: the booted one). The app must be installed, or give --app.
#   --phone DEVICE devicectl's device (its name, UDID or identifier). The app there must be a Debug or PERF_PROBE build.
#   --app PATH     installs this Tasks.app first.
#   --out DIR      where tmp/script/ goes (default: ./script-out, emptied first).
#   --timeout S    how long to wait for the done marker (default 120).
#   -e STEPS       the steps on the command line; otherwise SCRIPT_FILE is copied into the container and read from there.
#   APP ARGS       more launch arguments, e.g. -sampleData YES -screen list:phys
#
# Exit: 0 when the script ran clean, 1 when it logged errors (run.txt's ERR lines), 2 on a timeout or a failed launch.
set -u
BUNDLE=com.elguindi.Tasks
sim="" phone="" app="" out="./script-out" timeout=120 steps="" file=""
while (( $# )); do
  case $1 in
    --sim) sim=$2; shift 2 ;;
    --phone) phone=$2; shift 2 ;;
    --app) app=$2; shift 2 ;;
    --out) out=$2; shift 2 ;;
    --timeout) timeout=$2; shift 2 ;;
    -e) steps=$2; shift 2 ;;
    --) shift; break ;;
    -h|--help) sed -n 2,16p $0; exit 0 ;;
    *) if [[ -z $steps && -z $file && $1 != -* ]]; then file=$1; shift; else break; fi ;;
  esac
done
extra=("$@")
[[ -z $steps && -z $file ]] && { echo "run.sh: give -e STEPS or a script file" >&2; exit 2; }
[[ -n $file && ! -f $file ]] && { echo "run.sh: no file $file" >&2; exit 2; }
token="r$(date +%s)-$RANDOM"
if [[ -n $steps ]]; then script=(-debugScript "$steps"); else script=(-debugScriptFile tmp/script-in.txt); fi
rm -rf "$out"; mkdir -p "$out"

if [[ -z $phone ]]; then
  [[ -z $sim ]] && sim=booted
  [[ -n $app ]] && { xcrun simctl install $sim "$app" || exit 2; }
  data=$(xcrun simctl get_app_container $sim $BUNDLE data) || { echo "run.sh: Tasks isn't installed on $sim" >&2; exit 2; }
  mkdir -p "$data/tmp"
  rm -rf "$data/tmp/script"
  [[ -n $file ]] && cp "$file" "$data/tmp/script-in.txt"
  xcrun simctl launch --terminate-running-process $sim $BUNDLE "${script[@]}" -debugScriptToken $token "${extra[@]}" >/dev/null || exit 2
  end=$(( SECONDS + timeout ))
  until grep -q "^$token " "$data/tmp/script/done" 2>/dev/null; do
    (( SECONDS > end )) && { echo "run.sh: no done marker after ${timeout}s" >&2; cp -R "$data/tmp/script/." "$out/" 2>/dev/null; exit 2; }
    sleep 0.5
  done
  cp -R "$data/tmp/script/." "$out/"
else
  dc() { xcrun devicectl device "$@" --device "$phone" -q; }
  cf() { dc copy from --domain-type appDataContainer --domain-identifier $BUNDLE --source "$1" --destination "$2"; }
  [[ -n $app ]] && { dc install app "$app" || exit 2; }
  [[ -n $file ]] && { dc copy to --domain-type appDataContainer --domain-identifier $BUNDLE --source "$file" --destination tmp/script-in.txt || exit 2; }
  dc process launch --terminate-existing $BUNDLE -- "${script[@]}" -debugScriptToken $token "${extra[@]}" >/dev/null || exit 2
  tmp=$(mktemp -d)
  end=$(( SECONDS + timeout ))
  until cf tmp/script/done "$tmp/done" >/dev/null 2>&1 && grep -q "^$token " "$tmp/done"; do
    (( SECONDS > end )) && { echo "run.sh: no done marker after ${timeout}s" >&2; rm -rf "$tmp"; exit 2; }
    sleep 2
  done
  rm -rf "$tmp"
  cf tmp/script "$out" >/dev/null || { echo "run.sh: copying tmp/script back failed" >&2; exit 2; }
  # devicectl may put the folder itself inside the destination.
  [[ -d $out/script ]] && { mv "$out"/script/* "$out"/ && rmdir "$out/script"; }
fi

cat "$out/done"
grep ERR "$out/run.txt" >&2
grep -q " ok$" "$out/done"
