#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export XDG_STATE_HOME="$TMP/state"
export MONARCH_PATH="$ROOT"
export MONARCH_THEME_PALETTES_DIR="$ROOT/config/monarch/palettes"
export MONARCH_THEME_OUT_DIR="$HOME/.config/monarch/current/theme"
export PATH="$ROOT/bin:$TMP/bin:$PATH"
export HYPRLAND_INSTANCE_SIGNATURE=test
mkdir -p "$HOME" "$TMP/bin" "$XDG_STATE_HOME/monarch"
for stub in hyprctl makoctl pkill pgrep monarch-pkg-add; do
  printf '#!/bin/bash\nexit 0\n' >"$TMP/bin/$stub"
  chmod +x "$TMP/bin/$stub"
done
printf 'Monarch\n' >"$XDG_STATE_HOME/monarch/theme"

fail() { echo "not ok - $1" >&2; exit 1; }

# Helix: the Monarch theme is linked and config seeded, only when none exists.
bash "$ROOT/bin/monarch-install-helix" >/dev/null 2>&1
[[ -L $HOME/.config/helix/themes/monarch.toml ]] || fail "helix theme link"
grep -q '^"ui.background"' "$HOME/.config/helix/themes/monarch.toml" || fail "linked helix theme is the rendered file"
! grep -q '{{' "$HOME/.config/helix/themes/monarch.toml" || fail "helix placeholder left"
[[ $(<"$HOME/.config/helix/config.toml") == 'theme = "monarch"' ]] || fail "helix config seeded"
echo 'theme = "mine"' >"$HOME/.config/helix/config.toml"
out=$(bash "$ROOT/bin/monarch-install-helix" 2>&1)
[[ $(<"$HOME/.config/helix/config.toml") == 'theme = "mine"' ]] || fail "existing helix config rewritten"
[[ $out == *'theme = "monarch"'* ]] || fail "no note for an existing helix config"
echo "ok - Helix links the rendered Monarch theme and leaves an existing config alone"

# Obsidian: snippet linked and enabled in each vault, other snippets kept.
mkdir -p "$HOME/Documents/a/.obsidian" "$HOME/Documents/b/.obsidian"
printf '{"enabledCssSnippets":["other"],"baseFontSize":16}\n' >"$HOME/Documents/b/.obsidian/appearance.json"
monarch-obsidian-theme || fail "obsidian run"
for v in a b; do
  d=$HOME/Documents/$v/.obsidian
  [[ -L $d/snippets/monarch.css ]] && grep -q -- '--background-primary' "$d/snippets/monarch.css" || fail "vault $v snippet"
  jq -e '.enabledCssSnippets | index("monarch") != null' "$d/appearance.json" >/dev/null || fail "vault $v enabled"
done
jq -e '(.enabledCssSnippets | index("other") != null) and .baseFontSize == 16' "$HOME/Documents/b/.obsidian/appearance.json" >/dev/null || fail "existing vault settings kept"
before=$(jq -c . "$HOME/Documents/b/.obsidian/appearance.json")
monarch-obsidian-theme
[[ $(jq -c . "$HOME/Documents/b/.obsidian/appearance.json") == "$before" ]] || fail "second run changed the vault"
echo "ok - Obsidian vaults get the rendered Monarch snippet without Noctalia (not run in Obsidian)"
