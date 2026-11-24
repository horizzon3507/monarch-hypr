#!/bin/bash

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
export XDG_CONFIG_HOME="$HOME/.config"
export PATH="$ROOT/bin:$TMP_ROOT/bin:$PATH"
mkdir -p "$HOME" "$TMP_ROOT/bin"

fail() { echo "not ok - $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

cat >"$TMP_ROOT/bin/pgrep" <<'STUB'
#!/bin/bash
[[ -n ${HYPRPAPER_RUNNING:-} ]]
STUB
cat >"$TMP_ROOT/bin/hyprctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$HYPRCTL_CALLS"
STUB
chmod +x "$TMP_ROOT/bin/pgrep" "$TMP_ROOT/bin/hyprctl"
export HYPRCTL_CALLS="$TMP_ROOT/hyprctl-calls"

img="$TMP_ROOT/wall.png"
: >"$img"
[[ -z $(monarch-wallpaper get) ]] || fail "no wallpaper reads empty"
monarch-wallpaper set "$img" || fail "set succeeds"
[[ $(monarch-wallpaper get) == "$(readlink -f "$img")" ]] || fail "get returns the resolved path"
[[ ! -e $HYPRCTL_CALLS ]] || fail "no daemon, no live call"
pass "set records the link and get reads it"

HYPRPAPER_RUNNING=1 monarch-wallpaper set "$img"
grep -q 'hyprpaper wallpaper' "$HYPRCTL_CALLS" || fail "a running hyprpaper is updated live"
pass "a running hyprpaper is updated live"

monarch-wallpaper set "$TMP_ROOT/missing.png" 2>/dev/null && fail "missing file is rejected"
[[ $(monarch-wallpaper get) == "$(readlink -f "$img")" ]] || fail "failed set keeps the old wallpaper"
pass "a missing file is rejected and keeps the old wallpaper"
