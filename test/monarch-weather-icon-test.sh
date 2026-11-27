#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export PATH="$TMP/bin:/usr/bin"
mkdir -p "$TMP/bin"

# A stubbed curl serves wttr.in-shaped JSON. The sunrise/sunset windows are
# chosen so the day/night branch is deterministic at any wall-clock time.
fixture() {
  local code=$1 sunrise=${2:-12:00 AM} sunset=${3:-11:59 PM}
  cat <<JSON
{"current_condition":[{"weatherCode":"$code"}],"weather":[{"astronomy":[{"sunrise":"$sunrise","sunset":"$sunset"}]}]}
JSON
}

cat >"$TMP/bin/curl" <<'STUB'
#!/bin/bash
[[ -n $CURL_FIXTURE ]] && cat "$CURL_FIXTURE"
STUB
chmod +x "$TMP/bin/curl"
export CURL_FIXTURE="$TMP/wx.json"

expect_rc() {
  local want=$1
  shift
  local rc=0
  "$@" || rc=$?
  [[ $rc -eq $want ]]
}

icon_for() {
  fixture "$@" >"$CURL_FIXTURE"
  "$ROOT/bin/monarch-weather-icon"
}

# Every run prints exactly one non-empty icon.
clear_day=$(icon_for 113)
[[ -n $clear_day ]]

# Unknown codes fall back to the default icon, distinct from a known mapping.
fallback=$(icon_for 999)
[[ -n $fallback ]]
[[ $clear_day != "$fallback" ]]

# The same code maps day and night to different icons.
clear_night=$(icon_for 113 "11:59 PM" "11:58 PM")
[[ -n $clear_night ]]
[[ $clear_night != "$clear_day" ]]

# A night-insensitive code keeps one icon in both windows.
rain_day=$(icon_for 299)
rain_night=$(icon_for 299 "11:59 PM" "11:58 PM")
[[ -n $rain_day && $rain_day == "$rain_night" ]]

# A fetch or parse failure is an error, not a wrong icon.
CURL_FIXTURE= expect_rc 1 "$ROOT/bin/monarch-weather-icon"
printf 'not json' >"$CURL_FIXTURE"
expect_rc 1 "$ROOT/bin/monarch-weather-icon"

echo "Weather icon checks pass"
