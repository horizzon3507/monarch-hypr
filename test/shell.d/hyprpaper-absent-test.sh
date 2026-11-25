#!/bin/bash
# Gate: the shell draws the wallpaper; hyprpaper is neither started nor installed.
# It crashed on a QEMU virtual GPU (dumb buffer allocation failed, then SIGSEGV).

source "${BASH_SOURCE[0]%/*}/base-test.sh"

[[ ! -e $ROOT/config/hypr/hyprpaper.conf ]] || fail "hyprpaper.conf is still shipped"
# Probe scripts under iso/test only report that the daemon is not running, so
# the gate covers what ships: commands, install lists and ISO package lists.
! grep -rIl 'hyprpaper' "$ROOT/bin" "$ROOT/install" "$ROOT"/iso/*.packages "$ROOT"/iso/packages 2>/dev/null | grep -q . \
  || fail "hyprpaper is still referenced in bin, install or the ISO package lists"
pass "hyprpaper is not shipped, started or installed"
