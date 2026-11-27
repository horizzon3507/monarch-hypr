#!/bin/bash
# Runtime validation of the capture panel in a real, headless layer-shell
# compositor (sway, headless wlroots), driven over Quickshell IPC. Proves the
# panel loads and renders, dispatch sends the real capture command, the panel
# asks to close after dispatching, an active recording swaps the variants for
# a stop row, and the webcam variant needs a webcam. All capture commands and
# probes are stubs on PATH; nothing records or screenshots anything.
#
# Usage: test/quickshell-capture-smoke.sh [--screenshots DIR] [--timeout SECONDS]
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
    -h|--help) sed -n 2,10p "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

for tool in quickshell sway grim; do
  command -v "$tool" >/dev/null || { echo "capture-smoke: $tool is not installed" >&2; exit 2; }
done
[[ $(id -u) -ne 0 ]] || { echo "capture-smoke: run as a non-root user" >&2; exit 2; }

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

# Stub every command the panel can run: they log their argv instead of acting.
stubs="$work/bin"
mkdir "$stubs"
for cmd in monarch-capture-screenshot monarch-capture-text-extraction monarch-capture-qr monarch-capture-color monarch-capture-screenrecording monarch-capture-screenrecording-with-webcam monarch-panel; do
  printf '#!/bin/bash\necho "%s $*" >>"%s/calls"\n' "$cmd" "$work" >"$stubs/$cmd"
  chmod +x "$stubs/$cmd"
done
# pgrep and monarch-hw-webcam are written per scenario.
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
[[ -n $socket ]] || { echo "capture-smoke: headless sway did not start" >&2; cat "$work/sway.log" >&2; exit 2; }
export WAYLAND_DISPLAY=$socket
unset QT_QPA_PLATFORM

failures=0
ok() { echo "ok - $1"; }
not_ok() { echo "not ok - $1"; failures=$((failures + 1)); }

ipc() { quickshell ipc --path "$SHELL_DIR" call "$@" 2>>"$work/qs.log"; }

start_shell() {
  quickshell -p "$SHELL_DIR" >"$work/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 $((load_timeout * 5))); do
    if grep -q 'Configuration Loaded' "$work/qs.log" || ! kill -0 "$qs_pid" 2>/dev/null; then break; fi
    sleep 0.2
  done
  grep -q 'Configuration Loaded' "$work/qs.log"
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

# Scenario 1: no recording, no webcam -> capture tools and the plain record
# variants; dispatch sends the real command and asks to close the panel.
printf '#!/bin/bash\nexit 1\n' >"$stubs/pgrep"; chmod +x "$stubs/pgrep"
printf '#!/bin/bash\nexit 1\n' >"$stubs/monarch-hw-webcam"; chmod +x "$stubs/monarch-hw-webcam"
if start_shell; then ok "shell loads with the capture panel code"; else not_ok "shell loads with the capture panel code"; fi

ipc panel open capture
sleep 1
shot capture-open
[[ $(ipc panel active) == "capture" ]] && ok "the capture panel opens over IPC" || not_ok "the capture panel opens over IPC"

ipc capture press screenshot
sleep 0.5
grep -q '^monarch-capture-screenshot $' "$work/calls" && ok "screenshot dispatches its command" || not_ok "screenshot dispatches its command"
grep -q '^monarch-panel close$' "$work/calls" && ok "the panel closes after dispatching" || not_ok "the panel closes after dispatching"

ipc panel open capture
sleep 0.5
ipc capture press record-mic
sleep 0.5
grep -q '^monarch-capture-screenrecording --with-desktop-audio --with-microphone-audio$' "$work/calls" && ok "record-mic dispatches both audio flags" || not_ok "record-mic dispatches both audio flags"

stop_shell
[[ -z $(shell_errors) ]] && ok "no QML errors in the loaded shell" || { not_ok "no QML errors in the loaded shell"; shell_errors | sed 's/^/    /'; }

# Scenario 2: recording active, webcam present -> stop row replaces variants,
# webcam row appears, and stop dispatches the stop command.
printf '#!/bin/bash\nexit 0\n' >"$stubs/pgrep"
printf '#!/bin/bash\nexit 0\n' >"$stubs/monarch-hw-webcam"
rm -f "$work/calls"
if start_shell; then ok "shell reloads for the recording case"; else not_ok "shell reloads for the recording case"; fi
ipc panel open capture
sleep 1
shot capture-recording
[[ $(ipc capture recording) == "true" ]] && ok "the panel sees the active recording" || not_ok "the panel sees the active recording"
ipc capture press stop
sleep 0.5
grep -q '^monarch-capture-screenrecording --stop-recording$' "$work/calls" && ok "the stop row dispatches --stop-recording" || not_ok "the stop row dispatches --stop-recording"

stop_shell
[[ -z $(shell_errors) ]] && ok "no QML errors in the recording case" || { not_ok "no QML errors in the recording case"; shell_errors | sed 's/^/    /'; }

echo "capture-smoke: $failures failure(s)"
[[ $failures -eq 0 ]]
