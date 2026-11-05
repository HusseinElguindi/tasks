# Tasks for iPhone and iPad

The iOS app, in SwiftUI (Swift 6, complete strict concurrency), built from the Tasks designs and the Pane design
system. It lives in `ios/` and runs on `app/TasksCore`, the Mac app's own package: the data and its file format, every
change (ops, undo), Today, the views' grouping (`ViewGroups`), dates and their labels, ordering, Markdown and sync are
the Mac's own code. The app adds only the screens and their state (`Tasks/Model/AppModel.swift`).

Its data is in the app's Application Support: `Tasks` for Release builds, `Tasks Dev` for Debug ones (they share one
container on iOS, so they keep their data apart, as the Mac's two apps do).

## Sync

Settings ▸ Sync: the server URL (`https://tasks.elguindi.workers.dev` unless changed) and the token, the Worker's
`API_TOKEN`, pasted once into a secure field and kept in the Keychain (service `com.elguindi.Tasks.sync`, account
`API_TOKEN`, this device only); it's never shown again. TasksCore syncs about a second after each change; the app
also syncs at launch, on coming to the front, every 30 s while in front, and on pull to refresh. Nothing syncs in
the background. Home shows how it's going under the views; Settings shows the status and has Sync Now.

Debug builds only talk to a local `wrangler dev` (`localhost` or `127.0.0.1`), as the Mac's do, unless the
`allowRemoteServer` default is set; the sample data never syncs. To try it against `server/` (`pnpm dev`, with a
throwaway `API_TOKEN` in its `.dev.vars`), launch with `-serverURL http://127.0.0.1:8787 -syncToken <that token>`
(Debug only), or type them into Settings. `testSyncTokenInSettings` does the Settings path when
`TEST_RUNNER_SYNC_TEST_TOKEN` holds that throwaway token, and skips otherwise. XCTest writes what it types into its
log and result bundle, so use it only with a local throwaway token, and delete `build/Logs/Test` afterwards.

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
# The smoke set (Smoke.xctestplan, ~6 min): add, check, swipe, details, dates, Trash, Settings, headings, notes, drags,
# the press, select, undo and sync, for before a phone install. The full suite (Full.xctestplan, the default) runs once
# per batch, before a push or merge.
xcodebuild test -project Tasks.xcodeproj -scheme Tasks -testPlan Smoke -destination 'id=<sim>' -derivedDataPath build \
  -parallel-testing-enabled NO
# TasksCore's own tests and the theme's (TasksThemeTests), on iOS. CODE_SIGNING_ALLOWED=NO because the test bundle's
# copied Resources folder fails ad hoc signing on the simulator; that's why they have a scheme of their own.
xcodebuild test -project Tasks.xcodeproj -scheme TasksCoreTests -destination 'id=<sim>' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO
```

Run TasksCore's tests through this project, not from `app/TasksCore`: the package's own scheme also builds the
Mac-only CLI, and building there writes `.swiftpm/` into `app/TasksCore`. (The `tasks`, `TasksCLITests` and
`TasksCore` schemes that Xcode lists come from the package; the CLI ones are Mac-only.)

## Launch arguments

| Argument | Values |
|---|---|
| `-sampleData YES` | the sample lists and tasks, made with the Store's own actions in a scratch store (`Library/Caches/Sample Data`), fresh at each launch; never the app's data |
| `-dataDirectory <path>` | the store's folder (testing) |
| `-serverURL <url>` | the sync server, over Settings, without saving |
| `-syncToken <token>` | Debug only: a local server's throwaway token, over the Keychain |
| `-screen` | `home` `today` `upcoming` `undated` `completed` `trash` `list:<id>` `detail:<taskID>` `when:<taskID>` `deadline:<taskID>` `settings` `newtask` `notice` |
| `-appearance` | `system` (the default) `light` `dark`; wins over Settings without being saved |
| `-style` | `classic` `glass` |
| `-expand <listID>` | opens a deleted list in Trash (`w26`, `move`) |
| `-completed <listID>` | opens a list's Completed |
| `-hold YES` | keeps notices and just-checked rows on screen |
| `-remoteTask <taskID>` with `-remoteTitle <text>` and/or `-remoteNotes <text>`; `-remoteList <listID>` with `-remoteName <text>` | Debug only, for UI tests: that change, as if another device made it, each time the test posts the Darwin notification `com.elguindi.Tasks.test.remote-edit` (`Tasks/App/RemoteEdit.swift`) |

With `-sampleData`, lists go by short names: `inbox` `school` `phys` `tasks` `home` `errands`, and in Trash `w26`
`move`. Task ids are in `Tasks/Model/SampleData.swift`.

## Layout

- The theme is the Mac's, from the TasksTheme package (`app/TasksCore/Sources/TasksTheme`): Rex with the Ember accent,
  its tokens, and the lit tiles' finish (`TileArt`). `Tasks/Theme/Theme.swift` turns its values into SwiftUI colours;
  `Tasks/Theme/Palette.swift` holds its tokens for one appearance, by the Mac's names. A list tile and the logo mark's
  head are drawn by `TileArt`, as on the Mac (`ListTile` and `LogoMark` in `Tasks/Views/Components.swift`).
- `Tasks/Theme/Metrics.swift`: the phone's row grid (48pt rows, 22pt rings), type and motion.
- `Tasks/Model/AppModel.swift`: the UI state next to TasksCore's `Store` (navigation, sheets, open disclosures, the
  notice and its Undo, the draft, the appearance, rows checked a moment ago) and the actions, each a Store action.
- `Tasks/Model/Lines.swift`: what each view shows, read from the projection's buckets and grouped by `ViewGroups`.
- `Tasks/Model/SampleData.swift`: the sample, made with Store actions on a clock it moves, dates relative to today.
- `Tasks/Model/Sync.swift`: the Keychain, the sync config and triggers, and what Home and Settings say about sync.
- `Tasks/App/TasksApp.swift`: opening the store, the day and background triggers, the launch arguments.
- `Tasks/Views/`: home, list screen, rows, task detail, the When and Deadline picker, settings, and the root (a stack
  on iPhone, three panes on iPad). `MarkdownView.swift` draws notes from TasksCore's Markdown reading.
- `TasksUITests/FlowTests.swift`: adds tasks, completes and undoes, swipes, edits a date, deletes a list, changes the appearance.
- `Tools/MakeIcon.swift`: renders the app icon from the 04 · Log mark.
- `Tools/shot.sh`, `Tools/screenshots.sh`: screenshots on a simulator from the launch arguments above.
- `Tools/tailscale-bridge.py`: installs on the phone over Tailscale when it isn't on the Mac's network, by bridging
  Xcode's wireless connection (setup and usage in its header).
