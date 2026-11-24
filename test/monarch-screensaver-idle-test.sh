#!/bin/bash

set -euo pipefail
unset HYPRLAND_INSTANCE_SIGNATURE

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_screensaver_idle() {
  local config=$1

  # Screensaver at 150s, lock at 151s, screens off at 330s.
  awk '/^listener \{/{n++} n==1' "$config" | grep -Eq '^[[:space:]]*timeout = 150$'
  awk '/^listener \{/{n++} n==1' "$config" |
    grep -Eq '^[[:space:]]*on-timeout = monarch-launch-screensaver$'
  awk '/^listener \{/{n++} n==1' "$config" |
    grep -Eq "^[[:space:]]*on-resume = pkill -f '\[o\]rg.monarch.screensaver'$"
  awk '/^listener \{/{n++} n==2' "$config" | grep -Eq '^[[:space:]]*timeout = 151$'
  awk '/^listener \{/{n++} n==2' "$config" |
    grep -Eq '^[[:space:]]*on-timeout = loginctl lock-session$'
  awk '/^listener \{/{n++} n==3' "$config" | grep -Eq '^[[:space:]]*timeout = 330$'
  awk '/^listener \{/{n++} n==3' "$config" | grep -q "dpms({ action = 'disable' })"
  awk '/^listener \{/{n++} n==3' "$config" | grep -q 'monarch-brightness-keyboard restore'
  grep -Eq '^[[:space:]]*lock_cmd = monarch-system-lock$' "$config"
}

assert_screensaver_idle "$ROOT/config/hypr/hypridle.conf"
! grep -R -n "pkill -f org\.monarch\.screensaver" \
  "$ROOT/bin/monarch-screensaver" "$ROOT/bin/monarch-system-lock"
! grep -F "pgrep -f org.monarch.screensaver" "$ROOT/bin/monarch-launch-screensaver"

mkdir -p "$TMP/bin" "$TMP/disabled/.local/state/monarch/toggles"
touch "$TMP/bin/tte" "$TMP/disabled/.local/state/monarch/toggles/screensaver-off"
chmod +x "$TMP/bin/tte"
if HOME="$TMP/disabled" PATH="$TMP/bin:$ROOT/bin:/usr/bin" \
  "$ROOT/bin/monarch-launch-screensaver" >/dev/null 2>&1; then
  echo "Disabled screensaver still launches on idle" >&2
  exit 1
fi

echo "Fresh installs launch and stop the screensaver on idle"
