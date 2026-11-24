#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_equals() {
  if [[ $2 != "$3" ]]; then
    printf 'not ok - %s\nExpected: %s\nActual:   %s\n' "$1" "$3" "$2" >&2
    exit 1
  fi
  echo "ok - $1"
}

export HOME="$TMP/home"
export XDG_STATE_HOME="$TMP/state"
export MONARCH_PATH="$ROOT"
export MONARCH_THEME_PALETTES_DIR="$ROOT/config/monarch/palettes"
export MONARCH_THEME_OUT_DIR="$TMP/out"
export PATH="$ROOT/bin:$TMP/bin:$PATH"
mkdir -p "$HOME" "$TMP/bin"
# Running components are reloaded through these; the test records nothing from them.
for stub in hyprctl makoctl pkill pgrep; do
  printf '#!/bin/bash\nexit 1\n' >"$TMP/bin/$stub"
  chmod +x "$TMP/bin/$stub"
done

assert_equals "the default theme is Monarch" "$(monarch-theme-current)" "custom Monarch"
assert_equals "the default mode is dark" "$(monarch-theme-mode get)" "dark"

monarch-theme-render
for file in "$ROOT"/default/monarch/theme-templates/*; do
  [[ -s $MONARCH_THEME_OUT_DIR/${file##*/} ]] || { echo "not ok - ${file##*/} was not rendered" >&2; exit 1; }
done
echo "ok - every template is rendered"
if grep -rq '{{' "$MONARCH_THEME_OUT_DIR"; then
  echo "not ok - an unfilled placeholder is left" >&2
  grep -rn '{{' "$MONARCH_THEME_OUT_DIR" >&2
  exit 1
fi
echo "ok - no placeholder is left"

# The Quickshell colors are valid JSON of 6-digit colors for every key the shell reads.
colors="$MONARCH_THEME_OUT_DIR/quickshell.json"
assert_equals "quickshell colors are 7 six-digit values" \
  "$(jq '[.[] | select(test("^#[0-9a-f]{6}$"))] | length' "$colors")" "7"
assert_equals "and carry the keys the shell reads" \
  "$(jq -r 'keys | join(",")' "$colors")" "accent,bg,error,fg,outline,secondary,surfaceVariant"

# Every shipped palette renders in both modes.
for palette in "$ROOT"/config/monarch/palettes/*.json; do
  name=${palette##*/}; name=${name%.json}
  mkdir -p "$XDG_STATE_HOME/monarch"
  printf '%s\n' "$name" >"$XDG_STATE_HOME/monarch/theme"
  for mode in dark light; do
    printf '%s\n' "$mode" >"$XDG_STATE_HOME/monarch/theme-mode"
    monarch-theme-render || { echo "not ok - $name $mode does not render" >&2; exit 1; }
    jq -e '[.[] | select(test("^#[0-9a-f]{6}$"))] | length == 7' "$colors" >/dev/null \
      || { echo "not ok - $name $mode quickshell colors invalid" >&2; exit 1; }
  done
done
echo "ok - every palette renders in both modes"

printf 'No Such Theme\n' >"$XDG_STATE_HOME/monarch/theme"
if monarch-theme-render 2>/dev/null; then
  echo "not ok - an unknown theme is refused" >&2
  exit 1
fi
echo "ok - an unknown theme is refused"
