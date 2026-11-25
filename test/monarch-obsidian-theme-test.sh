#!/bin/bash

# The user service runs monarch-obsidian-theme with no desktop session
# environment: no Hyprland signature, no display, a minimal PATH.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "not ok - $1" >&2; exit 1; }

service="$ROOT/default/systemd/user/monarch-obsidian-theme.service"
grep -Fq 'ExecStart=/usr/bin/monarch-obsidian-theme' "$service" || fail "service runs the script"
! grep -qi noctalia "$service" "$ROOT/bin/monarch-obsidian-theme" "$ROOT/bin/monarch-install-helix" || fail "retired Noctalia reference left"
grep -Fqx 'PathChanged=%h/.config/obsidian/obsidian.json' "$ROOT/default/systemd/user/monarch-obsidian-theme.path" || fail "path unit watches the vault list"
grep -Fq 'monarch-obsidian-theme.path' "$ROOT/install/user/first-run/enable-user-units.sh" || fail "path unit is enabled"

# Service-like environment: scrubbed variables, no Hyprland, no noctalia on PATH.
mkdir -p "$TMP/home/Documents/first/.obsidian" "$TMP/home/Downloads/second/.obsidian" "$TMP/bin" "$TMP/state/monarch"
printf 'Monarch\n' >"$TMP/state/monarch/theme"
for stub in hyprctl makoctl pkill pgrep; do
  printf '#!/bin/bash\nexit 0\n' >"$TMP/bin/$stub"
  chmod +x "$TMP/bin/$stub"
done
run() {
  env -i HOME="$TMP/home" XDG_STATE_HOME="$TMP/state" MONARCH_PATH="$ROOT" \
    MONARCH_THEME_PALETTES_DIR="$ROOT/config/monarch/palettes" \
    PATH="$ROOT/bin:$TMP/bin:/usr/bin:/bin" "$ROOT/bin/monarch-obsidian-theme"
}
run || fail "service-like run"
for v in Documents/first Downloads/second; do
  d=$TMP/home/$v/.obsidian
  [[ -L $d/snippets/monarch.css ]] && grep -q -- '--background-primary' "$d/snippets/monarch.css" || fail "$v snippet is the rendered one"
  jq -e '.enabledCssSnippets | index("monarch") != null' "$d/appearance.json" >/dev/null || fail "$v enabled"
done
before=$(jq -c . "$TMP/home/Documents/first/.obsidian/appearance.json")
run || fail "second run"
[[ $(jq -c . "$TMP/home/Documents/first/.obsidian/appearance.json") == "$before" ]] || fail "second run changed the vault"

# No vaults: nothing to do, success. An unrenderable snippet is an error.
rm -rf "$TMP/home/Documents" "$TMP/home/Downloads"
run || fail "no vaults is not an error"
mkdir -p "$TMP/home/v/.obsidian"; rm -rf "$TMP/home/.config/monarch/current"; rm -f "$TMP/state/monarch/theme"
if env -i HOME="$TMP/home" XDG_STATE_HOME="$TMP/state" MONARCH_PATH="$ROOT" MONARCH_THEME_PALETTES_DIR="$TMP/none" \
  PATH="$ROOT/bin:$TMP/bin:/usr/bin:/bin" "$ROOT/bin/monarch-obsidian-theme" 2>/dev/null; then
  fail "missing render fails"
fi
echo "Obsidian theme service checks pass (not run in Obsidian)"
