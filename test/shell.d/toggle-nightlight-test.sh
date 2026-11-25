#!/bin/bash
# Night light is hyprsunset: daemon started on demand, filter switched with
# `hyprctl hyprsunset`. Stubs only: these prove command construction and state
# handling, not real colour output on Hyprland.
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
export TEST_LOG="$tmp/log" TEST_STATE="$tmp/state" TEST_RUNNING="$tmp/running"
cat >"$tmp/bin/pgrep" <<'STUB'
#!/bin/bash
[[ -f $TEST_RUNNING ]]
STUB
cat >"$tmp/bin/hyprsunset" <<'STUB'
#!/bin/bash
echo "hyprsunset $*" >>"$TEST_LOG"
touch "$TEST_RUNNING"; echo false >"$TEST_STATE"
STUB
cat >"$tmp/bin/setsid" <<'STUB'
#!/bin/bash
shift
exec "$@"
STUB
cat >"$tmp/bin/sleep" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$tmp/bin/hyprctl" <<'STUB'
#!/bin/bash
echo "hyprctl $*" >>"$TEST_LOG"
[[ ${HYPRCTL_FAIL:-} != 1 ]] || exit 1
[[ $1 == hyprsunset ]] || exit 2
case "$2 ${3:-}" in
  "temperature "*) echo false >"$TEST_STATE"; echo ok ;;
  "identity true") echo true >"$TEST_STATE"; echo ok ;;
  "identity get") cat "$TEST_STATE" ;;
  *) echo "invalid command" ;;
esac
STUB
printf '#!/bin/bash\necho "noctalia $*" >>"$TEST_LOG"\n' >"$tmp/bin/noctalia"
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:/usr/bin:/bin"
night="$ROOT/bin/monarch-toggle-nightlight"
: >"$TEST_LOG"

# Not running: off, and "off" does nothing.
"$night" status | jq -e '.enabled == false' >/dev/null || fail "no daemon reads as off"
"$night" off
[[ ! -s $TEST_LOG ]] || fail "off without a daemon issues no command"

# On starts the daemon with the default temperature.
"$night" on
grep -qx 'hyprsunset -t 4000' "$TEST_LOG" || fail "on starts hyprsunset at 4000 K"
"$night" status | jq -e '.enabled == true' >/dev/null || fail "status on after start"

# Toggle off, on, with the daemon already running (IPC only).
: >"$TEST_LOG"
"$night" toggle
grep -qx 'hyprctl hyprsunset identity true' "$TEST_LOG" || fail "toggle off sets identity"
! grep -q '^hyprsunset ' "$TEST_LOG" || fail "toggle off does not restart the daemon"
"$night" status | jq -e '.enabled == false' >/dev/null || fail "status off after toggle"
"$night" toggle
grep -qx 'hyprctl hyprsunset temperature 4000' "$TEST_LOG" || fail "toggle on sets the temperature"
"$night" status | jq -e '.enabled == true' >/dev/null || fail "status on again"

# Custom and invalid temperatures.
: >"$TEST_LOG"
MONARCH_NIGHTLIGHT_TEMPERATURE=3200 "$night" on
grep -qx 'hyprctl hyprsunset temperature 3200' "$TEST_LOG" || fail "custom temperature"
for bad in 999 20001 warm "3000; id"; do
  : >"$TEST_LOG"
  if MONARCH_NIGHTLIGHT_TEMPERATURE=$bad "$night" on 2>/dev/null; then fail "temperature $bad is rejected"; fi
  [[ ! -s $TEST_LOG ]] || fail "temperature $bad reaches no command"
done

# A daemon that does not answer is unavailable, never a false "off" or success.
if HYPRCTL_FAIL=1 "$night" status >"$tmp/out" 2>/dev/null; then fail "unanswering daemon fails status"; fi
jq -e '.tooltip | test("unavailable")' "$tmp/out" >/dev/null || fail "status says unavailable"
jq -e ".enabled == null" "$tmp/out" >/dev/null || fail "unavailable status is not a boolean"
if HYPRCTL_FAIL=1 "$night" toggle 2>/dev/null; then fail "toggle fails when state is unreadable"; fi
if HYPRCTL_FAIL=1 "$night" off 2>/dev/null; then fail "off fails when the daemon does not accept it"; fi
if HYPRCTL_FAIL=1 "$night" on 2>/dev/null; then fail "on fails when the daemon does not accept it"; fi

# Missing binary is reported.
rm -f "$TEST_RUNNING" "$tmp/bin/hyprsunset"
if "$night" on 2>"$tmp/err"; then fail "on without hyprsunset fails"; fi
grep -q 'not installed' "$tmp/err" || fail "missing hyprsunset is explained"
! grep -q '^noctalia' "$TEST_LOG" || fail "Noctalia was called"
pass "night light drives hyprsunset (stubbed) and reports unreadable state instead of guessing"
