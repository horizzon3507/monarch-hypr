#!/bin/bash
# Runtime validation of the toggles panel in a real, headless layer-shell
# compositor (sway, headless wlroots), driven over Quickshell IPC. Proves the
# panel loads and renders, rows read state from each toggle's own status
# command, a click dispatches the real toggle command and the switch settles
# on the re-read state, and hardware-gated rows stay hidden without their
# probe. All toggle commands are stubs on PATH; nothing is actually toggled.
#
# Usage: test/quickshell-toggles-smoke.sh [--screenshots DIR] [--timeout SECONDS]
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
  command -v "$tool" >/dev/null || { echo "toggles-smoke: $tool is not installed" >&2; exit 2; }
done
[[ $(id -u) -ne 0 ]] || { echo "toggles-smoke: run as a non-root user" >&2; exit 2; }

work=$(mktemp -d)
export XDG_RUNTIME_DIR="$work/run"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
export HOME="$work/home"
export MONARCH_SMOKE_STATE="$work/state"
mkdir -p "$HOME" "$MONARCH_SMOKE_STATE" $screenshots

sway_pid=""
qs_pid=""
cleanup() {
  [[ -z $qs_pid ]] || kill "$qs_pid" 2>/dev/null
  [[ -z $sway_pid ]] || kill "$sway_pid" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

# Stub every command the panel can run. The toggle stubs keep a state file
# per toggle: `status` reports it as the {"enabled":bool} JSON the real
# scripts print, a bare call flips it and logs the call. monarch-panel just
# logs.
stubs="$work/bin"
mkdir "$stubs"
cat >"$stubs/toggle-stub" <<'STUB'
#!/bin/bash
name=$(basename "$0")
state_dir=${MONARCH_SMOKE_STATE:?}
if [[ $# -eq 1 && $1 == "status" ]]; then
  echo "$name status" >>"$state_dir/../calls"
  if [[ -f $state_dir/$name ]]; then printf '{"enabled":true}\n'; else printf '{"enabled":false}\n'; fi
  exit 0
fi
echo "$name $*" >>"$state_dir/../calls"
if [[ -f $state_dir/$name ]]; then rm -f "$state_dir/$name"; else touch "$state_dir/$name"; fi
STUB
for cmd in monarch-toggle-nightlight monarch-toggle-idle monarch-toggle-notification-silencing monarch-toggle-bar monarch-toggle-battery-percentage monarch-toggle-touchpad monarch-toggle-touchscreen; do
  cp "$stubs/toggle-stub" "$stubs/$cmd"
done
chmod +x "$stubs"/*
printf '#!/bin/bash\necho "monarch-panel $*" >>"%s/calls"\n' "$work" >"$stubs/monarch-panel"
chmod +x "$stubs/monarch-panel"
# Hardware gates: a battery exists, touchpad and touchscreen do not, so their
# rows must stay hidden.
printf '#!/bin/bash\nexit 0\n' >"$stubs/monarch-battery-present"
printf '#!/bin/bash\nexit 1\n' >"$stubs/monarch-hw-touchpad"
printf '#!/bin/bash\nexit 1\n' >"$stubs/monarch-hw-touchscreen"
chmod +x "$stubs"/monarch-battery-present "$stubs"/monarch-hw-touchpad "$stubs"/monarch-hw-touchscreen
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
[[ -n $socket ]] || { echo "toggles-smoke: headless sway did not start" >&2; cat "$work/sway.log" >&2; exit 2; }
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

if start_shell; then ok "shell loads with the toggles panel code"; else not_ok "shell loads with the toggles panel code"; fi

ipc panel open toggles
sleep 2
shot toggles-open
[[ $(ipc panel active) == "toggles" ]] && ok "the toggles panel opens over IPC" || not_ok "the toggles panel opens over IPC"
[[ $(ipc toggles state nightlight) == "off" ]] && ok "rows read their status (nightlight off)" || not_ok "rows read their status (nightlight off)"
[[ $(ipc toggles state touchpad) == "unknown" ]] && ok "the touchpad row stays hidden without the hardware" || not_ok "the touchpad row stays hidden without the hardware"

# Flip the bar toggle: the stub flips its state file, the panel re-reads, and
# the switch must settle on the reported state.
ipc toggles press bar
sleep 2.5
shot toggles-bar-on
grep -q '^monarch-toggle-bar $' "$work/calls" && ok "the click dispatches the real toggle command" || not_ok "the click dispatches the real toggle command"
[[ $(grep -c '^monarch-toggle-bar status$' "$work/calls") -ge 2 ]] && ok "the panel re-reads the toggled row" || not_ok "the panel re-reads the toggled row"
[[ $(ipc toggles state bar) == "on" ]] && ok "the switch settles on the reported state" || not_ok "the switch settles on the reported state"

stop_shell
[[ -z $(shell_errors) ]] && ok "no QML errors in the loaded shell" || { not_ok "no QML errors in the loaded shell"; shell_errors | sed 's/^/    /'; }

echo "toggles-smoke: $failures failure(s)"
[[ $failures -eq 0 ]]
