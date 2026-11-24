#!/bin/bash
# Probe: can a real Hyprland compositor start in a GitHub-hosted runner container?
# Tries several backend/renderer combinations and records logs. Run as user tester.
set -u
OUT=${1:-/tmp/probe-out}; mkdir -p "$OUT"
export XDG_RUNTIME_DIR=/tmp/xdg; mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
{ id; uname -r; ls -l /dev/dri /dev/kvm 2>&1; Hyprland --version | head -n 3; } > "$OUT/env.txt" 2>&1
cat > /tmp/probe.lua <<'LUA'
hl.monitor({ output = "", mode = "1280x720@60", position = "0x0", scale = 1 })
LUA
try() { # name, env...
  local name=$1; shift
  local d=$OUT/$name; mkdir -p "$d"; rm -rf "$XDG_RUNTIME_DIR"/hypr "$XDG_RUNTIME_DIR"/wayland-*
  env "$@" Hyprland --config /tmp/probe.lua > "$d/stdout.log" 2>&1 &
  local pid=$!
  sleep 12
  if kill -0 $pid 2>/dev/null; then
    echo "RUNNING" > "$d/status"
    sig=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -n1)
    export HYPRLAND_INSTANCE_SIGNATURE=$sig
    hyprctl version > "$d/version.txt" 2>&1; hyprctl monitors > "$d/monitors.txt" 2>&1
    hyprctl dispatch 'hl.dsp.focus({ workspace = 3 })' > "$d/dispatch.txt" 2>&1
    hyprctl activeworkspace >> "$d/dispatch.txt" 2>&1
    cp "$XDG_RUNTIME_DIR"/hypr/*/hyprland.log "$d/hyprland.log" 2>/dev/null
    kill $pid; sleep 2
  else
    echo "EXITED" > "$d/status"; cp "$XDG_RUNTIME_DIR"/hypr/*/hyprland.log "$d/hyprland.log" 2>/dev/null
  fi
  echo "$name: $(cat "$d/status")"
}
try headless-default AQ_BACKENDS=headless
try headless-sw AQ_BACKENDS=headless LIBGL_ALWAYS_SOFTWARE=1 MESA_LOADER_DRIVER_OVERRIDE=llvmpipe
try headless-sw-wlr AQ_BACKENDS=headless WLR_RENDERER_ALLOW_SOFTWARE=1 LIBGL_ALWAYS_SOFTWARE=1 AQ_NO_ATOMIC=1
try wayland-nested-sway AQ_BACKENDS=headless LIBGL_ALWAYS_SOFTWARE=1 AQ_DRM_DEVICES=/dev/null
