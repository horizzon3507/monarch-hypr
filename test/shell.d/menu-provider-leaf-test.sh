#!/bin/bash
# `monarch-menu setup.power` (a provider leaf with no children) must open the
# provider's list and run its action, not exit 0 having done nothing.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" MONARCH_PATH="$ROOT" MONARCH_LANGUAGE=en CALLS="$TMP/calls"
mkdir -p "$HOME"
# A private copy of bin/: monarch-menu puts its own directory first on PATH, so
# the stubs below have to live there to win.
cp -r "$ROOT/bin" "$TMP/bin"
: >"$CALLS"
stub() { printf '#!/bin/bash\n%s\n' "$2" >"$TMP/bin/$1"; chmod +x "$TMP/bin/$1"; }
stub pgrep 'exit 1'
stub walker 'echo "walker $*" >>"$CALLS"; exit 1'
stub monarch-powerprofiles-list 'printf "balanced\nperformance\npower-saver\n"'
stub monarch-menu-select 'echo "select $*" >>"$CALLS"; cat >"$TMP/choices"; echo performance'
stub monarch-powerprofiles-set 'echo "set $*" >>"$CALLS"'
stub powerprofilesctl 'echo balanced'
export PATH="$TMP/bin:$PATH"
export TMP

rc=0
bash "$TMP/bin/monarch-menu" setup.power >"$TMP/out" 2>&1 || rc=$?
cat "$TMP/out" >&2; [[ $rc == 0 ]] || { echo "not ok - setup.power exited $rc" >&2; exit 1; }
grep -q '^select ' "$CALLS" || { echo "not ok - the power profile picker never opened (false success)" >&2; exit 1; }
[[ $(<"$TMP/choices") == $'balanced\nperformance\npower-saver' ]] || { echo "not ok - picker did not get the provider list" >&2; exit 1; }
grep -qx 'set autodetect performance' "$CALLS" || { echo "not ok - the chosen profile was not applied: $(<"$CALLS")" >&2; exit 1; }
! grep -q '^walker' "$CALLS" || { echo "not ok - a direct provider route drew a menu level" >&2; exit 1; }
echo "ok - a direct provider leaf opens its picker and applies the choice (stub commands, no real power profile)"
