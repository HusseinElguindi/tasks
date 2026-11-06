# In-app debug scripts

A repro without XCUITest, as the Mac's `-debugScript`: the app runs a list of steps itself, writes logs and snaps into its
container, and quits. About half a second to launch, no test runner, and the same on the phone as in the simulator.

The runner is `ios/Tasks/App/DebugScript.swift`. Its header has the full step list. It's compiled only into Debug builds
and builds with `PERF_PROBE` (the phone's measuring build, `ios/Tools/perf/README.md`): `strings` on a shipped Release
binary finds no "debugScript". It runs only when launched with `-debugScript` or `-debugScriptFile`.

## What it can and can't do

iOS gives an app no public way to make touches. So:

- **Drags** run through our own press's phases (`PressDrag`'s lift, moved, release) at a scripted finger, with the same
  calls its action makes, on the task lists (`CollectionDrag`) and on Home. The copy, the gap, the slots, a heading's
  fold, the landing and the write are all the app's own, with the probes on.
- **Editing** starts through the app's own calls: a heading's Rename and Edit Notes, a list's Edit Notes, a task's
  details. The text goes to the first responder as `insertText` and `deleteBackward`, as the keyboard sends them. The
  keyboard's own machinery (autocorrect, its Return key's handling before `insertText`) is not involved.
- **Out of reach:** anything UIKit has to see a touch for. That means the long-press menu, the rows' SwiftUI buttons,
  swipes, scrolling by pan, and gesture arbitration (quick holds, the highlight). XCUITest stays the way to test those.

## Steps

Separated by `;` or new lines. In a step's text, `\;` is a semicolon, `\n` a Return and `\\` a backslash. In a file,
`#` starts a comment line. ROW is a task's, heading's or list's title, its id, or a list item's id (`h:<id>`, `header`).

| Step | Does |
|---|---|
| `drag:ROW,DY[,STEPS,MS]` | press ROW's middle, hold 0.35 s (the lift), move DY pt in STEPS (10) moves MS (16) ms apart, let go |
| `down:ROW` `move:DY[,STEPS,MS]` `up` `cancel` | the same, a phase at a time (`move` is from where the finger is; `cancel`: the touch taken away) |
| `edit:ROW[:notes\|:title]` | a heading's name or notes, a list's notes (`edit:header:notes`) or name, a task's title or notes (its details open) |
| `type:TEXT` `ret` `del[:N]` | characters to the first responder; Return; N backspaces |
| `caret:N` | the caret to character N of the field being typed into (`-N`: N before its end) |
| `done` | the list's Done (the draft ends and writes), or the details' Done |
| `open:LIST` `home` `collapse:HEADING` `undo` `redo` `wait:MS` | navigation and the model, through the app's own calls |
| `snap:NAME` | the window, `NAME.png` (drawHierarchy, afterScreenUpdates false: what's drawn, no keyboard) |
| `log:NAME` | appends to `NAME.txt`: the drag probe's fields and the drag's state, the field being typed into (text, selection, caret rect), the shown rows' frames |
| `frames:MS[:NAME]` | for MS ms, every display frame's caret and rows as drawn (presentation layers), and the field and its views up to its cell as drawn (after `\|\|`, with its offset `tvoff=drawn/model`), to `NAME.txt` (`frames.txt`) |
| `quit` | the app exits once the done marker is written |

All points are window points. Output goes to the container's `tmp/script/`, emptied at each launch: `run.txt` (each
step, in ms from the first, and any `ERR` line), the snaps and logs, and `done` ("<token> ok" or "<token> errors=N").

## Running

```sh
# The simulator (the booted one, or --sim UDID). --app installs a build first.
ios/Tools/script/run.sh --app build/Build/Products/Debug-iphonesimulator/Tasks.app --out out \
  ios/Tools/script/examples/notes-returns.txt -sampleData YES -screen list:phys

# A one-liner.
ios/Tools/script/run.sh --out out -e "drag:Labs,-120;wait:600;log:after;quit" -sampleData YES -screen list:phys

# The phone: a Debug or PERF_PROBE build on it (ios/Tools/perf/README.md has the PERF_PROBE build).
ios/Tools/script/run.sh --phone <device> --out out ios/Tools/script/examples/drag-heading.txt -sampleData YES -screen list:phys
```

`run.sh` gives the launch a token (`-debugScriptToken`), so it never reads an earlier run's marker. It waits for the
done marker and copies `tmp/script/` into `--out`. Then it prints the marker and any `ERR` lines, and exits 0 for a
clean run, 1 for one with errors, or 2 for a timeout or a failed launch. A script file is copied into the container
(`tmp/script-in.txt`) and read with `-debugScriptFile`. In the simulator that uses `simctl`. On the phone it uses
`devicectl … copy to/from --domain-type appDataContainer --domain-identifier com.elguindi.Tasks`, as the probes do.

On the shared simulator, hold the sim lease while it runs (coord's `lease.sh sim acquire`).

From a UI test, check for the element `debugScript` instead: its value is the done marker and its label is the output
folder's path. `TasksUITests/DebugScriptTests.swift` runs a scripted heading drag that way and reads its log.

## Examples

### (a) Drag the last heading up and back home, then edit its notes

`examples/drag-heading.txt`. It presses "Exam prep" (Physics' last heading), lifts it, and moves it 200 pt up (its
section folds into the copy and the gap opens two sections higher). It logs and snaps there, then moves back down
200 pt and lets go at its own place: a refused drop, so it flies home and nothing is written. Then it opens its notes,
types two lines, and ends with Done.

### (b) A heading's notes, and Return 20 times

`examples/notes-returns.txt`. It opens Labs' notes, types a line, then presses Return 20 times. After each Return it
waits 400 ms (the row's resize spring) and appends the caret, the text view's frame and offset, and the rows to
`caret.txt`. A last Return records its frames (`frames.txt`), and Done writes the notes.

To read the caret after each Return:

```sh
grep -o 'caret=[^ ]*' out/caret.txt    # x,y,w,h in the window, once per log
```
