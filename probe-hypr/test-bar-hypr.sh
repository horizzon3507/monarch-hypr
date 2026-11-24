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

# Test copy of the bar: ONLY change is a console.log line in the workspace onClicked (labeled PROBE)
INSTR=/tmp/qs-instr; rm -rf "$INSTR"; cp -r "$ROOT/default/quickshell" "$INSTR"
python3 - "$INSTR/Workspaces.qml" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
a='var request = Logic.workspaceDispatch(slot.modelData);'
assert a in s
open(p,'w').write(s.replace(a,a+'\n                    console.log("PROBE onClicked slot", slot.modelData, "request:", request);'))
PY
say "bar under test: default/quickshell copied to $INSTR with one console.log added in onClicked"
fc-list | grep -ci dejavu | xargs -I{} echo "dejavu font files: {}" | tee -a "$res"
QT_QPA_PLATFORM=wayland quickshell --path "$INSTR" > "$OUT/quickshell.log" 2>&1 &
QPID=$!
sleep 8
kill -0 $QPID 2>/dev/null && say "quickshell running" || say "quickshell EXITED"
hyprctl layers > "$OUT/layers.txt" 2>&1
grep -qi "quickshell\|namespace" "$OUT/layers.txt" && say "layers: surface present" || say "layers: NO quickshell layer surface"
hyprctl monitors -j | python3 -c "import sys,json;m=json.load(sys.stdin)[0];print('reserved(top,bottom,left,right):',m['reserved'])" | tee -a "$res"

active() { hyprctl activeworkspace -j | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])"; }
shot() { grim "$OUT/$1.png" 2>>"$OUT/grim.log" && say "screenshot $1.png"; }
say "initial active workspace: $(active)"; shot ws1-initial

hyprctl dispatch 'hl.dsp.focus({ workspace = 3 })' >> "$OUT/dispatch.log" 2>&1
sleep 2; say "after dispatcher focus 3 -> active workspace: $(active)"; shot ws3-dispatch

VPTR=${VPTR:-/tmp/vptr}
# Real pointer click on the bar's slot 5 (slot centers: x = 10 + (i-1)*(w+4) + w/2, w = 13*1.9; y = 15)
slot_x() { python3 -c "w=13*1.9;print(round(10+($1-1)*(w+4)+w/2))"; }
X=$(slot_x 5); Y=15
"$VPTR" "$X" "$Y" 1280 720 >> "$OUT/pointer.log" 2>&1; say "pointer move rc=$?"
sleep 1; say "cursor pos: $(hyprctl cursorpos 2>&1)"
"$VPTR" "$X" "$Y" 1280 720 click >> "$OUT/pointer.log" 2>&1; say "pointer click rc=$?"
sleep 2; say "after real click on slot 5 (x=$X,y=$Y) -> active workspace: $(active)"; shot ws5-click

# back to 2 by dispatcher, then pixel-check the focused slot is highlighted
hyprctl dispatch 'hl.dsp.focus({ workspace = 2 })' >> "$OUT/dispatch.log" 2>&1
sleep 2; say "dispatcher focus 2 -> active: $(active)"; shot ws2-final
hyprctl workspaces -j | python3 -c "import sys,json;print('existing workspaces:',sorted(w['id'] for w in json.load(sys.stdin)))" | tee -a "$res"
python3 - "$OUT" <<'PY' | tee -a "$res"
import sys
from PIL import Image
out=sys.argv[1]
def accent_slots(png):
    im=Image.open(f"{out}/{png}.png").convert("RGB"); w=13*1.9; hits=[]
    for i in range(1,6):
        cx=round(10+(i-1)*(w+4)+w/2); cy=15
        px=[im.getpixel((cx+dx,cy+dy)) for dx in (-9,-8,8,9) for dy in (-6,6)]
        # accent default #7aa2f7 = (122,162,247)
        if all(abs(p[0]-122)<20 and abs(p[1]-162)<20 and abs(p[2]-247)<20 for p in px): hits.append(i)
    return hits
for name,exp in (("ws1-initial",1),("ws3-dispatch",3),("ws5-click",5),("ws2-final",2)):
    try: h=accent_slots(name)
    except Exception as e: h=f"error {e}"
    print(f"pixels {name}: accent-filled slot(s) {h} expected [{exp}]")
PY
grep -ciE "error|typeerror|referenceerror" "$OUT/quickshell.log" | xargs -I{} echo "quickshell log lines matching error: {}" | tee -a "$res"
say "onClicked log: $(grep -c 'PROBE onClicked' "$OUT/quickshell.log") line(s): $(grep 'PROBE onClicked' "$OUT/quickshell.log" | head -3 | tr '\n' '|')"

# Phase 2: does Quickshell's own Hyprland.dispatch() accept the Lua string? Fire it from QML, no pointer.
kill $QPID 2>/dev/null; sleep 1
hyprctl dispatch 'hl.dsp.focus({ workspace = 2 })' >/dev/null 2>&1; sleep 1
D=/tmp/qs-direct; rm -rf "$D"; cp -r "$ROOT/default/quickshell" "$D"
python3 - "$D/Workspaces.qml" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
a='    Repeater {\n        model: Logic.workspaceSlots'
assert a in s
t='    Timer {\n        interval: 5000; running: true; repeat: false\n        onTriggered: { var r = Logic.workspaceDispatch(4); console.log("PROBE direct dispatch", r); Hyprland.dispatch(r); }\n    }\n\n'
open(p,'w').write(s.replace(a,t+a,1))
PY
QT_QPA_PLATFORM=wayland quickshell --path "$D" > "$OUT/quickshell-direct.log" 2>&1 &
QPID2=$!
say "direct: active before timer: $(active)"
sleep 10
say "direct Hyprland.dispatch from QML (no pointer) -> active workspace: $(active) (expected 4)"; shot ws4-direct
grep -i 'PROBE' "$OUT/quickshell-direct.log" | head -5 | tee -a "$res"
kill $QPID2 $HPID 2>/dev/null; sleep 1

echo done
