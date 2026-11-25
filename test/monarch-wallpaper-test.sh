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

STATE="$XDG_CONFIG_HOME/monarch/current/wallpaper.json"
[[ $(jq -r .path "$STATE") == "$(readlink -f "$img")" ]] || fail "state file carries the resolved path"
rev1=$(jq -r .rev "$STATE")
img2="$TMP_ROOT/wall2.png"
: >"$img2"
monarch-wallpaper set "$img2"
[[ $(jq -r .path "$STATE") == "$(readlink -f "$img2")" ]] || fail "a changed symlink target updates the state path"
rev2=$(jq -r .rev "$STATE")
(( rev2 > rev1 )) || fail "a changed target raises rev"
echo new-content >"$img2"
monarch-wallpaper set "$img2"
rev3=$(jq -r .rev "$STATE")
for _ in 1 2 3 4 5 6 7 8; do monarch-wallpaper-sync; r=$(jq -r .rev "$STATE"); (( r > rev3 )) || fail "rev is strictly unique in a tight loop"; rev3=$r; done
[[ $rev3 =~ ^[0-9]+$ ]] && (( rev3 < 9007199254740992 )) || fail "rev is an exact integer below 2^53"
(( rev3 > rev2 )) || fail "same path with new content raises rev"
[[ ! -e $HYPRCTL_CALLS ]] || fail "no hyprpaper call is ever made"
ls "$XDG_CONFIG_HOME/monarch/current" | grep -q '\.XXXX\|wallpaper.json\.' && fail "no temp file is left behind"
pass "set publishes an atomic state file; rev grows on target change and on same-path content change"

rm -f "$XDG_CONFIG_HOME/monarch/current/background"
monarch-wallpaper-sync
[[ $(jq -r .path "$STATE") == "" ]] || fail "missing link gives an empty path"
ln -sfn "$TMP_ROOT/gone.png" "$XDG_CONFIG_HOME/monarch/current/background"
monarch-wallpaper-sync
[[ $(jq -r .path "$STATE") == "" ]] || fail "dangling link gives an empty path"
pass "a missing or dangling link publishes an empty path so the shell shows the fallback"
ln -sfn "$img2" "$XDG_CONFIG_HOME/monarch/current/background"

monarch-wallpaper set "$TMP_ROOT/missing.png" 2>/dev/null && fail "missing file is rejected"
[[ $(monarch-wallpaper get) == "$(readlink -f "$img2")" ]] || fail "failed set keeps the old wallpaper"
pass "a missing file is rejected and keeps the old wallpaper"
