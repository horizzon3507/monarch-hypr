#!/bin/bash
# Runtime validation of the share panel in a real, headless layer-shell
# compositor (sway, headless wlroots), driven over Quickshell IPC. Proves the
# panel loads and renders, a share action dispatches the real command and the
# panel asks to close, and the Wi-Fi QR row switches to the QR panel instead
# of closing. All share commands are stubs on PATH; nothing is shared.
#
# Usage: test/quickshell-share-smoke.sh [--screenshots DIR] [--timeout SECONDS]
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
  command -v "$tool" >/dev/null || { echo "share-smoke: $tool is not installed" >&2; exit 2; }
done
[[ $(id -u) -ne 0 ]] || { echo "share-smoke: run as a non-root user" >&2; exit 2; }

work=$(mktemp -d)
export XDG_RUNTIME_DIR="$work/run"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
export HOME="$work/home"
mkdir -p "$HOME" $screenshots

sway_pid=""
qs_pid=""
cleanup() {
  [[ -z $qs_pid ]] || kill "$qs_pid" 2>/dev/null
  [[ -z $sway_pid ]] || kill "$sway_pid" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

# Stub every command the panel can run: they log their argv instead of
# acting. The monarch-panel stub must not recurse into the real one.
stubs="$work/bin"
mkdir "$stubs"
for cmd in monarch-menu-share monarch-launch-or-focus monarch-panel; do
  printf '#!/bin/bash\necho "%s $*" >>"%s/calls"\n' "$cmd" "$work" >"$stubs/$cmd"
  chmod +x "$stubs/$cmd"
done
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
[[ -n $socket ]] || { echo "share-smoke: headless sway did not start" >&2; cat "$work/sway.log" >&2; exit 2; }
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

if start_shell; then ok "shell loads with the share panel code"; else not_ok "shell loads with the share panel code"; fi

ipc panel open share
sleep 1
shot share-open
[[ $(ipc panel active) == "share" ]] && ok "the share panel opens over IPC" || not_ok "the share panel opens over IPC"

# A share action dispatches its command and the panel asks to close.
ipc share press clipboard
sleep 0.5
grep -q '^monarch-menu-share clipboard$' "$work/calls" && ok "share clipboard dispatches its command" || not_ok "share clipboard dispatches its command"
grep -q '^monarch-panel close$' "$work/calls" && ok "the panel closes after dispatching" || not_ok "the panel closes after dispatching"

# The Wi-Fi QR row switches panels instead of closing.
rm -f "$work/calls"
ipc panel open share
sleep 0.5
ipc share press wifi-qr
sleep 0.5
grep -q '^monarch-panel open wifi-qr$' "$work/calls" && ok "the QR row switches to the Wi-Fi QR panel" || not_ok "the QR row switches to the Wi-Fi QR panel"
! grep -q '^monarch-panel close$' "$work/calls" && ok "the QR row does not close the panel" || not_ok "the QR row does not close the panel"

stop_shell
[[ -z $(shell_errors) ]] && ok "no QML errors in the loaded shell" || { not_ok "no QML errors in the loaded shell"; shell_errors | sed 's/^/    /'; }

echo "share-smoke: $failures failure(s)"
[[ $failures -eq 0 ]]
