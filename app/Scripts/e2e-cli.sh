#!/bin/bash
# End-to-end check for the agent CLI (docs/SDK-PLAN.md phase 2): the `tasks` CLI and a scratch Debug app instance,
# each its own replica, against a local `wrangler dev` (never the deployed Worker). Both edit, online and offline;
# both converge and match fresh replicas; an agent's change is undone while a later app edit is kept; a wiped
# server is recovered by both.
#
#   cd server && pnpm exec wrangler dev --port 8791 --persist-to /tmp/wrangler-cli   # fresh state = empty log
#   app/Scripts/e2e-cli.sh /tmp/tasks-e2e-cli phase1
#   # restart wrangler dev with a new --persist-to directory: the server log is wiped
#   app/Scripts/e2e-cli.sh /tmp/tasks-e2e-cli phase2
#
# APP and TASKS_CLI override the app and CLI binaries; TASKS_DEV_URL the server.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="${APP:-$ROOT/app/.build/DerivedData/Build/Products/Debug/Tasks Dev.app/Contents/MacOS/Tasks Dev}"
CLI="${TASKS_CLI:-$ROOT/app/TasksCore/.build/debug/tasks}"
E=$1
TOKEN="${TASKS_DEV_TOKEN:-$(sed -n "s/^API_TOKEN=//p" "$ROOT/server/.dev.vars")}"
GOOD="${TASKS_DEV_URL:-http://127.0.0.1:8791}"
DEAD=http://127.0.0.1:9
case "$GOOD" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *) echo "Refusing to run against $GOOD: the end-to-end check only talks to a local wrangler dev." >&2; exit 1 ;;
esac
FAILED=0
check() { # description, then a command that must succeed
  local what=$1; shift
  if "$@"; then echo "  ok   $what"; else echo "  FAIL $what"; FAILED=1; fi
}
run() { # dir url dump actions [extra args…]: one app launch (performs actions, syncs, dumps, quits)
  local dir=$1 url=$2 dump=$3 actions=$4; shift 4
  timeout 90 "$APP" -dataDirectory "$E/$dir" -serverURL "$url" -syncToken "$TOKEN" \
    -debugActions "$actions" -debugDumpTo "$E/$dump.json" "$@" >/dev/null 2>&1
  printf '  app %-3s %-3s pending=%s cursor=%s\n' "$dump" "$dir" "$(jq .pending "$E/$dump.json")" "$(jq .cursor "$E/$dump.json")"
}
cli() { # the CLI on its replica in $E/cli (or $CLIDIR); never the user's env file or Keychain
  TASKS_URL="$GOOD" TASKS_TOKEN="$TOKEN" TASKS_ENV_FILE=/dev/null TASKS_DATA_DIR="${CLIDIR:-$E/cli}" \
    TASKS_ACTOR=agent:e2e TASKS_RETRIES=0 "$CLI" "$@"
}
ref() { cli find "$1" --ids --cached | head -1; }
# A replica's visible state, normalized the same way for the app's dump and the CLI.
app_state() {
  jq -S '{tasks: [.visible.tasks[] | {id, list, title, when: (.when // null), deadline: (.deadline // null),
          done: (.completedAt != null), deleted}] | sort_by(.id),
          lists: [.visible.lists[] | {id, name, archived: (.archivedAt != null)}] | sort_by(.id)}' "$E/$1.json"
}
cli_state() {
  jq -S -n --argjson t "$(cli find "" --deleted --json --cached)" --argjson a "$(cli lists --json --cached)" \
    --argjson b "$(cli deleted --json --cached)" \
    '{tasks: [$t[] | {id, list, title, when, deadline, done, deleted}] | sort_by(.id),
      lists: [($a + $b)[] | {id, name, archived: (.archivedAt != null)}] | sort_by(.id)}'
}
same() { # labels: states identical?
  local first="" ok=1
  for label in "$@"; do
    local h; h=$(cat "$E/state-$label.json" | shasum | cut -c1-12)
    [ -z "$first" ] && first=$h
    [ "$h" = "$first" ] || ok=0
    printf '  %-12s %s\n' "$label" "$h"
  done
  check "converged: $*" test $ok = 1
}
case "${2:-phase1}" in
phase1)
  # Start from empty data directories, but only ever delete a directory this script made.
  if [ -e "$E" ] && [ ! -e "$E/.tasks-e2e-cli" ]; then echo "$E exists and wasn't made by this script; pick a new path." >&2; exit 1; fi
  rm -rf "$E"; mkdir -p "$E"; touch "$E/.tasks-e2e-cli"
  run A $GOOD A1 '[]' -demoData YES
  check "the CLI sees the app's lists" test "$(cli lists --json | jq -c '[.[].name]')" = "$(jq -c .lists "$E/A1.json")"
  check "the CLI's Today is the app's" test "$(cli today --json | jq -c '[.groups[].tasks[].title]')" = "$(jq -c .today "$E/A1.json")"

  # The agent's changes, online. Each is one batch.
  HEAT=$(ref "Call landlord about the heating")
  MOVE=$(cli move "$HEAT" --to School --json | jq -r .batch)
  cli when fri "$(ref "Book flu shot")" "$(ref "Pick up prescription")" >/dev/null
  cli add "From the agent" --list Home --today >/dev/null
  cli done "$(ref "Write sync log spec")" >/dev/null
  # An agent change made offline: queued, exit 75.
  cli add "Agent offline" --list Home --cached >/dev/null 2>&1; check "an offline write exits 75" test $? = 75

  # The app, offline: renames the task the agent moved, and adds one.
  run A $DEAD A2 '[{"rename":"Call landlord about the heating","to":"Call landlord (app)"},{"createTask":"Offline on A","list":"Home","when":"today"}]'
  # Both online.
  cli sync >/dev/null
  run A $GOOD A3 '[]'
  cli sync >/dev/null

  # Undo the agent's move: the task goes back to Home, and the app's later rename is kept.
  cli undo "$MOVE" | sed 's/^/  cli: /'
  run A $GOOD A4 '[]'
  cli sync >/dev/null
  check "the undo moved it back" test "$(cli show "$HEAT" --json | jq -r .listName)" = Home
  check "the app's later rename was kept" test "$(cli show "$HEAT" --json | jq -r .title)" = "Call landlord (app)"
  check "the app sees the undo" test "$(jq -r --arg id "$HEAT" '.visible.lists[.visible.tasks[$id].list].name' "$E/A4.json")" = Home
  check "the log credits the agent's changes to it" test "$(cli log --actor 'agent:*' --json --cached | jq length)" -ge 6
  check "the app's changes have no actor" test "$(cli log --actor app --json --cached | jq length)" -ge 1

  # Fresh replicas from 0 match.
  run C $GOOD C1 '[]'
  app_state A4 > "$E/state-appA.json"
  app_state C1 > "$E/state-appC.json"
  cli_state > "$E/state-cli.json"
  CLIDIR="$E/cli2" cli sync >/dev/null
  CLIDIR="$E/cli2" cli_state > "$E/state-cli2.json"
  same appA appC cli cli2
  ;;
phase2)
  # The server log was wiped (fresh wrangler dev state). Both replicas recover it; fresh ones see everything.
  cli sync | sed 's/^/  cli: /'
  run A $GOOD A5 '[]'
  cli sync >/dev/null
  run A $GOOD A6 '[]'
  run D $GOOD D1 '[]'
  app_state A6 > "$E/state-appA6.json"
  app_state D1 > "$E/state-appD.json"
  cli_state > "$E/state-cli-recovered.json"
  CLIDIR="$E/cli3" cli sync >/dev/null
  CLIDIR="$E/cli3" cli_state > "$E/state-cli3.json"
  same appA appA6 appD cli-recovered cli3
  ls "$E/A" "$E/cli/"* | grep -c 'bak-' | sed 's/^/  backups left: /'
  ;;
esac
exit $FAILED
