#!/bin/bash
# First login: monarch-theme-apply runs before the shell starts. It must still
# record the default wallpaper link (the shell reads it at start), and a later
# run must not replace what the user picked. Stub tests: no real shell.
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" XDG_STATE_HOME="$tmp/home/.local/state"
export MONARCH_PATH="$tmp/root" MONARCH_ROOT="$tmp/root"
mkdir -p "$HOME" "$MONARCH_PATH/themes/monarch" "$tmp/bin"
: >"$MONARCH_PATH/themes/monarch/1-first.png"
: >"$MONARCH_PATH/themes/monarch/2-second.png"
printf '#!/bin/bash\nexit 1\n' >"$tmp/bin/pgrep"   # the shell is not running yet
printf '#!/bin/bash\nexit 0\n' >"$tmp/bin/hyprctl"
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$ROOT/bin:/usr/bin:/bin"
link="$XDG_CONFIG_HOME/monarch/current/background"

monarch-theme-apply >/dev/null 2>&1 || true
[[ -L $link ]] || fail "first run records the wallpaper link before the shell exists"
[[ $(readlink -f "$link") == "$MONARCH_PATH/themes/monarch/1-first.png" ]] || fail "the link points at the scheme's first wallpaper"
[[ -f $HOME/.local/state/monarch/wallpaper-applied ]] || fail "the first application is stamped"

# The user picks another shipped wallpaper; later runs keep the choice.
monarch-wallpaper set "$MONARCH_PATH/themes/monarch/2-second.png"
monarch-theme-apply >/dev/null 2>&1 || true
[[ $(readlink -f "$link") == "$MONARCH_PATH/themes/monarch/2-second.png" ]] || fail "a later run keeps the user's choice"

# A user wallpaper outside Monarch's folders is never replaced either.
mkdir -p "$tmp/pics"; : >"$tmp/pics/mine.png"
monarch-wallpaper set "$tmp/pics/mine.png"
monarch-theme-apply >/dev/null 2>&1 || true
[[ $(readlink -f "$link") == "$tmp/pics/mine.png" ]] || fail "an outside wallpaper is untouched"

# A vanished target is replaced by a shipped one.
rm "$tmp/pics/mine.png"
monarch-theme-apply >/dev/null 2>&1 || true
[[ $(readlink -f "$link") == "$MONARCH_PATH/themes/monarch/1-first.png" ]] || fail "a missing wallpaper is re-seeded"
pass "first-login theme apply seeds the wallpaper link without the shell and keeps later choices"
