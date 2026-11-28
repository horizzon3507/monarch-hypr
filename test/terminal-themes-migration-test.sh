#!/bin/bash
# Evidence driver for install/reconcile/terminal-themes.sh.
# Scenarios: fresh / legacy-broken (migrated) / legacy-but-working (kept) /
# custom (kept) / idempotent / symlink-preserve. Run from anywhere:
#   bash terminal-themes-test.sh
set -uo pipefail

REPO="${MONARCH_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." REPO="${MONARCH_PATH:-$HOME/monarch}"REPO="${MONARCH_PATH:-$HOME/monarch}" pwd)}"
SCRIPT="$REPO/install/reconcile/terminal-themes.sh"
BASE=""

pass=0 fail=0
ok()   { pass=$((pass+1)); echo "ok - $1"; }
bad()  { fail=$((fail+1)); echo "FAIL - $1"; }

new_home() {
  BASE=$(mktemp -d)
  mkdir -p "$BASE/.local/state/monarch"
  cp -a "$REPO/config/monarch" "$BASE/.config-monarch-src" 2>/dev/null || true
  mkdir -p "$BASE/.config"
  cp -a "$REPO/config/monarch" "$BASE/.config/"
  echo Everforest >"$BASE/.local/state/monarch/theme"
  echo dark >"$BASE/.local/state/monarch/theme-mode"
  HOME=$BASE MONARCH_PATH=$REPO PATH="$REPO/bin:$PATH" bash "$REPO/bin/monarch-theme-render" >/dev/null 2>&1
}

run_migration() { HOME=$BASE bash -c 'source "$1"; terminal_themes_migrate' _ "$SCRIPT" 2>/dev/null; }

legacy_config() { git -C "$REPO" show "99e0f22:config/$1"; }

backups() { find "$BASE/.config" -name '*.monarch-backup.*' | wc -l; }

# --- A: fresh (no terminal configs at all) -----------------------------------
new_home
out=$(run_migration)
[[ -z $(find "$BASE/.config" -mindepth 1 -not -path '*/monarch*' -print -quit) ]] \
  && ok "fresh: nothing created, no-op" || bad "fresh: created files: $out"
[[ $(backups) == 0 ]] && ok "fresh: no backups" || bad "fresh: backups appeared"

# --- B: legacy defaults, legacy theme files absent (broken refs) -------------
new_home
for app in foot/foot.ini kitty/kitty.conf alacritty/alacritty.toml ghostty/config btop/btop.conf; do
  mkdir -p "$BASE/.config/${app%/*}"
  legacy_config "$app" >"$BASE/.config/$app"
done
# user.sh seeds this import independently of the theme migration
cp "$REPO/config/alacritty/monarch-text-size.toml" "$BASE/.config/alacritty/"
run_migration
grep -q 'include=~/.config/monarch/current/theme/foot.ini' "$BASE/.config/foot/foot.ini" \
  && ok "legacy: foot reference migrated" || bad "legacy: foot not migrated"
grep -q 'include ../monarch/current/theme/kitty.conf' "$BASE/.config/kitty/kitty.conf" \
  && ok "legacy: kitty reference migrated" || bad "legacy: kitty not migrated"
grep -q '"~/.config/monarch/current/theme/alacritty.toml",' "$BASE/.config/alacritty/alacritty.toml" \
  && ok "legacy: alacritty import migrated" || bad "legacy: alacritty not migrated"
grep -q 'theme = monarch-current' "$BASE/.config/ghostty/config" \
  && ok "legacy: ghostty theme migrated" || bad "legacy: ghostty not migrated"
! grep -q 'Noctalia\|noctalia' "$BASE/.config/ghostty/config" \
  && ok "legacy: ghostty noctalia comment removed" || bad "legacy: ghostty stale comment"
grep -q 'color_theme = "monarch-current"' "$BASE/.config/btop/btop.conf" \
  && ok "legacy: btop theme migrated" || bad "legacy: btop not migrated"
[[ $(backups) == 5 ]] && ok "legacy: one backup per migrated file (5)" || bad "legacy: backups=$(backups)"
[[ -L "$BASE/.config/ghostty/themes/monarch-current" && -f "$BASE/.config/ghostty/themes/monarch-current" ]] \
  && ok "legacy: ghostty theme symlink seeded and resolving" || bad "legacy: ghostty symlink"
[[ -L "$BASE/.config/btop/themes/monarch-current.theme" && -f "$BASE/.config/btop/themes/monarch-current.theme" ]] \
  && ok "legacy: btop theme symlink seeded and resolving" || bad "legacy: btop symlink"
# every reference in the migrated configs resolves to a real file
python3 - "$BASE" <<'PY' && ok "legacy: all migrated includes/imports/symlinks resolve" || bad "legacy: unresolved reference"
import os, re, sys
home = sys.argv[1]
bad = []
ini = open(home + "/.config/foot/foot.ini").read()
for m in re.finditer(r'^include=(.+)$', ini, re.M):
    if not os.path.isfile(m.group(1).strip().replace("~", home, 1)): bad.append("foot")
kc = home + "/.config/kitty/kitty.conf"
for m in re.finditer(r'^include\s+(.+)$', open(kc).read(), re.M):
    p = os.path.normpath(os.path.join(os.path.dirname(kc), m.group(1).strip()))
    if not os.path.isfile(p): bad.append("kitty")
for m in re.finditer(r'"(~[^"]+)"', open(home + "/.config/alacritty/alacritty.toml").read()):
    if not os.path.isfile(m.group(1).replace("~", home, 1)): bad.append("alacritty")
sys.exit(1 if bad else 0)
PY
# custom keybindings/content around the migrated line preserved
grep -q 'map ctrl+insert copy_to_clipboard' "$BASE/.config/kitty/kitty.conf" \
  && ok "legacy: surrounding kitty content preserved" || bad "legacy: kitty content lost"
perm=$(stat -c %a "$BASE/.config/foot/foot.ini"); [[ $perm == 644 || $perm == 664 ]] \
  && ok "legacy: file permissions preserved ($perm)" || bad "legacy: perms $perm"

# --- idempotent: second run changes nothing -----------------------------------
sum1=$(find "$BASE/.config" -type f -not -name '*.monarch-backup.*' -exec md5sum {} + | sort | md5sum)
n1=$(backups)
run_migration
sum2=$(find "$BASE/.config" -type f -not -name '*.monarch-backup.*' -exec md5sum {} + | sort | md5sum)
[[ $sum1 == "$sum2" && $(backups) == "$n1" ]] \
  && ok "idempotent: second run is a no-op" || bad "idempotent: second run changed state"

# --- C: legacy reference but user-provided theme at legacy path ---------------
new_home
mkdir -p "$BASE/.config/foot/themes" "$BASE/.config/ghostty/themes"
legacy_config foot/foot.ini >"$BASE/.config/foot/foot.ini"
legacy_config ghostty/config >"$BASE/.config/ghostty/config"
echo "user's own colors" >"$BASE/.config/foot/themes/noctalia"
echo "user's own theme" >"$BASE/.config/ghostty/themes/noctalia"
run_migration
grep -qxF 'include=~/.config/foot/themes/noctalia' "$BASE/.config/foot/foot.ini" \
  && ok "working-legacy: foot left untouched" || bad "working-legacy: foot rewritten"
grep -qxF 'theme = noctalia' "$BASE/.config/ghostty/config" \
  && ok "working-legacy: ghostty left untouched" || bad "working-legacy: ghostty rewritten"
[[ $(backups) == 0 ]] && ok "working-legacy: no backups" || bad "working-legacy: backups"

# --- D: custom configs are never touched --------------------------------------
new_home
mkdir -p "$BASE/.config/kitty" "$BASE/.config/btop" "$BASE/.config/alacritty"
sed 's|include themes/noctalia.conf|include my-custom-theme.conf|' < <(legacy_config kitty/kitty.conf) >"$BASE/.config/kitty/kitty.conf"
sed 's|color_theme = "noctalia"|color_theme = "Everforest"|' < <(legacy_config btop/btop.conf) >"$BASE/.config/btop/btop.conf"
printf 'general.import = ["~/elsewhere.toml"]\n' >"$BASE/.config/alacritty/alacritty.toml"
run_migration
grep -q 'include my-custom-theme.conf' "$BASE/.config/kitty/kitty.conf" \
  && ok "custom: kitty untouched" || bad "custom: kitty rewritten"
grep -q 'color_theme = "Everforest"' "$BASE/.config/btop/btop.conf" \
  && ok "custom: btop untouched" || bad "custom: btop rewritten"
grep -q 'elsewhere' "$BASE/.config/alacritty/alacritty.toml" \
  && ok "custom: alacritty untouched" || bad "custom: alacritty rewritten"
[[ $(backups) == 0 ]] && ok "custom: no backups" || bad "custom: backups"
# but additive symlink seeding still happens for apps that exist
[[ -L "$BASE/.config/btop/themes/monarch-current.theme" ]] \
  && ok "custom: btop symlink still seeded (additive only)" || bad "custom: btop symlink"

# --- E: existing monarch-current file is never overwritten --------------------
new_home
mkdir -p "$BASE/.config/ghostty/themes"
echo "user's own monarch-current" >"$BASE/.config/ghostty/themes/monarch-current"
run_migration
[[ -f "$BASE/.config/ghostty/themes/monarch-current" && ! -L "$BASE/.config/ghostty/themes/monarch-current" ]] \
  && ok "seed: existing real file preserved" || bad "seed: real file clobbered"

echo
echo "RESULT: $pass passed, $fail failed"
exit $((fail > 0))
