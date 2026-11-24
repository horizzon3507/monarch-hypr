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
export PATH="$ROOT/bin:$TMP/bin:$PATH"
mkdir -p "$HOME" "$TMP/bin"
for stub in hyprctl makoctl pkill pgrep; do
  printf '#!/bin/bash\nexit 1\n' >"$TMP/bin/$stub"
  chmod +x "$TMP/bin/$stub"
done

mkdir -p "$XDG_STATE_HOME/monarch"
checked=0
for palette in "$MONARCH_THEME_PALETTES_DIR"/*.json; do
  name=${palette##*/}
  name=${name%.json}
  printf '%s\n' "$name" >"$XDG_STATE_HOME/monarch/theme"
  export MONARCH_THEME_OUT_DIR="$TMP/out-${name// /_}"
  monarch-theme-render >/dev/null 2>&1 || { echo "not ok - $name does not render" >&2; exit 1; }
  out=$MONARCH_THEME_OUT_DIR/zed.json
  [[ -f $out ]] || { echo "not ok - $name: no zed.json" >&2; exit 1; }
  jq -e . "$out" >/dev/null || { echo "not ok - $name: invalid JSON" >&2; exit 1; }
  [[ $(jq -r '.themes | map(.name) | sort | join(",")' "$out") == "Monarch Dark,Monarch Light" ]] \
    || { echo "not ok - $name: expected the two Monarch themes" >&2; exit 1; }
  bad=$(jq -r '[.. | strings | select(startswith("#"))] | map(select(test("^#[0-9a-f]{6}([0-9a-f]{2})?$") | not)) | length' "$out")
  [[ $bad == 0 ]] || { echo "not ok - $name: $bad malformed colors" >&2; exit 1; }
  ! grep -q '{{' "$out" || { echo "not ok - $name: placeholder left" >&2; exit 1; }
  checked=$((checked + 1))
done
[[ $checked -gt 0 ]] || { echo "not ok - no palettes found" >&2; exit 1; }
echo "ok - $checked palettes render a schema-shaped Zed theme (not loaded in Zed)"

# A template whose placeholders cannot be filled is skipped, not written half done.
mkdir -p "$TMP/tpl"
cp "$ROOT/default/monarch/theme-templates/foot.ini" "$TMP/tpl/"
printf '{"x":"{{no.such.role}}"}\n' >"$TMP/tpl/broken.json"
printf 'Monarch\n' >"$XDG_STATE_HOME/monarch/theme"
export MONARCH_THEME_OUT_DIR="$TMP/out-skip"
err=$(MONARCH_THEME_TEMPLATES_DIR="$TMP/tpl" monarch-theme-render 2>&1 >/dev/null) || { echo "not ok - a skipped template must not fail the render" >&2; exit 1; }
[[ -f $MONARCH_THEME_OUT_DIR/foot.ini && ! -e $MONARCH_THEME_OUT_DIR/broken.json ]] \
  || { echo "not ok - broken template was written or good one lost" >&2; exit 1; }
[[ $err == *broken.json* ]] || { echo "not ok - no warning for the skipped template" >&2; exit 1; }
echo "ok - an unfillable template is skipped with a warning"
