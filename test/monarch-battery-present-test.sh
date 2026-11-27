#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export MONARCH_POWER_SUPPLY_PATH="$TMP/ps"
mkdir -p "$MONARCH_POWER_SUPPLY_PATH/bat0"

# No readable battery information means no battery.
if "$ROOT/bin/monarch-battery-present"; then
  echo "monarch-battery-present found a battery in an empty supply directory" >&2
  exit 1
fi

# A present non-battery supply does not count.
printf '1\n' >"$MONARCH_POWER_SUPPLY_PATH/bat0/present"
printf 'Mains\n' >"$MONARCH_POWER_SUPPLY_PATH/bat0/type"
if "$ROOT/bin/monarch-battery-present"; then
  echo "monarch-battery-present counted a mains supply as a battery" >&2
  exit 1
fi

# A battery that is not present does not count.
printf 'Battery\n' >"$MONARCH_POWER_SUPPLY_PATH/bat0/type"
printf '0\n' >"$MONARCH_POWER_SUPPLY_PATH/bat0/present"
if "$ROOT/bin/monarch-battery-present"; then
  echo "monarch-battery-present counted an absent battery" >&2
  exit 1
fi

# A present battery counts, even alongside other supplies.
printf '1\n' >"$MONARCH_POWER_SUPPLY_PATH/bat0/present"
"$ROOT/bin/monarch-battery-present"

echo "Battery presence checks pass"
