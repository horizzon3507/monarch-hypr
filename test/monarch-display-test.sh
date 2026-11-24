#!/bin/bash

# Exercises the display commands against a stub hyprctl: the output list, the
# scale and on-off writes, the guard that refuses to blank the last screen, the
# runtime override file. None of it needs a compositor
# or a second monitor.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
LIST="$ROOT/bin/monarch-display-list"
SCALE="$ROOT/bin/monarch-display-scale"
TOGGLE="$ROOT/bin/monarch-display-toggle"

RUNTIME="$ROOT/bin/monarch-hypr-runtime"
SET="$ROOT/bin/monarch-hypr-output-set"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home/.config/hypr" "$TMP/cfg"

pass() { printf 'ok - %s\n' "$1"; }

fail() {
  printf 'not ok - %s\n' "$1" >&2
  shift
  (($# == 0)) || printf '%b\n' "$@" >&2
  exit 1
}

assert_equals() {
  local description="$1" actual="$2" expected="$3"
  [[ $actual == "$expected" ]] || fail "$description" "Expected: $expected" "Actual:   $actual"
  pass "$description"
}

# One eDP on at 1.25 and one DP off, which is the shape both the guard and the
# list have to read correctly.
cat >"$TMP/outputs.json" <<'JSON'
[
  {"name": "eDP-1", "make": "Lenovo", "model": "0x41A6", "disabled": false, "focused": true,
   "width": 1920, "height": 1200, "refreshRate": 60.026, "x": 0, "y": 0, "scale": 1.25},
  {"name": "DP-1", "make": "Dell", "model": "U2720Q", "disabled": true, "focused": false,
   "width": 3840, "height": 2160, "refreshRate": 60.0, "x": 1536, "y": 0, "scale": 1.0}
]
JSON

cat >"$TMP/bin/hyprctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$HYPR_CALLS"
case "$*" in
  "monitors all -j" | "monitors -j")
    cat "$OUTPUTS_JSON"
    exit 0
    ;;
  "devices -j")
    echo '{"mice": [], "touch": []}'
    exit 0
    ;;
  "keyword monitor"*)
    [[ ${HYPR_STATUS:-0} == 0 ]] || echo "error: refused"
    exit 0
    ;;
esac
exit 0
STUB

cat >"$TMP/bin/monarch-hw-hypr-instance" <<'STUB'
#!/bin/bash
[[ -n ${HYPR_ABSENT:-} ]] && exit 1
echo stub_signature
STUB

cat >"$TMP/bin/gsettings" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$GS_CALLS"
[[ $1 == get ]] && echo 1.0
exit 0
STUB

cat >"$TMP/bin/monarch-cmd-present" <<'STUB'
#!/bin/bash
command -v "$1" >/dev/null
STUB

# The runtime writer reloads Hyprland when one is running; pretend one is, so
# the test sees the hyprctl reload call without depending on the host.
cat >"$TMP/bin/pgrep" <<'STUB'
#!/bin/bash
exit 0
STUB

chmod +x "$TMP"/bin/*
export PATH="$TMP/bin:$ROOT/bin:$PATH"
export OUTPUTS_JSON="$TMP/outputs.json" HYPR_CALLS="$TMP/hypr" GS_CALLS="$TMP/gs"
export HOME="$TMP/home"
# Set here and not further down: these commands resolve their files under
# XDG_CONFIG_HOME when it is set, and a shell that exports it would otherwise
# point them at the author's own Hyprland config.
export XDG_CONFIG_HOME="$TMP/home/.config"
CONF="$XDG_CONFIG_HOME/hypr/runtime.lua"
: >"$HYPR_CALLS"
: >"$GS_CALLS"

# ── The list ─────────────────────────────────────────────────────────────────

listing=$("$LIST")
assert_equals "reports the lit output with its mode and scale" \
  "$(awk -F'\t' '$1 == "eDP-1" { print $2, $3, $4 }' <<<"$listing")" "on 1.25 1920x1200@60"
assert_equals "and names it" \
  "$(awk -F'\t' '$1 == "eDP-1" { print $6 }' <<<"$listing")" "Lenovo 0x41A6"

assert_equals "marks the focused output" \
  "$(awk -F'\t' '$5 == "focused" { print $1 }' <<<"$listing")" "eDP-1"
assert_equals "and only that one" \
  "$(awk -F'\t' '$5 == "focused"' <<<"$listing" | grep -c .)" "1"

# A disabled output keeps its row: it is the only way to name it to turn it on.
assert_equals "a disabled output is listed as off" \
  "$(awk -F'\t' '$1 == "DP-1" { print $2 }' <<<"$listing")" "off"
assert_equals "with no mode" \
  "$(awk -F'\t' '$1 == "DP-1" { print "[" $4 "]" }' <<<"$listing")" "[]"

# A sibling called by name must resolve without Monarch's bin on PATH.
# Asserted by reading the source: exercising the fallback would mean planting a
# stub in the repository's own bin/.
for command in "$LIST" "$SCALE" "$TOGGLE"; do
  grep -qF 'PATH="$PATH:$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)"' "$command" ||
    fail "each display command can find its siblings without Monarch's bin on PATH" \
      "Missing from: $command"
done
pass "each display command can find its siblings without Monarch's bin on PATH"

HYPR_ABSENT=1 "$LIST" 2>"$TMP/err" && fail "no compositor is an error, not an empty list"
assert_equals "and says so" "$(<"$TMP/err")" "Error: Hyprland is not running."

# ── The scale ────────────────────────────────────────────────────────────────

: >"$HYPR_CALLS"
"$SCALE" eDP-1 1.5
assert_equals "a scale change reloads Hyprland" \
  "$(grep -c '^reload' "$HYPR_CALLS")" "1"
assert_equals "and persisted where a reload will find it" \
  "$(grep -c '^-- monarch-scale eDP-1 1.5$' "$CONF")" "1"
assert_equals "with the layout it had" \
  "$(grep '^hl.monitor' "$CONF")" 'hl.monitor({ output = "eDP-1", mode = "1920x1200@60.026", position = "0x0", scale = 1.5 })'

for bad in 0.2 5 abc; do
  "$SCALE" eDP-1 "$bad" 2>/dev/null && fail "an out-of-range scale is refused: $bad"
done
pass "an out-of-range or non-numeric scale is refused"

"$SCALE" NOPE 1.5 2>"$TMP/err" && fail "an unknown output is refused"
assert_equals "and names it" "$(<"$TMP/err")" "Error: no display named NOPE."

"$SCALE" --help 1.5 >"$TMP/out" 2>"$TMP/err" &&
  fail "an option-like unknown output is refused"
assert_equals "an option-like output is matched literally" \
  "$(<"$TMP/err")" "Error: no display named --help."

# ── The on-off ───────────────────────────────────────────────────────────────

: >"$HYPR_CALLS"
"$TOGGLE" DP-1 on
assert_equals "turning a dark output on reloads Hyprland" \
  "$(grep -c '^reload' "$HYPR_CALLS")" "1"

: >"$HYPR_CALLS"
"$TOGGLE" eDP-1 on
assert_equals "asking for the state it is already in does nothing" \
  "$(grep -c '^reload' "$HYPR_CALLS" || true)" "0"

# Turning one off needs a second lit screen, or the guard below fires first.
sed 's/"disabled": true/"disabled": false/' "$TMP/outputs.json" >"$TMP/outputs-both.json"

: >"$HYPR_CALLS"
OUTPUTS_JSON="$TMP/outputs-both.json" "$TOGGLE" eDP-1 off
assert_equals "turning a lit one off reloads Hyprland" \
  "$(grep -c '^reload' "$HYPR_CALLS")" "1"
assert_equals "and is persisted" \
  "$(grep -c '^hl.monitor({ output = \"eDP-1\", disabled = true })$' "$CONF")" "1"

# The last screen standing is refused: there would be nothing on screen to turn
# it back on with.
cat >"$TMP/outputs-single.json" <<'JSON'
[ {"name": "eDP-1", "make": "Lenovo", "model": "0x41A6", "disabled": false, "focused": true,
   "width": 1920, "height": 1200, "refreshRate": 60.0, "x": 0, "y": 0, "scale": 1.0} ]
JSON
OUTPUTS_JSON="$TMP/outputs-single.json" "$TOGGLE" eDP-1 off 2>"$TMP/err" &&
  fail "blanking the only screen is refused"
pass "blanking the only screen is refused"
assert_equals "and says why" "$(<"$TMP/err")" "Error: eDP-1 is the only display that is on."

# ── The runtime file ─────────────────────────────────────────────────────────

# Two properties for one output: turning it off must not lose its scale.
rm -f "$CONF"
"$RUNTIME" output-scale DP-1 2
"$RUNTIME" output DP-1 off >/dev/null
assert_equals "a disabled output keeps its scale" \
  "$(grep -c '^-- monarch-scale DP-1 2$' "$CONF")" "1"
assert_equals "and is disabled" "$(grep -c '^hl.monitor({ output = "DP-1", disabled = true })$' "$CONF")" "1"
"$RUNTIME" output DP-1 on >/dev/null
assert_equals "it gets its scale back when it is turned on" \
  "$(grep '^hl.monitor' "$CONF")" 'hl.monitor({ output = "DP-1", mode = "3840x2160@60", position = "1536x0", scale = 2 })'
assert_equals "with the off gone" "$(grep -c 'monarch-off' "$CONF" || true)" "0"

# A second output written later must not drop the first.
"$RUNTIME" output-scale eDP-1 1 >/dev/null
assert_equals "another output keeps the first one's scale" \
  "$(grep -c '^-- monarch-scale DP-1 2$' "$CONF")" "1"

# Bad input is refused without touching the file.
before=$(<"$CONF")
"$RUNTIME" output-scale DP-1 abc 2>/dev/null && fail "a non-numeric scale is refused by the runtime writer"
assert_equals "and leaves the file alone" "$(<"$CONF")" "$before"

# Input devices come back as `hl.device` calls naming what the compositor reports.
cat >"$TMP/bin/hyprctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$HYPR_CALLS"
case "$*" in
  "devices -j") echo '{"mice": [{"name": "elan-touchpad"}, {"name": "usb-mouse"}], "touch": []}' ;;
  "monitors all -j") cat "$OUTPUTS_JSON" ;;
esac
STUB
rm -f "$CONF"
assert_equals "turning the touchpad off reports it" "$("$RUNTIME" input touchpad off)" "disabled"
assert_equals "and disables only the touchpad" \
  "$(sed -n 's/^hl.device({ name = "\(.*\)", enabled = false })$/\1/p' "$CONF")" "elan-touchpad"
assert_equals "turning it on again reports it" "$("$RUNTIME" input touchpad on)" "enabled"
assert_equals "and removes the override" "$(grep -c '^device' "$CONF" || true)" "0"

# ── The shared entry point ───────────────────────────────────────────────────

rm -f "$CONF"
"$SET" eDP-1 scale 2
assert_equals "output-set forwards a scale to the runtime file" \
  "$(grep -c '^-- monarch-scale eDP-1 2$' "$CONF")" "1"
"$SET" DP-1 power off >/dev/null
assert_equals "and a power change" "$(grep -c '^hl.monitor({ output = "DP-1", disabled = true })$' "$CONF")" "1"
"$SET" DP-1 color red 2>/dev/null && fail "an unknown property is refused"
pass "an unknown property is refused"
rm -f "$CONF"
