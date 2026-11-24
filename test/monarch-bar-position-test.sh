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

[[ $(monarch-bar-position) == top ]] || fail "missing file defaults to top"
monarch-bar-position bottom
[[ $(monarch-bar-position) == bottom && $(jq -r .barPosition "$SETTINGS") == bottom ]] || fail "bottom persists in shell.json"
pass "bottom persists"
echo '{"barPosition":"left"}' >"$SETTINGS"
[[ $(monarch-bar-position) == top ]] || fail "unsupported stored value reads as top"
pass "unsupported stored value reads as top"
for bad in left right diagonal; do
  monarch-bar-position "$bad" 2>/dev/null && fail "rejects $bad"
done
pass "rejects left, right and invalid positions"
