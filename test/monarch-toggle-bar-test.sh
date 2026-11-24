#!/bin/bash

set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
export XDG_CONFIG_HOME="$HOME/.config"
export PATH="$ROOT/bin:$TMP_ROOT/bin:$PATH"
mkdir -p "$HOME" "$TMP_ROOT/bin"
SETTINGS="$HOME/.config/monarch/shell.json"

fail() { echo "not ok - $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

[[ $(monarch-toggle-bar status | jq -r .enabled) == true ]] || fail "bar starts enabled"
monarch-toggle-bar off
[[ -f $HOME/.local/state/monarch/toggles/bar-off ]] || fail "off records the state"
[[ $(jq -r .barVisible "$SETTINGS") == false ]] || fail "off writes barVisible false"
[[ $(monarch-toggle-bar status | jq -r .enabled) == false ]] || fail "status reports hidden"
pass "off hides and records"
echo '{"barVisible":true,"barPosition":"bottom"}' >"$SETTINGS"
monarch-toggle-bar apply
[[ $(jq -r .barVisible "$SETTINGS") == false ]] || fail "apply restores the recorded choice"
[[ $(jq -r .barPosition "$SETTINGS") == bottom ]] || fail "apply keeps other keys"
pass "apply restores the choice and keeps other keys"
monarch-toggle-bar toggle
[[ $(jq -r .barVisible "$SETTINGS") == true && ! -f $HOME/.local/state/monarch/toggles/bar-off ]] || fail "toggle shows again"
monarch-toggle-bar on; monarch-toggle-bar on
[[ ! -f $HOME/.local/state/monarch/toggles/bar-off ]] || fail "on is idempotent"
pass "toggle and on"
monarch-toggle-bar nope 2>/dev/null && fail "rejects unknown action"
pass "rejects unknown action"
