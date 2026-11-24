#!/bin/bash
# Run Monarch's UNMODIFIED Hyprland config + autostart (monarch-shell-start) in a real Hyprland on a CI runner.
# Runner session, not an installed ISO. Run as non-root user "tester".
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT=${1:-$ROOT/out}; mkdir -p "$OUT"
export XDG_RUNTIME_DIR=/tmp/xdg; mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
export HOME=/tmp/home; mkdir -p "$HOME"
export MONARCH_PATH=$ROOT PATH="$ROOT/bin:$PATH"
res=$OUT/results.txt; : > "$res"
say() { echo "$*" | tee -a "$res"; }
say "commit: $(git -C "$ROOT" log -1 --format=%H HEAD~0) parent: $(git -C "$ROOT" log -1 --format=%H HEAD~1 2>/dev/null)"
say "$(Hyprland --version | head -n1)"; say "$(quickshell --version)"
say "drm: $(for c in /sys/class/drm/card?; do echo "$c $(readlink -f $c/device/driver)"; done | tr '\n' ' ')"
for t in quickshell hyprpaper hypridle hyprlock mako swayosd-server swayosd-client walker uwsm-app uwsm; do command -v $t >/dev/null && say "tool present: $t" || say "tool MISSING: $t"; done

monarch-refresh-hypr > "$OUT/refresh-hypr.log" 2>&1; say "monarch-refresh-hypr rc=$?"
tail -5 "$OUT/refresh-hypr.log" | tee -a "$res"
# force 1280x720 for deterministic click coords (user-owned monitors.lua, as a user would)
echo 'hl.monitor({ output = "", mode = "1280x720@60", position = "0x0", scale = 1 })' > "$HOME/.config/hypr/monitors.lua"
say "monitors.lua overridden to 1280x720 (user-owned override file); everything else is Monarch default"

# Diagnose the real uwsm-app in this session-less container (no systemd user manager)
( uwsm-app -t service -- true ) > "$OUT/uwsm-app-real.log" 2>&1; say "REAL uwsm-app -t service -- true rc=$? : $(head -c 300 "$OUT/uwsm-app-real.log" | tr '\n' ' ')"
# LABELED TEST SHIM: uwsm-app needs a uwsm/systemd session that a CI container lacks, so run the command directly.
# Everything else (monarch-shell-start, config, bar) is unmodified Monarch code.
SHIM=/tmp/shim; mkdir -p $SHIM
printf '%s\n' '#!/bin/bash' 'while [[ $# -gt 0 && $1 != -- ]]; do shift; done; shift' 'echo "shim uwsm-app: $*" >> /tmp/shim-uwsm.log' 'exec "$@" >> "/tmp/shim-out-$(basename "$1").log" 2>&1' > $SHIM/uwsm-app; chmod +x $SHIM/uwsm-app
export PATH="$SHIM:$PATH"; say "TEST SHIM in PATH: uwsm-app runs the command directly (stand-in for the uwsm session of a real install)"
started=0
for attempt in 1 2 3; do
  rm -rf "$XDG_RUNTIME_DIR"/hypr "$XDG_RUNTIME_DIR"/wayland-*
  Hyprland --config "$HOME/.config/hypr/hyprland.lua" > "$OUT/hyprland-stdout.log" 2>&1 &
  HPID=$!; sleep 10
  kill -0 $HPID 2>/dev/null && { started=1; break; }
  say "Hyprland start attempt $attempt failed: $(tail -n2 "$OUT/hyprland-stdout.log" | tr '\n' ' ')"
done
[[ $started == 1 ]] || { say "RESULT: Hyprland could not start"; exit 3; }
export HYPRLAND_INSTANCE_SIGNATURE=$(ls "$XDG_RUNTIME_DIR/hypr" | head -n1)
export WAYLAND_DISPLAY=$(cd "$XDG_RUNTIME_DIR" && ls wayland-* | grep -v lock | head -n1)
say "Hyprland up with Monarch config, display $WAYLAND_DISPLAY"
sleep 12
hyprctl configerrors > "$OUT/configerrors.txt" 2>&1; say "configerrors: $(tr '\n' ' ' < "$OUT/configerrors.txt" | head -c 600)"
hyprctl layers > "$OUT/layers.txt" 2>&1; hyprctl monitors > "$OUT/monitors.txt" 2>&1
ps -eo pid,args | grep -E 'quickshell|hyprpaper|mako|swayosd|hypridle|monarch-shell-start' | grep -v grep > "$OUT/procs.txt"; say "autostarted processes:"; cat "$OUT/procs.txt" | tee -a "$res"
grep -qi quickshell "$OUT/layers.txt" && say "layers: quickshell bar surface present (started by Monarch autostart)" || say "layers: NO quickshell layer"
say "reserved: $(hyprctl monitors -j | python3 -c "import sys,json;print(json.load(sys.stdin)[0]['reserved'])")"
active() { hyprctl activeworkspace -j | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])"; }
shot() { grim "$OUT/$1.png" 2>>"$OUT/grim.log" && say "screenshot $1.png"; }
say "initial active: $(active)"; shot f1-initial
hyprctl dispatch 'hl.dsp.focus({ workspace = 3 })' >> "$OUT/dispatch.log" 2>&1; sleep 2; say "dispatcher 3 -> $(active)"; shot f3-dispatch
X=$(python3 -c "w=13*1.9;print(round(10+4*(w+4)+w/2))"); Y=15
/tmp/vptr $X $Y 1280 720 >> "$OUT/pointer.log" 2>&1; sleep 1; say "cursor: $(hyprctl cursorpos)"
/tmp/vptr $X $Y 1280 720 click >> "$OUT/pointer.log" 2>&1; sleep 2
say "real click slot 5 (x=$X,y=$Y) -> active $(active)"; shot f5-click
# Monarch keybind SUPER+K etc. are not exercised here. List binds to prove config loaded:
hyprctl binds -j > "$OUT/binds.json" 2>&1; say "binds loaded: $(python3 -c "import json;print(len(json.load(open('$OUT/binds.json'))))" 2>&1)"
say "mako running: $(pgrep -x mako >/dev/null && echo yes || echo no); hyprpaper: $(pgrep -x hyprpaper >/dev/null && echo yes || echo no); swayosd-server: $(pgrep -x swayosd-server >/dev/null && echo yes || echo no); hypridle: $(pgrep -x hypridle >/dev/null && echo yes || echo no)"
for f in /tmp/shim-out-*.log; do cp "$f" "$OUT/"; done; say "--- daemon outputs ---"; for f in /tmp/shim-out-*.log; do say "[$f] $(head -c 500 "$f" | tr "\n" " ")"; done; cp /tmp/shim-uwsm.log "$OUT/" 2>/dev/null; cp /tmp/home/.local/state/*/*.log "$OUT/" 2>/dev/null
kill $HPID 2>/dev/null; sleep 1; echo done
