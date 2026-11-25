#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

binds="$ROOT/default/hypr/binds/tiling.lua"
line=$(grep -F 'switch:on:Lid Switch' "$binds") || fail "a lid-close binding exists"
[[ $line == *'MONARCH_LOCK_ONLY=true monarch-system-lock'* ]] || fail "closing the lid runs the lock command"
[[ $line == *'locked = true'* ]] || fail "the lid binding also fires while locked"
[[ $line == *'monarch-hw-external-monitors && monarch-hypr-monitor-internal off'* ]] || fail "the laptop panel still turns off with an external monitor"
# The lock must come before the panel handling so a missing external monitor cannot skip it.
lock_pos=${line%%monarch-system-lock*}; mon_pos=${line%%monarch-hw-external-monitors*}
(( ${#lock_pos} < ${#mon_pos} )) || fail "the lock runs before the monitor handling"
pass "lid close locks first, then handles the laptop panel"
