#!/bin/bash
# Builds the agent CLI (`tasks`, docs/SDK-PLAN.md) in release, signs it, and copies it into a directory on PATH.
#
#   app/Scripts/install-cli.sh                    # → ~/.local/bin/tasks
#   app/Scripts/install-cli.sh --prefix ~/bin     # → ~/bin/tasks
#
# It's signed with the "Tasks Local Signing" identity when Scripts/make-signing-identity.sh has made it, so a
# Keychain "Always Allow" for the app's token survives rebuilds (README, Signing); otherwise ad hoc.
set -euo pipefail
PREFIX="$HOME/.local/bin"
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    *) echo "usage: $0 [--prefix DIR]" >&2; exit 2 ;;
  esac
done
PKG="$(cd "$(dirname "$0")/../TasksCore" && pwd)"
swift build -c release --package-path "$PKG" --product tasks
BIN="$(swift build -c release --package-path "$PKG" --show-bin-path)/tasks"
mkdir -p "$PREFIX"
cp "$BIN" "$PREFIX/tasks.new"
NAME="Tasks Local Signing"
if security find-identity -p codesigning 2>/dev/null | grep -qF "\"$NAME\""; then
  codesign --force --sign "$NAME" --identifier com.elguindi.tasks-cli "$PREFIX/tasks.new"
else
  echo "No \"$NAME\" identity (Scripts/make-signing-identity.sh makes it); signing ad hoc." >&2
  codesign --force --sign - --identifier com.elguindi.tasks-cli "$PREFIX/tasks.new"
fi
mv "$PREFIX/tasks.new" "$PREFIX/tasks"
echo "Installed $PREFIX/tasks"
case ":$PATH:" in *":$PREFIX:"*) ;; *) echo "Note: $PREFIX isn't on PATH." >&2 ;; esac
