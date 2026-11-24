#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

SHELL_LUA="$ROOT/default/hypr/shell.lua"

grep -Fq 'monarch.autostart("monarch-shell-start")' "$SHELL_LUA" || fail "the shell starts at login"
pass "the shell autostarts"

# These binds must exist in the final shell layer; a missing one fails the build.
for bind in \
  '"monarch-capture-webcam-resize smaller"' \
  '"monarch-capture-webcam-resize larger"' \
  '"monarch-menu-keybindings"' \
  '"monarch-system-lock"' \
  '"monarch-toggle-notification-silencing"' \
  '"monarch-osd volume up"' \
  '"monarch-osd brightness down"'; do
  grep -Fq "$bind" "$SHELL_LUA" || fail "shell.lua binds $bind"
done
pass "webcam, menu, lock, toggle and OSD binds are present"

# Every monarch-* command a bind launches must exist in bin/.
missing=0
while read -r command; do
  [[ -x $ROOT/bin/$command ]] || { echo "bound command is missing: $command" >&2; missing=1; }
done < <(grep -o 'monarch\.cmd("[^"]*", "monarch-[a-z0-9-]*' "$SHELL_LUA" | sed 's/.*"monarch-/monarch-/' | sort -u)
[[ $missing == 0 ]] || fail "every bound monarch command exists"
pass "every bound monarch command exists in bin/"
