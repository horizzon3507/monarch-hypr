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
active() { timeout 5 quickshell ipc --path "$MONARCH_SHELL_DIR" call panel active 2>&1 | tr -d '\n'; }
shot() { grim "$OUT/$1.png" 2>>"$OUT/grim.log"; }
layer() { hyprctl layers | grep -c 'namespace' ; }
layers_list() { hyprctl layers | grep namespace | sed 's/.*namespace: //;s/,.*//' | tr '\n' ' '; }
say "baseline layers: $(layers_list) active='$(active)'"
click() { /tmp/vptr $1 $2 1280 720 click >> "$OUT/pointer.log" 2>&1; }
move() { /tmp/vptr $1 $2 1280 720 >> "$OUT/pointer.log" 2>&1; }
openp() { timeout 5 monarch-panel open wifi-qr >> "$OUT/ipc.log" 2>&1; sleep 2; }
# E/F: valid keyboard receiver. A normal toplevel (quickshell FloatingWindow) logs every key it gets.
mkdir -p /tmp/rx; cat > /tmp/rx/shell.qml <<'QML'
import QtQuick
import Quickshell
FloatingWindow {
  id: w; visible: true; implicitWidth: 300; implicitHeight: 200; color: "#223344"
  Item { anchors.fill: parent; focus: true; Component.onCompleted: forceActiveFocus()
    Keys.onPressed: function(e) { console.log("RXKEY " + e.key + " text=" + e.text) } }
}
QML
QT_QPA_PLATFORM=wayland quickshell --path /tmp/rx > "$OUT/rx.log" 2>&1 &
RXPID=$!; sleep 5; shot e-rx-up
hyprctl clients | grep -E 'class|title|focus' | head -4 | tee -a "$res"
rxn() { grep -c 'RXKEY' "$OUT/rx.log"; }
# One wtype process = one persistent virtual keyboard: keys 2..n are not the first key of a fresh keyboard.
n0=$(rxn); timeout 8 wtype -s 400 a -s 400 a -s 400 a; sleep 1; n1=$(rxn)
say "R1 receiver baseline, one wtype process typing a,a,a: keys $n0 -> $n1 (valid iff >0; if 2 of 3 => first key of a fresh keyboard is dropped)"
for i in 1 2 3 4 5; do
  openp; a1=$(active)
  timeout 8 wtype -s 300 -k shift -s 300 -k shift -s 300 -k Escape; sleep 1.5; a2=$(active)
  say "P$i panel open, ONE wtype process shift,shift,Escape (no click): active before='$a1' after='$a2'"
  [[ -n $a2 ]] && timeout 5 monarch-panel close >/dev/null 2>&1; sleep 1
done
openp; n2=$(rxn); timeout 8 wtype -s 400 a -s 400 a -s 400 a; sleep 1; n3=$(rxn)
say "R2 panel open (exclusive): receiver keys $n2 -> $n3 (expect ~0 if exclusive focus captures keys)"
move 798 147; sleep 1; click 798 147; sleep 1.5; say "R2b x click: active='$(active)'"
n4=$(rxn); timeout 8 wtype -s 400 a -s 400 a -s 400 a; sleep 1; n5=$(rxn)
say "R3 after close: receiver keys $n4 -> $n5 (expect >0 = keyboard released to previous window)"
shot r-after
kill $RXPID 2>/dev/null
kill $HPID 2>/dev/null; sleep 1; echo done
