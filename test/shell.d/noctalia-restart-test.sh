#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export test_tmp XDG_RUNTIME_DIR="$test_tmp/runtime"
export PATH="$ROOT/bin:$PATH"
mkdir -p "$XDG_RUNTIME_DIR"

monarch-refresh-config() { :; }
pkill() {
  [[ $* == '-x noctalia' ]] || return 99
}
pgrep() { return 1; }
setsid() { :; }
uwsm-app() {
  printf '%s\n' "$@" > "$test_tmp/launch"
  return "${LAUNCH_STATUS:-0}"
}
export -f monarch-refresh-config pkill pgrep setsid uwsm-app

for command in refresh restart; do
  mkdir -p "$XDG_RUNTIME_DIR/monarch"
  touch "$XDG_RUNTIME_DIR/monarch/nightlight" "$XDG_RUNTIME_DIR/monarch/caffeine"
  "monarch-$command-noctalia"
  [[ -f $test_tmp/launch ]] || fail "$command must submit the shell launch before returning"
  mapfile -t launch < "$test_tmp/launch"
  [[ ${launch[*]} == '-t service -- noctalia' ]] ||
    fail "$command must use the session manager environment and keep Noctalia in the foreground"
  rm "$test_tmp/launch"
  [[ ! -e $XDG_RUNTIME_DIR/monarch/nightlight && ! -e $XDG_RUNTIME_DIR/monarch/caffeine ]] ||
    fail "$command must clear the previous shell's toggle state"
  pass "$command keeps the shell and toggle indicators consistent"
done

if LAUNCH_STATUS=23 monarch-restart-noctalia; then
  fail "a rejected service launch must not report a successful restart"
else
  [[ $? == 23 ]] || fail "restart must preserve the service launch failure"
fi
pass "restart propagates service launch failures"
