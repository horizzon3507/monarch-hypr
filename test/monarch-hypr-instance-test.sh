#!/bin/bash

# Guards the Hyprland instance discovery in monarch-hw-hypr-instance.
#
# Callers (display commands, the internal-monitor watcher) need a working
# HYPRLAND_INSTANCE_SIGNATURE even after a Hyprland restart or from a systemd
# unit. Needs no Hyprland: Python names a fixture process with prctl and Perl
# creates the socket file.
#
# Run: bash test/monarch-hypr-instance-test.sh

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
FINDER="$ROOT/bin/monarch-hw-hypr-instance"

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
check() { [[ $2 == "$3" ]] || fail "$1: expected [$3], got [$2]"; pass "$1"; }

command -v perl >/dev/null || fail "perl is required to create the socket files this exercises"

TMP=$(mktemp -d)
FAKE_PID=""
cleanup() {
  [[ -n $FAKE_PID ]] && kill "$FAKE_PID" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

make_socket() {
  perl -MSocket -e '
    socket(S, AF_UNIX, SOCK_STREAM, 0) or die $!;
    bind(S, sockaddr_un($ARGV[0])) or die $!;
  ' "$1"
}

python3 -c 'import ctypes,time; assert ctypes.CDLL(None).prctl(15,b"Hyprland",0,0,0)==0; time.sleep(300)' &
FAKE_PID=$!
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ $(cat "/proc/$FAKE_PID/comm" 2>/dev/null) == Hyprland ]] && break
  sleep 0.01
done
[[ $(cat "/proc/$FAKE_PID/comm" 2>/dev/null) == Hyprland ]] || fail "Hyprland stand-in did not start"

export XDG_RUNTIME_DIR="$TMP"
unset HYPRLAND_INSTANCE_SIGNATURE
DEAD_PID=$(cat /proc/sys/kernel/pid_max 2>/dev/null || echo 4194304)

mkdir -p "$TMP/hypr/live_sig" "$TMP/hypr/stale_sig"
make_socket "$TMP/hypr/live_sig/.socket.sock"
make_socket "$TMP/hypr/stale_sig/.socket.sock"
printf '%s\nwayland-1\n' "$FAKE_PID" >"$TMP/hypr/live_sig/hyprland.lock"
printf '%s\nwayland-1\n' "$DEAD_PID" >"$TMP/hypr/stale_sig/hyprland.lock"

check "an unset signature is discovered from the running instance" "$("$FINDER")" "live_sig"

export HYPRLAND_INSTANCE_SIGNATURE=stale_sig
check "a signature left by a dead session is replaced" "$("$FINDER")" "live_sig"

export HYPRLAND_INSTANCE_SIGNATURE=gone
check "an unknown signature is replaced" "$("$FINDER")" "live_sig"

export HYPRLAND_INSTANCE_SIGNATURE=live_sig
check "a live signature is kept" "$("$FINDER")" "live_sig"

rm -rf "$TMP/hypr/live_sig"
unset HYPRLAND_INSTANCE_SIGNATURE
"$FINDER" >/dev/null && fail "no live instance must not report success"
pass "no live instance is reported as a failure"
