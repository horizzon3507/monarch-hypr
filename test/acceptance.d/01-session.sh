#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base.sh"

outputs=$(hyprctl monitors -j) || fail "Hyprland reports its monitors"
(( $(jq 'length' <<<"$outputs") > 0 )) || fail "Hyprland reports at least one monitor"
pass "Hyprland reports at least one monitor"

wait_until "Quickshell is running" 60 pgrep -u "$(id -u)" -x quickshell
for process in mako hypridle hyprpaper swayosd-server; do
  pgrep -u "$(id -u)" -x "$process" >/dev/null || fail "$process is running"
done
pass "Quickshell, mako, hypridle, hyprpaper and swayosd are running"

monarch-menu --check >/dev/null || fail "installed Monarch menu validates"
monarch commands --check >/dev/null || fail "installed Monarch commands validate"
pass "installed Monarch menu and command routes validate"

wait_until "PipeWire responds" 30 wpctl status
[[ $(findmnt -no FSTYPE /) == "btrfs" ]] || fail "root filesystem is Btrfs"
pass "root filesystem is Btrfs"

monarch-version >/dev/null || fail "installed Monarch version is readable"
pass "installed Monarch version is readable"

failed_units() {
  systemctl "$@" --failed --no-legend --plain | awk '{print $1}' |
    grep -Ev "${MONARCH_ACCEPTANCE_IGNORE_UNITS:-^$}" || true
}

failed_system=$(failed_units --system)
[[ -z $failed_system ]] || fail "no system units failed" "$failed_system"
pass "no system units failed"

failed_user=$(failed_units --user)
[[ -z $failed_user ]] || fail "no user units failed" "$failed_user"
pass "no user units failed"

screenshot success-desktop
