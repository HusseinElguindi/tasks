# Measuring the drag on the phone

Instruments can't reach the phone over the Tailscale bridge, so the app measures itself. The probes are compiled
only into Debug builds and into builds with the Swift condition `PERF_PROBE`. A shipped Release build has none of them;
`strings` on its binary finds no "launch frameProbe". At run time they are on only with launch arguments, which are
never saved, so a launch from the home screen runs as usual even in a probe build.

## Build (Release, with the probes)

```sh
cd ios && xcodegen generate
xcodebuild -project Tasks.xcodeproj -scheme Tasks -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/perf -allowProvisioningUpdates \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) PERF_PROBE' build
# the app: build/perf/Build/Products/Release-iphoneos/Tasks.app
```

Keep its derived data (`build/perf`, ignored by git) apart from the shipping build's. Afterwards, install a build without
`PERF_PROBE` over it.

## Run

```sh
xcrun devicectl device install app --device <phone> build/perf/Build/Products/Release-iphoneos/Tasks.app
xcrun devicectl device process launch --device <phone> --terminate-existing com.elguindi.Tasks -- \
  -frameProbe YES -dragTrace YES
```

- `-frameProbe YES`: every display frame from launch, to `tmp/frame-trace.log` (FrameProbe.swift).
- `-dragTrace YES`: every frame of each drag, from the lift to 0.5 s after the set-down, to `tmp/drag-trace.log`
  (DragProbe, in TaskCollection+Drag.swift).

Both logs are appended to on every probe launch. Delete them (or copy them away) between runs. They are written
about once a second, and again when the app leaves the foreground: before copying, send the app to the background
(or just wait 2 s).

## Copy back

```sh
xcrun devicectl device copy from --device <phone> --domain-type appDataContainer \
  --domain-identifier com.elguindi.Tasks --source tmp/frame-trace.log --destination frame-trace.log
xcrun devicectl device copy from --device <phone> --domain-type appDataContainer \
  --domain-identifier com.elguindi.Tasks --source tmp/drag-trace.log --destination drag-trace.log
```

## Read

```sh
python3 ios/Tools/perf/drags.py frame-trace.log drag-trace.log            # per drag: frames, finger, copy, gap
python3 ios/Tools/perf/drags.py frame-trace.log drag-trace.log --frames 2 # drag 2, frame by frame
```

The script's docstring explains each figure. The log formats are in FrameProbe.swift and DragProbe's doc comment.
