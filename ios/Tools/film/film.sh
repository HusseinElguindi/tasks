#!/bin/bash
# film.sh <name> [test]: records the booted simulator ($UDID) at full frame rate while a FilmTests script runs, from a
# build-for-testing in ios/build. Writes <name>.mov, <name>.log (with its FILM marks) and <name>.start into $FILM_DIR
# (default /tmp/tasks-film). Then: events.py <name> (each mark's burst of frames), rows.py / sync.py (each frame's
# heading rules and task rings, in points), strip.py (frames side by side, to look at).
set -u
D=${FILM_DIR:-/tmp/tasks-film}
mkdir -p "$D"
UDID=${UDID:?the simulator id}
TEST=${2:-TasksUITests/FilmTests/testFilm}
cd "$(dirname "$0")/../.."
xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$D/$1.mov" 2> "$D/$1.rec" &
rec=$!
for i in $(seq 1 100); do grep -q "Recording started" "$D/$1.rec" 2>/dev/null && break; python3 -c 'import time; time.sleep(0.1)'; done
python3 -c 'import time; print("%.3f" % time.time())' > "$D/$1.start"
TEST_RUNNER_FILM=1 xcodebuild test-without-building -project Tasks.xcodeproj -scheme Tasks -destination "id=$UDID" \
  -derivedDataPath build -parallel-testing-enabled NO -disable-concurrent-destination-testing -only-testing:"$TEST" \
  > "$D/$1.log" 2>&1
python3 -c 'import time; time.sleep(1)'
kill -INT $rec; wait $rec
grep -E "FILM|Test Case.*(passed|failed)|error:" "$D/$1.log" | head -40
