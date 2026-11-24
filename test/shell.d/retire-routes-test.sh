#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"
unset HYPRLAND_INSTANCE_SIGNATURE

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat >"$tmp/bin/recorder" <<'STUB'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >>"$TEST_CALLS"
case ${0##*/} in
  monarch-panel) [[ ${PANEL_FAIL:-} != 1 ]] || exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/recorder"
for c in noctalia monarch-panel monarch-launch-tui monarch-menu; do ln -s recorder "$tmp/bin/$c"; done
export TEST_CALLS="$tmp/calls" MONARCH_PATH="$tmp/runtime"
mkdir -p "$MONARCH_PATH/bin"
cp "$tmp/bin/recorder" "$MONARCH_PATH/bin/monarch-panel"
run() { : >"$TEST_CALLS"; PATH="$tmp/bin:/usr/bin:/bin" bash "$ROOT/bin/$1" "${@:2}" >/dev/null 2>"$tmp/err" || true; cat "$TEST_CALLS"; }

# Outside Hyprland the Noctalia routes stay as they were.
[[ $(run monarch-launch-wifi) == "noctalia msg panel-toggle control-center network" ]] || fail "wifi keeps the Noctalia route outside Hyprland"
[[ $(run monarch-launch-bluetooth) == "noctalia msg panel-toggle control-center bluetooth" ]] || fail "bluetooth keeps the Noctalia route outside Hyprland"
[[ $(run monarch-launch-powerprofile) == "noctalia msg panel-toggle control-center power" ]] || fail "power keeps the Noctalia route outside Hyprland"

# On Hyprland nothing reaches Noctalia.
export HYPRLAND_INSTANCE_SIGNATURE=test
[[ $(run monarch-launch-wifi) == "monarch-panel toggle network" ]] || fail "wifi opens the network panel on Hyprland"
[[ $(PANEL_FAIL=1 run monarch-launch-wifi) == $'monarch-panel toggle network\nmonarch-launch-tui impala' ]] || fail "wifi falls back to the terminal UI when the shell does not answer"
[[ $(run monarch-launch-bluetooth) == "monarch-launch-tui bluetui" ]] || fail "bluetooth opens the terminal UI on Hyprland"
[[ $(run monarch-launch-powerprofile) == "monarch-menu setup.power" ]] || fail "power opens the menu rows on Hyprland"
[[ $(run monarch-crash-history open) == "monarch-panel open crashes" ]] || fail "crash history opens the crash panel on Hyprland"
[[ $(PANEL_FAIL=1 run monarch-crash-history open) == "monarch-panel open crashes" ]] || fail "a missing panel is reported, not routed through Noctalia"
! grep -q noctalia "$TEST_CALLS" || fail "no Hyprland route calls Noctalia"
pass "launch and crash-history routes use the shell on Hyprland and keep Noctalia elsewhere"
