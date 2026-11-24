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

[[ -z $(monarch-shell-setting get barVisible) ]] || fail "missing file reads empty"
monarch-shell-setting set barVisible false || fail "set bool"
[[ $(jq -c .barVisible "$SETTINGS") == false ]] || fail "bool keeps its JSON type"
monarch-shell-setting set barPosition '"bottom"'
monarch-shell-setting set textScale 1.15
[[ $(jq -c . "$SETTINGS") == '{"barVisible":false,"barPosition":"bottom","textScale":1.15}' ]] || fail "keys accumulate"
pass "set keeps types and other keys"
monarch-shell-setting set x 'not json' 2>/dev/null && fail "rejects invalid JSON"
monarch-shell-setting set 'bad key' 1 2>/dev/null && fail "rejects invalid key"
pass "rejects invalid JSON and keys"
echo '{broken' >"$SETTINGS"
monarch-shell-setting set barVisible true || fail "replaces a broken file"
[[ $(jq -c . "$SETTINGS") == '{"barVisible":true}' ]] || fail "broken file replaced"
pass "broken file is replaced"
[[ -z $(ls "$HOME/.config/monarch" | grep -v '^shell.json$') ]] || fail "no temp files left"
pass "no temporary files left"
