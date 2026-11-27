#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export PATH="$TMP/bin:/usr/bin"
mkdir -p "$TMP/bin"

cat >"$TMP/bin/upower" <<'STUB'
#!/bin/bash
if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/battery_BAT0"
  exit 0
fi
[[ $1 == "-i" ]] && cat "$UPOWER_FIXTURE"
STUB
chmod +x "$TMP/bin/upower"
export UPOWER_FIXTURE="$TMP/info"

# Percentage is reported as a truncated integer.
cat >"$UPOWER_FIXTURE" <<'INFO'
  state:                discharging
  percentage:           80.5%
INFO
[[ $("$ROOT/bin/monarch-battery-remaining") == "80" ]]

# Hours with a fraction become hours and minutes.
cat >"$UPOWER_FIXTURE" <<'INFO'
  percentage:           80%
  time to empty:        3.5 hours
INFO
[[ $("$ROOT/bin/monarch-battery-remaining-time") == "3h 30m" ]]

# Whole hours drop the minutes.
cat >"$UPOWER_FIXTURE" <<'INFO'
  percentage:           20%
  time to empty:        2.0 hours
INFO
[[ $("$ROOT/bin/monarch-battery-remaining-time") == "2h" ]]

# Minutes stay minutes, and charging uses the same formatter.
cat >"$UPOWER_FIXTURE" <<'INFO'
  percentage:           40%
  time to full:         45 minutes
INFO
[[ $("$ROOT/bin/monarch-battery-remaining-time") == "45m" ]]

echo "Battery remaining checks pass"
