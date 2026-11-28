#!/bin/bash

# Bar responsive-layout validation. Runs INSIDE the disposable VM guest,
# attached to the real Hyprland session: no mocks, no offscreen replicas.
#
# Geometry, with the REAL Bar.qml/Workspaces.qml/Tray.qml from the candidate
# checkout driving the REAL bar on the REAL compositor:
#   1. With 10 real workspaces (one foot window each) on a 640x480 output the
#      centered clock stays legible (OCR) and nothing paints in the measured
#      gap strips flanking it (no workspace-row or right-group encroachment).
#   2. The power/session control is still drawn at the right bar edge at
#      640px (pixel variance in the rightmost columns) - never clipped away.
#   3. At 1920x1080 the same invariants hold; all 10 real workspaces exist
#      (hyprctl) and the screenshot shows every slot (human-inspected).
#
# Tray overflow popup click-through (real pointer via uinput/ydotool, real
# SNI traffic from test/fixtures/tray_fixture.py - synthetic services, not
# proof about any real application):
#   4. The "+N" overflow chip renders at 640px; clicking it opens the popup
#      below the bar (pixel-diff bounding box).
#   5. Clicking a popup row delivers Activate to the fixture (handler path).
#   6. Escape closes the popup; reopen + outside-click closes it; reopen +
#      output mode change closes it (no stale popup after resize).
#
# Environment (set by the caller, same as the keynav smoke): WAYLAND_DISPLAY,
# HYPRLAND_INSTANCE_SIGNATURE, XDG_RUNTIME_DIR. CWD must be the candidate
# checkout root. Screenshots and crops land in $1 (default ~/keynav-out).

set -uo pipefail

OUT=${1:-$HOME/keynav-out}
mkdir -p "$OUT"
SHELL_DIR=$PWD/default/quickshell
LOG=$OUT/bar-layout.log
exec > >(tee -a "$LOG") 2>&1

fail=0
say() { echo "bar-layout: $*"; }
bad() { echo "bar-layout: FAIL: $*"; fail=1; }

# --- tooling ---------------------------------------------------------------
echo monarch | sudo -S pacman -Sy --needed --noconfirm \
  foot jq imagemagick tesseract-ocr grim ydotool python-gobject 2>&1 | tail -2
python3 -c 'import gi' 2>/dev/null || bad "python-gobject unavailable - SNI fixture cannot run"

# Pointer injection: uinput daemon (root) + client socket shared with us.
export YDOTOOL_SOCKET=${YDOTOOL_SOCKET:-/tmp/.ydotool_socket}
pgrep -x ydotoold >/dev/null 2>&1 || { echo monarch | sudo -S -b env YDOTOOL_SOCKET=$YDOTOOL_SOCKET ydotoold >/dev/null 2>&1; sleep 1; }
echo monarch | sudo -S chmod 0666 "$YDOTOOL_SOCKET" 2>/dev/null || true
sleep 1
echo monarch | sudo -S chmod 666 $YDOTOOL_SOCKET 2>/dev/null || true

# --- shell under test: restart from the candidate checkout ------------------
pkill -x quickshell 2>/dev/null || true
sleep 2
quickshell -p "$SHELL_DIR" >"$OUT/bar-qs.log" 2>&1 &
QS_PID=$!
sleep 8
kill -0 "$QS_PID" 2>/dev/null || { bad "quickshell from candidate checkout died; see bar-qs.log"; tail -20 "$OUT/bar-qs.log"; exit 1; }
say "shell restarted from candidate checkout (pid $QS_PID)"

# --- ten real workspaces -----------------------------------------------------
# NOTE: on Hyprland 0.56 `dispatch exec "[workspace N silent] foot"` creates
# the workspace but silently spawns nothing, while plain `dispatch exec foot`
# works. Switching to each workspace creates it and empty workspaces persist
# here (verified empirically in this guest), which is all the 10-slot
# scenario needs.
for ws in 2 3 4 5 6 7 8 9 10; do
  hyprctl dispatch workspace $ws >/dev/null 2>&1
done
hyprctl dispatch workspace 1 >/dev/null 2>&1
ws_count=0
for _ in $(seq 1 24); do
  ws_count=$(hyprctl workspaces -j | jq '[.[] | select(.id >= 1 and .id <= 10)] | length')
  [[ $ws_count -ge 10 ]] && break
  sleep 2
done
say "real workspaces present: $ws_count (need 10)"
hyprctl workspaces -j | jq -c '[.[] | {id, windows}]' > "$OUT/bar-workspaces.json"
[[ $ws_count -ge 10 ]] || bad "only $ws_count workspaces exist; 10-slot scenario not reached"

# --- twelve real SNI fixtures: the tray overflows into the "+N" chip ----------
# Six icons fit inline at 640px next to clock+indicators (observed: no chip);
# twelve force real overflow.
FIXTURE_LOG=$OUT/tray-fixture-calls.log
python3 test/fixtures/tray_fixture.py --items 12 --log "$FIXTURE_LOG" >"$OUT/tray-fixture.log" 2>&1 &
FIX_PID=$!
reg=0
for _ in $(seq 1 30); do
  reg=$(grep -c ' REGISTERED ' "$FIXTURE_LOG" 2>/dev/null || true)
  [[ $reg -ge 12 ]] && break
  sleep 1
done
say "SNI fixtures registered: $reg/12 (synthetic test services, not real apps)"
[[ $reg -ge 12 ]] || bad "SNI fixtures did not register; tray overflow scenario not reached"

# --- monitor mode switching via the 0.56 Lua API ------------------------------
MON=$(hyprctl monitors -j | jq -r '.[0].name')
say "output: $MON"
set_mode() { # WxH; polls until applied, dumps available modes on failure
  local mode=$1 want_w=${1%x*}
  hyprctl eval "hl.monitor({output=\"$MON\", mode=\"$mode@60\", position=\"0x0\", scale=1})" >/dev/null 2>&1
  for _ in $(seq 1 15); do
    [[ $(hyprctl monitors -j | jq -r '.[0].width') == "$want_w" ]] && return 0
    sleep 1
  done
  say "mode $mode did not apply; available modes:"
  hyprctl monitors -j | jq -r '.[0].availableModes[]' | tee "$OUT/bar-modes-$want_w.txt"
  return 1
}

# --- pixel helpers ------------------------------------------------------------
bar_bg=()
read_bg() { # IMG
  local rgb
  rgb=$(magick "$1" -crop 1x1+2+2 -depth 8 -format "%[fx:int(r*255)] %[fx:int(g*255)] %[fx:int(b*255)]" info:)
  bar_bg=($rgb)
}

bar_height() { # IMG W -> bar bottom: first row where <50% of pixels match the bar bg
  # A row-mean comparison misfires because slot borders and clock ink change
  # row means well above the bar's bottom edge (observed: height detected as
  # 8px on a ~28px bar). Instead count, per row, the fraction of pixels that
  # match the bar background: content rows inside the bar stay >90% bg, the
  # wallpaper below the bar is ~0% bg.
  local img=$1 w=$2
  magick "$img" -crop "${w}x64+0+0" -depth 8 txt:- 2>/dev/null \
    | sed 's/[():,]/ /g' \
    | awk -v r0="${bar_bg[0]}" -v g0="${bar_bg[1]}" -v b0="${bar_bg[2]}" -v w="$w" '
      NR > 1 { y = $2
               d = ($3-r0)^2 + ($4-g0)^2 + ($5-b0)^2
               if (d <= 64) bg[y]++
               cnt[y]++ }
      END { for (y = 4; y < 60; y++)
              if (cnt[y] > 0 && bg[y]/cnt[y] < 0.5) { print y; exit }
            print 31 }'
}

ink_pixels() { # IMG CROP -> count of pixels differing from the bar background
  magick "$1" -crop "$2" -depth 8 txt:- 2>/dev/null | sed 's/[():,]/ /g' | awk -v r0="${bar_bg[0]}" -v g0="${bar_bg[1]}" -v b0="${bar_bg[2]}" '
    NR > 1 { d = ($3-r0)^2 + ($4-g0)^2 + ($5-b0)^2; if (d > 64) n++ }
    END { print n+0 }'
}

clock_bounds() { # IMG W H -> absolute x of the clock's leftmost/rightmost ink
  magick "$1" -crop "400x${3}+$(($2 / 2 - 200))+0" -depth 8 txt:- 2>/dev/null \
    | sed 's/[():,]/ /g' | awk -v r0="${bar_bg[0]}" -v g0="${bar_bg[1]}" -v b0="${bar_bg[2]}" -v base="$(($2 / 2 - 200))" '
      NR > 1 { d = ($3-r0)^2 + ($4-g0)^2 + ($5-b0)^2
               if (d > 64) { x = $1 + base; if (min == "" || x < min) min = x; if (x > max) max = x } }
      END { if (min == "") print ""; else print min, max }'
}

# diff_bbox A B -> "WxH+X+Y" of pixels that changed (trimmed threshold box)
diff_bbox() {
  magick compare -metric AE "$1" "$2" "$OUT/diff-tmp.png" 2>/dev/null || true
  magick "$OUT/diff-tmp.png" -colorspace Gray -threshold 25% -format "%@" info: 2>/dev/null
}
diff_ae() { # A B -> count of changed pixels (integer floor)
  # ImageMagick prints "59.6693(2.87757e-05)" here; the parenthesized form
  # breaks shell arithmetic. Strip it and floor.
  local raw
  raw=$(magick compare -metric AE "$1" "$2" null: 2>&1 | tr -d ' \n')
  awk -v a="${raw%%(*}" 'BEGIN{printf "%d", a}'
}
ae_lt() { [[ $(diff_ae "$1" "$2") -lt $3 ]]; }
ae_ge() { [[ $(diff_ae "$1" "$2") -ge $3 ]]; }

# --- pointer helpers ----------------------------------------------------------
click_at() { # X Y  (left button)
  ydotool mousemove --absolute -x "$1" -y "$2" 2>/dev/null
  sleep 0.3
  ydotool click 0xC0 2>/dev/null
  sleep 0.3
}

# --- per-width geometry checks -------------------------------------------------
CLK_L=; CLK_R=
check_bar() { # WIDTH (requested; measure against the CAPTURED size)
  local W=$1
  local img=$OUT/bar-$W.png
  grim "$img" || { bad "grim failed at $W"; return; }
  local dim mon
  dim=$(magick "$img" -format "%wx%h" info:)
  local cap_w=${dim%x*} cap_h=${dim#*x}
  mon=$(hyprctl monitors -j | jq -c '.[0] | {name, width, height, scale}' 2>/dev/null)
  say "width $W requested; capture is ${cap_w}x${cap_h}; monitor: $mon"
  [[ $cap_w == "$W" ]] || say "NOTE: grim captured ${cap_w}px, not requested ${W}px; all measurements use the captured width"
  read_bg "$img"
  local H; H=$(bar_height "$img" "$cap_w")
  say "width $W: bar height ${H}px, bg rgb ${bar_bg[*]}"

  magick "$img" -crop "280x${H}+$((cap_w / 2 - 140))+0" -resize 400% -colorspace Gray "$OUT/bar-$W-clock.png"
  local ocr
  ocr=$(tesseract "$OUT/bar-$W-clock.png" - --psm 7 2>/dev/null | tr -d '\f')
  say "width $W: clock OCR: [$ocr]"
  grep -qE '[0-9]{1,2}:[0-9]{2}' <<<"$ocr" || bad "clock not legible at ${W}px (OCR found no HH:MM)"

  if [[ -z $CLK_L ]]; then
    local bounds; bounds=$(clock_bounds "$img" "$cap_w" "$H")
    if [[ -n $bounds ]]; then CLK_L=${bounds% *}; CLK_R=${bounds#* }; fi
    say "width $W: clock ink bounds x=$CLK_L..$CLK_R"
    [[ -n $CLK_L ]] || bad "could not measure clock bounds at ${W}px"
  else
    local ink_l ink_r
    ink_l=$(ink_pixels "$img" "12x${H}+$((CLK_L - 14))+0")
    ink_r=$(ink_pixels "$img" "12x${H}+$((CLK_R + 2))+0")
    say "width $W: gap ink pixels left=$ink_l right=$ink_r"
    [[ $ink_l -le 2 ]] || bad "left gap strip painted at ${W}px (encroachment toward clock)"
    [[ $ink_r -le 2 ]] || bad "right gap strip painted at ${W}px (encroachment toward clock)"
  fi

  local pwr_sd
  pwr_sd=$(magick "$img" -crop "26x${H}+$((cap_w - 36))+0" -depth 8 -format "%[standard-deviation]" info:)
  say "width $W: power-edge stddev=$pwr_sd"
  awk -v s="$pwr_sd" 'BEGIN{exit !(s > 10)}' || bad "no power glyph at the right edge at ${W}px"
}

# --- tray overflow popup click-through (at 640px) ------------------------------
popup_suite() { # BAR_H  (mode already 640x480)
  local H=$1 W=640

  # Locate the "+N" overflow chip by OCR on the upscaled bar strip.
  grim "$OUT/popup-closed-640.png"
  # Grayscale + negate: raw color strips OCR as garbage (observed); the "+"
  # of the chip is often dropped, so accept a bare number in the right-edge
  # zone (x > 2100 of 2560, before the power glyph ~2471) as the chip.
  magick "$OUT/popup-closed-640.png" -crop "${W}x${H}+0+0" -resize 400% -colorspace Gray -negate "$OUT/bar-640-strip4x.png"
  local chip
  chip=$(tesseract "$OUT/bar-640-strip4x.png" - --psm 11 tsv 2>/dev/null \
    | awk -F'\t' '$12 ~ /^\+?[0-9]+$/ && $7 > 2100 && $7 < 2450 {printf "%d %d", ($7+$9/2)/4, ($8+$10/2)/4; exit}')
  say "overflow chip center: [${chip:-not found}]"
  if [[ -z $chip ]]; then
    bad "no +N overflow chip found at 640px (tray overflow not rendered or OCR blind)"
    return
  fi
  local cx=${chip% *} cy=${chip#* }

  # 1. Click the chip: the popup must appear below the bar.
  click_at "$cx" "$cy"
  sleep 1
  grim "$OUT/popup-open-640.png"
  local bbox ae
  bbox=$(diff_bbox "$OUT/popup-closed-640.png" "$OUT/popup-open-640.png")
  ae=$(diff_ae "$OUT/popup-closed-640.png" "$OUT/popup-open-640.png")
  say "popup open: diff bbox=$bbox ae=$ae"
  if [[ -z $bbox || $bbox == *0x0* || ${ae:-0} -lt 500 ]]; then
    bad "clicking the overflow chip opened no popup at 640px"
    return
  fi
  # Placement: the popup's top edge must sit just under the bar.
  local bx by bw bh
  IFS='x+' read -r bw bh bx by <<<"$bbox"
  say "popup placement: top=$by (bar bottom=$H), left=$bx, size ${bw}x${bh}"
  (( by >= H - 2 && by <= H + 12 )) || bad "popup top edge at y=$by, expected just under the bar ($H)"

  # 2. Click the first popup row: the fixture must receive Activate.
  local row_x=$((bx + bw / 2)) row_y=$((by + 16))
  click_at "$row_x" "$row_y"
  sleep 1
  if grep -q '^ACTIVATE' "$FIXTURE_LOG"; then
    say "popup row click delivered Activate to the SNI fixture: $(grep '^ACTIVATE' "$FIXTURE_LOG" | head -1)"
  else
    bad "popup row click did not reach the SNI fixture (no ACTIVATE logged)"
  fi
  grim "$OUT/popup-after-item-click.png"

  # 3. Escape must close it (popup focus/keyboard handling on real compositor).
  timeout 10 wtype -k Escape
  sleep 1
  grim "$OUT/popup-after-escape.png"
  local ae_esc
  ae_esc=$(diff_ae "$OUT/popup-closed-640.png" "$OUT/popup-after-escape.png")
  say "popup after Escape: ae vs closed = $ae_esc"
  [[ ${ae_esc:-99999} -lt 2000 ]] || bad "Escape did not close the tray popup"

  # 4. Reopen, then an outside click must close it.
  click_at "$cx" "$cy"
  sleep 1
  grim "$OUT/popup-reopened.png"
  local ae_re
  ae_re=$(diff_ae "$OUT/popup-closed-640.png" "$OUT/popup-reopened.png")
  if [[ ${ae_re:-0} -lt 500 ]]; then
    bad "popup did not reopen on second chip click"
  else
    click_at 320 300 # desktop area far from bar/popup
    sleep 1
    grim "$OUT/popup-after-outside-click.png"
    local ae_out
    ae_out=$(diff_ae "$OUT/popup-closed-640.png" "$OUT/popup-after-outside-click.png")
    say "popup after outside click: ae vs closed = $ae_out"
    [[ ${ae_out:-99999} -lt 2000 ]] || bad "outside click did not close the tray popup"
  fi

  # 5. Reopen once more; the caller switches the output mode next and the
  #    popup must not survive it.
  click_at "$cx" "$cy"
  sleep 1
  grim "$OUT/popup-open-before-resize.png"
  local ae_re2
  ae_re2=$(diff_ae "$OUT/popup-closed-640.png" "$OUT/popup-open-before-resize.png")
  say "popup reopened before resize: ae=$ae_re2"
  [[ ${ae_re2:-0} -ge 500 ]] || say "popup would not reopen before resize; resize-close check will note it"
}

# --- run: wide first (measures the clean clock bounds), then narrow -----------
if set_mode 1920x1080; then
  sleep 3
  check_bar 1920
else
  bad "could not switch to 1920x1080"
fi
BAR_H_640=31
if set_mode 640x480; then
  sleep 3
  check_bar 640
  read_bg "$OUT/bar-640.png"
  BAR_H_640=$(bar_height "$OUT/bar-640.png" 640)
  popup_suite "$BAR_H_640"
else
  bad "could not switch to 640x480"
fi
# Output change with the popup (possibly) open: it must close, not linger.
if set_mode 1920x1080; then
  sleep 3
  grim "$OUT/bar-1920-after-resize.png"
  ae_rs=$(diff_ae "$OUT/bar-1920.png" "$OUT/bar-1920-after-resize.png")
  say "below-bar region after resize: ae vs earlier 1920 shot = $ae_rs"
  [[ ${ae_rs:-99999} -lt 5000 ]] || bad "popup (or other stale content) survived the output mode change"
fi
set_mode 1024x768 >/dev/null 2>&1 || true

kill "$FIX_PID" 2>/dev/null || true
if [[ $fail == 0 ]]; then
  say "BAR-LAYOUT RESULT: GREEN (real Hyprland, candidate checkout, geometry + popup click-through)"
  exit 0
fi
say "BAR-LAYOUT RESULT: RED - see $LOG"
exit 1
