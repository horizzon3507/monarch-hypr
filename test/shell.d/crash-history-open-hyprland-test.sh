#!/bin/bash
# `monarch-crash-history open` on Hyprland goes to the shell's crashes panel, and
# reports failure (exit 1 plus a message) when the panel cannot open, so a menu
# row can fall back to its terminal route. It never touches Noctalia there.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/runtime/bin" "$TMP/bin"
export CALLS="$TMP/calls"; : >"$CALLS"
# monarch-crash-history calls "$MONARCH_PATH/bin/monarch-panel"
printf '#!/bin/bash\necho "panel $*" >>"$CALLS"\nexit "${PANEL_STATUS:-0}"\n' >"$TMP/runtime/bin/monarch-panel"
printf '#!/bin/bash\necho "noctalia $*" >>"$CALLS"\nexit 0\n' >"$TMP/bin/noctalia"
chmod +x "$TMP/runtime/bin/monarch-panel" "$TMP/bin/noctalia"
export MONARCH_PATH="$TMP/runtime" HYPRLAND_INSTANCE_SIGNATURE=test PATH="$TMP/bin:$PATH"
fail() { echo "not ok - $1" >&2; exit 1; }
run() { rc=0; err=$(bash "$ROOT/bin/monarch-crash-history" "$@" 2>&1 >/dev/null) || rc=$?; }

PANEL_STATUS=0 run open
[[ $rc == 0 ]] || fail "open with a working panel exits $rc: $err"
grep -qx 'panel open crashes' "$CALLS" || fail "open did not ask the shell for the crashes panel: $(<"$CALLS")"
echo "ok - open asks the shell for the crashes panel"

: >"$CALLS"
PANEL_STATUS=1 run open
[[ $rc == 1 ]] || fail "open with a failing panel exits $rc, not 1 (a false success hides the fallback)"
[[ $err == *"crash history panel is unavailable"* ]] || fail "no message when the panel is unavailable: $err"
echo "ok - a panel that cannot open is exit 1 with a message"

! grep -q '^noctalia' "$CALLS" || fail "Noctalia was called on Hyprland"
: >"$CALLS"
PANEL_STATUS=0 run open 'not-an-id'
[[ $rc != 0 ]] && [[ ! -s $CALLS ]] || fail "an invalid id must fail before any panel call"
echo "ok - an invalid id fails before opening anything, and Noctalia is never called (stub panel, not a real shell)"
