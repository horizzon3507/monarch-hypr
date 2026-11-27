#!/bin/bash
# Runtime validation of the session panel in a real, headless layer-shell
# compositor (sway with the headless wlroots backend), driven over Quickshell
# IPC. Proves the panel loads and renders, the arm/confirm flow works in the
# running shell, the confirmed click dispatches the real session command, and
# the suspend row follows the suspend-off toggle. Session commands are stubs
# on PATH, so nothing actually reboots or locks the runner.
#
# Usage: test/quickshell-session-smoke.sh [--screenshots DIR] [--timeout SECONDS]
# Needs: quickshell, sway, grim; run as non-root.

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SHELL_DIR="$ROOT/default/quickshell"
screenshots=""
load_timeout=10

while [[ $# -gt 0 ]]; do
  case $1 in
    --screenshots) screenshots=$2; shift 2 ;;
    --timeout) load_timeout=$2; shift 2 ;;
    -h|--help) sed -n 2,11p "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

for tool in quickshell sway grim; do
  command -v "$tool" >/dev/null || { echo "session-smoke: $tool is not installed" >&2; exit 2; }
done
[[ $(id -u) -ne 0 ]] || { echo "session-smoke: run as a non-root user" >&2; exit 2; }

work=$(mktemp -d)
export XDG_RUNTIME_DIR="$work/run"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
export HOME="$work/home"
mkdir -p "$HOME" "$screenshots"

sway_pid=""
qs_pid=""
cleanup() {
  [[ -z $qs_pid ]] || kill "$qs_pid" 2>/dev/null
  [[ -z $sway_pid ]] || kill "$sway_pid" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

# Stub every command the panel can run: they log their name instead of acting.
stubs="$work/bin"
mkdir "$stubs"
for cmd in monarch-system-lock monarch-system-logout monarch-system-reboot monarch-system-shutdown systemctl; do
  printf '#!/bin/bash\necho "%s $*" >>"%s/calls"\n' "$cmd" "$work" >"$stubs/$cmd"
  chmod +x "$stubs/$cmd"
done
# monarch-toggle-enabled and monarch-hibernation-available are written per
# scenario (suspend on/off, hibernation present/absent).
export PATH="$stubs:$PATH"

cp "$(command -v sway)" "$work/sway-bin"
WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman \
  "$work/sway-bin" -c /dev/null >"$work/sway.log" 2>&1 &
sway_pid=$!

socket=""
for _ in $(seq 1 50); do
  socket=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'wayland-[0-9]*' ! -name '*.lock' -printf '%f\n' | head -n 1)
  [[ -n $socket ]] && break
  sleep 0.2
done
[[ -n $socket ]] || { echo "session-smoke: headless sway did not start" >&2; cat "$work/sway.log" >&2; exit 2; }
export WAYLAND_DISPLAY=$socket
unset QT_QPA_PLATFORM

failures=0
ok() { echo "ok - $1"; }
not_ok() { echo "not ok - $1"; failures=$((failures + 1)); }

ipc() { quickshell ipc --path "$SHELL_DIR" call "$@" 2>>"$work/qs.log"; }

start_shell() {
  local log="$work/qs.log"
  quickshell -p "$SHELL_DIR" >"$log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 $((load_timeout * 5))); do
    if grep -q 'Configuration Loaded' "$log" || ! kill -0 "$qs_pid" 2>/dev/null; then break; fi
    sleep 0.2
  done
  grep -q 'Configuration Loaded' "$log"
}

stop_shell() {
  kill "$qs_pid" 2>/dev/null
  wait "$qs_pid" 2>/dev/null
  qs_pid=""
}

shot() { [[ -z $screenshots ]] || { sleep 1; grim "$screenshots/$1.png" 2>>"$work/qs.log" || true; }; }

shell_errors() {
  grep -aE 'ERROR|ReferenceError|TypeError' "$work/qs.log" | sed 's/\x1b\[[0-9;]*m//g' \
    | grep -vF -e 'quickshell.service.pipewire.loop: Failed to create pipewire context.' \
      -e 'quickshell.network: Network will not work. Could not find an available backend.' || true
}

# Scenario 1: suspend on, hibernation available -> six rows, arm/confirm over
# IPC, real dispatch.
printf '#!/bin/bash\nexit 1\n' >"$stubs/monarch-toggle-enabled"; chmod +x "$stubs/monarch-toggle-enabled"
printf '#!/bin/bash\nexit 0\n' >"$stubs/monarch-hibernation-available"; chmod +x "$stubs/monarch-hibernation-available"
if start_shell; then ok "shell loads with the session panel code"; else not_ok "shell loads with the session panel code"; fi

ipc panel open session
sleep 1
shot session-open
[[ $(ipc panel active) == "session" ]] && ok "the session panel opens over IPC" || not_ok "the session panel opens over IPC"

ipc session press shutdown
sleep 0.5
[[ $(ipc session armed) == "shutdown" ]] && ok "first click arms shutdown" || not_ok "first click arms shutdown (armed=$(ipc session armed))"
shot session-armed

ipc session press reboot
sleep 0.5
[[ $(ipc session armed) == "reboot" ]] && ok "clicking another row moves the arm" || not_ok "clicking another row moves the arm"
[[ ! -s "$work/calls" ]] && ok "no session command ran before a confirm" || not_ok "no session command ran before a confirm"

ipc session press reboot
sleep 0.5
grep -q '^monarch-system-reboot ' "$work/calls" 2>/dev/null && ok "the confirming click runs the command" || not_ok "the confirming click runs the command"
[[ $(ipc session armed) == "" ]] && ok "the arm clears after the run" || not_ok "the arm clears after the run"

ipc session press lock
sleep 0.5
grep -q '^monarch-system-lock ' "$work/calls" && ok "lock runs without a confirm" || not_ok "lock runs without a confirm"

ipc session press suspend
sleep 0.5
[[ $(ipc session armed) == "suspend" ]] && ok "first click arms suspend" || not_ok "first click arms suspend"
ipc session press suspend
sleep 0.5
grep -q '^systemctl suspend$' "$work/calls" && ok "confirming suspend runs systemctl suspend" || not_ok "confirming suspend runs systemctl suspend"

ipc session press hibernate
sleep 0.5
[[ $(ipc session armed) == "hibernate" ]] && ok "first click arms hibernate" || not_ok "first click arms hibernate"
ipc session press hibernate
sleep 0.5
grep -q '^systemctl hibernate$' "$work/calls" && ok "confirming hibernate runs systemctl hibernate" || not_ok "confirming hibernate runs systemctl hibernate"

ipc panel close
stop_shell
[[ -z $(shell_errors) ]] && ok "no QML errors in the loaded shell" || { not_ok "no QML errors in the loaded shell"; shell_errors | sed 's/^/    /'; }

# Scenario 2: suspend off and no hibernation -> neither is offered.
printf '#!/bin/bash\nexit 0\n' >"$stubs/monarch-toggle-enabled"
printf '#!/bin/bash\nexit 1\n' >"$stubs/monarch-hibernation-available"
rm -f "$work/calls"
if start_shell; then ok "shell reloads for the suspend-off case"; else not_ok "shell reloads for the suspend-off case"; fi
ipc panel open session
sleep 1
shot session-suspend-off
# With suspend off, the panel refuses suspend entirely: no arm, no dispatch.
ipc session press suspend
sleep 0.5
[[ $(ipc session armed) == "" ]] && ok "suspend is refused when the toggle disables it" || not_ok "suspend is refused when the toggle disables it"
ipc session press hibernate
sleep 0.5
[[ $(ipc session armed) == "" ]] && ok "hibernate is refused when unavailable" || not_ok "hibernate is refused when unavailable"
[[ ! -s "$work/calls" ]] && ok "no command ran in the suspend-off case" || not_ok "no command ran in the suspend-off case"
ipc panel close
stop_shell
[[ -z $(shell_errors) ]] && ok "no QML errors with suspend off" || { not_ok "no QML errors with suspend off"; shell_errors | sed 's/^/    /'; }

echo "session-smoke: $failures failure(s)"
[[ $failures -eq 0 ]]
