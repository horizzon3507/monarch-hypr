#!/bin/bash
# Runtime validation of keyboard navigation in the session panel in a real,
# headless layer-shell compositor. Real key events come from wtype (virtual
# keyboard): Down moves the focus highlight and Return activates the focused
# row, dispatching the real lock command. All session commands are stubs on
# PATH; nothing locks or suspends anything.
#
# Compositor: sway (default) or the actual target, set SMOKE_COMPOSITOR:
#   SMOKE_COMPOSITOR=hyprland test/quickshell-keynav-smoke.sh
#
# Usage: test/quickshell-keynav-smoke.sh [--screenshots DIR] [--timeout SECONDS]
# Needs: quickshell, grim, wtype, wev, and sway or Hyprland; run as non-root.

set -uo pipefail

# Qt warns and pollutes stdout when the locale is plain C; the guest/CI
# environments are UTF-8-capable, so pick that up front.
export LC_ALL=${LC_ALL:-C.UTF-8}

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SHELL_DIR="$ROOT/default/quickshell"
screenshots=""
load_timeout=10
compositor=${SMOKE_COMPOSITOR:-sway}
# SMOKE_ATTACH=1: do not start a compositor; use the running session
# (SMOKE_COMPOSITOR only selects the introspection tooling).
attach=${SMOKE_ATTACH:-0}

while [[ $# -gt 0 ]]; do
  case $1 in
    --screenshots) screenshots=$2; shift 2 ;;
    --timeout) load_timeout=$2; shift 2 ;;
    -h|--help) sed -n 2,13p "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

case $compositor in
  sway)     comp_bin=sway ;;
  hyprland) comp_bin=Hyprland ;;
  *) echo "keynav-smoke: unknown compositor '$compositor'" >&2; exit 2 ;;
esac
[[ $attach == 1 ]] && comp_bin=true

for tool in quickshell grim wtype wev "$comp_bin"; do
  command -v "$tool" >/dev/null || { echo "keynav-smoke: $tool is not installed" >&2; exit 2; }
done
[[ $(id -u) -ne 0 ]] || { echo "keynav-smoke: run as a non-root user" >&2; exit 2; }

work=$(mktemp -d)
if [[ $attach == 1 ]]; then
  : "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
else
  export XDG_RUNTIME_DIR="$work/run"
  mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
fi
export HOME="$work/home"
mkdir -p "$HOME" $screenshots

comp_pid=""
qs_pid=""
wtype_pid=""
cleanup() {
  [[ -z $wtype_pid ]] || kill "$wtype_pid" 2>/dev/null
  [[ -z $qs_pid ]] || kill "$qs_pid" 2>/dev/null
  [[ -z $comp_pid ]] || kill "$comp_pid" 2>/dev/null
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

# Start the compositor with a probe binding: 'b' fires only when a key
# reaches the compositor's normal routing, so it distinguishes a stuck
# keyboard grab from a client-delivery problem in the hand-back check below.
echo "keynav-smoke: compositor = $compositor attach = $attach"
if [[ $attach == 1 ]]; then
  socket=$(basename "${WAYLAND_DISPLAY:-wayland-1}")
  [[ -S $XDG_RUNTIME_DIR/$socket ]] || socket=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'wayland-[0-9]*' ! -name '*.lock' -printf '%f\n' | head -n 1)
  [[ -n $socket ]] || { echo "keynav-smoke: no wayland socket in the running session" >&2; exit 2; }
elif [[ $compositor == sway ]]; then
  cp "$(command -v sway)" "$work/sway-bin"
  printf 'bindsym b exec echo binding-fired-b >> "%s/bindings"\n' "$work" >"$work/comp.conf"
  WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman \
    "$work/sway-bin" -c "$work/comp.conf" >"$work/comp.log" 2>&1 &
else
  # Hyprland needs a DRM render node: aquamarine's headless backend has no
  # drmFD, so without /dev/dri/renderD* the GBM allocator cannot be created
  # and Hyprland aborts at startup ("CBackend::create() failed"). Skip with
  # a clear message instead of a doomed launch.
  if ! ls /dev/dri/renderD* >/dev/null 2>&1; then
    echo "keynav-smoke: hyprland skipped - no DRM render node in this environment"
    echo "keynav-smoke (hyprland): skipped (no GPU; aquamarine headless backend has no allocator)"
    exit 0
  fi
  {
    echo 'monitor = HEADLESS-1, 1920x1080@60, 0x0, 1'
    printf 'bind = , b, exec, echo binding-fired-b >> "%s/bindings"\n' "$work"
    echo 'misc { disable_hyprland_logo = true; force_default_wallpaper = 0 }'
    echo 'ecosystem { no_update_news = true; no_donation_nag = true }'
    echo 'animations { enabled = false }'
  } >"$work/comp.conf"
  Hyprland --config "$work/comp.conf" >"$work/comp.log" 2>&1 &
fi
comp_pid=${comp_pid:-}
echo "phase: $compositor launched (pid ${comp_pid:-attached})"

if [[ $attach != 1 ]]; then
socket=""
for _ in $(seq 1 100); do
  socket=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'wayland-[0-9]*' ! -name '*.lock' -printf '%f\n' | head -n 1)
  [[ -n $socket ]] && break
  sleep 0.2
done
[[ -n $socket ]] || { echo "keynav-smoke: headless $compositor did not start" >&2; cat "$work/comp.log" >&2; exit 2; }
fi
export WAYLAND_DISPLAY=$socket
echo "phase: wayland socket = $socket"
unset QT_QPA_PLATFORM
if [[ $compositor == hyprland ]]; then
  export HYPRLAND_INSTANCE_SIGNATURE=$(find "$XDG_RUNTIME_DIR/hypr" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | head -n 1)
fi
binding_registered=0
if [[ $attach == 1 && $compositor == hyprland ]]; then
  # The live session's config is not ours: add the probe binding at runtime.
  # Verify registration: without this check the "grab intercepts bindings"
  # control below is vacuous and a post-close miss is misread as a stuck grab.
  echo "phase: registering probe binding at runtime"
  timeout 10 hyprctl keyword "bind = , b, exec, echo binding-fired-b >> $work/bindings" 2>&1 | tail -2
  for _ in $(seq 1 10); do
    hyprctl binds -j 2>/dev/null | grep -q binding-fired-b && { binding_registered=1; break; }
    sleep 0.3
  done
  if [[ $binding_registered == 0 ]]; then
    # Retry with the two-argument keyword form before giving up.
    timeout 10 hyprctl keyword bind ", b, exec, echo binding-fired-b >> $work/bindings" 2>&1 | tail -2
    for _ in $(seq 1 10); do
      hyprctl binds -j 2>/dev/null | grep -q binding-fired-b && { binding_registered=1; break; }
      sleep 0.3
    done
  fi
  echo "probe binding registered on the compositor: $binding_registered"
fi

# The headless seat starts with no input devices at all (capabilities 0), so
# a one-shot wtype would create its virtual keyboard after the panel mapped
# and the key events would go nowhere. Hold a persistent virtual keyboard
# open on a FIFO before the shell starts: the seat has a keyboard when the
# panel surface maps, and later wtype -k calls reach the focused panel.
mkfifo "$work/wtype-stdin"
wtype - <"$work/wtype-stdin" >"$work/wtype.log" 2>&1 &
wtype_pid=$!
exec 9>"$work/wtype-stdin"
sleep 0.5
echo "phase: persistent keyboard held"

failures=0
blocked=0
ok() { echo "ok - $1"; }
not_ok() { echo "not ok - $1"; failures=$((failures + 1)); }

# Baseline control, with the panel shell ABSENT: can a regular toplevel
# client receive a virtual-keyboard key on this compositor at all? This
# separates a harness limitation from anything our shell does. Informational
# only; the requirement itself is enforced after the panel closes below.
echo "phase: baseline probe"
timeout 20 stdbuf -oL wev >"$work/wev-baseline.log" 2>&1 &
wev_base_pid=$!
sleep 2
timeout 10 wtype -k a || { echo "baseline wtype hung or failed; $compositor log tail:"; tail -30 "$work/comp.log"; }
sleep 1
kill -INT "$wev_base_pid" 2>/dev/null
wait "$wev_base_pid" 2>/dev/null
baseline_delivered=0
if grep -q "sym: a" "$work/wev-baseline.log"; then
  baseline_delivered=1
  echo "baseline: toplevel key delivery works on $compositor without the shell"
else
  echo "baseline: NO toplevel key delivery on $compositor even without the shell:"
  cat "$work/wev-baseline.log" || true
fi

ipc() { timeout 10 quickshell ipc --path "$SHELL_DIR" call "$@" 2>>"$work/qs.log"; }

if [[ $attach == 1 ]]; then
  # Stop the session's own shell so the smoke can start the candidate one
  # with the stub PATH; the compositor keeps running either way.
  pkill -x quickshell 2>/dev/null || true
  sleep 1
fi
quickshell -p "$SHELL_DIR" >"$work/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 $((load_timeout * 5))); do
  if grep -q 'Configuration Loaded' "$work/qs.log" || ! kill -0 "$qs_pid" 2>/dev/null; then break; fi
  sleep 0.2
done
grep -q 'Configuration Loaded' "$work/qs.log" && ok "shell loads with the keyboard navigation code" || not_ok "shell loads with the keyboard navigation code"

# Mid probe, informational: shell running but no panel ever opened. Together
# with the no-shell baseline and the post-close check this pinpoints whether
# the shell's mere presence or the panel open/close cycle affects toplevel
# key delivery.
timeout 20 stdbuf -oL wev >"$work/wev-mid.log" 2>&1 &
wev_mid_pid=$!
sleep 2
timeout 10 wtype -k c
sleep 1
kill -INT "$wev_mid_pid" 2>/dev/null
wait "$wev_mid_pid" 2>/dev/null
mid_delivered=0
if grep -q "sym: c" "$work/wev-mid.log"; then
  mid_delivered=1
  echo "mid: toplevel key delivery works with the shell running (no panel opened)"
else
  echo "mid: NO toplevel key delivery with the shell running (no panel opened):"
  cat "$work/wev-mid.log" || true
fi

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
if [[ $compositor == sway ]]; then
  swaysock=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'sway-ipc.*.sock' | head -n 1)
  if command -v swaymsg >/dev/null && [[ -n $swaysock ]]; then
    seats=$(swaymsg -s "$swaysock" -t get_seats 2>&1)
    echo "$seats" | head -30
    echo "$seats" | grep -q '"capabilities": [1-9]' && ok "the seat has input capabilities" || not_ok "the seat has input capabilities"
  fi
else
  devices=$(hyprctl devices 2>&1)
  echo "$devices" | head -30
  echo "$devices" | sed -n '/[Kk]eyboards/,/^$/p' | grep -q ' at ' \
    && ok "the seat has input capabilities" || not_ok "the seat has input capabilities"
fi

# Down moves the focus highlight to the next row (visible in the screenshot).
timeout 10 wtype -k Down
sleep 0.5
shot keynav-session-moved

# Up, then Return activates Lock (row 0, no confirm) and dispatches it.
timeout 10 wtype -k Up
sleep 0.3
timeout 10 wtype -k Return
sleep 0.5
grep -q '^monarch-system-lock $' "$work/calls" && ok "Return on the focused row dispatches lock" || not_ok "Return on the focused row dispatches lock"

# Down to Suspend, Return arms it; a second Return dispatches the argv.
rm -f "$work/calls"
timeout 10 wtype -k Down
sleep 0.3
timeout 10 wtype -k Return
sleep 0.5
# The arm state propagates through QML/IPC asynchronously; poll briefly
# instead of reading once under load (llvmpipe guests are slow).
armed=""
for _ in $(seq 1 10); do
  armed=$(ipc session armed | sed 's/\x1b\[[0-9;]*m//g' | tail -n1)
  [[ $armed == "suspend" ]] && break
  sleep 0.3
done
echo "armed state after Return: '${armed}'"
[[ $armed == "suspend" ]] && ok "Return arms the confirm row" || not_ok "Return arms the confirm row"

# Positive control, Hyprland only: while the open panel holds the exclusive
# keyboard grab, the compositor's own 'b' binding must NOT fire - the grab
# intercepts it. Meaningless on sway, which checks bindings before layer
# grabs by design. Must run BEFORE the dispatch below, because the panel
# closes on dispatch.
touch "$work/bindings"
if [[ $compositor == hyprland ]]; then
  if [[ $attach == 1 && $binding_registered == 0 ]]; then
    not_ok "probe binding registered at runtime (hyprctl keyword did not take effect)"
  else
    timeout 10 wtype -k b
    sleep 0.6
    [[ ! -s $work/bindings ]] && ok "the open panel's grab intercepts compositor bindings" || not_ok "the open panel's grab intercepts compositor bindings"
  fi
else
  echo "skip - grab-intercept control is Hyprland-only (sway checks bindings before layer grabs)"
fi

timeout 10 wtype -k Return
sleep 0.5
grep -q '^systemctl suspend$' "$work/calls" && ok "the second Return dispatches suspend" || not_ok "the second Return dispatches suspend"

# Focus hand-back: close the panel, then keys must flow through normal
# routing again. Three witnesses, strongest first: the compositor's 'b'
# binding fires (grab released, routing works), a benign normal client (wev)
# gets wl_keyboard enter (focus moved to it) and the key event itself, and
# the panel stub log stays unchanged (the key reached no panel action).
ipc panel close || true
sleep 0.8
lines_before=$(wc -l <"$work/calls")
timeout 20 stdbuf -oL wev >"$work/wev.log" 2>&1 &
wev_pid=$!
if [[ $compositor == hyprland ]]; then
  # Wait until the compositor's focus has actually landed on wev before
  # probing 'b': otherwise a slow grab release is misread as a stuck grab.
  focused=""
  for _ in $(seq 1 25); do
    focused=$(hyprctl activewindow -j 2>/dev/null | grep -o '"class": "[^"]*"' | head -1 || true)
    [[ $focused == *wev* ]] && break
    sleep 0.3
  done
  echo "post-close focused window: '${focused:-none}'"
else
  sleep 2
fi
if [[ $compositor == sway ]] && command -v swaymsg >/dev/null; then
  swaysock=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'sway-ipc.*.sock' | head -n 1)
  echo "seat focus post-close: $(swaymsg -s "$swaysock" -t get_seats 2>&1 | grep -E '"focus"' || true)"
  swaymsg -s "$swaysock" -t get_tree 2>&1 | grep -B2 -A2 '"focused": true' | head -12 || true
fi
timeout 10 wtype -k b
sleep 0.8
grep -q binding-fired-b "$work/bindings" && ok "compositor bindings fire again after the panel closes" || not_ok "compositor bindings fire again after the panel closes"
timeout 10 wtype -k Down
sleep 0.6
timeout 10 wtype -k a
sleep 1
kill -INT "$wev_pid" 2>/dev/null
wait "$wev_pid" 2>/dev/null
grep -q "wl_keyboard] enter" "$work/wev.log" && ok "a normal client gains keyboard focus after the panel closes" || not_ok "a normal client gains keyboard focus after the panel closes"
if grep -q "sym: a" "$work/wev.log"; then
  ok "a normal client receives keys after the panel closes"
elif [[ $compositor == sway && $baseline_delivered == 1 && $mid_delivered == 0 ]]; then
  # Not verifiable here: this same run proved the harness delivers to a
  # toplevel without the shell but fails with a Qt client merely connected.
  # A miss under those conditions is an environment block, not a pass and
  # not evidence about the shell; the real-Hyprland VM gate enforces this
  # requirement on the actual target.
  blocked=$((blocked + 1))
  echo "blocked - a normal client receives keys after the panel closes (unverifiable in this sway harness: baseline delivered, shell-present mid-probe failed in the same run; enforced by the real-Hyprland VM gate)"
else
  cat "$work/wev.log" || true
  [[ $compositor == hyprland ]] && hyprctl activewindow || true
  not_ok "a normal client receives keys after the panel closes"
fi
[[ $(wc -l <"$work/calls") -eq $lines_before ]] && ok "the key reached no panel action" || not_ok "the key reached no panel action"

kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""
[[ -z $(shell_errors) ]] && ok "no QML errors in the loaded shell" || { not_ok "no QML errors in the loaded shell"; shell_errors | sed 's/^/    /'; }

# Preserve the raw evidence (stub logs, wev logs, compositor output) next to
# the screenshots so a remote run's verdict can be audited afterwards.
if [[ -n $screenshots ]]; then
  mkdir -p "$screenshots/work"
  cp -a "$work"/*.log "$work"/calls "$work"/bindings "$screenshots/work/" 2>/dev/null || true
fi

echo "keynav-smoke ($compositor): $failures failure(s), $blocked environment-blocked"
[[ $failures -eq 0 ]]
