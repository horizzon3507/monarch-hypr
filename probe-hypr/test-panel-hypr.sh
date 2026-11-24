#!/bin/bash
# Run the actual Quickshell bar (default/quickshell) inside a REAL Hyprland session
# on a CI runner, switch workspaces by dispatcher and by a real pointer click, and
# record screenshots + pixel checks. Run as the non-root user "tester".
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT=${1:-$ROOT/out}; mkdir -p "$OUT"
export XDG_RUNTIME_DIR=/tmp/xdg; mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
export HOME=/tmp/home; mkdir -p "$HOME"
res=$OUT/results.txt; : > "$res"
say() { echo "$*" | tee -a "$res"; }
say "commit: $(git -C "$ROOT" rev-parse HEAD)"
say "$(Hyprland --version | head -n1)"; say "$(quickshell --version)"
say "drm: $(for c in /sys/class/drm/card?; do echo "$c $(readlink -f $c/device/driver)"; done | tr '\n' ' ')"

cat > /tmp/session.lua <<'LUA'
hl.config({ debug = { enable_stdout_logs = true } })
hl.monitor({ output = "", mode = "1280x720@60", position = "0x0", scale = 1 })
LUA

started=0
for attempt in 1 2 3; do
  rm -rf "$XDG_RUNTIME_DIR"/hypr "$XDG_RUNTIME_DIR"/wayland-*
  Hyprland --config /tmp/session.lua > "$OUT/hyprland-stdout.log" 2>&1 &
  HPID=$!
  sleep 8
  if kill -0 $HPID 2>/dev/null; then started=1; break; fi
  say "Hyprland start attempt $attempt failed: $(tail -n2 "$OUT/hyprland-stdout.log" | tr '\n' ' ')"
done
[[ $started == 1 ]] || { say "RESULT: Hyprland could not start"; exit 3; }
export HYPRLAND_INSTANCE_SIGNATURE=$(ls "$XDG_RUNTIME_DIR/hypr" | head -n1)
export WAYLAND_DISPLAY=$(cd "$XDG_RUNTIME_DIR" && ls wayland-* | grep -v lock | head -n1)
say "Hyprland up, display $WAYLAND_DISPLAY, sig ${HYPRLAND_INSTANCE_SIGNATURE:0:12}"
hyprctl monitors > "$OUT/monitors.txt" 2>&1

export WAYLAND_DISPLAY=$(cd "$XDG_RUNTIME_DIR" && ls wayland-* | grep -v lock | head -n1)
export HYPRLAND_INSTANCE_SIGNATURE=$(ls "$XDG_RUNTIME_DIR/hypr" | head -n1)
say "Hyprland up (minimal config) display $WAYLAND_DISPLAY"
# Synthetic fixtures ONLY: stub helpers (real qrencode over a fake payload). No NetworkManager, no real Wi-Fi data.
FIX=/tmp/fix; mkdir -p $FIX; CALLS=/tmp/fix-calls.log; : > $CALLS
cat > $FIX/monarch-wifi-qr <<'STUB'
#!/bin/bash
echo "qr $*" >> /tmp/fix-calls.log
d=$(printf 'WIFI:T:WPA;S:FIXTURE-NET;P:FIXTURE-pass-123;;' | qrencode --size 10 --margin 4 --level M --type PNG --output - | base64 -w0)
printf 'meta\twlan0\tWPA\tdata:image/png;base64,%s\tFIXTURE-NET\n' "$d"
STUB
cat > $FIX/monarch-wifi-password <<'STUB'
#!/bin/bash
echo "password $*" >> /tmp/fix-calls.log; echo FIXTURE-pass-123
STUB
chmod +x $FIX/*; export PATH="$FIX:$ROOT/cand/bin:$PATH"
export MONARCH_SHELL_DIR="$ROOT/cand/default/quickshell"
QT_QPA_PLATFORM=wayland quickshell --path "$MONARCH_SHELL_DIR" > "$OUT/quickshell.log" 2>&1 &
sleep 8
active() { quickshell ipc --path "$MONARCH_SHELL_DIR" call panel active 2>&1 | tr -d '\n'; }
shot() { grim "$OUT/$1.png" 2>>"$OUT/grim.log"; }
layer() { hyprctl layers | grep -c 'namespace' ; }
layers_list() { hyprctl layers | grep namespace | sed 's/.*namespace: //;s/,.*//' | tr '\n' ' '; }
say "baseline layers: $(layers_list) active='$(active)'"
click() { /tmp/vptr $1 $2 1280 720 click >> "$OUT/pointer.log" 2>&1; }
move() { /tmp/vptr $1 $2 1280 720 >> "$OUT/pointer.log" 2>&1; }
openp() { monarch-panel open wifi-qr >> "$OUT/ipc.log" 2>&1; sleep 2; }
# A: open + Escape with NO click, 5 tries
for i in 1 2 3 4 5; do
  openp; a1=$(active); L1=$(layers_list); [[ $i == 1 ]] && shot p-open
  wtype -k Escape; sleep 1.5; a2=$(active)
  say "A$i open+Escape(no click): active before='$a1' after='$a2' layers-open=[$L1] layers-after=[$(layers_list)]"
  [[ -n $a2 ]] && monarch-panel close >/dev/null 2>&1; sleep 1
done
# B: open + click inside card (on the title area) then Escape, 5 tries
for i in 1 2 3 4 5; do
  openp; click 640 160; sleep 1; wtype -k Escape; sleep 1.5; a2=$(active)
  say "B$i open+click+Escape: active after='$a2'"; [[ -n $a2 ]] && { [[ $i == 1 ]] && shot p-b-stuck; monarch-panel close >/dev/null 2>&1; }; sleep 1
done
# C: pointer close via the x button. Locate card from screenshot: find button by pixel scan later; use estimate first
openp; shot p-c-open
for xy in "799 147"; do set -- $xy; move $1 $2; sleep 1; click $1 $2; sleep 1.5; say "C x-click at $xy: active after='$(active)' layers=[$(layers_list)]"; shot p-c-after; done
[[ -n $(active) ]] && monarch-panel close >/dev/null 2>&1
# D: keyboard release after close: panel layer must be gone; bar workspace dispatch still ok; keystroke goes nowhere in panel
sleep 1; say "D after close: layers=[$(layers_list)] hyprctl activewindow: $(hyprctl activewindow | head -1)"
# E: reveal path with real click needs the reveal button; just record password calls
say "fixture calls: $(sort $CALLS | uniq -c | tr '\n' ';')"
grep -ciE 'typeerror|referenceerror' "$OUT/quickshell.log" | xargs -I{} echo "TypeError/ReferenceError lines: {}" | tee -a "$res"
kill $HPID 2>/dev/null; sleep 1; echo done
