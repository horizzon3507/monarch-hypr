#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
mkdir -p "$HOME"
STATE_DIR="$HOME/.local/state/monarch"
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id)

expect_rc() {
  local want=$1
  shift
  local rc=0
  "$@" || rc=$?
  [[ $rc -eq $want ]]
}

# Usage and input validation.
expect_rc 1 "$ROOT/bin/monarch-state"
expect_rc 1 "$ROOT/bin/monarch-state" set
expect_rc 2 "$ROOT/bin/monarch-state" set a/b
expect_rc 2 "$ROOT/bin/monarch-state" set ..
expect_rc 2 "$ROOT/bin/monarch-state" bogus-command foo

# Plain state names create and remove flag files.
"$ROOT/bin/monarch-state" set welcome-shown
[[ -f "$STATE_DIR/welcome-shown" ]]
"$ROOT/bin/monarch-state" clear welcome-shown
[[ ! -e "$STATE_DIR/welcome-shown" ]]
"$ROOT/bin/monarch-state" clear never-existed

# Restart markers record the current boot identity.
"$ROOT/bin/monarch-state" set reboot-required
[[ $(cat "$STATE_DIR/reboot-required") == "$BOOT_ID" ]]

# clear-stale-restarts keeps current-boot markers, stamps empty ones,
# and drops markers from older boots.
mkdir -p "$STATE_DIR"
printf '%s\n' "$BOOT_ID" >"$STATE_DIR/renow-required"
: >"$STATE_DIR/reempty-required"
printf '%s\n' "11111111-2222-4333-8444-555555555555" >"$STATE_DIR/reold-required"
"$ROOT/bin/monarch-state" clear-stale-restarts
[[ -f "$STATE_DIR/renow-required" ]]
[[ $(cat "$STATE_DIR/renow-required") == "$BOOT_ID" ]]
[[ $(cat "$STATE_DIR/reempty-required") == "$BOOT_ID" ]]
[[ ! -e "$STATE_DIR/reold-required" ]]

echo "State file management checks pass"
