#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export PATH="$TMP/bin:/usr/bin"
mkdir -p "$HOME" "$TMP/bin"

cat >"$TMP/bin/monarch-weather-icon" <<'STUB'
#!/bin/bash
echo "WXICON"
STUB
chmod +x "$TMP/bin/monarch-weather-icon"

expect_rc() {
  local want=$1
  shift
  local rc=0
  "$@" || rc=$?
  [[ $rc -eq $want ]]
}

# A failed fetch reports unavailability and is an error.
cat >"$TMP/bin/curl" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$TMP/bin/curl"
out=$(expect_rc 1 "$ROOT/bin/monarch-weather-status" 2>&1) && true
[[ $("$ROOT/bin/monarch-weather-status" 2>/dev/null || true) == "Weather unavailable" ]]

# A normal answer formats place, temperature and wind under the icon.
cat >"$TMP/bin/curl" <<'STUB'
#!/bin/bash
printf 'salvador|+31C|10km/h'
STUB
[[ $("$ROOT/bin/monarch-weather-status") == "WXICON    Salvador  ·  Temp 31C  ·  Wind 10km/h" ]]

# Raw coordinates are replaced by the nearest area name from a second lookup.
cat >"$TMP/bin/curl" <<'STUB'
#!/bin/bash
if [[ $* == *format=j1* ]]; then
  printf '{"nearest_area":[{"areaName":[{"value":"Itapua"}]}]}'
else
  printf '%s' '-12.98,-38.51|+29C|8km/h'
fi
STUB
[[ $("$ROOT/bin/monarch-weather-status") == "WXICON    Itapua  ·  Temp 29C  ·  Wind 8km/h" ]]

echo "Weather status checks pass"
