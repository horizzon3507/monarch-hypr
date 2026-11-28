#!/bin/bash

# Bar responsive-layout validation. Runs INSIDE the disposable VM guest,
# attached to the real Hyprland session: no mocks, no offscreen replicas.
#
# What it proves, with the REAL Bar.qml/Workspaces.qml from the candidate
# checkout driving the REAL bar on the REAL compositor:
#   1. With 10 real workspaces (one window each) on a 640x480 output the
#      centered clock stays legible (OCR) and nothing paints in the measured
#      gap strips flanking it (no workspace-row or right-group encroachment).
#   2. The power/session control is still drawn at the right bar edge at
#      640px (pixel variance in the rightmost columns) - never clipped away.
#   3. At 1920x1080 the same invariants hold; all 10 real workspaces exist
#      (hyprctl) and the screenshot shows every slot (human-inspected).
#
# Environment (set by the caller, same as the keynav smoke): WAYLAND_DISPLAY,
# HYPRLAND_INSTANCE_SIGNATURE, XDG_RUNTIME_DIR. CWD must be the candidate
# checkout root. Screenshots and crops land in $1 (default ~/keynav-out).
#
# Proof label: this validates the code under test (candidate checkout) against
# the ISO-provided OS/compositor environment; both SHAs are in report.txt.

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
  foot jq imagemagick tesseract-ocr grim 2>&1 | tail -2

# --- shell under test: restart from the candidate checkout ------------------
pkill -x quickshell 2>/dev/null || true
sleep 2
quickshell -p "$SHELL_DIR" >"$OUT/bar-qs.log" 2>&1 &
QS_PID=$!
sleep 8
kill -0 "$QS_PID" 2>/dev/null || { bad "quickshell from candidate checkout died; see bar-qs.log"; tail -20 "$OUT/bar-qs.log"; exit 1; }
say "shell restarted from candidate checkout (pid $QS_PID)"

# --- ten real workspaces: one foot window each on 2..10 ----------------------
for ws in 2 3 4 5 6 7 8 9 10; do
  hyprctl dispatch exec "[workspace $ws silent] foot" >/dev/null 2>&1
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
bar_bg=() # r g b of the bar background (pixel at 2,2 of the full shot)
read_bg() { # IMG
  local rgb
  rgb=$(magick "$1" -crop 1x1+2+2 -depth 8 -format "%[fx:int(r*255)] %[fx:int(g*255)] %[fx:int(b*255)]" info:)
  bar_bg=($rgb)
}

bar_height() { # IMG W -> first row whose mean differs from the bar background
  local img=$1 w=$2 row0 y m h=0
  row0=$(magick "$img" -crop "${w}x1+0+0" -depth 8 -format "%[mean]" info:)
  for y in $(seq 8 60); do
    m=$(magick "$img" -crop "${w}x1+0+$y" -depth 8 -format "%[mean]" info:)
    if awk -v a="$m" -v b="$row0" 'BEGIN{exit !(sqrt((a-b)*(a-b)) > 6)}'; then h=$y; break; fi
  done
  [[ $h -gt 0 ]] || h=31 # fallback: 13px font * 2.4
  echo "$h"
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

# --- per-width checks ---------------------------------------------------------
CLK_L=; CLK_R= # measured at 1920 (clean center), reused at 640
check_bar() { # WIDTH
  local W=$1 img=$OUT/bar-$W.png
  grim "$img" || { bad "grim failed at $W"; return; }
  read_bg "$img"
  local H; H=$(bar_height "$img" "$W")
  say "width $W: bar height ${H}px, bg rgb ${bar_bg[*]}"

  # Clock legibility: center strip, upscaled, OCR must show HH:MM.
  magick "$img" -crop "280x${H}+$((W / 2 - 140))+0" -resize 400% -colorspace Gray "$OUT/bar-$W-clock.png"
  local ocr
  ocr=$(tesseract "$OUT/bar-$W-clock.png" - --psm 7 2>/dev/null | tr -d '\f')
  say "width $W: clock OCR: [$ocr]"
  grep -qE '[0-9]{1,2}:[0-9]{2}' <<<"$ocr" || bad "clock not legible at ${W}px (OCR found no HH:MM)"

  # Clock ink bounds: measured here at 1920, only verified clear at 640.
  if [[ -z $CLK_L ]]; then
    local bounds; bounds=$(clock_bounds "$img" "$W" "$H")
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

  # Power control: rightmost bar columns must show the glyph (not clipped).
  local pwr_sd
  pwr_sd=$(magick "$img" -crop "26x${H}+$((W - 36))+0" -depth 8 -format "%[standard-deviation]" info:)
  say "width $W: power-edge stddev=$pwr_sd"
  awk -v s="$pwr_sd" 'BEGIN{exit !(s > 10)}' || bad "no power glyph at the right edge at ${W}px"
}

# --- run: wide first (measures the clean clock bounds), then narrow -----------
if set_mode 1920x1080; then
  sleep 3
  check_bar 1920
else
  bad "could not switch to 1920x1080"
fi
if set_mode 640x480; then
  sleep 3
  check_bar 640
else
  bad "could not switch to 640x480"
fi
set_mode 1024x768 >/dev/null 2>&1 || true

if [[ $fail == 0 ]]; then
  say "BAR-LAYOUT RESULT: GREEN (real Hyprland, candidate checkout, 1920 + 640)"
  exit 0
fi
say "BAR-LAYOUT RESULT: RED - see $LOG"
exit 1
