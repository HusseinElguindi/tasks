#!/bin/zsh
# Builds a scratch Release copy of the Mac app for performance measurement (coord title-design T8).
#
#   app/Scripts/perf/build.sh <out-dir> [--automation]
#
# It copies app/, widgets/ and ios/Widgets into <out-dir>/src and builds there, so the worktree is never touched.
# The copy differs from a real Release build in three ways, all so it can't touch the installed app:
#   - its own bundle ids (com.elguindi.Tasks.perf, .perf.Widgets) and name ("Tasks Perf"): its own defaults, saved
#     state and Launch Services entry;
#   - its widget feed goes to <group>/Tasks Perf/, never the installed app's <group>/Tasks/;
#   - get-task-allow is on, so vmmap, heap, leaks and xctrace can read it. That changes nothing at run time.
# --automation also compiles the DEBUG-only tooling (-debugScript and friends) into an optimized (-O) build, to drive
# typing, scrolling and dragging without synthetic events. Measure idle, memory and disk with the plain build.
#
# Never passes -allowProvisioningUpdates: the build needs only the Apple Development certificate already in the
# login keychain (app/Signing.xcconfig).
set -euo pipefail
out=${1:?usage: build.sh <out-dir> [--automation]}
automation=${2:-}
repo=${0:A:h:h:h:h}
src=$out/src
mkdir -p "$src/ios"
rsync -a --delete --exclude .build --exclude Tasks.xcodeproj "$repo/app/" "$src/app/"
rsync -a --delete "$repo/widgets/" "$src/widgets/"
rsync -a --delete "$repo/ios/Widgets/" "$src/ios/Widgets/"

# The widget feed's folder: "Tasks Perf", never "Tasks" or "Tasks Dev".
perl -0pi -e 's/\.map \{ WidgetFolder\.url\(in: \$0, debug: isDebug\) \}/.map { \$0.appendingPathComponent("Tasks Perf", isDirectory: true) }/' \
  "$src/widgets/Shared/WidgetGroup.swift"
grep -q '"Tasks Perf"' "$src/widgets/Shared/WidgetGroup.swift" || { echo "widget folder patch failed" >&2; exit 1; }

# Own bundle ids and name.
perl -pi -e 's/PRODUCT_BUNDLE_IDENTIFIER: com\.elguindi\.Tasks$/PRODUCT_BUNDLE_IDENTIFIER: com.elguindi.Tasks.perf/;
              s/PRODUCT_BUNDLE_IDENTIFIER: com\.elguindi\.Tasks\.Widgets$/PRODUCT_BUNDLE_IDENTIFIER: com.elguindi.Tasks.perf.Widgets/;
              s/^(\s+)PRODUCT_NAME: Tasks$/$1PRODUCT_NAME: Tasks Perf/' "$src/app/project.yml"
grep -q 'com.elguindi.Tasks.perf$' "$src/app/project.yml" || { echo "bundle id patch failed" >&2; exit 1; }

(cd "$src/app" && xcodegen generate --quiet)

extra=()
if [[ $automation == --automation ]]; then
  extra=(SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG GCC_PREPROCESSOR_DEFINITIONS='DEBUG=1')
fi
xcodebuild -project "$src/app/Tasks.xcodeproj" -scheme Tasks -configuration Release \
  -derivedDataPath "$out/dd" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES "${extra[@]}" build -quiet
app="$out/dd/Build/Products/Release/Tasks Perf.app"
echo "built: $app"

# The copy to run: without the widget extension, so launching it never registers a second set of Tasks widgets.
rm -rf "$out/run" && mkdir -p "$out/run" && ditto "$app" "$out/run/Tasks Perf.app"
rm -rf "$out/run/Tasks Perf.app/Contents/PlugIns"
codesign --force --sign "Apple Development" --preserve-metadata=entitlements,identifier "$out/run/Tasks Perf.app" 2>/dev/null \
  || echo "note: re-signing the run copy failed; it runs with a broken seal" >&2
echo "run copy: $out/run/Tasks Perf.app"
