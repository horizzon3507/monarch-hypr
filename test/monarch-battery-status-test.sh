#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export MONARCH_POWER_SUPPLY_PATH="$TMP/ps"
export PATH="$TMP/bin:/usr/bin"
mkdir -p "$HOME" "$TMP/bin" "$MONARCH_POWER_SUPPLY_PATH/BAT0" "$MONARCH_POWER_SUPPLY_PATH/AC0"

printf 'Mains\n' >"$MONARCH_POWER_SUPPLY_PATH/AC0/type"
printf '0\n' >"$MONARCH_POWER_SUPPLY_PATH/AC0/online"

# sysfs provides the live draw; the stubbed upower energy-rate disagrees on
# purpose so the test proves sysfs wins.
printf '2000000\n' >"$MONARCH_POWER_SUPPLY_PATH/BAT0/current_now"
printf '15000000\n' >"$MONARCH_POWER_SUPPLY_PATH/BAT0/voltage_now"

cat >"$TMP/upower-info" <<'INFO'
  native-path:          BAT0
  state:                discharging
  energy-full:          50.0 Wh
  energy-rate:          99.9 W
  percentage:           80.5%
  charge-cycles:        123
  time to empty:        3.5 hours
INFO

cat >"$TMP/bin/upower" <<'STUB'
#!/bin/bash
if [[ $1 == "-e" ]]; then
  [[ -e $UPOWER_FIXTURE ]] && echo "/org/freedesktop/UPower/devices/battery_BAT0"
  exit 0
fi
[[ $1 == "-i" && -e $UPOWER_FIXTURE ]] && cat "$UPOWER_FIXTURE"
exit 0
STUB
chmod +x "$TMP/bin/upower"

export UPOWER_FIXTURE="$TMP/upower-info"

expect_rc() {
  local want=$1
  shift
  local rc=0
  "$@" || rc=$?
  [[ $rc -eq $want ]]
}

# Unknown arguments are a usage error.
expect_rc 2 "$ROOT/bin/monarch-battery-status" --bogus

# No battery device: quiet success, no output.
[[ -z $(UPOWER_FIXTURE="$TMP/no-device" "$ROOT/bin/monarch-battery-status") ]]

# Discharging battery on battery power.
out=$("$ROOT/bin/monarch-battery-status" --shell)
grep -Fqx $'percentage\t80' <<<"$out"
grep -Fqx $'state\tdischarging' <<<"$out"
grep -Fqx $'rate\t30' <<<"$out"
grep -Fqx $'size\t50' <<<"$out"
grep -Fqx $'time\t3h 30m' <<<"$out"
grep -Fqx $'cycles\t123' <<<"$out"
grep -Fqx $'ac\tfalse' <<<"$out"

human=$("$ROOT/bin/monarch-battery-status")
grep -qF "Battery 80%" <<<"$human"
grep -qF "30W / 50Wh" <<<"$human"

# On mains with a charge limit and a pending charge, the state reads holding.
printf '1\n' >"$MONARCH_POWER_SUPPLY_PATH/AC0/online"
printf '80\n' >"$MONARCH_POWER_SUPPLY_PATH/BAT0/charge_control_end_threshold"
sed -i 's/state:                discharging/state:                pending-charge/' "$UPOWER_FIXTURE"
out=$("$ROOT/bin/monarch-battery-status" --shell)
grep -Fqx $'state\tholding' <<<"$out"
grep -Fqx $'threshold\t80%' <<<"$out"
grep -Fqx $'ac\ttrue' <<<"$out"

echo "Battery status checks pass"
