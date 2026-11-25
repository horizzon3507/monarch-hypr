#!/bin/bash
# Gate: the Hyprland tree carries no Niri or Noctalia assets, packages or session.

source "${BASH_SOURCE[0]%/*}/base-test.sh"

for path in config/niri config/noctalia default/niri default/noctalia default/sddm/niri.kdl; do
  [[ ! -e $ROOT/$path ]] || fail "$path is still shipped"
done
pass "Niri and Noctalia asset directories are gone"

leftover=$(find "$ROOT/bin" "$ROOT/install" -type f \( -name '*niri*' -o -name '*noctalia*' \) | sort)
[[ -z $leftover ]] || fail "Niri or Noctalia scripts remain" "$leftover"
pass "no Niri or Noctalia scripts remain under bin or install"

# Real package names seen in the intermediate ISO: niri, noctalia (5.6.0), noctalia-qs,
# and the older noctalia-shell. Match the whole family, never one name.
for list in "$ROOT"/install/*.packages "$ROOT"/iso/*.packages "$ROOT"/iso/packages/*; do
  [[ -f $list ]] || continue
  if grep -Eiq '^[[:space:]]*(niri|noctalia)(-|[[:space:]]|$)' "$list"; then
    fail "$list lists a Niri or Noctalia package"
  fi
done
if grep -Eq "^[[:space:]]*'(niri|noctalia)[-']" "$ROOT/pkgs/pkgbuilds/monarch/PKGBUILD"; then
  fail "the monarch package depends on Niri or Noctalia"
fi
pass "no package manifest or dependency pulls in the Niri or Noctalia family"
