#!/bin/zsh
# Captures the named screenshot set into Screenshots/ on one booted iPhone simulator, one launch at a time.
#   Tools/screenshots.sh [device-id]
set -e
cd "$(dirname "$0")/.."
dev=${1:-0A00313D-1B20-4CC6-810F-2E7A72852D35}
out=Screenshots
mkdir -p $out
xcrun simctl status_bar $dev override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null || true

shot() { local name=$1; shift; Tools/shot.sh $dev $out/$name.png 2.5 "$@" >/dev/null; echo "  $name"; }

shot iphone-01-home                  -screen home
shot iphone-02-today                 -screen today
shot iphone-03-list-with-headings    -screen list:phys
shot iphone-04-list-school           -screen list:school -completed school
shot iphone-05-upcoming              -screen upcoming
shot iphone-06-detail-sheet          -screen detail:i5
shot iphone-07-when-picker           -screen when:s4
shot iphone-08-new-task              -screen newtask
shot iphone-09-complete-undo         -screen notice -hold YES
shot iphone-11-trash                 -screen trash -expand w26
shot iphone-12-settings              -screen settings
shot iphone-13-light                 -screen list:school -appearance light
shot iphone-14-paper-light-today     -screen today -theme paper -appearance light
shot iphone-15-glass-iris            -screen today -style glass -theme iris
shot iphone-17-harbor-light-home     -screen home -theme harbor -appearance light
