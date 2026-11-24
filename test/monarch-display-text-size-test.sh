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

ALA="$HOME/.config/alacritty/monarch-text-size.toml"
[[ $(monarch-display-text-size --current) == 100% ]] || fail "default is 100%"
monarch-display-text-size 115 >/dev/null || fail "sets 115"
[[ $(jq -r .textScale "$SETTINGS") == 1.15 ]] || fail "writes textScale"
[[ $(monarch-display-text-size --current) == 115% ]] || fail "reads back 115% (rounded, not truncated)"
grep -qx 'size = 10.3' "$ALA" || fail "terminal size scales off 9"
pass "sets and reads back"
monarch-display-text-size 112 2>/dev/null && fail "rejects off-grid"
monarch-display-text-size 200 2>/dev/null && fail "rejects out of range"
pass "rejects off-grid and out-of-range"
echo '{"barVisible":false}' >"$SETTINGS"; monarch-display-text-size 125 >/dev/null
[[ $(jq -r .barVisible "$SETTINGS") == false ]] || fail "keeps other keys"
monarch-display-text-size reset >/dev/null
[[ $(monarch-display-text-size --current) == 100% ]] || fail "reset returns to 100%"
[[ $(monarch-display-text-size --list | head -1) == 75% && $(monarch-display-text-size --list | tail -1) == 175% ]] || fail "list spans 75..175"
pass "keeps other keys, reset and list"
