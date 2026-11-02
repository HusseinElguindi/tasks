# Tasks for iPhone and iPad

The iOS app, in SwiftUI (Swift 6, complete strict concurrency), built from the Tasks designs and the Pane design
system. It lives in `ios/` and links `app/TasksCore`, the Mac app's own package. For now the interface still runs on
sample data in memory; nothing syncs or saves. Check off, add, rename, date, move, delete and restore all work on that
data.

Bundle id `com.elguindi.Tasks` (UI tests: `com.elguindi.TasksUITests`). iOS 26.

## Signing

The team isn't checked in. To run on a device, put it in `ios/Signing.local.xcconfig` (ignored by git), one line:

```
DEVELOPMENT_TEAM = <team id>
```

The team id is in Xcode ▸ Settings ▸ Accounts, or the Team menu under Signing & Capabilities. Without the file the app
still builds and runs in the simulator.

## Build and run

From `ios/`:

```sh
xcodegen generate                      # project.yml → Tasks.xcodeproj (not checked in)
open Tasks.xcodeproj                   # then Run on an iPhone simulator
```

From the command line (`<sim>` is a simulator id from `xcrun simctl list devices`):

```sh
xcodebuild -project Tasks.xcodeproj -scheme Tasks -destination 'id=<sim>' -derivedDataPath build build
Tools/shot.sh <sim> out.png 2 -screen list:phys        # install the build above, launch at a screen, screenshot
Tools/screenshots.sh <sim>                             # the named set, into Screenshots/
```

Tests:

```sh
# The UI flows; SHOTS is where each step's screenshot goes (default /tmp/tasks-shots). xcodebuild hands the test
# runner only TEST_RUNNER_-prefixed variables, minus the prefix.
TEST_RUNNER_SHOTS=$PWD/Screenshots/flow xcodebuild test -project Tasks.xcodeproj -scheme Tasks -destination 'id=<sim>' \
  -derivedDataPath build -only-testing:TasksUITests
# TasksCore's own tests, on iOS. CODE_SIGNING_ALLOWED=NO because the test bundle's copied Resources folder fails
# ad hoc signing on the simulator; that's why they have a scheme of their own.
xcodebuild test -project Tasks.xcodeproj -scheme TasksCoreTests -destination 'id=<sim>' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO
```

Run TasksCore's tests through this project, not from `app/TasksCore`: the package's own scheme also builds the
Mac-only CLI, and building there writes `.swiftpm/` into `app/TasksCore`. (The `tasks`, `TasksCLITests` and
`TasksCore` schemes that Xcode lists come from the package; the CLI ones are Mac-only.)

## Launch arguments

| Argument | Values |
|---|---|
| `-screen` | `home` `today` `upcoming` `undated` `completed` `trash` `list:<id>` `detail:<taskID>` `when:<taskID>` `deadline:<taskID>` `settings` `newtask` `notice` |
| `-theme` | `default` `paper` `contrast` `dusk` `harbor` `iris` `moss` |
| `-appearance` | `system` `light` `dark` |
| `-style` | `classic` `glass` |
| `-expand <listID>` | opens a deleted list in Trash (`w26`, `move`) |
| `-completed <listID>` | opens a list's Completed |
| `-hold YES` | keeps notices and just-checked rows on screen |

List ids: `inbox` `school` `phys` `tasks` `home` `errands`. Task ids are in `Tasks/Model/SampleData.swift`.

## Layout

- `Tasks/Theme/Palette.swift`: the theme engine, ported from `themes.js`. Seven themes, each in dark and light,
  every token mixed from base, ink and accent, then checked against the contrast floors. Default pins Rex's values.
- `Tasks/Theme/Metrics.swift`: the phone's row grid (48pt rows, 22pt rings), type and motion.
- `Tasks/Model/`: lists, headings, tasks; the store with every action and the lines each view shows; sample data
  with dates relative to today.
- `Tasks/Views/`: home, list screen, rows, task detail, the When and Deadline picker, settings, and the root (a stack
  on iPhone, three panes on iPad).
- `TasksUITests/FlowTests.swift`: adds tasks, completes and undoes, swipes, edits a date, deletes a list, changes theme.
- `Tools/MakeIcon.swift`: renders the app icon from the 04 · Log mark.
- `Tools/shot.sh`, `Tools/screenshots.sh`: screenshots on a simulator from the launch arguments above.
