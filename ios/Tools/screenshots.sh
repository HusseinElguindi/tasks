#!/bin/zsh
# Captures the named screenshot set into Screenshots/ on one booted iPhone simulator, one launch at a time.
#   Tools/screenshots.sh [device-id]
set -e
cd "$(dirname "$0")/.."
dev=${1:-0A00313D-1B20-4CC6-810F-2E7A72852D35}
out=Screenshots
mkdir -p $out
xcrun simctl status_bar $dev override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null || true

shot() { local name=$1; shift; Tools/shot.sh $dev $out/$name.png 2.5 -sampleData YES "$@" >/dev/null; echo "  $name"; }

shot iphone-01-home                   -screen home -appearance dark -style classic
shot iphone-02-today                  -screen today -appearance dark -style classic
shot iphone-03-list-with-headings     -screen list:phys -appearance dark -style classic
shot iphone-04-list-school            -screen list:school -completed school -appearance dark -style classic
shot iphone-05-upcoming               -screen upcoming -appearance dark -style classic
shot iphone-06-detail-sheet           -screen detail:i5 -appearance dark -style classic
shot iphone-07-when-picker            -screen when:s4 -appearance dark -style classic
shot iphone-08-new-task               -screen newtask -appearance dark -style classic
shot iphone-09-complete-undo          -screen notice -hold YES -appearance dark -style classic
shot iphone-11-trash                  -screen trash -expand w26 -appearance dark -style classic
shot iphone-12-settings               -screen settings -appearance dark -style classic
shot iphone-13-light                  -screen list:school -appearance light -style classic
shot iphone-14-light-today            -screen today -appearance light -style classic
shot iphone-15-glass                  -screen today -style glass -appearance dark
shot iphone-17-light-home             -screen home -appearance light -style classic
