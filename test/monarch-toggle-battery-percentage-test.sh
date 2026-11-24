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

[[ $(monarch-toggle-battery-percentage status | jq -r .enabled) == false ]] || fail "starts hidden"
monarch-toggle-battery-percentage on
[[ $(jq -r .batteryPercent "$SETTINGS") == true ]] || fail "on writes batteryPercent true"
monarch-toggle-battery-percentage toggle
[[ $(jq -r .batteryPercent "$SETTINGS") == false && ! -f $HOME/.local/state/monarch/toggles/battery-percentage ]] || fail "toggle turns it off"
monarch-toggle-battery-percentage off
pass "on, toggle and off write shell.json"
monarch-toggle-battery-percentage nope 2>/dev/null && fail "rejects unknown action"
pass "rejects unknown action"
