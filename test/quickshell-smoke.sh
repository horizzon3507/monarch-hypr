#!/bin/bash
# Load Quickshell configurations in a real, headless layer-shell compositor
# (sway with the headless wlroots backend) and fail on any load error.
#
# This proves that imports resolve, QML parses, the object tree is created and
# layer-shell windows map. It does NOT prove Hyprland behaviour: there is no
# Hyprland IPC, no real GPU and no real input. Use a live session for that.
#
# Usage: test/quickshell-smoke.sh [--screenshots DIR] [--timeout SECONDS] [ENTRY.qml...]
# Without entries it runs the built-in self-test fixtures plus the shell in
# default/quickshell/shell.qml when that file exists.
# Needs: quickshell, sway, grim (for screenshots), qt6-wayland; run as non-root.

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
screenshots=""
load_timeout=10
entries=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --screenshots) screenshots=$2; shift 2 ;;
    --timeout) load_timeout=$2; shift 2 ;;
    -h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) entries+=("$1"); shift ;;
  esac
done

for tool in quickshell sway; do
  command -v "$tool" >/dev/null || { echo "quickshell-smoke: $tool is not installed" >&2; exit 2; }
done
[[ $(id -u) -ne 0 ]] || { echo "quickshell-smoke: run as a non-root user" >&2; exit 2; }

work=$(mktemp -d)
export XDG_RUNTIME_DIR="$work/run"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
export HOME="$work/home"
mkdir -p "$HOME"
[[ -z $screenshots ]] || mkdir -p "$screenshots"

sway_pid=""
cleanup() {
  [[ -z $sway_pid ]] || kill "$sway_pid" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman \
  sway -c /dev/null >"$work/sway.log" 2>&1 &
sway_pid=$!

socket=""
for _ in $(seq 1 50); do
  socket=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'wayland-[0-9]*' ! -name '*.lock' -printf '%f\n' | head -n 1)
  [[ -n $socket ]] && break
  sleep 0.2
done
[[ -n $socket ]] || { echo "quickshell-smoke: headless sway did not start" >&2; cat "$work/sway.log" >&2; exit 2; }
export WAYLAND_DISPLAY=$socket
unset QT_QPA_PLATFORM

failures=0
total=0

# run_entry NAME FILE EXPECT   (EXPECT: pass, or fail:<text expected in the log>)
run_entry() {
  local name=$1 file=$2 expect=$3 log="$work/$1.log" loaded=0 pid
  total=$((total + 1))
  quickshell -p "$file" >"$log" 2>&1 &
  pid=$!
  for _ in $(seq 1 $((load_timeout * 5))); do
    if grep -q 'Configuration Loaded' "$log" || ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep 0.2
  done
  grep -q 'Configuration Loaded' "$log" && loaded=1
  if [[ $loaded == 1 && $expect == pass && -n $screenshots ]] && command -v grim >/dev/null; then
    sleep 1
    grim "$screenshots/$name.png" 2>>"$log" || true
  fi
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null

  local errors
  errors=$(grep -a 'ERROR' "$log" | sed 's/\x1b\[[0-9;]*m//g')
  if [[ $expect == pass ]]; then
    if [[ $loaded == 1 && -z $errors ]]; then
      echo "ok - $name loads"
    else
      echo "not ok - $name fails to load"
      sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -a 'ERROR\|WARN' | sed 's/^/    /'
      failures=$((failures + 1))
    fi
  else
    local needle=${expect#fail:}
    if [[ $loaded == 0 && $errors == *"$needle"* ]]; then
      echo "ok - $name is rejected with: $needle"
    else
      echo "not ok - $name was expected to fail with: $needle"
      sed 's/\x1b\[[0-9;]*m//g' "$log" | sed 's/^/    /' | tail -n 10
      failures=$((failures + 1))
    fi
  fi
}

if [[ ${#entries[@]} -eq 0 ]]; then
  fixtures="$ROOT/test/quickshell"
  run_entry self-test-good "$fixtures/good.qml" pass
  run_entry self-test-bad-import "$fixtures/bad-import.qml" 'is not installed'
  run_entry self-test-bad-property "$fixtures/bad-property.qml" 'non-existent property'
  [[ ! -f $ROOT/default/quickshell/shell.qml ]] || entries=("$ROOT/default/quickshell/shell.qml")
fi
for entry in "${entries[@]}"; do
  run_entry "$(basename "$(dirname "$entry")")-$(basename "$entry" .qml)" "$entry" pass
done

echo "quickshell-smoke: $((total - failures))/$total passed"
[[ $failures -eq 0 ]]
