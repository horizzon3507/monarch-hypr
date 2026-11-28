#!/bin/bash
# Runtime validation of keyboard navigation in the session panel in a real,
# headless layer-shell compositor (sway, headless wlroots). Real key events
# come from wtype (virtual keyboard): Down moves the focus highlight and
# Return activates the focused row, dispatching the real lock command. All
# session commands are stubs on PATH; nothing locks or suspends anything.
#
# Usage: test/quickshell-keynav-smoke.sh [--screenshots DIR] [--timeout SECONDS]
# Needs: quickshell, sway, grim, wtype; run as non-root.

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

for tool in quickshell sway grim wtype; do
  command -v "$tool" >/dev/null || { echo "keynav-smoke: $tool is not installed" >&2; exit 2; }
done
[[ $(id -u) -ne 0 ]] || { echo "keynav-smoke: run as a non-root user" >&2; exit 2; }

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
# acting. monarch-toggle-enabled exits 1 (suspend stays on) and
# monarch-hibernation-available exits 1 (no hibernate row).
stubs="$work/bin"
mkdir "$stubs"
for cmd in monarch-system-lock monarch-system-logout monarch-system-reboot monarch-system-shutdown systemctl monarch-panel; do
  printf '#!/bin/bash\necho "%s $*" >>"%s/calls"\n' "$cmd" "$work" >"$stubs/$cmd"
  chmod +x "$stubs/$cmd"
done
printf '#!/bin/bash\nexit 1\n' >"$stubs/monarch-toggle-enabled"
printf '#!/bin/bash\nexit 1\n' >"$stubs/monarch-hibernation-available"
chmod +x "$stubs"/monarch-toggle-enabled "$stubs"/monarch-hibernation-available
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
[[ -n $socket ]] || { echo "keynav-smoke: headless sway did not start" >&2; cat "$work/sway.log" >&2; exit 2; }
export WAYLAND_DISPLAY=$socket
unset QT_QPA_PLATFORM

failures=0
ok() { echo "ok - $1"; }
not_ok() { echo "not ok - $1"; failures=$((failures + 1)); }

ipc() { quickshell ipc --path "$SHELL_DIR" call "$@" 2>>"$work/qs.log"; }

quickshell -p "$SHELL_DIR" >"$work/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 $((load_timeout * 5))); do
  if grep -q 'Configuration Loaded' "$work/qs.log" || ! kill -0 "$qs_pid" 2>/dev/null; then break; fi
  sleep 0.2
done
grep -q 'Configuration Loaded' "$work/qs.log" && ok "shell loads with the keyboard navigation code" || not_ok "shell loads with the keyboard navigation code"

shot() { [[ -z $screenshots ]] || { sleep 1; grim "$screenshots/$1.png" 2>>"$work/qs.log" || true; }; }

shell_errors() {
  grep -aE 'ERROR|ReferenceError|TypeError' "$work/qs.log" | sed 's/\x1b\[[0-9;]*m//g' \
    | grep -vF -e 'quickshell.service.pipewire.loop: Failed to create pipewire context.' \
      -e 'quickshell.network: Network will not work. Could not find an available backend.' || true
}

ipc panel open session
sleep 1
shot keynav-session-top
echo "card focus: $(ipc panel cardFocused)"
swaysock=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'sway-ipc.*.sock' | head -n 1)
command -v swaymsg >/dev/null && [[ -n $swaysock ]] && swaymsg -s "$swaysock" -t get_seats 2>&1 | head -30 || true

# Down moves the focus highlight to the next row (visible in the screenshot).
wtype -k Down
sleep 0.5
shot keynav-session-moved

# Up, then Return activates Lock (row 0, no confirm) and dispatches it.
wtype -k Up
sleep 0.3
wtype -k Return
sleep 0.5
grep -q '^monarch-system-lock $' "$work/calls" && ok "Return on the focused row dispatches lock" || not_ok "Return on the focused row dispatches lock"

# Down to Suspend, Return arms it; a second Return dispatches the argv.
rm -f "$work/calls"
wtype -k Down
sleep 0.3
wtype -k Return
sleep 0.5
[[ $(ipc session armed) == "suspend" ]] && ok "Return arms the confirm row" || not_ok "Return arms the confirm row"
wtype -k Return
sleep 0.5
grep -q '^systemctl suspend$' "$work/calls" && ok "the second Return dispatches suspend" || not_ok "the second Return dispatches suspend"

kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""
[[ -z $(shell_errors) ]] && ok "no QML errors in the loaded shell" || { not_ok "no QML errors in the loaded shell"; shell_errors | sed 's/^/    /'; }

echo "keynav-smoke: $failures failure(s)"
[[ $failures -eq 0 ]]
