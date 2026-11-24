#!/bin/bash

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"

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

# The shell is the only route; nothing reaches Noctalia, with or without session variables.
[[ $(run monarch-launch-wifi) == "monarch-panel toggle network" ]] || fail "wifi opens the network panel"
[[ $(PANEL_FAIL=1 run monarch-launch-wifi) == $'monarch-panel toggle network\nmonarch-launch-tui impala' ]] || fail "wifi falls back to the terminal UI when the shell does not answer"
[[ $(run monarch-launch-bluetooth) == "monarch-launch-tui bluetui" ]] || fail "bluetooth opens the terminal UI"
[[ $(run monarch-launch-powerprofile) == "monarch-menu setup.power" ]] || fail "power opens the menu rows"
[[ $(run monarch-crash-history open) == "monarch-panel open crashes" ]] || fail "crash history opens the crash panel"
out=$(PANEL_FAIL=1 run monarch-crash-history open); [[ $(head -n 1 <<<"$out") == "monarch-panel open crashes" && $(sed -n 2p <<<"$out") == "monarch-launch-tui bash -c"* ]] || fail "a missing panel falls back to a terminal, not Noctalia"
! grep -q noctalia <<<"$out" || fail "crash history never reaches Noctalia"
! grep -q noctalia "$TEST_CALLS" || fail "no Hyprland route calls Noctalia"
# Fingerprint on Hyprland: refuse before any sudo, PAM write or enrollment change.
for S in setup remove; do
  F="$ROOT/bin/monarch-$S-security-fingerprint"
  out=$(HYPRLAND_INSTANCE_SIGNATURE=x PATH=/nonexistent /bin/bash "$F" 2>&1) && fail "fingerprint $S must exit non-zero"
  [[ $out == *"not available with this lock screen yet"* ]] || fail "fingerprint $S states the gap: $out"
  [[ $out != *"command not found"* ]] || fail "fingerprint $S ran something before refusing"
done
# First run no longer enables Noctalia plugins.
! grep -q 'enable-noctalia-plugins' "$ROOT/bin/monarch-provision-first-run" || fail "first run still enables Noctalia plugins"
# Reconcile no longer waits for, restarts or enables anything from Noctalia (static check).
U="$ROOT/install/reconcile/user.sh"
! grep -qi noctalia "$U" || fail "reconcile user step has no Noctalia handling"
pass "launch and crash-history routes use the shell and never call Noctalia"
