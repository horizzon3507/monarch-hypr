#!/bin/bash
# Probe: can a real Hyprland compositor start in a GitHub-hosted runner container?
# Tries several backend/renderer combinations and records logs. Run as user tester.
set -u
OUT=${1:-/tmp/probe-out}; mkdir -p "$OUT"
export XDG_RUNTIME_DIR=/tmp/xdg; mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
{ id; uname -r; for c in /sys/class/drm/*; do echo "$c $(readlink -f $c/device/driver 2>/dev/null)"; done; ls /run/seatd.sock 2>&1; ls -l /dev/dri /dev/kvm 2>&1; Hyprland --version | head -n 3; } > "$OUT/env.txt" 2>&1
cat > /tmp/probe.lua <<'LUA'
hl.config({ debug = { enable_stdout_logs = true } })
hl.monitor({ output = "", mode = "1280x720@60", position = "0x0", scale = 1 })
LUA
trace() { env AQ_TRACE=1 HYPRLAND_TRACE=1 "$@"; }
try() { # name, env...
  local name=$1; shift
  local d=$OUT/$name; mkdir -p "$d"; rm -rf "$XDG_RUNTIME_DIR"/hypr
  env AQ_TRACE=1 "$@" Hyprland --config /tmp/probe.lua > "$d/stdout.log" 2>&1 &
  local pid=$!
  sleep 15
  if kill -0 $pid 2>/dev/null; then
    echo "RUNNING" > "$d/status"
    export HYPRLAND_INSTANCE_SIGNATURE=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -n1)
    hyprctl version > "$d/version.txt" 2>&1; hyprctl monitors > "$d/monitors.txt" 2>&1
    hyprctl dispatch 'hl.dsp.focus({ workspace = 3 })' > "$d/dispatch.txt" 2>&1
    hyprctl activeworkspace >> "$d/dispatch.txt" 2>&1
    kill $pid; sleep 2
  else echo "EXITED" > "$d/status"; fi
  cp -r "$XDG_RUNTIME_DIR"/hypr "$d/hypr-dir" 2>/dev/null; find "$XDG_RUNTIME_DIR/hypr" -type f 2>/dev/null > "$d/hypr-files.txt"
  echo "$name: $(cat "$d/status")"
}
# 0) strace the default start to see what fails
mkdir -p "$OUT/strace"; rm -rf "$XDG_RUNTIME_DIR"/hypr
timeout 15 strace -f -s 160 -e trace=openat,connect,ioctl,socket -o "$OUT/strace/trace.txt" Hyprland --config /tmp/probe.lua > "$OUT/strace/stdout.log" 2>&1
grep -nE "ENOENT|EACCES|EPERM|ENODEV|= -1" "$OUT/strace/trace.txt" | grep -vE "locale|\.so|/etc/ld|/usr/share/(icons|mime)|fonts|\.cache|terminfo" | tail -60 > "$OUT/strace/errors.txt"
# 1) real DRM card (made accessible), default backend selection
try drm-card0
try drm-seatd LIBSEAT_BACKEND=seatd
try drm-card0-sw LIBGL_ALWAYS_SOFTWARE=1 AQ_NO_ATOMIC=1
# 2) nested inside a headless sway (wayland backend)
rm -rf "$XDG_RUNTIME_DIR"/wayland-*
WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 sway -c /dev/null > "$OUT/sway.log" 2>&1 &
sleep 4; export WAYLAND_DISPLAY=$(cd "$XDG_RUNTIME_DIR" && ls wayland-* 2>/dev/null | grep -v lock | head -n1); echo "sway display: $WAYLAND_DISPLAY" >> "$OUT/env.txt"
try nested-in-sway
try nested-in-sway-sw LIBGL_ALWAYS_SOFTWARE=1
