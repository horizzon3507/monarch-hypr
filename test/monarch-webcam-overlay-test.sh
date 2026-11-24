#!/bin/bash

set -euo pipefail
umask 077

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'status=$?; rm -rf "$TMP"; exit $status' EXIT

mkdir -p "$TMP/bin" "$TMP/runtime"
export MOCK_NIRI_STATE="$TMP/niri-state"
export MOCK_NIRI_LOG="$TMP/niri.log"

printf '100\n' >"$MOCK_NIRI_STATE.width"
printf '100\n' >"$MOCK_NIRI_STATE.height"
printf '0\n' >"$MOCK_NIRI_STATE.x"
printf '0\n' >"$MOCK_NIRI_STATE.y"

cat >"$TMP/bin/hyprctl" <<'EOF'
#!/bin/bash

if [[ $* == "clients -j" ]]; then
  width=$(<"$MOCK_NIRI_STATE.width")
  height=$(<"$MOCK_NIRI_STATE.height")
  x=$(<"$MOCK_NIRI_STATE.x")
  y=$(<"$MOCK_NIRI_STATE.y")
  app_id=$(jq -r '.app_id' "${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/monarch}/monarch-screenrecord-webcam-$UID.json")
  jq -cn --arg app_id "$app_id" --argjson width "$width" --argjson height "$height" --argjson x "$x" --argjson y "$y" \
    '[{address: "0x2a", pid: 123, class: $app_id, size: [$width, $height], at: [$x, $y]}]'
elif [[ $* == "monitors -j" ]]; then
  jq -cn '[{name: "DP-1", x: 0, y: 0, width: 1920, height: 1080, scale: 1.0, transform: 0, focused: true, activeWorkspace: {id: 1}}]'
elif [[ $1 == "dispatch" ]]; then
  expr=$2
  [[ $expr =~ x\ =\ (-?[0-9]+),\ y\ =\ (-?[0-9]+),\ relative\ =\ false,\ window\ =\ \"address:0x2a\" ]] || exit 1
  a=${BASH_REMATCH[1]} b=${BASH_REMATCH[2]}
  case $expr in
  hl.dsp.window.resize\(*)
    printf 'resize %s %s\n' "$a" "$b" >>"$MOCK_NIRI_LOG"
    printf '%s\n' "$a" >"$MOCK_NIRI_STATE.width"
    printf '%s\n' "$b" >"$MOCK_NIRI_STATE.height"
    ;;
  hl.dsp.window.move\(*)
    printf 'move %s %s\n' "$a" "$b" >>"$MOCK_NIRI_LOG"
    printf '%s\n' "$a" >"$MOCK_NIRI_STATE.x"
    printf '%s\n' "$b" >"$MOCK_NIRI_STATE.y"
    ;;
  *) exit 1 ;;
  esac
fi
EOF
chmod +x "$TMP/bin/hyprctl"
PATH="$TMP/bin:$PATH"
cat >"$TMP/bin/monarch-hypr-geometry" <<EOF
#!/bin/bash
exec "$ROOT/bin/monarch-hypr-geometry" "\$@"
EOF
chmod +x "$TMP/bin/monarch-hypr-geometry"

cat >"$TMP/bin/v4l2-ctl" <<'EOF'
#!/bin/bash
printf 'Q17 Camera\n\t/dev/video42\n'
EOF

cat >"$TMP/bin/monarch-capture-screenrecording" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >"$MOCK_SCREENRECORD_LOG"
EOF

chmod +x "$TMP/bin/v4l2-ctl" "$TMP/bin/monarch-capture-screenrecording"

run_resize() {
  PATH="$TMP/bin:/usr/bin" XDG_RUNTIME_DIR="$TMP/runtime" \
    "$ROOT/bin/monarch-capture-webcam-resize" "$1"
}

jq -cn '{target: "monitor:DP-1", shape: "circle", app_id: "org.monarch.webcam-overlay.circle", pid: 123}' >"$TMP/runtime/monarch-screenrecord-webcam-$UID.json"
run_resize medium
W=270
H=270
grep -Fqx "resize $W $H" "$MOCK_NIRI_LOG"
grep -Fqx "move 1610 770" "$MOCK_NIRI_LOG"

: >"$MOCK_NIRI_LOG"
jq -cn '{target: "region:800x600+200+100", shape: "circle", app_id: "org.monarch.webcam-overlay.circle", pid: 123}' >"$TMP/runtime/monarch-screenrecord-webcam-$UID.json"
run_resize reset
W=150
H=150
grep -Fqx "resize $W $H" "$MOCK_NIRI_LOG"
grep -Fqx "move 810 510" "$MOCK_NIRI_LOG"

: >"$MOCK_NIRI_LOG"
jq -cn '{target: "region:800x600+200+100", shape: "rectangle", app_id: "org.monarch.webcam-overlay.rectangle", pid: 123}' >"$TMP/runtime/monarch-screenrecord-webcam-$UID.json"
run_resize large
W=180
H=203
grep -Fqx "resize $W $H" "$MOCK_NIRI_LOG"
grep -Fqx "move 780 457" "$MOCK_NIRI_LOG"

: >"$MOCK_NIRI_LOG"
mkdir -p "$TMP/state/monarch"
jq -cn '{target: "region:800x600+200+100", shape: "circle", app_id: "org.monarch.webcam-overlay.circle", pid: 123}' >"$TMP/state/monarch/monarch-screenrecord-webcam-$UID.json"
env -u XDG_RUNTIME_DIR HOME="$TMP" XDG_STATE_HOME="$TMP/state" PATH="$TMP/bin:/usr/bin" \
  "$ROOT/bin/monarch-capture-webcam-resize" reset
W=150
H=150
grep -Fqx "resize $W $H" "$MOCK_NIRI_LOG"
grep -Fqx "move 810 510" "$MOCK_NIRI_LOG"

env -u XDG_RUNTIME_DIR HOME="$TMP" XDG_STATE_HOME="$TMP/unused-state" PATH="$TMP/bin:/usr/bin" \
  "$ROOT/bin/monarch-capture-webcam-resize" medium
[[ ! -e $TMP/unused-state ]]

if run_resize huge >/dev/null 2>&1; then
  echo "Invalid webcam size was accepted" >&2
  exit 1
fi

for args in '--webcam-size=huge' '--webcam-shape=triangle'; do
  if XDG_RUNTIME_DIR="$TMP/runtime" MONARCH_SCREENRECORD_DIR="$TMP" HOME="$TMP" "$ROOT/bin/monarch-capture-screenrecording" "$args" >/dev/null 2>&1; then
    echo "Invalid screen recording webcam option was accepted: $args" >&2
    exit 1
  fi
done

export MOCK_SCREENRECORD_LOG="$TMP/screenrecord.log"
PATH="$TMP/bin:/usr/bin" "$ROOT/bin/monarch-capture-screenrecording-with-webcam" --webcam-shape=rectangle
grep -Fqx -- '--with-desktop-audio --with-microphone-audio --with-webcam --webcam-shape=rectangle --webcam-device=/dev/video42' "$MOCK_SCREENRECORD_LOG"
if PATH="$TMP/bin:/usr/bin" "$ROOT/bin/monarch-capture-screenrecording-with-webcam" --webcam-shape=triangle >/dev/null 2>&1; then
  echo "Invalid wrapper webcam shape was accepted" >&2
  exit 1
fi

grep -Fq -- '--wayland-app-id="$app_id"' "$ROOT/bin/monarch-capture-screenrecording"

echo "Webcam overlay sizing, placement, identity and shape checks pass"
