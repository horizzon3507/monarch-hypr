#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export XDG_RUNTIME_DIR="$TMP/run"
export PATH="$TMP/bin:/usr/bin"
mkdir -p "$XDG_RUNTIME_DIR" "$TMP/bin"

cat >"$TMP/bin/monarch-battery-status" <<'STUB'
#!/bin/bash
cat "$BATTERY_STATUS_FIXTURE"
STUB
for cmd in notify-send monarch-hook monarch-powerprofiles-set; do
  cat >"$TMP/bin/$cmd" <<'STUB'
#!/bin/bash
printf '%s\n' "$(basename "$0") $*" >>"$CALLS"
STUB
done
chmod +x "$TMP/bin/"*
export CALLS="$TMP/calls"
export BATTERY_STATUS_FIXTURE="$TMP/status"

# No battery information at all: quiet success, nothing recorded.
: >"$BATTERY_STATUS_FIXTURE"
"$ROOT/bin/monarch-battery-monitor"
[[ ! -f $CALLS ]]

# A low discharging battery notifies once and flags that it did.
printf 'percentage\t8\nstate\tdischarging\nac\tfalse\n' >"$BATTERY_STATUS_FIXTURE"
"$ROOT/bin/monarch-battery-monitor"
grep -qF "notify-send" "$CALLS"
grep -Fqx "monarch-hook battery-low 8" "$CALLS"
[[ -f $XDG_RUNTIME_DIR/monarch_battery_notified ]]

# The second pass with the flag set does not notify again.
: >"$CALLS"
"$ROOT/bin/monarch-battery-monitor"
[[ ! -s $CALLS ]]

# Back above the threshold the flag resets without a notification.
printf 'percentage\t50\nstate\tdischarging\nac\tfalse\n' >"$BATTERY_STATUS_FIXTURE"
"$ROOT/bin/monarch-battery-monitor"
[[ ! -f $XDG_RUNTIME_DIR/monarch_battery_notified ]]
[[ ! -s $CALLS ]]

# Switching to AC applies the matching power profile and records the source.
printf 'battery\n' >"$XDG_RUNTIME_DIR/monarch_power_source"
printf 'percentage\t80\nstate\tcharging\nac\ttrue\n' >"$BATTERY_STATUS_FIXTURE"
"$ROOT/bin/monarch-battery-monitor"
grep -Fqx "monarch-powerprofiles-set ac" "$CALLS"
[[ $(cat "$XDG_RUNTIME_DIR/monarch_power_source") == "ac" ]]

echo "Battery monitor checks pass"
