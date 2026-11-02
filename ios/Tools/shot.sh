#!/bin/zsh
# Launch the app on a simulator with deep-link arguments and save a screenshot.
#   Tools/shot.sh <device-id> <out.png> <seconds-after-launch> [launch args…]
# Installs the simulator build from ios/build (the -derivedDataPath in README.md).
dev=$1; out=$2; wait=$3; shift 3
bundle=com.elguindi.Tasks
app=${0:A:h}/../build/Build/Products/Debug-iphonesimulator/Tasks.app
xcrun simctl terminate $dev $bundle >/dev/null 2>&1
xcrun simctl install $dev $app
xcrun simctl launch $dev $bundle "$@" >/dev/null
# Wait for the process, then for the first frames.
for i in {1..40}; do xcrun simctl spawn $dev launchctl list 2>/dev/null | grep -q "UIKitApplication:$bundle" && break; sleep 0.25; done
sleep 1.5
sleep $wait
xcrun simctl io $dev screenshot --type=png "$out" >/dev/null 2>&1 && echo "saved $out"
