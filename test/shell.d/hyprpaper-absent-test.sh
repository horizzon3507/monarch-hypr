#!/bin/bash
# Gate: the shell draws the wallpaper; hyprpaper is neither started nor installed.
# It crashed on a QEMU virtual GPU (dumb buffer allocation failed, then SIGSEGV).

source "${BASH_SOURCE[0]%/*}/base-test.sh"

[[ ! -e $ROOT/config/hypr/hyprpaper.conf ]] || fail "hyprpaper.conf is still shipped"
! grep -rIl 'hyprpaper' "$ROOT/bin" "$ROOT/install" "$ROOT/iso" 2>/dev/null | grep -q . \
  || fail "hyprpaper is still referenced under bin, install or iso"
pass "hyprpaper is not shipped, started or installed"
