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
  for mode in dark light; do
    out=$MONARCH_THEME_OUT_DIR/vscode-$mode.json
    [[ -f $out ]] || { echo "not ok - $name: no vscode-$mode.json" >&2; exit 1; }
    jq -e '(.colors | length) > 50 and (.tokenColors | length) > 5 and .type == "'$mode'"' "$out" >/dev/null \
      || { echo "not ok - $name $mode: malformed VS Code theme" >&2; exit 1; }
    bad=$(jq -r '[.colors[], (.tokenColors[].settings.foreground)] | map(select(test("^#[0-9a-f]{6}([0-9a-f]{2})?$") | not)) | length' "$out")
    [[ $bad == 0 ]] || { echo "not ok - $name $mode: $bad malformed colors" >&2; exit 1; }
    ! grep -q '{{' "$out" || { echo "not ok - $name $mode: placeholder left" >&2; exit 1; }
  done
  checked=$((checked + 1))
done
[[ $checked -gt 0 ]] || { echo "not ok - no palettes found" >&2; exit 1; }
echo "ok - $checked palettes render both VS Code themes (schema-shaped, not loaded in VS Code)"

# The extension manifest points at exactly the two files the renderer writes.
manifest="$ROOT/default/monarch/vscode-extension/package.json"
jq -e '.contributes.themes | map(.path) == ["./themes/monarch-dark.json","./themes/monarch-light.json"]' "$manifest" >/dev/null \
  || { echo "not ok - manifest theme paths" >&2; exit 1; }
echo "ok - the extension manifest lists the two rendered themes"

# The installer links them and never rewrites an existing settings.json.
mkdir -p "$TMP/bin" "$HOME/.config/Code/User"
for stub in monarch-pkg-add code gtk-launch setsid; do
  printf '#!/bin/bash\nexit 0\n' >"$TMP/bin/$stub"; chmod +x "$TMP/bin/$stub"
done
printf '{ "custom": 1 }\n' >"$HOME/.config/Code/User/settings.json"
bash "$ROOT/bin/monarch-install-vscode" >/dev/null 2>&1
[[ $(<"$HOME/.config/Code/User/settings.json") == '{ "custom": 1 }' ]] || { echo "not ok - settings.json was rewritten" >&2; exit 1; }
ext=$HOME/.vscode/extensions/monarch.monarch-theme-1.0.0
[[ -L $ext/themes/monarch-dark.json && -f $ext/package.json ]] || { echo "not ok - extension not installed" >&2; exit 1; }
echo "ok - the installer links the themes and leaves an existing settings.json alone"
