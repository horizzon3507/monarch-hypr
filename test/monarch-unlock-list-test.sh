#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export MONARCH_PATH="$TMP/root"
export MONARCH_THEME_PALETTES_DIR="$TMP/palettes"
mkdir -p "$HOME" "$MONARCH_PATH/default/plymouth" "$MONARCH_PATH/themes/tokyo-night" \
  "$MONARCH_PATH/themes/orphan" "$MONARCH_THEME_PALETTES_DIR"

touch "$MONARCH_PATH/default/plymouth/logo.png" "$MONARCH_PATH/default/plymouth/preview-unlock.png"
touch "$MONARCH_PATH/themes/tokyo-night/preview-unlock.png" "$MONARCH_PATH/themes/orphan/preview-unlock.png"
printf '{}\n' >"$MONARCH_THEME_PALETTES_DIR/Tokyo Night.json"

out=$("$ROOT/bin/monarch-unlock-list")

# The built-in default is always listed first field selected=false with no state
# file, and a theme only appears when a palette gives it a display name.
grep -Fqx "false	Monarch Default	default	$MONARCH_PATH/default/plymouth/preview-unlock.png" <<<"$out"
grep -Fqx "false	Tokyo Night	tokyo-night	$MONARCH_PATH/themes/tokyo-night/preview-unlock.png" <<<"$out"
! grep -qF "orphan" <<<"$out"

# The state file marks the current theme.
mkdir -p "$HOME/.local/state/monarch"
printf 'Tokyo Night\n' >"$HOME/.local/state/monarch/unlock-theme"
out=$("$ROOT/bin/monarch-unlock-list")
grep -Fqx "true	Tokyo Night	tokyo-night	$MONARCH_PATH/themes/tokyo-night/preview-unlock.png" <<<"$out"

echo "Unlock theme listing checks pass"
