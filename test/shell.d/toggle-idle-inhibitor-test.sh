#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"
unset HYPRLAND_INSTANCE_SIGNATURE

command -v setsid >/dev/null || { pass "skipped: setsid is not installed"; exit 0; }
tmp=$(mktemp -d)
cleanup() { [[ ! -f $tmp/run/monarch/caffeine.pid ]] || kill -TERM -- "-$(<"$tmp/run/monarch/caffeine.pid")" 2>/dev/null || true; rm -rf "$tmp"; }
trap cleanup EXIT
mkdir -p "$tmp/bin" "$tmp/run"
# Stand-in inhibitor: records its arguments and stays alive until signalled.
cat >"$tmp/bin/systemd-inhibit" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_LOG"
sleep 300 &
wait
STUB
cat >"$tmp/bin/noctalia" <<'STUB'
#!/bin/bash
echo "noctalia $*" >>"$TEST_LOG"
STUB
chmod +x "$tmp/bin/"*
export TEST_LOG="$tmp/log" XDG_RUNTIME_DIR="$tmp/run" HYPRLAND_INSTANCE_SIGNATURE=test PATH="$tmp/bin:$PATH"
: >"$TEST_LOG"
idle="$ROOT/bin/monarch-toggle-idle"
# A zombie has no command line, so this is false for a process that has exited.
alive() { [[ -n $(tr -d '\0' <"/proc/$1/cmdline" 2>/dev/null) ]]; }
status() { "$idle" status | jq -r .enabled; }

[[ $(status) == false ]] || fail "caffeine starts off"
"$idle" on
[[ $(status) == true ]] || fail "on holds an inhibitor"
grep -q -- '--what=idle --who=monarch --why=caffeine' "$TEST_LOG" || fail "the inhibitor blocks idle only"
pid=$(<"$tmp/run/monarch/caffeine.pid")
alive "$pid" || fail "the inhibitor process is running"
"$idle" on
[[ $(grep -c -- '--why=caffeine' "$TEST_LOG") == 1 ]] || fail "a second on does not start a second inhibitor"
"$idle" off
[[ $(status) == false ]] || fail "off reports off"
sleep 0.3
! alive "$pid" || fail "off ends the inhibitor"
[[ ! -e $tmp/run/monarch/caffeine.pid ]] || fail "off removes the pid file"

# A flag whose inhibitor is gone is stale: off, cleaned up.
"$idle" on
pid=$(<"$tmp/run/monarch/caffeine.pid")
kill -TERM -- "-$pid"; sleep 0.3
[[ $(status) == false ]] || fail "a dead inhibitor reads as off"
[[ ! -e $tmp/run/monarch/caffeine ]] || fail "the stale flag is removed"

# A recycled pid is never signalled: the command line must be the inhibitor's.
mkdir -p "$tmp/run/monarch"
sleep 300 & other=$!
printf '%s\n' "$other" >"$tmp/run/monarch/caffeine.pid"
printf 'user\n' >"$tmp/run/monarch/caffeine"
[[ $(status) == false ]] || fail "a foreign pid does not count as the inhibitor"
alive "$other" || fail "a foreign process is left alone"
"$idle" off
alive "$other" || fail "off does not kill a process that is not the inhibitor"
kill "$other"

# Owners: claim, a second claim is refused, only the owner releases.
"$idle" claim update-owner
"$idle" claim other 2>/dev/null && fail "a held caffeine cannot be claimed twice" || true
"$idle" release other
[[ $(status) == true ]] || fail "another owner cannot release"
"$idle" release update-owner
[[ $(status) == false ]] || fail "the owner releases"

! grep -q '^noctalia' "$TEST_LOG" || fail "the Hyprland path never calls Noctalia"
pass "caffeine on Hyprland is a held idle inhibitor with safe pid handling"
